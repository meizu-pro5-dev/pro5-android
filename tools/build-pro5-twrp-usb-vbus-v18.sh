#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s V17_RECOVERY_IMG USB_KERNEL_DONOR_IMG OUTPUT_DIRECTORY\n' \
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
usb_patch="$project_root/patches/twrp-kernel-m86/0001-usb-force-gadget-vbus-on-enable.patch"

expected_base_sha256=e7d17b0dc4bd0136bb9338a2263f1bad602c75d3d0db123a9e6e512b804c6cda
expected_base_size=29335552
expected_base_kernel_sha256=5df2fd06a58635c0299f10686c715a35fbc7ba0169bf9ffccdb292bba42c7d04
expected_ramdisk_size=12104206
expected_ramdisk_sha256=ffed93c7672f8b56e83610bd7a983e10f27e8394ce1c718293b8844a93100b64
expected_init_sha256=f211c6a264d49d7b0dcd908b0ce3744248b75e9b706cdb9cd41ecb5a2384ee3e
expected_device_init_sha256=2550cabe02e6c711f905e180729ba5760b2cb9a608a8363a16e1ed02d4da2ded
expected_wrapper_sha256=136b881e587df48ddb9e272d41beb888a05c36fce0c5cc3bd00d5885ed6d864f
expected_recovery_sha256=ee950be58363bd499c43af37464453ed6af8d3a50cf102855cc1b8ca5b63f079
expected_minui_sha256=9f77e4ef45c36d85b20e4e502e9f4a3e5de5f2467d0a27ad97ef36ec54eca18b
expected_adbd_sha256=881013de700ebba49ca8d9dd5670601b140e61a6365770ac0a7226b0f74de08f
expected_fstab_sha256=e493296b929734453dce9740503c66070f7cdf911b88df3e89a049bf0e062e48
expected_donor_sha256=85af306ec06daa18f403cca79ef217438fdfe46c7f33f0470d4a03fff6232e06
expected_donor_size=27287552
expected_kernel_size=17222424
expected_kernel_sha256=959b97010805584b9935ba2004a684b9330b76de82a5ac911ee876d3f38e9b38
expected_usb_patch_sha256=9a86012475d1ad8e893749be05f5bae5eb56620af509577e90b13cce621a68ab
expected_android_source_sha256=e0058fc84b4043aef966932507a190c655ef51b2f7c6e0d2c610dda64f1961ce
expected_display_source_sha256=455f1e7f71eafb4f4516c789a28fa3c90f3880a3a484c54d3a8dfd19f44112d0
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

for required_file in "$inspector" "$repacker" "$usb_patch"; do
  if [[ ! -s "$required_file" ]]; then
    printf 'Required v18 build input is absent: %s\n' "$required_file" >&2
    exit 1
  fi
done
require_sha256 "$expected_usb_patch_sha256" "$usb_patch"

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
require_sha256 "$expected_donor_sha256" "$donor_image"

stage_root="$(mktemp -d "$output_parent/.pro5-twrp-v18.XXXXXX")"
cleanup() {
  if [[ -n "${stage_root:-}" && -d "$stage_root" && \
      "$stage_root" == "$output_parent/.pro5-twrp-v18."* ]]; then
    rm -r -- "$stage_root"
  fi
}
trap cleanup EXIT

pass_one="$stage_root/pass-one"
pass_two="$stage_root/pass-two"
staged_artifact="$stage_root/artifact"
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
  --expect-ramdisk-file-sha256 "init.rc=$expected_init_sha256" \
  --expect-ramdisk-file-sha256 \
    "init.recovery.m86.rc=$expected_device_init_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/permissive.sh=$expected_wrapper_sha256" \
  --expect-ramdisk-file-sha256 "sbin/recovery=$expected_recovery_sha256" \
  --expect-ramdisk-file-sha256 "sbin/libminuitwrp.so=$expected_minui_sha256" \
  --expect-ramdisk-file-sha256 "sbin/adbd=$expected_adbd_sha256" \
  --expect-ramdisk-file-sha256 "etc/recovery.fstab=$expected_fstab_sha256" \
  --expect-ramdisk-elf sbin/recovery \
  --expect-ramdisk-elf sbin/libminuitwrp.so \
  --expect-ramdisk-elf sbin/adbd \
  --max-size "$conservative_image_limit" >"$base_header"
require_line "file_size=$expected_base_size" "$base_header"
require_line "kernel_size=$expected_kernel_size" "$base_header"
require_line "kernel_sha256=$expected_base_kernel_sha256" "$base_header"
require_line "ramdisk_size=$expected_ramdisk_size" "$base_header"
require_line "ramdisk_sha256=$expected_ramdisk_sha256" "$base_header"
require_line 'image_id_scheme=conditional-dtb' "$base_header"

donor_header="$staged_artifact/DONOR-RECOVERY-HEADER.txt"
python3 "$inspector" "$donor_image" \
  --expect-page-size 4096 \
  --expect-second-size 0 \
  --expect-dt-size 0 \
  --expect-valid-image-id \
  --expect-ramdisk-compression lzma \
  --max-size "$conservative_image_limit" >"$donor_header"
require_line "file_size=$expected_donor_size" "$donor_header"
require_line "kernel_size=$expected_kernel_size" "$donor_header"
require_line "kernel_sha256=$expected_kernel_sha256" "$donor_header"
require_line 'image_id_scheme=all-sections' "$donor_header"

for pass_dir in "$pass_one" "$pass_two"; do
  python3 "$repacker" "$base_image" \
    --kernel-from-image "$donor_image" \
    --image-id-scheme conditional-dtb \
    --output "$pass_dir/recovery.img"
done
if ! cmp --silent "$pass_one/recovery.img" "$pass_two/recovery.img"; then
  printf 'The two v18 kernel-only repacks are not byte-identical.\n' >&2
  exit 1
fi

cp "$pass_one/recovery.img" "$staged_artifact/recovery.img"
cp "$usb_patch" "$staged_artifact/provenance/0001-usb-force-gadget-vbus-on-enable.patch"
cp "$inspector" "$staged_artifact/provenance/inspect-android-boot-image.py"
cp "$repacker" "$staged_artifact/provenance/repack-android-boot-image.py"
cp "${BASH_SOURCE[0]}" \
  "$staged_artifact/provenance/build-pro5-twrp-usb-vbus-v18.sh"

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
  --expect-ramdisk-file-sha256 "init.rc=$expected_init_sha256" \
  --expect-ramdisk-file-sha256 \
    "init.recovery.m86.rc=$expected_device_init_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/permissive.sh=$expected_wrapper_sha256" \
  --expect-ramdisk-file-sha256 "sbin/recovery=$expected_recovery_sha256" \
  --expect-ramdisk-file-sha256 "sbin/libminuitwrp.so=$expected_minui_sha256" \
  --expect-ramdisk-file-sha256 "sbin/adbd=$expected_adbd_sha256" \
  --expect-ramdisk-file-sha256 "etc/recovery.fstab=$expected_fstab_sha256" \
  --expect-ramdisk-elf sbin/recovery \
  --expect-ramdisk-elf sbin/libminuitwrp.so \
  --expect-ramdisk-elf sbin/adbd \
  --max-size "$conservative_image_limit" >"$output_header"
require_line "file_size=$expected_base_size" "$output_header"
require_line "kernel_size=$expected_kernel_size" "$output_header"
require_line "kernel_sha256=$expected_kernel_sha256" "$output_header"
require_line "ramdisk_size=$expected_ramdisk_size" "$output_header"
require_line "ramdisk_sha256=$expected_ramdisk_sha256" "$output_header"
require_line 'image_id_scheme=conditional-dtb' "$output_header"
require_line 'dt_size=0' "$output_header"
require_line 'trailing_size=0' "$output_header"

artifact_size="$(wc -c <"$staged_artifact/recovery.img" | tr -d ' ')"
artifact_sha256="$(sha256_of "$staged_artifact/recovery.img")"
conservative_margin=$((conservative_image_limit - artifact_size))
partition_margin=$((recovery_partition_size - artifact_size))
built_at="$(date '+%Y-%m-%dT%H:%M:%S%z')"

{
  printf 'artifact_role=test-only TWRP v18 forced DWC3 USB session diagnostic\n'
  printf 'artifact_generation=v18\n'
  printf 'artifact_file=recovery.img\n'
  printf 'artifact_size=%s\n' "$artifact_size"
  printf 'artifact_sha256=%s\n' "$artifact_sha256"
  printf 'built_at=%s\n' "$built_at"
  printf 'base_recovery_sha256=%s\n' "$expected_base_sha256"
  printf 'kernel_donor_recovery_sha256=%s\n' "$expected_donor_sha256"
  printf 'changed_components=kernel only\n'
  printf 'base_kernel_sha256=%s\n' "$expected_base_kernel_sha256"
  printf 'output_kernel_sha256=%s\n' "$expected_kernel_sha256"
  printf 'ramdisk_sha256=%s\n' "$expected_ramdisk_sha256"
  printf 'ramdisk_identical_to_v17=yes\n'
  printf 'usb_id=2A45:0C02\n'
  printf 'usb_serial=860BDNA2225S\n'
  printf 'usb_functions=adb\n'
  printf 'adbd_sha256=%s\n' "$expected_adbd_sha256"
  printf 'minuitwrp_sha256=%s\n' "$expected_minui_sha256"
  printf 'kernel_source_baseline=v11 proven kernel\n'
  printf 'kernel_android_usb_source_sha256=%s\n' \
    "$expected_android_source_sha256"
  printf 'kernel_display_source_sha256=%s\n' \
    "$expected_display_source_sha256"
  printf 'kernel_patch_sha256=%s\n' "$expected_usb_patch_sha256"
  printf 'kernel_behavior=force DWC3 gadget VBUS session when android_usb enable becomes 1\n'
  printf 'conservative_image_limit=%s\n' "$conservative_image_limit"
  printf 'conservative_image_margin=%s\n' "$conservative_margin"
  printf 'recovery_partition_size=%s\n' "$recovery_partition_size"
  printf 'recovery_partition_margin=%s\n' "$partition_margin"
  printf 'reproducibility=two byte-identical kernel-only repacks\n'
  printf 'final_acceptance=no; host USB enumeration and adb tests required\n'
} >"$staged_artifact/METADATA.txt"

{
  printf 'pass_one_recovery_sha256=%s\n' "$artifact_sha256"
  printf 'pass_two_recovery_sha256=%s\n' \
    "$(sha256_of "$pass_two/recovery.img")"
  printf 'recovery_byte_identical=yes\n'
  printf 'base_ramdisk_sha256=%s\n' "$expected_ramdisk_sha256"
  printf 'output_ramdisk_sha256=%s\n' "$expected_ramdisk_sha256"
  printf 'ramdisk_byte_identical=yes\n'
  printf 'changed_components=kernel only\n'
} >"$staged_artifact/REPRODUCIBILITY.txt"

{
  printf '# PRO 5 TWRP v18 USB diagnostic\n\n'
  printf 'This image is v17 with only the kernel component replaced. '
  printf 'It keeps the exact v17 ramdisk, ADB daemon, minui library, '
  printf '2A45:0C02 descriptor, and serial 860BDNA2225S.\n\n'
  printf 'After flashing and booting Recovery, test host enumeration first:\n\n'
  printf '1. Confirm macOS sees VID:PID 2A45:0C02.\n'
  printf '2. Run `adb kill-server`, then `adb start-server`.\n'
  printf '3. Run `adb devices -l`; the expected serial is 860BDNA2225S.\n'
  printf '4. Do not use display behavior as the acceptance criterion for this build.\n'
} >"$staged_artifact/README.md"

require_sha256 "$expected_base_sha256" "$base_image"
require_sha256 "$expected_donor_sha256" "$donor_image"
require_sha256 "$expected_usb_patch_sha256" "$usb_patch"

(
  cd "$staged_artifact"
  find . -type f ! -name SHA256SUMS -print0 |
    LC_ALL=C sort -z |
    xargs -0 sha256sum
) >"$staged_artifact/SHA256SUMS"

mv "$staged_artifact" "$artifact_dir"
trap - EXIT
cleanup
printf 'Built PRO 5 TWRP v18 USB diagnostic: %s\n' "$artifact_dir"
printf 'SHA-256: %s\n' "$artifact_sha256"
