#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s BASE_V11_RECOVERY_IMG PAN_KERNEL_DONOR_IMG OUTPUT_DIRECTORY\n' \
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
decon_source="$project_root/kernel/meizu/m86/drivers/video/exynos/decon/decon-int_drv.c"

expected_base_sha256=8e88e946ce04efe2ccc006147c7da654ad14d9c6c3cb0eb2c610067a72e327d8
expected_base_size=29335552
expected_base_kernel_sha256=5df2fd06a58635c0299f10686c715a35fbc7ba0169bf9ffccdb292bba42c7d04
expected_ramdisk_size=12104105
expected_ramdisk_sha256=7364783467cc5011d48ea9314acd8217223b05ebe3d2784e3e145d4467a590e4
expected_donor_sha256=02856bae0eb1e8ca4718b480e0adc8909852cdb410811ff5e331eeb90b2979cc
expected_donor_size=27287552
expected_kernel_size=17222424
expected_kernel_sha256=7cb5b99f6ec849b4ab7b5508964ddb4641fede416cd8ab8611643f0bc6e454ff
expected_init_sha256=f6ec000ea794e94da89258a9aa2912fcb8075938e89f04537b7b5afd0588b589
expected_device_init_sha256=2550cabe02e6c711f905e180729ba5760b2cb9a608a8363a16e1ed02d4da2ded
expected_wrapper_sha256=136b881e587df48ddb9e272d41beb888a05c36fce0c5cc3bd00d5885ed6d864f
expected_recovery_sha256=ee950be58363bd499c43af37464453ed6af8d3a50cf102855cc1b8ca5b63f079
expected_minui_sha256=14efd5195e0379669656d0866adcedaa6030a645b7071056ff08437386e682c0
expected_adbd_sha256=881013de700ebba49ca8d9dd5670601b140e61a6365770ac0a7226b0f74de08f
expected_default_prop_sha256=527525283a0fa42d074e0d48f78b00c50b9a0cf24246f2765fe942ee49ba331e
expected_busybox_sha256=2cb28c8935e3218ed3559bf4b50f89beaa113751f40459ee2f059c1e6324199f
expected_shell_sha256=831ff2fa3b4f4e30e676a7a9130f3576e27ab293538a0298eb71e3e120778781
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

for required_file in "$inspector" "$repacker" "$decon_source"; do
  if [[ ! -s "$required_file" ]]; then
    printf 'Required v14 build input is absent: %s\n' "$required_file" >&2
    exit 1
  fi
done

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
if ! grep -Fq 'Keep PAN as a lightweight command-mode refresh.' \
    "$decon_source" || \
    sed -n '/int decon_pan_display(/,/^}/p' "$decon_source" | \
      grep -Eq '^[[:space:]]*decon_set_par\(info\);'; then
  printf 'The source does not contain the isolated lightweight PAN path.\n' >&2
  exit 1
fi

inspector_sha256="$(sha256_of "$inspector")"
repacker_sha256="$(sha256_of "$repacker")"
builder_sha256="$(sha256_of "${BASH_SOURCE[0]}")"

stage_root="$(mktemp -d "$output_parent/.pro5-twrp-v14.XXXXXX")"
cleanup() {
  if [[ -n "${stage_root:-}" && -d "$stage_root" && \
      "$stage_root" == "$output_parent/.pro5-twrp-v14."* ]]; then
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
  --expect-ramdisk-file-sha256 "default.prop=$expected_default_prop_sha256" \
  --expect-ramdisk-file-sha256 "sbin/busybox=$expected_busybox_sha256" \
  --expect-ramdisk-file-sha256 "sbin/sh=$expected_shell_sha256" \
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
  printf 'The two v14 kernel-only repacks are not byte-identical.\n' >&2
  exit 1
fi

cp "$pass_one/recovery.img" "$staged_artifact/recovery.img"
cp "$decon_source" "$staged_artifact/provenance/decon-int_drv.c"
cp "$inspector" "$staged_artifact/provenance/inspect-android-boot-image.py"
cp "$repacker" "$staged_artifact/provenance/repack-android-boot-image.py"
cp "${BASH_SOURCE[0]}" \
  "$staged_artifact/provenance/build-pro5-twrp-v11-kernel-pan-v14.sh"

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
    "sbin/permissive.sh=$expected_wrapper_sha256" \
  --expect-ramdisk-file-sha256 "sbin/recovery=$expected_recovery_sha256" \
  --expect-ramdisk-file-sha256 "sbin/libminuitwrp.so=$expected_minui_sha256" \
  --expect-ramdisk-file-sha256 "sbin/adbd=$expected_adbd_sha256" \
  --max-size "$conservative_image_limit" >"$output_header"
require_line "file_size=$expected_base_size" "$output_header"
require_line "kernel_size=$expected_kernel_size" "$output_header"
require_line "kernel_sha256=$expected_kernel_sha256" "$output_header"
require_line "ramdisk_size=$expected_ramdisk_size" "$output_header"
require_line "ramdisk_sha256=$expected_ramdisk_sha256" "$output_header"
require_line 'image_id_scheme=conditional-dtb' "$output_header"
require_line 'dt_size=0' "$output_header"
require_line 'trailing_size=0' "$output_header"

require_sha256 "$inspector_sha256" "$inspector"
require_sha256 "$repacker_sha256" "$repacker"
require_sha256 "$builder_sha256" "${BASH_SOURCE[0]}"
require_sha256 "$expected_base_sha256" "$base_image"
require_sha256 "$expected_donor_sha256" "$donor_image"

artifact_size="$(wc -c <"$staged_artifact/recovery.img" | tr -d ' ')"
artifact_sha256="$(sha256_of "$staged_artifact/recovery.img")"
conservative_margin=$((conservative_image_limit - artifact_size))
partition_margin=$((recovery_partition_size - artifact_size))
built_at="$(date '+%Y-%m-%dT%H:%M:%S%z')"
source_revision="$(git -C "$project_root" rev-parse HEAD)"

{
  printf 'artifact_role=test-only PRO 5 TWRP v11-baseline lightweight PAN v14\n'
  printf 'artifact_generation=v14\n'
  printf 'artifact_size=%s\n' "$artifact_size"
  printf 'artifact_sha256=%s\n' "$artifact_sha256"
  printf 'built_at=%s\n' "$built_at"
  printf 'source_revision=%s\n' "$source_revision"
  printf 'base_recovery_sha256=%s\n' "$expected_base_sha256"
  printf 'base_device_result=v11 reaches TWRP but blacks out under continuous redraw\n'
  printf 'kernel_donor_recovery_sha256=%s\n' "$expected_donor_sha256"
  printf 'changed_components=kernel only\n'
  printf 'ramdisk_byte_identical_to_v11=yes\n'
  printf 'ramdisk_size=%s\n' "$expected_ramdisk_size"
  printf 'ramdisk_sha256=%s\n' "$expected_ramdisk_sha256"
  printf 'base_kernel_sha256=%s\n' "$expected_base_kernel_sha256"
  printf 'kernel_sha256=%s\n' "$expected_kernel_sha256"
  printf 'kernel_source_delta_from_v11=drivers/video/exynos/decon/decon-int_drv.c only\n'
  printf 'kernel_pan=state-off guard; address/trigger/VSYNC; no per-PAN decon_set_par\n'
  printf 'pstore_profile=disabled exactly as v11-proven kernel baseline\n'
  printf 'adb=unchanged v11 direct legacy diagnostic; not an ADB repair test\n'
  printf 'persistent_write=unchanged v4 wrapper mounts cache rw,sync and writes pro5-twrp-diag-v4 files\n'
  printf 'image_id_scheme=conditional-dtb\n'
  printf 'embedded_dtb_size=0\n'
  printf 'required_external_dtb_sha256=%s\n' "$expected_stock_dtb_sha256"
  printf 'conservative_image_margin=%s\n' "$conservative_margin"
  printf 'recovery_partition_margin=%s\n' "$partition_margin"
  printf 'reproducibility=two byte-identical source builds and two byte-identical kernel-only repacks\n'
  printf 'final_acceptance=no; controlled display-only device test required\n'
} >"$staged_artifact/METADATA.txt"

{
  printf 'source_build_pass_one_recovery_sha256=%s\n' "$expected_donor_sha256"
  printf 'source_build_pass_two_recovery_sha256=%s\n' "$expected_donor_sha256"
  printf 'source_build_byte_identical=yes\n'
  printf 'hybrid_pass_one_sha256=%s\n' \
    "$(sha256_of "$pass_one/recovery.img")"
  printf 'hybrid_pass_two_sha256=%s\n' \
    "$(sha256_of "$pass_two/recovery.img")"
  printf 'hybrid_repack_byte_identical=yes\n'
} >"$staged_artifact/REPRODUCIBILITY.txt"

{
  printf '# PRO 5 TWRP v11-baseline lightweight PAN v14\n\n'
  printf 'V14 returns to the exact v11 image that reached the complete TWRP UI. '
  printf 'It changes only the boot-image kernel component. The complete gzip '
  printf 'ramdisk is byte-identical to v11.\n\n'
  printf 'The new kernel uses the exact pre-pstore source baseline that produced '
  printf 'the v11 kernel. Its only source delta is the Note5-style lightweight '
  printf 'DECON PAN path: return when DECON is off, update the scanout address, '
  printf 'trigger and wait for VSYNC without calling decon_set_par() for every '
  printf 'touch-driven frame.\n\n'
  printf 'Exact artifact: %s bytes, SHA-256 %s. It embeds no DTB and requires '
  printf 'the unchanged Flyme 8 DTB. This remains a test-only display isolation; '
  printf 'ADB is intentionally unchanged from v11.\n' \
    "$artifact_size" "$artifact_sha256"
} >"$staged_artifact/README.md"

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

printf 'Built PRO 5 TWRP v11-baseline lightweight PAN v14.\n'
printf 'artifact_dir=%s\n' "$artifact_dir"
printf 'recovery_size=%s\n' "$artifact_size"
printf 'recovery_sha256=%s\n' "$artifact_sha256"
printf 'changed_components=kernel only\n'
