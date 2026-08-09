#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s BASE_V4_RECOVERY_IMG SINGLE_BUFFER_DONOR_IMG OUTPUT_DIRECTORY\n' \
    "$(basename "$0")" >&2
}

if (( $# != 3 )); then
  usage
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
boot_image_inspector="$script_dir/inspect-android-boot-image.py"
boot_image_repacker="$script_dir/repack-android-boot-image.py"
ramdisk_rewriter="$script_dir/rewrite-newc-ramdisk.py"

expected_base_sha256=929308abf56395ab6ec74d5f53734d5b90f7ce6a45086680e207002e3f6f6029
expected_base_size=29335552
expected_base_ramdisk_sha256=54d9071c1720f7460b5518179e0a95b09c4d36ad20d14e0a9443692eb08ba010
expected_donor_sha256=370064ffa114783119fed8eea52ca6505a47954f62a1db309d7f268462b9c704
expected_donor_size=27303936
expected_kernel_sha256=5df2fd06a58635c0299f10686c715a35fbc7ba0169bf9ffccdb292bba42c7d04
expected_init_sha256=f1e17f7d93dad91efa607098495debda771429a8ba326c0ab6ba9e883811ee70
expected_wrapper_sha256=136b881e587df48ddb9e272d41beb888a05c36fce0c5cc3bd00d5885ed6d864f
expected_recovery_elf_sha256=0b31d94944fe11b1bf2ead63753b0ad2bfd3358073755150b3a6c900b6179e51
expected_base_minui_sha256=35698bff0cead8468880ac09a581b2ea0a5614daef889bb1e751a53bfd7b3cc0
expected_single_buffer_minui_sha256=ecd2d3dedced81b9122c9fedcb32f278e9d914e2a923dc4bf85cd571ab4cc8f1
expected_single_buffer_minui_size=398968
expected_busybox_sha256=2cb28c8935e3218ed3559bf4b50f89beaa113751f40459ee2f059c1e6324199f
expected_shell_sha256=831ff2fa3b4f4e30e676a7a9130f3576e27ab293538a0298eb71e3e120778781
expected_device_init_sha256=2550cabe02e6c711f905e180729ba5760b2cb9a608a8363a16e1ed02d4da2ded
expected_recovery_fstab_sha256=e493296b929734453dce9740503c66070f7cdf911b88df3e89a049bf0e062e48
expected_stock_dtb_sha256=b45054fa87a5ffe114843953172d48d36408e1f93db35a6cbdfb0a8fc58a2165
conservative_image_limit=33550336
recovery_partition_size=33554432
artifact_generation=v5
artifact_description='single-buffer fbdev repair'
base_device_result='TWRP stops after Using fbdev graphics with double buffering'
required_page_zero_marker=''
required_refresh_marker=''
required_precopy_vsync_marker=''
required_legacy_geometry_marker=''
required_force_mode_marker=''

page_zero_v6="${PRO5_TWRP_PAGE_ZERO_V6:-0}"
command_refresh_v7="${PRO5_TWRP_COMMAND_REFRESH_V7:-0}"
precopy_vsync_v11="${PRO5_TWRP_PRECOPY_VSYNC_V11:-0}"
legacy_pan_v12="${PRO5_TWRP_LEGACY_PAN_V12:-0}"
legacy_force_mode_v16="${PRO5_TWRP_LEGACY_FORCE_MODE_V16:-0}"
if [[ "$page_zero_v6" != "0" && "$page_zero_v6" != "1" ]]; then
  printf 'Invalid PRO5_TWRP_PAGE_ZERO_V6 value: %s\n' \
    "$page_zero_v6" >&2
  exit 2
fi
if [[ "$command_refresh_v7" != "0" && "$command_refresh_v7" != "1" ]]; then
  printf 'Invalid PRO5_TWRP_COMMAND_REFRESH_V7 value: %s\n' \
    "$command_refresh_v7" >&2
  exit 2
fi
if [[ "$precopy_vsync_v11" != "0" && "$precopy_vsync_v11" != "1" ]]; then
  printf 'Invalid PRO5_TWRP_PRECOPY_VSYNC_V11 value: %s\n' \
    "$precopy_vsync_v11" >&2
  exit 2
fi
if [[ "$legacy_pan_v12" != "0" && "$legacy_pan_v12" != "1" ]]; then
  printf 'Invalid PRO5_TWRP_LEGACY_PAN_V12 value: %s\n' \
    "$legacy_pan_v12" >&2
  exit 2
fi
if [[ "$legacy_force_mode_v16" != "0" && \
    "$legacy_force_mode_v16" != "1" ]]; then
  printf 'Invalid PRO5_TWRP_LEGACY_FORCE_MODE_V16 value: %s\n' \
    "$legacy_force_mode_v16" >&2
  exit 2
fi
selected_generation_count=$((
  page_zero_v6 + command_refresh_v7 + precopy_vsync_v11 + legacy_pan_v12 +
    legacy_force_mode_v16
))
if ((selected_generation_count > 1)); then
  printf 'Select only one TWRP artifact generation.\n' >&2
  exit 2
fi

if [[ "$legacy_force_mode_v16" == "1" ]]; then
  artifact_generation=v16
  artifact_description='legacy forced-mode framebuffer initialization repair'
  expected_base_sha256=4e4320b297c3ca086a697f488f0ddaca5017f62e40512fb1b980eb2f2b642463
  expected_base_size=29335552
  expected_base_ramdisk_sha256=a5644b67e806609aec4dcb3c5f46e1cbe0658312eec981bdcdc9271d0cbad5e1
  expected_donor_sha256=b445ddea63a95ce2c48f29069ae6e188c4bc4ccd6aff0737554c175414d10cd6
  expected_donor_size=27303936
  expected_init_sha256=f6ec000ea794e94da89258a9aa2912fcb8075938e89f04537b7b5afd0588b589
  expected_recovery_elf_sha256=ee950be58363bd499c43af37464453ed6af8d3a50cf102855cc1b8ca5b63f079
  expected_base_minui_sha256=84ce54a1df62e76ef58838edb3b94a200f0eb3f4ce05aeaad68265783826b0ed
  expected_single_buffer_minui_sha256=9f77e4ef45c36d85b20e4e502e9f4a3e5de5f2467d0a27ad97ef36ec54eca18b
  expected_single_buffer_minui_size=398976
  base_device_result='v12 shows a top white line and intermittent full frames after UI transitions'
  required_refresh_marker='forced single-buffer flips refresh with FBIOPAN_DISPLAY'
  required_precopy_vsync_marker='forced single-buffer pre-copy vsync failed'
  required_legacy_geometry_marker='legacy single-buffer keeps kernel framebuffer geometry'
  required_force_mode_marker='replayed legacy forced single-buffer fb0 mode'
elif [[ "$legacy_pan_v12" == "1" ]]; then
  artifact_generation=v12
  artifact_description='legacy single-buffer initialization contract repair'
  expected_base_sha256=8e88e946ce04efe2ccc006147c7da654ad14d9c6c3cb0eb2c610067a72e327d8
  expected_base_size=29335552
  expected_base_ramdisk_sha256=7364783467cc5011d48ea9314acd8217223b05ebe3d2784e3e145d4467a590e4
  expected_donor_sha256=331087361e2bd02f7628793d7361117df52ba0184329961b509ad82a25db6471
  expected_donor_size=27303936
  expected_init_sha256=f6ec000ea794e94da89258a9aa2912fcb8075938e89f04537b7b5afd0588b589
  expected_recovery_elf_sha256=ee950be58363bd499c43af37464453ed6af8d3a50cf102855cc1b8ca5b63f079
  expected_base_minui_sha256=14efd5195e0379669656d0866adcedaa6030a645b7071056ff08437386e682c0
  expected_single_buffer_minui_sha256=84ce54a1df62e76ef58838edb3b94a200f0eb3f4ce05aeaad68265783826b0ed
  expected_single_buffer_minui_size=398976
  base_device_result='v11 UI blacks out during continuous interaction; ADB never enumerates'
  required_refresh_marker='forced single-buffer flips refresh with FBIOPAN_DISPLAY'
  required_precopy_vsync_marker='forced single-buffer pre-copy vsync failed'
  required_legacy_geometry_marker='legacy single-buffer keeps kernel framebuffer geometry'
elif [[ "$precopy_vsync_v11" == "1" ]]; then
  artifact_generation=v11
  artifact_description='single-buffer pre-copy VSYNC pacing repair'
  expected_base_sha256=6d1455bd633e439158df6b13602cc26344eeea0bdcc56ac7614ceaef35fc5690
  expected_base_size=29335552
  expected_base_ramdisk_sha256=15ef31a42fbc1be6d3e6e27e0639b3fadf8bf0ce1a01442c1326a3046d233ff6
  expected_donor_sha256=bdfc2aa9ac4401614572d92c48eb72a2151dacf569ee95b09032e062376e4697
  expected_donor_size=27308032
  expected_init_sha256=f6ec000ea794e94da89258a9aa2912fcb8075938e89f04537b7b5afd0588b589
  expected_recovery_elf_sha256=ee950be58363bd499c43af37464453ed6af8d3a50cf102855cc1b8ca5b63f079
  expected_base_minui_sha256=d59012dd3491f0dc12b542a09648b1a1fdeba410cf360fca608f96abbc848cfe
  expected_single_buffer_minui_sha256=14efd5195e0379669656d0866adcedaa6030a645b7071056ff08437386e682c0
  expected_single_buffer_minui_size=398968
  base_device_result='v9 blacks out during continuous touch; v7 PAN reprograms DECON on every changed frame'
  required_page_zero_marker='forcing single-buffer scanout to framebuffer page 0'
  required_refresh_marker='forced single-buffer flips refresh with FBIOPAN_DISPLAY'
  required_precopy_vsync_marker='forced single-buffer pre-copy vsync failed'
elif [[ "$command_refresh_v7" == "1" ]]; then
  artifact_generation=v7
  artifact_description='single-buffer page-zero command refresh repair'
  expected_base_sha256=398dc69d5af4b9210b09c27d8a50e16edeaebbbf7f4844d3efefaa402c6934c8
  expected_base_size=29335552
  expected_base_ramdisk_sha256=27a43742f3245a9b92c7054d225cbd76159873114c01df49b74b3324409e2690
  expected_donor_sha256=dc2b15534fcb678889064fc1cedb55912398f523e0f03a6b5ae4563ce74590ab
  expected_donor_size=27303936
  expected_base_minui_sha256=e051032762c474654192460e85c94144b368d9a1d441435a603088955a032978
  expected_single_buffer_minui_sha256=d59012dd3491f0dc12b542a09648b1a1fdeba410cf360fca608f96abbc848cfe
  expected_single_buffer_minui_size=398968
  base_device_result='TWRP reaches main GUI but unrefreshed page 0 remains black'
  required_page_zero_marker='forcing single-buffer scanout to framebuffer page 0'
  required_refresh_marker='forced single-buffer flips refresh with FBIOPAN_DISPLAY'
elif [[ "$page_zero_v6" == "1" ]]; then
  artifact_generation=v6
  artifact_description='single-buffer page-zero scanout repair'
  expected_base_sha256=23db8d86e7b6523b2a4ad1c8ed2b2bbd319d490d05d57381f3670dbad42f5fe1
  expected_base_size=29335552
  expected_base_ramdisk_sha256=32603758753db481881eb1f7b1527e469f0641aa64a732cb31bb7aac7792238d
  expected_donor_sha256=7cbef6a30c2a380b479266b5399c6a6647c897950519e96f8473ff50e64f886c
  expected_donor_size=27308032
  expected_base_minui_sha256=ecd2d3dedced81b9122c9fedcb32f278e9d914e2a923dc4bf85cd571ab4cc8f1
  expected_single_buffer_minui_sha256=e051032762c474654192460e85c94144b368d9a1d441435a603088955a032978
  expected_single_buffer_minui_size=398968
  base_device_result='TWRP reaches main GUI but DECON retains the bootloader logo page'
  required_page_zero_marker='forcing single-buffer scanout to framebuffer page 0'
fi

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
  "$boot_image_inspector" \
  "$boot_image_repacker" \
  "$ramdisk_rewriter"; do
  if [[ ! -s "$required_file" ]]; then
    printf 'Required v5 build input is absent: %s\n' "$required_file" >&2
    exit 1
  fi
done

base_input="$1"
donor_input="$2"
for image_spec in "base:$base_input" "donor:$donor_input"; do
  image_role="${image_spec%%:*}"
  image_path="${image_spec#*:}"
  if [[ ! -f "$image_path" ]]; then
    printf 'The %s image is absent: %s\n' "$image_role" "$image_path" >&2
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

inspector_sha256="$(sha256_of "$boot_image_inspector")"
repacker_sha256="$(sha256_of "$boot_image_repacker")"
rewriter_sha256="$(sha256_of "$ramdisk_rewriter")"
builder_sha256="$(sha256_of "${BASH_SOURCE[0]}")"

stage_root="$(mktemp -d \
  "$output_parent/.pro5-twrp-${artifact_generation}.XXXXXX")"
cleanup() {
  if [[ -n "${stage_root:-}" && -d "$stage_root" && \
    "$stage_root" == \
      "$output_parent/.pro5-twrp-${artifact_generation}."* ]]; then
    rm -r -- "$stage_root"
  fi
}
trap cleanup EXIT

work_dir="$stage_root/work"
pass_one="$work_dir/pass-one"
pass_two="$work_dir/pass-two"
donor_lib="$work_dir/libminuitwrp-single-buffer.so"
staged_artifact="$stage_root/artifact"
mkdir -p "$pass_one" "$pass_two" "$staged_artifact/provenance"

base_header="$staged_artifact/BASE-RECOVERY-HEADER.txt"
python3 "$boot_image_inspector" "$base_image" \
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
  --expect-ramdisk-file-sha256 \
    "init.rc=$expected_init_sha256" \
  --expect-ramdisk-file-sha256 \
    "init.recovery.m86.rc=$expected_device_init_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/permissive.sh=$expected_wrapper_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/recovery=$expected_recovery_elf_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/libminuitwrp.so=$expected_base_minui_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/busybox=$expected_busybox_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/sh=$expected_shell_sha256" \
  --expect-ramdisk-file-sha256 \
    "etc/recovery.fstab=$expected_recovery_fstab_sha256" \
  --expect-ramdisk-elf sbin/recovery \
  --expect-ramdisk-elf sbin/libminuitwrp.so \
  --expect-ramdisk-elf sbin/busybox \
  --expect-ramdisk-elf sbin/sh \
  --max-size "$conservative_image_limit" >"$base_header"
require_line "file_size=$expected_base_size" "$base_header"
require_line "kernel_sha256=$expected_kernel_sha256" "$base_header"
require_line "ramdisk_sha256=$expected_base_ramdisk_sha256" "$base_header"
require_line 'image_id_scheme=conditional-dtb' "$base_header"

donor_header="$staged_artifact/DONOR-RECOVERY-HEADER.txt"
python3 "$boot_image_inspector" "$donor_image" \
  --expect-page-size 4096 \
  --expect-second-size 0 \
  --expect-dt-size 0 \
  --expect-valid-image-id \
  --expect-ramdisk-compression lzma \
  --expect-ramdisk-file-sha256 \
    "sbin/libminuitwrp.so=$expected_single_buffer_minui_sha256" \
  --expect-ramdisk-elf sbin/libminuitwrp.so \
  --extract-ramdisk-file "sbin/libminuitwrp.so=$donor_lib" \
  >"$donor_header"
require_line "file_size=$expected_donor_size" "$donor_header"
require_sha256 "$expected_single_buffer_minui_sha256" "$donor_lib"
if [[ "$(wc -c <"$donor_lib" | tr -d ' ')" != \
    "$expected_single_buffer_minui_size" ]]; then
  printf 'Unexpected single-buffer minuitwrp size.\n' >&2
  exit 1
fi
if ! strings -a "$donor_lib" | \
    grep -Fx 'RECOVERY_GRAPHICS_FORCE_SINGLE_BUFFER := true' >/dev/null; then
  printf 'The donor minuitwrp does not prove the single-buffer build flag.\n' >&2
  exit 1
fi
if strings -a "$donor_lib" | grep -Fx 'double buffered' >/dev/null; then
  printf 'The donor minuitwrp still contains the double-buffer branch.\n' >&2
  exit 1
fi
if ! strings -a "$donor_lib" | grep -Fx 'single buffered' >/dev/null; then
  printf 'The donor minuitwrp omits the single-buffer runtime marker.\n' >&2
  exit 1
fi
if [[ -n "$required_page_zero_marker" ]] && \
    ! strings -a "$donor_lib" | \
      grep -Fx "$required_page_zero_marker" >/dev/null; then
  printf 'The donor minuitwrp omits the page-zero scanout marker.\n' >&2
  exit 1
fi
if [[ -n "$required_refresh_marker" ]] && \
    ! strings -a "$donor_lib" | \
      grep -Fx "$required_refresh_marker" >/dev/null; then
  printf 'The donor minuitwrp omits the command-mode refresh marker.\n' >&2
  exit 1
fi
if [[ -n "$required_precopy_vsync_marker" ]] && \
    ! strings -a "$donor_lib" | \
      grep -Fx "$required_precopy_vsync_marker" >/dev/null; then
  printf 'The donor minuitwrp omits the pre-copy VSYNC marker.\n' >&2
  exit 1
fi
if [[ -n "$required_legacy_geometry_marker" ]] && \
    ! strings -a "$donor_lib" | \
      grep -Fx "$required_legacy_geometry_marker" >/dev/null; then
  printf 'The donor minuitwrp omits the legacy geometry marker.\n' >&2
  exit 1
fi
if [[ -n "$required_force_mode_marker" ]] && \
    ! strings -a "$donor_lib" | \
      grep -Fx "$required_force_mode_marker" >/dev/null; then
  printf 'The donor minuitwrp omits the forced-mode initialization marker.\n' >&2
  exit 1
fi

for pass_spec in "ONE:$pass_one" "TWO:$pass_two"; do
  pass_name="${pass_spec%%:*}"
  pass_dir="${pass_spec#*:}"
  rewrite_log="$staged_artifact/RAMDISK-REWRITE-PASS-$pass_name.txt"

  python3 "$ramdisk_rewriter" \
    --base-boot-image "$base_image" \
    --expect-base-sha256 "$expected_base_sha256" \
    --replace-data "sbin/libminuitwrp.so=$donor_lib" \
    --compression gzip \
    --output "$pass_dir/ramdisk.gzip" >"$rewrite_log"
  require_line 'base_entry_count_including_trailer=489' "$rewrite_log"
  require_line 'output_entry_count_including_trailer=489' "$rewrite_log"
  require_line 'added_paths=' "$rewrite_log"
  require_line 'removed_paths=' "$rewrite_log"
  require_line 'changed_data_paths=sbin/libminuitwrp.so' "$rewrite_log"
  require_line 'changed_metadata_paths=' "$rewrite_log"
  require_line 'entry_order_identical=yes' "$rewrite_log"
  require_line 'archive_tail_identical=yes' "$rewrite_log"

  python3 "$boot_image_repacker" "$base_image" \
    --ramdisk "$pass_dir/ramdisk.gzip" \
    --image-id-scheme conditional-dtb \
    --output "$pass_dir/recovery.img"
done

if ! cmp --silent "$pass_one/ramdisk.gzip" "$pass_two/ramdisk.gzip" || \
    ! cmp --silent "$pass_one/recovery.img" "$pass_two/recovery.img"; then
  printf 'The two clean %s repacks are not byte-identical.\n' \
    "$artifact_generation" >&2
  exit 1
fi

cp "$pass_one/ramdisk.gzip" "$staged_artifact/ramdisk.gzip"
cp "$pass_one/recovery.img" "$staged_artifact/recovery.img"
cp "$donor_lib" \
  "$staged_artifact/provenance/libminuitwrp-single-buffer.so"
cp "$boot_image_inspector" \
  "$staged_artifact/provenance/inspect-android-boot-image.py"
cp "$boot_image_repacker" \
  "$staged_artifact/provenance/repack-android-boot-image.py"
cp "$ramdisk_rewriter" \
  "$staged_artifact/provenance/rewrite-newc-ramdisk.py"
cp "${BASH_SOURCE[0]}" \
  "$staged_artifact/provenance/build-pro5-twrp-single-buffer-v5.sh"

output_header="$staged_artifact/RECOVERY-HEADER.txt"
python3 "$boot_image_inspector" "$staged_artifact/recovery.img" \
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
  --expect-ramdisk-file-sha256 \
    "init.rc=$expected_init_sha256" \
  --expect-ramdisk-file-sha256 \
    "init.recovery.m86.rc=$expected_device_init_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/permissive.sh=$expected_wrapper_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/recovery=$expected_recovery_elf_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/libminuitwrp.so=$expected_single_buffer_minui_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/busybox=$expected_busybox_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/sh=$expected_shell_sha256" \
  --expect-ramdisk-file-sha256 \
    "etc/recovery.fstab=$expected_recovery_fstab_sha256" \
  --expect-ramdisk-elf sbin/recovery \
  --expect-ramdisk-elf sbin/libminuitwrp.so \
  --expect-ramdisk-elf sbin/busybox \
  --expect-ramdisk-elf sbin/sh \
  --max-size "$conservative_image_limit" >"$output_header"
require_line "kernel_sha256=$expected_kernel_sha256" "$output_header"
require_line 'image_id_scheme=conditional-dtb' "$output_header"
require_line 'dt_size=0' "$output_header"

require_sha256 "$inspector_sha256" "$boot_image_inspector"
require_sha256 "$repacker_sha256" "$boot_image_repacker"
require_sha256 "$rewriter_sha256" "$ramdisk_rewriter"
require_sha256 "$builder_sha256" "${BASH_SOURCE[0]}"
require_sha256 "$expected_base_sha256" "$base_image"
require_sha256 "$expected_donor_sha256" "$donor_image"
require_sha256 "$expected_single_buffer_minui_sha256" "$donor_lib"

artifact_size="$(wc -c <"$staged_artifact/recovery.img" | tr -d ' ')"
artifact_sha256="$(sha256_of "$staged_artifact/recovery.img")"
ramdisk_size="$(wc -c <"$staged_artifact/ramdisk.gzip" | tr -d ' ')"
ramdisk_sha256="$(sha256_of "$staged_artifact/ramdisk.gzip")"
conservative_margin=$((conservative_image_limit - artifact_size))
partition_margin=$((recovery_partition_size - artifact_size))
source_revision="$(git -C "$project_root" rev-parse HEAD)"
source_state=clean
if [[ -n "$(git -C "$project_root" status --porcelain --untracked-files=normal)" ]]; then
  source_state=dirty
fi
built_at="$(date '+%Y-%m-%dT%H:%M:%S%z')"

{
  printf 'artifact_role=test-only TWRP %s %s with synchronous log capture\n' \
    "$artifact_description" "$artifact_generation"
  printf 'artifact_generation=%s\n' "$artifact_generation"
  printf 'artifact_file=recovery.img\n'
  printf 'artifact_size=%s\n' "$artifact_size"
  printf 'artifact_sha256=%s\n' "$artifact_sha256"
  printf 'built_at=%s\n' "$built_at"
  printf 'source_revision=%s\n' "$source_revision"
  printf 'source_worktree=%s\n' "$source_state"
  printf 'base_image=%s\n' "$base_image"
  printf 'base_recovery_sha256=%s\n' "$expected_base_sha256"
  printf 'base_device_result=%s\n' "$base_device_result"
  printf 'donor_image=%s\n' "$donor_image"
  printf 'donor_recovery_sha256=%s\n' "$expected_donor_sha256"
  printf 'changed_data_paths=sbin/libminuitwrp.so\n'
  printf 'changed_metadata_paths=none\n'
  printf 'ramdisk_entry_count_including_trailer=489\n'
  printf 'ramdisk_order=byte-identical path order\n'
  printf 'ramdisk_compression=gzip\n'
  printf 'ramdisk_size=%s\n' "$ramdisk_size"
  printf 'ramdisk_sha256=%s\n' "$ramdisk_sha256"
  printf 'kernel_sha256=%s\n' "$expected_kernel_sha256"
  printf 'recovery_elf_sha256=%s\n' "$expected_recovery_elf_sha256"
  printf 'base_minuitwrp_sha256=%s\n' "$expected_base_minui_sha256"
  printf 'single_buffer_minuitwrp_sha256=%s\n' \
    "$expected_single_buffer_minui_sha256"
  printf 'single_buffer_build_flag=RECOVERY_GRAPHICS_FORCE_SINGLE_BUFFER := true\n'
  printf 'page_zero_scanout_marker=%s\n' "$required_page_zero_marker"
  printf 'command_mode_refresh_marker=%s\n' "$required_refresh_marker"
  printf 'precopy_vsync_marker=%s\n' "$required_precopy_vsync_marker"
  printf 'legacy_geometry_marker=%s\n' "$required_legacy_geometry_marker"
  printf 'legacy_force_mode_marker=%s\n' "$required_force_mode_marker"
  printf 'double_buffer_runtime_branch=absent\n'
  printf 'wrapper_sha256=%s\n' "$expected_wrapper_sha256"
  printf 'image_id_scheme=conditional-dtb\n'
  printf 'embedded_dtb_size=0\n'
  printf 'required_external_dtb=Flyme 8.0.5.0A stock DTB\n'
  printf 'required_external_dtb_sha256=%s\n' "$expected_stock_dtb_sha256"
  printf 'conservative_image_limit=%s\n' "$conservative_image_limit"
  printf 'conservative_image_margin=%s\n' "$conservative_margin"
  printf 'recovery_partition_size=%s\n' "$recovery_partition_size"
  printf 'recovery_partition_margin=%s\n' "$partition_margin"
  printf 'reproducibility=two byte-identical ramdisk and recovery repacks\n'
  printf 'persistent_write=unchanged v4 wrapper mounts cache rw,sync and writes pro5-twrp-diag-v4 files\n'
  printf 'final_acceptance=no; single-variable device test required\n'
} >"$staged_artifact/METADATA.txt"

{
  printf 'source_revision=%s\n' "$source_revision"
  printf 'source_worktree=%s\n' "$source_state"
  printf 'inspector_sha256=%s\n' "$inspector_sha256"
  printf 'repacker_sha256=%s\n' "$repacker_sha256"
  printf 'rewriter_sha256=%s\n' "$rewriter_sha256"
  printf 'builder_sha256=%s\n' "$builder_sha256"
  printf 'donor_recovery_sha256=%s\n' "$expected_donor_sha256"
  printf 'single_buffer_minuitwrp_sha256=%s\n' \
    "$expected_single_buffer_minui_sha256"
  printf '\nworktree_status:\n'
  git -C "$project_root" status --short --untracked-files=normal
} >"$staged_artifact/SOURCE-STATE.txt"

{
  printf 'pass_one_ramdisk_sha256=%s\n' \
    "$(sha256_of "$pass_one/ramdisk.gzip")"
  printf 'pass_two_ramdisk_sha256=%s\n' \
    "$(sha256_of "$pass_two/ramdisk.gzip")"
  printf 'ramdisk_byte_identical=yes\n'
  printf 'pass_one_recovery_sha256=%s\n' \
    "$(sha256_of "$pass_one/recovery.img")"
  printf 'pass_two_recovery_sha256=%s\n' \
    "$(sha256_of "$pass_two/recovery.img")"
  printf 'recovery_byte_identical=yes\n'
} >"$staged_artifact/REPRODUCIBILITY.txt"

if [[ "$artifact_generation" == "v16" ]]; then
  cat >"$staged_artifact/README.md" <<EOF
# PRO 5 TWRP legacy forced-mode initialization repair v16

V12 can enter the complete TWRP UI, but the panel shows only a white line or
turns black; changing pages can temporarily restore a complete frame. V16
starts from that exact v12 image and changes only the data payload of
\`sbin/libminuitwrp.so\`.

Fresh disassembly of the known-working TWRP 3.0 library corrects the earlier
initialization model. Immediately after FBIOGET_VSCREENINFO it clears
\`vi.vmode\`, sets \`vi.activate = FB_ACTIVATE_FORCE\`, and replays the
kernel-provided structure through FBIOPUT_VSCREENINFO before querying fixed
geometry or mapping framebuffer memory. V16 reproduces that one-time mode
transaction exactly. It retains v12's single page, pre-copy VSYNC and
post-copy page-zero PAN path, and never selects \`yoffset=1920\`.

The original v12 kernel, init, recovery ELF, old adbd, synchronous wrapper,
fstab, all other ramdisk payloads and boot geometry remain byte-for-byte
unchanged.

## Exact artifact

- size: $artifact_size bytes
- SHA-256: \`$artifact_sha256\`
- embedded DTB: none
- required external DTB: unchanged Flyme 8.0.5.0A stock DTB,
  SHA-256 \`$expected_stock_dtb_sha256\`

Flash only the recovery partition for this single-variable test. Do not
change the DTB or write any boot, firmware, parameter or identity partition.
EOF
elif [[ "$artifact_generation" == "v12" ]]; then
  cat >"$staged_artifact/README.md" <<EOF
# PRO 5 TWRP legacy framebuffer initialization repair v12

V11 reached the complete TWRP UI but still turned black during continuous
interaction, and host ADB never enumerated. V12 starts from the exact flashed
and partition-verified v11 image and changes only the data payload of
\`sbin/libminuitwrp.so\`.

Disassembly of the known-working TWRP 3.0 library shows that its single-buffer
backend never calls \`FBIOPUT_VSCREENINFO\` during initialization. It retains
the framebuffer geometry returned by the kernel, then performs each changed
frame as VSYNC, active-page copy and PAN. V12 matches that contract while
retaining the v11 pacing and page-zero PAN refresh. It does not select page 1
or request \`yoffset=1920\`.

The kernel, direct legacy ADB init, timeout-disabled recovery ELF, old adbd,
synchronous wrapper, fstab, all other ramdisk payloads and boot geometry are
unchanged from v11. This display-only intermediate is used as the audited base
for the Note5-style kernel and ready-first ADB candidate.

## Exact artifact

- size: $artifact_size bytes
- SHA-256: \`$artifact_sha256\`
- embedded DTB: none
- required external DTB: unchanged Flyme 8.0.5.0A stock DTB,
  SHA-256 \`$expected_stock_dtb_sha256\`

Do not flash this intermediate unless it is explicitly selected for a
single-variable test. Do not change the DTB or write any boot, firmware,
parameter or identity partition.
EOF
elif [[ "$artifact_generation" == "v11" ]]; then
  cat >"$staged_artifact/README.md" <<EOF
# PRO 5 TWRP pre-copy VSYNC pacing repair v11

The owner clarified that the display can turn black during continuous touch,
so idle timeout is not the root cause. V11 supersedes the untested v10 image.
It starts from the exact v10 image and changes only the data payload of
\`sbin/libminuitwrp.so\`.

V7 made page-zero updates visible by calling \`FBIOPAN_DISPLAY\` after each
changed frame. On the PRO 5 kernel, each PAN runs \`decon_set_par()\`, rewrites
live window state, toggles the command-mode hardware trigger and waits for
VSYNC. Touch-driven redraw bursts therefore repeatedly reprogram DECON.

Disassembly of the original working TWRP fbdev backend shows a missing ordering
constraint in the new path: its single-buffer flip waits for
\`FBIO_WAITFORVSYNC\` before overwriting the active framebuffer page, then issues
the PAN. V11 restores that exact ordering. The blocking wait also paces redraw
bursts to the panel instead of allowing back-to-back page-zero copies while a
previous command-mode transfer is active.

The v10 direct legacy ADB configuration remains unchanged: 18D1:4EE7, serial
PRO5TWRPV10, native \`/dev/android_adb\`, no FunctionFS and no USB property
actions. MTP remains disabled. The v4 synchronous cache logger is also
unchanged.

## Exact artifact

- size: $artifact_size bytes
- SHA-256: \`$artifact_sha256\`
- embedded DTB: none
- required external DTB: unchanged Flyme 8.0.5.0A stock DTB,
  SHA-256 \`$expected_stock_dtb_sha256\`

Do not flash this image until the exact artifact and command are explicitly
approved. The retained diagnostic deliberately mounts cache read-write with
synchronous I/O and creates \`/cache/recovery/pro5-twrp-diag-v4-*\` files.
Do not change the DTB or write any boot, firmware, parameter or identity
partition. Do not mount, wipe, format, install or restore.
EOF
elif [[ "$artifact_generation" == "v7" ]]; then
  cat >"$staged_artifact/README.md" <<EOF
# PRO 5 TWRP page-zero command refresh repair v7

This is a single-variable device-test candidate with the v4 synchronous log
harness retained. V6 selected framebuffer page 0 and changed the retained
bootloader logo into a pure black panel. Its exact device log nevertheless
proves that TWRP loaded the complete theme, entered the main GUI, timed out and
handled key wake without a panic, oops or watchdog reset.

The runtime kernel identifies Exynos DECON as MIPI command mode. Copying new
pixels into mapped framebuffer page 0 does not itself transmit a panel frame;
the driver's \`FBIOPAN_DISPLAY\` callback programs the page, enables the hardware
trigger and waits for VSYNC. V7 starts from the exact handset-tested v6 image
and changes only the data payload of \`sbin/libminuitwrp.so\`. It retains forced
single buffering and the initial page-zero selection, then issues
\`FBIOPAN_DISPLAY\` with \`yoffset=0\` after each page-zero copy. It never selects
page 1 or \`yoffset=1920\`.

All 489 cpio paths, path order and metadata, the proven kernel, init, patched
TWRP ELF, dependencies, resources, fstab, synchronous wrapper and boot geometry
remain identical. The replacement library comes from two byte-identical clean
source builds, and two v7 repacks are byte-identical.

## Exact artifact

- size: $artifact_size bytes
- SHA-256: \`$artifact_sha256\`
- embedded DTB: none
- required external DTB: unchanged Flyme 8.0.5.0A stock DTB,
  SHA-256 \`$expected_stock_dtb_sha256\`

Do not flash this image until the exact artifact and command are explicitly
approved. The retained diagnostic deliberately mounts cache read-write with
synchronous I/O and creates \`/cache/recovery/pro5-twrp-diag-v4-*\` files.
Do not change the DTB or write any boot, firmware, parameter or identity
partition. Do not mount, wipe, format, install, restore or perform any other
recovery write test.
EOF
elif [[ "$artifact_generation" == "v6" ]]; then
  cat >"$staged_artifact/README.md" <<EOF
# PRO 5 TWRP single-buffer page-zero scanout repair v6

This is a single-variable device-test candidate with the v4 synchronous log
harness retained. V5 proved that forced single buffering lets TWRP process
fstab, load the complete theme, enter the main GUI and handle screen timeout
and key wake. The panel nevertheless keeps displaying the bootloader Meizu
logo because upstream fbdev skips set_displayed_framebuffer(0) whenever
double_buffered is false.

V6 is built from the exact handset-tested v5 image. Only the data payload of
sbin/libminuitwrp.so changes. The replacement is extracted from the
two-clean-build source candidate. It retains
RECOVERY_GRAPHICS_FORCE_SINGLE_BUFFER := true, permits exactly the initial
page-zero scanout request, and leaves subsequent flips memcpy-only. It
contains the page-zero runtime marker and no double-buffer runtime branch.
All 489 cpio paths, path order and metadata, the proven kernel, init, patched
TWRP ELF, dependencies, resources, fstab, synchronous wrapper and boot
geometry remain identical.

## Exact artifact

- size: $artifact_size bytes
- SHA-256: $artifact_sha256
- embedded DTB: none
- required external DTB: unchanged Flyme 8.0.5.0A stock DTB,
  SHA-256 $expected_stock_dtb_sha256

Do not flash this image until the exact artifact and command are explicitly
approved. The retained diagnostic deliberately mounts cache read-write with
synchronous I/O and creates /cache/recovery/pro5-twrp-diag-v4-* files.
Do not change the DTB or write any boot, firmware, parameter or identity
partition. Do not mount, wipe, format, install, restore or perform any other
recovery write test.
EOF
else
  cat >"$staged_artifact/README.md" <<EOF
# PRO 5 TWRP single-buffer fbdev repair v5

This is a single-variable device-test candidate with the v4 synchronous log
harness retained. V4 proved that TWRP reaches fbdev, detects a 1080x1920
32-bit BGRA framebuffer, selects double buffering and stops immediately after
\`Using fbdev graphics.\`, before fstab processing. At the pinned source
revision, the next graphics path performs the first second-buffer flip and
changes the framebuffer y-offset to 1920.

V5 is built from the exact handset-tested v4 image. Only the data payload of
\`sbin/libminuitwrp.so\` changes. The replacement is extracted from the
two-clean-build source candidate compiled with
\`RECOVERY_GRAPHICS_FORCE_SINGLE_BUFFER := true\`; it contains the explicit
single-buffer runtime marker and no double-buffer runtime branch. All 489 cpio
paths, path order and metadata, the proven kernel, init, patched TWRP ELF,
dependencies, resources, fstab, synchronous wrapper and boot geometry remain
identical.

## Exact artifact

- size: $artifact_size bytes
- SHA-256: \`$artifact_sha256\`
- embedded DTB: none
- required external DTB: unchanged Flyme 8.0.5.0A stock DTB,
  SHA-256 \`$expected_stock_dtb_sha256\`

Do not flash this image until the exact artifact and command are explicitly
approved. The retained diagnostic deliberately mounts cache read-write with
synchronous I/O and creates \`/cache/recovery/pro5-twrp-diag-v4-*\` files.
Do not change the DTB or write any boot, firmware, parameter or identity
partition. Do not mount, wipe, format, install, restore or perform any other
recovery write test.
EOF
fi

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

printf 'Built PRO 5 TWRP %s %s.\n' \
  "$artifact_description" "$artifact_generation"
printf 'artifact_dir=%s\n' "$artifact_dir"
printf 'recovery_size=%s\n' "$artifact_size"
printf 'recovery_sha256=%s\n' "$artifact_sha256"
printf 'changed_data_paths=sbin/libminuitwrp.so\n'
printf 'persistent_device_write=/cache/recovery/pro5-twrp-diag-v4-*\n'
printf 'flash_authorized=no\n'
