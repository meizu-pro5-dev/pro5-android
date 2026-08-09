#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s V19_RECOVERY_IMG UNPATCHED_RECOVERY_DONOR_IMG OUTPUT_DIRECTORY\n' \
    "$(basename "$0")" >&2
}

if (( $# != 3 )); then
  usage
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
inspector="$script_dir/inspect-android-boot-image.py"
repacker="$script_dir/repack-android-boot-image.py"
rewriter="$script_dir/rewrite-newc-ramdisk.py"
replacement_init="$project_root/patches/twrp-runtime/recovery-functional-v20.rc"

expected_base_sha256=aa366fe911ccb31a71bf4ee3213a644b1973bb90229e243d4c9eaa76bb99902e
expected_base_size=29335552
expected_base_kernel_sha256=45474fdcdd7f354b81e18d4aa13704d9d990838ff562f1625c6ba11f7c036d21
expected_base_ramdisk_sha256=ffed93c7672f8b56e83610bd7a983e10f27e8394ce1c718293b8844a93100b64
expected_base_init_sha256=f211c6a264d49d7b0dcd908b0ce3744248b75e9b706cdb9cd41ecb5a2384ee3e
expected_output_init_sha256=837c7ac469aa4de26a728781a9b77ecf9a31e8c848b0d989a22331735bc6d929
expected_patched_recovery_sha256=ee950be58363bd499c43af37464453ed6af8d3a50cf102855cc1b8ca5b63f079
expected_unpatched_donor_sha256=faff297b31eab8aa1a6b85b31e801d72d0bc512cdee6850bd6d0451749013d31
expected_unpatched_donor_size=27303936
expected_unpatched_recovery_sha256=fb86468df29070d51ec2ce63466cfb49249fac94d4c5a1e59b84fff127968678
expected_recovery_size=935160
expected_minui_sha256=9f77e4ef45c36d85b20e4e502e9f4a3e5de5f2467d0a27ad97ef36ec54eca18b
expected_adbd_sha256=881013de700ebba49ca8d9dd5670601b140e61a6365770ac0a7226b0f74de08f
expected_device_init_sha256=2550cabe02e6c711f905e180729ba5760b2cb9a608a8363a16e1ed02d4da2ded
expected_wrapper_sha256=136b881e587df48ddb9e272d41beb888a05c36fce0c5cc3bd00d5885ed6d864f
expected_fstab_sha256=e493296b929734453dce9740503c66070f7cdf911b88df3e89a049bf0e062e48
conservative_image_limit=33550336
recovery_partition_size=33554432

sha256_of() {
  sha256sum "$1" | awk '{ print $1 }'
}

require_sha256() {
  local expected="$1"
  local source_file="$2"
  local actual

  actual="$(sha256_of "$source_file")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'SHA-256 mismatch for %s: expected %s, found %s\n' \
      "$source_file" "$expected" "$actual" >&2
    exit 1
  fi
}

require_line() {
  local expected="$1"
  local source_file="$2"

  if ! grep -Fqx -- "$expected" "$source_file"; then
    printf 'Required audit line is absent from %s: %s\n' \
      "$source_file" "$expected" >&2
    exit 1
  fi
}

for required_file in \
  "$inspector" \
  "$repacker" \
  "$rewriter" \
  "$replacement_init"; do
  if [[ ! -s "$required_file" ]]; then
    printf 'Required v20 build input is absent: %s\n' "$required_file" >&2
    exit 1
  fi
done
require_sha256 "$expected_output_init_sha256" "$replacement_init"

for required_init_line in \
  'on property:sys.usb.config=adb' \
  'on property:sys.usb.config=mtp,adb' \
  '    write /sys/class/android_usb/android0/functions mtp,adb' \
  'on property:sys.powerctl=*' \
  'service recovery /sbin/recovery'; do
  require_line "$required_init_line" "$replacement_init"
done
if grep -Eq '^[[:space:]]*setprop[[:space:]]+mtp\.crash_check' \
    "$replacement_init"; then
  printf 'The v20 init still forces TWRP to suppress MTP.\n' >&2
  exit 1
fi
if grep -Fq '/sbin/permissive.sh' "$replacement_init"; then
  printf 'The v20 recovery service still launches the diagnostic wrapper.\n' >&2
  exit 1
fi

base_input="$1"
donor_input="$2"
for image_spec in "base:$base_input" "donor:$donor_input"; do
  image_role="${image_spec%%:*}"
  image_file="${image_spec#*:}"
  if [[ ! -f "$image_file" ]]; then
    printf 'The %s image is absent: %s\n' "$image_role" "$image_file" >&2
    exit 1
  fi
done
base_dir="$(cd "$(dirname "$base_input")" && pwd -P)"
base_image="$base_dir/$(basename "$base_input")"
donor_dir="$(cd "$(dirname "$donor_input")" && pwd -P)"
donor_image="$donor_dir/$(basename "$donor_input")"

output_input="$3"
output_parent_input="$(dirname "$output_input")"
if [[ ! -d "$output_parent_input" ]]; then
  printf 'The output parent directory is absent: %s\n' \
    "$output_parent_input" >&2
  exit 1
fi
output_parent="$(cd "$output_parent_input" && pwd -P)"
output_name="$(basename "$output_input")"
if [[ -z "$output_name" || "$output_name" == "." || \
    "$output_name" == ".." ]]; then
  printf 'Invalid output directory name: %s\n' "$output_name" >&2
  exit 1
fi
artifact_dir="$output_parent/$output_name"
if [[ -e "$artifact_dir" ]]; then
  printf 'Refusing to overwrite artifact directory: %s\n' \
    "$artifact_dir" >&2
  exit 1
fi

require_sha256 "$expected_base_sha256" "$base_image"
require_sha256 "$expected_unpatched_donor_sha256" "$donor_image"

stage_root="$(mktemp -d "$output_parent/.pro5-twrp-v20.XXXXXX")"
cleanup() {
  if [[ -n "${stage_root:-}" && -d "$stage_root" && \
      "$stage_root" == "$output_parent/.pro5-twrp-v20."* ]]; then
    rm -r -- "$stage_root"
  fi
}
trap cleanup EXIT

pass_one="$stage_root/pass-one"
pass_two="$stage_root/pass-two"
staged_artifact="$stage_root/artifact"
base_recovery="$stage_root/base-recovery"
unpatched_recovery="$stage_root/unpatched-recovery"
mkdir -p "$pass_one" "$pass_two" "$staged_artifact/provenance"

base_header="$staged_artifact/BASE-RECOVERY-HEADER.txt"
python3 "$inspector" "$base_image" \
  --expect-page-size 4096 \
  --expect-kernel-addr 0x40080000 \
  --expect-ramdisk-addr 0x42000000 \
  --expect-second-addr 0x40f78000 \
  --expect-tags-addr 0x40000100 \
  --expect-second-size 0 \
  --expect-dt-size 0 \
  --expect-valid-image-id \
  --expect-empty-cmdline \
  --expect-ramdisk-compression gzip \
  --expect-ramdisk-file-sha256 "init.rc=$expected_base_init_sha256" \
  --expect-ramdisk-file-sha256 \
    "init.recovery.m86.rc=$expected_device_init_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/permissive.sh=$expected_wrapper_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/recovery=$expected_patched_recovery_sha256" \
  --expect-ramdisk-file-sha256 "sbin/libminuitwrp.so=$expected_minui_sha256" \
  --expect-ramdisk-file-sha256 "sbin/adbd=$expected_adbd_sha256" \
  --expect-ramdisk-file-sha256 "etc/recovery.fstab=$expected_fstab_sha256" \
  --expect-ramdisk-elf sbin/recovery \
  --expect-ramdisk-elf sbin/libminuitwrp.so \
  --expect-ramdisk-elf sbin/adbd \
  --extract-ramdisk-file "sbin/recovery=$base_recovery" \
  --max-size "$conservative_image_limit" >"$base_header"
require_line "file_size=$expected_base_size" "$base_header"
require_line "kernel_sha256=$expected_base_kernel_sha256" "$base_header"
require_line "ramdisk_sha256=$expected_base_ramdisk_sha256" "$base_header"
require_line 'image_id_scheme=conditional-dtb' "$base_header"
require_sha256 "$expected_patched_recovery_sha256" "$base_recovery"

donor_header="$staged_artifact/DONOR-RECOVERY-HEADER.txt"
python3 "$inspector" "$donor_image" \
  --expect-page-size 4096 \
  --expect-second-size 0 \
  --expect-dt-size 0 \
  --expect-valid-image-id \
  --expect-ramdisk-compression lzma \
  --expect-ramdisk-file-sha256 \
    "sbin/recovery=$expected_unpatched_recovery_sha256" \
  --expect-ramdisk-elf sbin/recovery \
  --extract-ramdisk-file "sbin/recovery=$unpatched_recovery" \
  --max-size "$conservative_image_limit" >"$donor_header"
require_line "file_size=$expected_unpatched_donor_size" "$donor_header"
require_sha256 "$expected_unpatched_recovery_sha256" "$unpatched_recovery"
if [[ "$(wc -c <"$unpatched_recovery" | tr -d ' ')" != \
    "$expected_recovery_size" ]]; then
  printf 'The unpatched v20 recovery ELF has an unexpected size.\n' >&2
  exit 1
fi
if [[ "$(strings -a "$unpatched_recovery" | grep -Fxc 'sys.powerctl')" != \
    "1" ]] || strings -a "$unpatched_recovery" | \
    grep -Fx 'twrp.loghold' >/dev/null; then
  printf 'The v20 recovery ELF does not restore the real power property.\n' >&2
  exit 1
fi
if [[ "$(cmp -l "$base_recovery" "$unpatched_recovery" | wc -l | tr -d ' ')" \
    != "12" ]]; then
  printf 'The recovered TWRP ELF differs outside the 12-byte power literal.\n' >&2
  exit 1
fi

for pass_spec in "ONE:$pass_one" "TWO:$pass_two"; do
  pass_name="${pass_spec%%:*}"
  pass_dir="${pass_spec#*:}"
  rewrite_log="$staged_artifact/RAMDISK-REWRITE-PASS-$pass_name.txt"

  python3 "$rewriter" \
    --base-boot-image "$base_image" \
    --expect-base-sha256 "$expected_base_sha256" \
    --replace-data "init.rc=$replacement_init" \
    --replace-data "sbin/recovery=$unpatched_recovery" \
    --compression gzip \
    --output "$pass_dir/ramdisk.gzip" >"$rewrite_log"
  require_line 'base_entry_count_including_trailer=489' "$rewrite_log"
  require_line 'output_entry_count_including_trailer=489' "$rewrite_log"
  require_line 'added_paths=' "$rewrite_log"
  require_line 'removed_paths=' "$rewrite_log"
  require_line 'changed_data_paths=init.rc,sbin/recovery' "$rewrite_log"
  require_line 'changed_metadata_paths=' "$rewrite_log"
  require_line 'entry_order_identical=yes' "$rewrite_log"
  require_line 'archive_tail_identical=yes' "$rewrite_log"

  python3 "$repacker" "$base_image" \
    --ramdisk "$pass_dir/ramdisk.gzip" \
    --image-id-scheme conditional-dtb \
    --output "$pass_dir/recovery.img"
done

if ! cmp --silent "$pass_one/ramdisk.gzip" "$pass_two/ramdisk.gzip" || \
    ! cmp --silent "$pass_one/recovery.img" "$pass_two/recovery.img"; then
  printf 'The two clean v20 repacks are not byte-identical.\n' >&2
  exit 1
fi

cp "$pass_one/ramdisk.gzip" "$staged_artifact/ramdisk.gzip"
cp "$pass_one/recovery.img" "$staged_artifact/recovery.img"
cp "$replacement_init" "$staged_artifact/provenance/init-functional-v20.rc"
cp "$unpatched_recovery" "$staged_artifact/provenance/recovery-unpatched"
cp "$inspector" "$staged_artifact/provenance/inspect-android-boot-image.py"
cp "$repacker" "$staged_artifact/provenance/repack-android-boot-image.py"
cp "$rewriter" "$staged_artifact/provenance/rewrite-newc-ramdisk.py"
cp "${BASH_SOURCE[0]}" \
  "$staged_artifact/provenance/build-pro5-twrp-functional-v20.sh"

output_header="$staged_artifact/RECOVERY-HEADER.txt"
python3 "$inspector" "$staged_artifact/recovery.img" \
  --expect-page-size 4096 \
  --expect-kernel-addr 0x40080000 \
  --expect-ramdisk-addr 0x42000000 \
  --expect-second-addr 0x40f78000 \
  --expect-tags-addr 0x40000100 \
  --expect-second-size 0 \
  --expect-dt-size 0 \
  --expect-valid-image-id \
  --expect-empty-cmdline \
  --expect-ramdisk-compression gzip \
  --expect-ramdisk-file-sha256 "init.rc=$expected_output_init_sha256" \
  --expect-ramdisk-file-sha256 \
    "init.recovery.m86.rc=$expected_device_init_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/permissive.sh=$expected_wrapper_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/recovery=$expected_unpatched_recovery_sha256" \
  --expect-ramdisk-file-sha256 "sbin/libminuitwrp.so=$expected_minui_sha256" \
  --expect-ramdisk-file-sha256 "sbin/adbd=$expected_adbd_sha256" \
  --expect-ramdisk-file-sha256 "etc/recovery.fstab=$expected_fstab_sha256" \
  --expect-ramdisk-elf sbin/recovery \
  --expect-ramdisk-elf sbin/libminuitwrp.so \
  --expect-ramdisk-elf sbin/adbd \
  --max-size "$conservative_image_limit" >"$output_header"
require_line "kernel_sha256=$expected_base_kernel_sha256" "$output_header"
require_line 'image_id_scheme=conditional-dtb' "$output_header"
require_line 'dt_size=0' "$output_header"
require_line 'trailing_size=0' "$output_header"

artifact_size="$(wc -c <"$staged_artifact/recovery.img" | tr -d ' ')"
artifact_sha256="$(sha256_of "$staged_artifact/recovery.img")"
ramdisk_size="$(wc -c <"$staged_artifact/ramdisk.gzip" | tr -d ' ')"
ramdisk_sha256="$(sha256_of "$staged_artifact/ramdisk.gzip")"
conservative_margin=$((conservative_image_limit - artifact_size))
partition_margin=$((recovery_partition_size - artifact_size))
built_at="$(date '+%Y-%m-%dT%H:%M:%S%z')"

cat >"$staged_artifact/METADATA.txt" <<EOF
artifact_role=test-only TWRP v20 functional runtime cleanup
artifact_generation=v20
artifact_file=recovery.img
artifact_size=$artifact_size
artifact_sha256=$artifact_sha256
built_at=$built_at
base_recovery_sha256=$expected_base_sha256
changed_data_paths=init.rc,sbin/recovery
changed_metadata_paths=none
kernel_sha256=$expected_base_kernel_sha256
display_behavior=DECON LPD disabled exactly as v19
usb_id=2A45:0C02
usb_serial=860BDNA2225S
usb_boot_functions=adb
usb_twrp_functions=mtp,adb
mtp_transport=/dev/mtp_usb
adb_transport=/dev/android_adb
mtp_crash_suppression=removed
reboot_property=sys.powerctl restored
diagnostic_wrapper=not launched
ramdisk_entry_count_including_trailer=489
ramdisk_size=$ramdisk_size
ramdisk_sha256=$ramdisk_sha256
recovery_elf_sha256=$expected_unpatched_recovery_sha256
minuitwrp_sha256=$expected_minui_sha256
adbd_sha256=$expected_adbd_sha256
image_id_scheme=conditional-dtb
embedded_dtb_size=0
conservative_image_limit=$conservative_image_limit
conservative_image_margin=$conservative_margin
recovery_partition_size=$recovery_partition_size
recovery_partition_margin=$partition_margin
reproducibility=two byte-identical ramdisk and recovery repacks
final_acceptance=no; device MTP and reboot tests required
EOF

cat >"$staged_artifact/REPRODUCIBILITY.txt" <<EOF
pass_one_ramdisk_sha256=$(sha256_of "$pass_one/ramdisk.gzip")
pass_two_ramdisk_sha256=$(sha256_of "$pass_two/ramdisk.gzip")
ramdisk_byte_identical=yes
pass_one_recovery_sha256=$(sha256_of "$pass_one/recovery.img")
pass_two_recovery_sha256=$(sha256_of "$pass_two/recovery.img")
recovery_byte_identical=yes
changed_data_paths=init.rc,sbin/recovery
changed_metadata_paths=none
EOF

cat >"$staged_artifact/README.md" <<EOF
# PRO 5 TWRP functional runtime cleanup v20

V20 starts from the exact display- and ADB-tested v19 image. It keeps the
v19 kernel, disabled DECON LPD, minui library, old adbd, fstab and all other
ramdisk data. Only two existing data payloads change:

- \`init.rc\` removes forced MTP crash suppression, adds reversible
  \`adb\` / \`mtp,adb\` gadget actions and launches recovery directly;
- \`sbin/recovery\` restores its original \`sys.powerctl\` literal so system,
  recovery, bootloader and power-off menu requests can reach init.

The v19 live probe already proved that the Exynos kernel binds both MTP and
ADB, macOS enumerates the composite device and ADB reconnects. V20 still needs
an on-device TWRP MTP server test and each safe reboot target must be tested
separately. Keep the stock Flyme DTB and flash only \`recovery.img\`.
EOF

require_sha256 "$expected_base_sha256" "$base_image"
require_sha256 "$expected_unpatched_donor_sha256" "$donor_image"
require_sha256 "$expected_output_init_sha256" "$replacement_init"
require_sha256 "$expected_unpatched_recovery_sha256" "$unpatched_recovery"

(
  cd "$staged_artifact"
  find . -type f ! -name SHA256SUMS -print0 |
    LC_ALL=C sort -z |
    xargs -0 sha256sum
) >"$staged_artifact/SHA256SUMS"

mv "$staged_artifact" "$artifact_dir"
trap - EXIT
cleanup
printf 'Built PRO 5 TWRP v20 functional cleanup: %s\n' "$artifact_dir"
printf 'SHA-256: %s\n' "$artifact_sha256"
