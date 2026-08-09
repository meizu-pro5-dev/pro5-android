#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s V18_RECOVERY_IMG NO_LPD_DONOR_IMG OUTPUT_DIRECTORY\n' \
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
lpd_patch="$project_root/patches/twrp-kernel-m86/0002-display-disable-decon-lpd.patch"

expected_base_sha256=975710e9214f8c471791748e42029c623ecb6b9a35e6fc6c856c4a6c77d0943f
expected_base_size=29335552
expected_base_kernel_sha256=959b97010805584b9935ba2004a684b9330b76de82a5ac911ee876d3f38e9b38
expected_ramdisk_size=12104206
expected_ramdisk_sha256=ffed93c7672f8b56e83610bd7a983e10f27e8394ce1c718293b8844a93100b64
expected_init_sha256=f211c6a264d49d7b0dcd908b0ce3744248b75e9b706cdb9cd41ecb5a2384ee3e
expected_device_init_sha256=2550cabe02e6c711f905e180729ba5760b2cb9a608a8363a16e1ed02d4da2ded
expected_wrapper_sha256=136b881e587df48ddb9e272d41beb888a05c36fce0c5cc3bd00d5885ed6d864f
expected_recovery_sha256=ee950be58363bd499c43af37464453ed6af8d3a50cf102855cc1b8ca5b63f079
expected_minui_sha256=9f77e4ef45c36d85b20e4e502e9f4a3e5de5f2467d0a27ad97ef36ec54eca18b
expected_adbd_sha256=881013de700ebba49ca8d9dd5670601b140e61a6365770ac0a7226b0f74de08f
expected_fstab_sha256=e493296b929734453dce9740503c66070f7cdf911b88df3e89a049bf0e062e48
expected_donor_sha256=7ce879901169990f8aea6fa48ca436e16bd15345e6634b4384cd4a6237fb4614
expected_donor_size=27287552
expected_kernel_size=17222424
expected_kernel_sha256=45474fdcdd7f354b81e18d4aa13704d9d990838ff562f1625c6ba11f7c036d21
expected_kernel_config_sha256=d8a081e100d581447fba72990cc3f2d738c0a18a3e6bba6f4fef51730ba5f909
expected_defconfig_sha256=3ed5fa4bc2303541df9b26de1dfd96737562b604c967d8615d66e27f5677d996
expected_usb_patch_sha256=9a86012475d1ad8e893749be05f5bae5eb56620af509577e90b13cce621a68ab
expected_lpd_patch_sha256=e4645d69fc7204e44fbbf2ef5e1638c6f805038093caacfa71a8e9ec5ec4b622
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

for required_file in "$inspector" "$repacker" "$usb_patch" "$lpd_patch"; do
  if [[ ! -s "$required_file" ]]; then
    printf 'Required v19 build input is absent: %s\n' "$required_file" >&2
    exit 1
  fi
done
require_sha256 "$expected_usb_patch_sha256" "$usb_patch"
require_sha256 "$expected_lpd_patch_sha256" "$lpd_patch"

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
donor_config="$donor_dir/kernel.config"
donor_defconfig="$donor_dir/cm_pro5_defconfig"
donor_reproducibility="$donor_dir/REPRODUCIBILITY.txt"

for donor_evidence in \
  "$donor_config" \
  "$donor_defconfig" \
  "$donor_reproducibility"; do
  if [[ ! -s "$donor_evidence" ]]; then
    printf 'Required no-LPD donor evidence is absent: %s\n' \
      "$donor_evidence" >&2
    exit 1
  fi
done

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
require_sha256 "$expected_kernel_config_sha256" "$donor_config"
require_sha256 "$expected_defconfig_sha256" "$donor_defconfig"
require_line '# CONFIG_DECON_LPD_DISPLAY is not set' "$donor_config"
require_line '# CONFIG_DECON_LPD_DISPLAY is not set' "$donor_defconfig"
require_line 'result=byte-identical' "$donor_reproducibility"
require_line "recovery_pass1_sha256=$expected_donor_sha256" \
  "$donor_reproducibility"
require_line "recovery_pass2_sha256=$expected_donor_sha256" \
  "$donor_reproducibility"

stage_root="$(mktemp -d "$output_parent/.pro5-twrp-v19.XXXXXX")"
cleanup() {
  if [[ -n "${stage_root:-}" && -d "$stage_root" && \
      "$stage_root" == "$output_parent/.pro5-twrp-v19."* ]]; then
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
  printf 'The two v19 kernel-only repacks are not byte-identical.\n' >&2
  exit 1
fi

cp "$pass_one/recovery.img" "$staged_artifact/recovery.img"
cp "$usb_patch" \
  "$staged_artifact/provenance/0001-usb-force-gadget-vbus-on-enable.patch"
cp "$lpd_patch" \
  "$staged_artifact/provenance/0002-display-disable-decon-lpd.patch"
cp "$donor_config" "$staged_artifact/provenance/kernel.config"
cp "$donor_defconfig" "$staged_artifact/provenance/cm_pro5_defconfig"
cp "$donor_reproducibility" \
  "$staged_artifact/provenance/DONOR-REPRODUCIBILITY.txt"
cp "$inspector" "$staged_artifact/provenance/inspect-android-boot-image.py"
cp "$repacker" "$staged_artifact/provenance/repack-android-boot-image.py"
cp "${BASH_SOURCE[0]}" \
  "$staged_artifact/provenance/build-pro5-twrp-no-lpd-v19.sh"

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
  printf 'artifact_role=test-only TWRP v19 DECON LPD isolation\n'
  printf 'artifact_generation=v19\n'
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
  printf 'ramdisk_identical_to_v18=yes\n'
  printf 'usb_id=2A45:0C02\n'
  printf 'usb_serial=860BDNA2225S\n'
  printf 'usb_functions=adb\n'
  printf 'adbd_sha256=%s\n' "$expected_adbd_sha256"
  printf 'minuitwrp_sha256=%s\n' "$expected_minui_sha256"
  printf 'kernel_profile=pre-pstore-usb-vbus-no-lpd\n'
  printf 'kernel_config_sha256=%s\n' "$expected_kernel_config_sha256"
  printf 'kernel_usb_patch_sha256=%s\n' "$expected_usb_patch_sha256"
  printf 'kernel_lpd_patch_sha256=%s\n' "$expected_lpd_patch_sha256"
  printf 'kernel_behavior=forced DWC3 gadget VBUS; DECON LPD disabled\n'
  printf 'conservative_image_limit=%s\n' "$conservative_image_limit"
  printf 'conservative_image_margin=%s\n' "$conservative_margin"
  printf 'recovery_partition_size=%s\n' "$recovery_partition_size"
  printf 'recovery_partition_margin=%s\n' "$partition_margin"
  printf 'reproducibility=two clean donor builds and two byte-identical kernel-only repacks\n'
  printf 'final_acceptance=no; device display and adb tests required\n'
} >"$staged_artifact/METADATA.txt"

{
  printf 'pass_one_recovery_sha256=%s\n' "$artifact_sha256"
  printf 'pass_two_recovery_sha256=%s\n' \
    "$(sha256_of "$pass_two/recovery.img")"
  printf 'recovery_byte_identical=yes\n'
  printf 'donor_clean_builds_byte_identical=yes\n'
  printf 'base_ramdisk_sha256=%s\n' "$expected_ramdisk_sha256"
  printf 'output_ramdisk_sha256=%s\n' "$expected_ramdisk_sha256"
  printf 'ramdisk_byte_identical=yes\n'
  printf 'changed_components=kernel only\n'
} >"$staged_artifact/REPRODUCIBILITY.txt"

{
  printf '# PRO 5 TWRP v19 no-LPD display diagnostic\n\n'
  printf 'This image is the exact v18 userspace with only the kernel replaced. '
  printf 'The forced-DWC3 ADB fix, 2A45:0C02 identity, serial 860BDNA2225S, '
  printf 'old adbd and v16 minui library are unchanged.\n\n'
  printf 'The sole display-variable change from v18 is disabling '
  printf '`CONFIG_DECON_LPD_DISPLAY`. Keep the stock Flyme DTB and flash only '
  printf '`recovery.img`. After boot, keep USB attached so DECON/DSIM state '
  printf 'can be sampled over ADB while the UI is exercised.\n'
} >"$staged_artifact/README.md"

require_sha256 "$expected_base_sha256" "$base_image"
require_sha256 "$expected_donor_sha256" "$donor_image"
require_sha256 "$expected_usb_patch_sha256" "$usb_patch"
require_sha256 "$expected_lpd_patch_sha256" "$lpd_patch"

(
  cd "$staged_artifact"
  find . -type f ! -name SHA256SUMS -print0 |
    LC_ALL=C sort -z |
    xargs -0 sha256sum
) >"$staged_artifact/SHA256SUMS"

mv "$staged_artifact" "$artifact_dir"
trap - EXIT
cleanup
printf 'Built PRO 5 TWRP v19 no-LPD diagnostic: %s\n' "$artifact_dir"
printf 'SHA-256: %s\n' "$artifact_sha256"
