#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s V16_RECOVERY_IMG OUTPUT_DIRECTORY\n' \
    "$(basename "$0")" >&2
}

if (( $# != 2 )); then
  usage
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
inspector="$script_dir/inspect-android-boot-image.py"
repacker="$script_dir/repack-android-boot-image.py"
rewriter="$script_dir/rewrite-newc-ramdisk.py"
replacement_init="$project_root/patches/twrp-diagnostics/recovery-direct-adb-v17.rc"

expected_base_sha256=7c92a6268b0c4d57dc94b3382ea9cbae7c9c1e6ee74866d6ce611d026e9691d4
expected_base_size=29335552
expected_base_ramdisk_sha256=56ec701b040d8886ec61ff12e0ff78355daac4ce50824b4ffd13392f2598a747
expected_base_init_sha256=f6ec000ea794e94da89258a9aa2912fcb8075938e89f04537b7b5afd0588b589
expected_output_init_sha256=f211c6a264d49d7b0dcd908b0ce3744248b75e9b706cdb9cd41ecb5a2384ee3e
expected_kernel_sha256=5df2fd06a58635c0299f10686c715a35fbc7ba0169bf9ffccdb292bba42c7d04
expected_minui_sha256=9f77e4ef45c36d85b20e4e502e9f4a3e5de5f2467d0a27ad97ef36ec54eca18b
expected_recovery_sha256=ee950be58363bd499c43af37464453ed6af8d3a50cf102855cc1b8ca5b63f079
expected_adbd_sha256=881013de700ebba49ca8d9dd5670601b140e61a6365770ac0a7226b0f74de08f
expected_device_init_sha256=2550cabe02e6c711f905e180729ba5760b2cb9a608a8363a16e1ed02d4da2ded
expected_wrapper_sha256=136b881e587df48ddb9e272d41beb888a05c36fce0c5cc3bd00d5885ed6d864f
expected_fstab_sha256=e493296b929734453dce9740503c66070f7cdf911b88df3e89a049bf0e062e48
expected_stock_dtb_sha256=b45054fa87a5ffe114843953172d48d36408e1f93db35a6cbdfb0a8fc58a2165
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
    printf 'Required v17 build input is absent: %s\n' "$required_file" >&2
    exit 1
  fi
done

require_sha256 "$expected_output_init_sha256" "$replacement_init"
for required_descriptor in \
  '    write /sys/class/android_usb/android0/idVendor 2A45' \
  '    write /sys/class/android_usb/android0/idProduct 0C02' \
  '    write /sys/class/android_usb/android0/iManufacturer Meizu' \
  '    write /sys/class/android_usb/android0/iProduct M86' \
  '    write /sys/class/android_usb/android0/iSerial 860BDNA2225S' \
  '    write /sys/class/android_usb/android0/functions adb'; do
  require_line "$required_descriptor" "$replacement_init"
done

base_input="$1"
if [[ ! -f "$base_input" ]]; then
  printf 'The v16 base image is absent: %s\n' "$base_input" >&2
  exit 1
fi
base_dir="$(cd "$(dirname "$base_input")" && pwd -P)"
base_image="$base_dir/$(basename "$base_input")"

output_input="$2"
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

stage_root="$(mktemp -d "$output_parent/.pro5-twrp-v17.XXXXXX")"
cleanup() {
  if [[ -n "${stage_root:-}" && -d "$stage_root" && \
      "$stage_root" == "$output_parent/.pro5-twrp-v17."* ]]; then
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
  --expect-ramdisk-file-sha256 "init.rc=$expected_base_init_sha256" \
  --expect-ramdisk-file-sha256 "init.recovery.m86.rc=$expected_device_init_sha256" \
  --expect-ramdisk-file-sha256 "sbin/permissive.sh=$expected_wrapper_sha256" \
  --expect-ramdisk-file-sha256 "sbin/recovery=$expected_recovery_sha256" \
  --expect-ramdisk-file-sha256 "sbin/libminuitwrp.so=$expected_minui_sha256" \
  --expect-ramdisk-file-sha256 "sbin/adbd=$expected_adbd_sha256" \
  --expect-ramdisk-file-sha256 "etc/recovery.fstab=$expected_fstab_sha256" \
  --expect-ramdisk-elf sbin/recovery \
  --expect-ramdisk-elf sbin/libminuitwrp.so \
  --expect-ramdisk-elf sbin/adbd \
  --max-size "$conservative_image_limit" >"$base_header"
require_line "file_size=$expected_base_size" "$base_header"
require_line "kernel_sha256=$expected_kernel_sha256" "$base_header"
require_line "ramdisk_sha256=$expected_base_ramdisk_sha256" "$base_header"
require_line 'image_id_scheme=conditional-dtb' "$base_header"

for pass_spec in "ONE:$pass_one" "TWO:$pass_two"; do
  pass_name="${pass_spec%%:*}"
  pass_dir="${pass_spec#*:}"
  rewrite_log="$staged_artifact/RAMDISK-REWRITE-PASS-$pass_name.txt"

  python3 "$rewriter" \
    --base-boot-image "$base_image" \
    --expect-base-sha256 "$expected_base_sha256" \
    --replace-data "init.rc=$replacement_init" \
    --compression gzip \
    --output "$pass_dir/ramdisk.gzip" >"$rewrite_log"
  require_line 'base_entry_count_including_trailer=489' "$rewrite_log"
  require_line 'output_entry_count_including_trailer=489' "$rewrite_log"
  require_line 'added_paths=' "$rewrite_log"
  require_line 'removed_paths=' "$rewrite_log"
  require_line 'changed_data_paths=init.rc' "$rewrite_log"
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
  printf 'The two clean v17 repacks are not byte-identical.\n' >&2
  exit 1
fi

cp "$pass_one/ramdisk.gzip" "$staged_artifact/ramdisk.gzip"
cp "$pass_one/recovery.img" "$staged_artifact/recovery.img"
cp "$replacement_init" "$staged_artifact/provenance/init-v17.rc"
cp "$inspector" "$staged_artifact/provenance/inspect-android-boot-image.py"
cp "$repacker" "$staged_artifact/provenance/repack-android-boot-image.py"
cp "$rewriter" "$staged_artifact/provenance/rewrite-newc-ramdisk.py"
cp "${BASH_SOURCE[0]}" \
  "$staged_artifact/provenance/build-pro5-twrp-meizu-usb-v17.sh"

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
  --expect-ramdisk-file-sha256 "init.recovery.m86.rc=$expected_device_init_sha256" \
  --expect-ramdisk-file-sha256 "sbin/permissive.sh=$expected_wrapper_sha256" \
  --expect-ramdisk-file-sha256 "sbin/recovery=$expected_recovery_sha256" \
  --expect-ramdisk-file-sha256 "sbin/libminuitwrp.so=$expected_minui_sha256" \
  --expect-ramdisk-file-sha256 "sbin/adbd=$expected_adbd_sha256" \
  --expect-ramdisk-file-sha256 "etc/recovery.fstab=$expected_fstab_sha256" \
  --expect-ramdisk-elf sbin/recovery \
  --expect-ramdisk-elf sbin/libminuitwrp.so \
  --expect-ramdisk-elf sbin/adbd \
  --max-size "$conservative_image_limit" >"$output_header"
require_line "kernel_sha256=$expected_kernel_sha256" "$output_header"
require_line 'image_id_scheme=conditional-dtb' "$output_header"
require_line 'dt_size=0' "$output_header"

artifact_size="$(wc -c <"$staged_artifact/recovery.img" | tr -d ' ')"
artifact_sha256="$(sha256_of "$staged_artifact/recovery.img")"
ramdisk_size="$(wc -c <"$staged_artifact/ramdisk.gzip" | tr -d ' ')"
ramdisk_sha256="$(sha256_of "$staged_artifact/ramdisk.gzip")"
conservative_margin=$((conservative_image_limit - artifact_size))
partition_margin=$((recovery_partition_size - artifact_size))
built_at="$(date '+%Y-%m-%dT%H:%M:%S%z')"

cat >"$staged_artifact/METADATA.txt" <<EOF
artifact_role=test-only TWRP v17 Flyme USB identity diagnostic
artifact_generation=v17
artifact_file=recovery.img
artifact_size=$artifact_size
artifact_sha256=$artifact_sha256
built_at=$built_at
base_image=$base_image
base_recovery_sha256=$expected_base_sha256
changed_data_paths=init.rc
changed_metadata_paths=none
usb_id=2A45:0C02
usb_manufacturer=Meizu
usb_product=M86
usb_serial=860BDNA2225S
usb_functions=adb
ramdisk_entry_count_including_trailer=489
ramdisk_size=$ramdisk_size
ramdisk_sha256=$ramdisk_sha256
kernel_sha256=$expected_kernel_sha256
recovery_elf_sha256=$expected_recovery_sha256
minuitwrp_sha256=$expected_minui_sha256
adbd_sha256=$expected_adbd_sha256
image_id_scheme=conditional-dtb
embedded_dtb_size=0
required_external_dtb=Flyme 8.0.5.0A stock DTB
required_external_dtb_sha256=$expected_stock_dtb_sha256
conservative_image_limit=$conservative_image_limit
conservative_image_margin=$conservative_margin
recovery_partition_size=$recovery_partition_size
recovery_partition_margin=$partition_margin
reproducibility=two byte-identical ramdisk and recovery repacks
final_acceptance=no; device USB enumeration test required
EOF

cat >"$staged_artifact/REPRODUCIBILITY.txt" <<EOF
pass_one_ramdisk_sha256=$(sha256_of "$pass_one/ramdisk.gzip")
pass_two_ramdisk_sha256=$(sha256_of "$pass_two/ramdisk.gzip")
ramdisk_byte_identical=yes
pass_one_recovery_sha256=$(sha256_of "$pass_one/recovery.img")
pass_two_recovery_sha256=$(sha256_of "$pass_two/recovery.img")
recovery_byte_identical=yes
EOF

cat >"$staged_artifact/README.md" <<EOF
# PRO 5 TWRP Flyme USB identity diagnostic v17

This image starts from the exact v16 recovery and changes only the data
payload of \`init.rc\`. The kernel, framebuffer library, recovery executable,
adbd, synchronous logger, fstab, remaining ramdisk paths and boot geometry are
unchanged.

The recovery publishes USB VID:PID \`2A45:0C02\`, manufacturer \`Meizu\`,
product \`M86\` and serial \`860BDNA2225S\`, matching the identity observed
while Flyme exposed MTP+ADB. The diagnostic recovery still requests only the
\`adb\` function so the test isolates descriptor/host matching; MTP remains
disabled.

## Exact artifact

- size: $artifact_size bytes
- SHA-256: \`$artifact_sha256\`
- embedded DTB: none
- required external DTB: unchanged Flyme 8.0.5.0A stock DTB,
  SHA-256 \`$expected_stock_dtb_sha256\`

Flash only the recovery partition. Do not change the DTB or write any boot,
firmware, parameter or identity partition.
EOF

(
  cd "$staged_artifact"
  find . -type f ! -name SHA256SUMS -print | LC_ALL=C sort | \
    while IFS= read -r artifact_file; do
      sha256sum "$artifact_file"
    done | sed 's#  \./#  #' >SHA256SUMS
  sha256sum --quiet -c SHA256SUMS
)

mv "$staged_artifact" "$artifact_dir"
trap - EXIT
cleanup

printf 'Built PRO 5 TWRP Flyme USB identity diagnostic v17.\n'
printf 'artifact_dir=%s\n' "$artifact_dir"
printf 'recovery_size=%s\n' "$artifact_size"
printf 'recovery_sha256=%s\n' "$artifact_sha256"
printf 'changed_data_paths=init.rc\n'
printf 'usb_identity=2A45:0C02/860BDNA2225S\n'
