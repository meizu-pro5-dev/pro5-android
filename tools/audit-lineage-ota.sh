#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 3 ]]; then
  printf 'Usage: %s OTA_ZIP BOOT_IMAGE RAW_DTB\n' "${0##*/}" >&2
  exit 2
fi

ota_package="$1"
boot_image="$2"
raw_dtb="$3"

for required_file in "$ota_package" "$boot_image" "$raw_dtb"; do
  if [[ ! -s "$required_file" ]]; then
    printf 'Required OTA audit input is missing: %s\n' "$required_file" >&2
    exit 1
  fi
done
for required_tool in awk cmp grep paste sha256sum sort unzip wc; do
  if ! command -v "$required_tool" >/dev/null; then
    printf 'Required OTA audit tool is missing: %s\n' "$required_tool" >&2
    exit 1
  fi
done

unzip -tq "$ota_package" >/dev/null
entry_list="$(unzip -Z1 "$ota_package")"

require_entry() {
  local entry_name="$1"

  if ! grep -F -x -q "$entry_name" <<<"$entry_list"; then
    printf 'Required OTA entry is missing: %s\n' "$entry_name" >&2
    exit 1
  fi
}

for required_entry in \
  META-INF/com/android/metadata \
  META-INF/com/google/android/update-binary \
  META-INF/com/google/android/updater-script \
  boot.img \
  dtb.img \
  system.new.dat.br \
  system.patch.dat \
  system.transfer.list; do
  require_entry "$required_entry"
done

if ! unzip -p "$ota_package" dtb.img | cmp -s - "$raw_dtb"; then
  printf 'OTA DTB differs from the reviewed Flyme-based hybrid.\n' >&2
  exit 1
fi

if grep -E \
    '^(bootloader|sboot|ldfw|bootlogo|dtb_backup|param|proinfo|private|rstinfo)([./]|$)' \
    <<<"$entry_list" >/dev/null; then
  printf 'OTA contains a forbidden firmware, identity, or backup payload.\n' >&2
  exit 1
fi

if ! unzip -p "$ota_package" boot.img | cmp -s - "$boot_image"; then
  printf 'OTA boot image differs from the validated product boot image.\n' >&2
  exit 1
fi
metadata="$(unzip -p "$ota_package" META-INF/com/android/metadata)"
for required_metadata in \
  ota-required-cache=0 \
  ota-type=BLOCK; do
  if ! grep -F -x -q "$required_metadata" <<<"$metadata"; then
    printf 'Required full-OTA metadata is absent: %s\n' \
      "$required_metadata" >&2
    exit 1
  fi
done

updater_script="$(
  unzip -p "$ota_package" META-INF/com/google/android/updater-script
)"
block_targets="$(
  grep -Eo \
    '/dev/block/platform/15570000\.ufs/by-name/[A-Za-z0-9_.-]+' \
    <<<"$updater_script" |
    LC_ALL=C sort -u
)"
expected_block_targets="$(
  printf '%s\n' \
    /dev/block/platform/15570000.ufs/by-name/bootimg \
    /dev/block/platform/15570000.ufs/by-name/dtb \
    /dev/block/platform/15570000.ufs/by-name/system
)"
if [[ "$block_targets" != "$expected_block_targets" ]]; then
  printf 'OTA updater writes an unreviewed partition set:\n%s\n' \
    "$block_targets" >&2
  exit 1
fi
if ! grep -F -q \
    'package_extract_file("boot.img", "/dev/block/platform/15570000.ufs/by-name/bootimg");' \
    <<<"$updater_script"; then
  printf 'OTA updater does not contain the reviewed boot-image write.\n' >&2
  exit 1
fi
if ! grep -F -q \
    'package_extract_file("dtb.img", "/dev/block/platform/15570000.ufs/by-name/dtb");' \
    <<<"$updater_script"; then
  printf 'OTA updater does not contain the reviewed hybrid-DTB write.\n' >&2
  exit 1
fi

transfer_list="$(unzip -p "$ota_package" system.transfer.list)"
if ! awk '
    NR == 1 && $0 != "4" { bad = 1 }
    NR == 2 && $0 !~ /^[1-9][0-9]*$/ { bad = 1 }
    (NR == 3 || NR == 4) && $0 != "0" { bad = 1 }
    NR > 4 {
      seen = 1
      if ($1 == "new") {
        has_new = 1
      } else if ($1 != "zero" && $1 != "erase") {
        bad = 1
      }
    }
    END {
      if (NR < 5 || !seen || !has_new) {
        bad = 1
      }
      exit(bad ? 1 : 0)
    }
  ' <<<"$transfer_list"; then
  printf 'OTA is not a stash-free full block transfer.\n' >&2
  exit 1
fi

zip_entry_size() {
  local entry_name="$1"

  unzip -l "$ota_package" "$entry_name" |
    awk -v entry_name="$entry_name" '
      $4 == entry_name { size = $1 }
      END {
        if (size == "") {
          exit 1
        }
        print size
      }
    '
}

patch_size="$(zip_entry_size system.patch.dat)"
new_dat_size="$(zip_entry_size system.new.dat.br)"
if [[ "$patch_size" != "0" ]]; then
  printf 'Full OTA unexpectedly contains non-empty patch data.\n' >&2
  exit 1
fi
if [[ ! "$new_dat_size" =~ ^[1-9][0-9]*$ ]]; then
  printf 'Full OTA has no system.new.dat.br payload.\n' >&2
  exit 1
fi

transfer_operations="$(
  awk 'NR > 4 { print $1 }' <<<"$transfer_list" |
    LC_ALL=C sort -u |
    paste -sd, -
)"

printf 'ota_sha256=%s\n' \
  "$(sha256sum "$ota_package" | awk '{ print $1 }')"
printf 'boot_sha256=%s\n' \
  "$(sha256sum "$boot_image" | awk '{ print $1 }')"
printf 'hybrid_dtb_sha256=%s\n' \
  "$(sha256sum "$raw_dtb" | awk '{ print $1 }')"
printf 'ota_required_cache=0\n'
printf 'block_targets=bootimg,dtb,system\n'
printf 'transfer_operations=%s\n' "$transfer_operations"
printf 'system_patch_dat_size=%s\n' "$patch_size"
printf 'system_new_dat_br_size=%s\n' "$new_dat_size"
printf 'LineageOS full OTA audit passed.\n'
