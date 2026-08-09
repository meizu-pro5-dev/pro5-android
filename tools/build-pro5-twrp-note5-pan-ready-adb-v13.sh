#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s BASE_V12_RECOVERY_IMG NOTE5_PAN_DONOR_IMG OUTPUT_DIRECTORY\n' \
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
v13_init="$project_root/patches/twrp-diagnostics/recovery-ready-first-adb-v13.rc"
v13_wrapper="$project_root/patches/twrp-diagnostics/recovery-ready-first-wrapper-v13.sh"
decon_source="$project_root/kernel/meizu/m86/drivers/video/exynos/decon/decon-int_drv.c"

expected_base_sha256=4e4320b297c3ca086a697f488f0ddaca5017f62e40512fb1b980eb2f2b642463
expected_base_size=29335552
expected_base_kernel_sha256=5df2fd06a58635c0299f10686c715a35fbc7ba0169bf9ffccdb292bba42c7d04
expected_base_ramdisk_sha256=a5644b67e806609aec4dcb3c5f46e1cbe0658312eec981bdcdc9271d0cbad5e1
expected_donor_sha256=dba0bf646c2e82a480c02fca94bb430cd7b2f6f902a5b00899224f2f73dc6a48
expected_donor_size=27303936
expected_kernel_size=17239832
expected_kernel_sha256=aac6338d2b64f49e2988215fff186a2f229fc7d6e2545f7d9178ff307835a5e5
expected_base_init_sha256=f6ec000ea794e94da89258a9aa2912fcb8075938e89f04537b7b5afd0588b589
expected_v13_init_sha256=b640d2223630168beb12023a617ef1df6d16af82d13a98a2c9686344ea889def
expected_device_init_sha256=2550cabe02e6c711f905e180729ba5760b2cb9a608a8363a16e1ed02d4da2ded
expected_base_wrapper_sha256=136b881e587df48ddb9e272d41beb888a05c36fce0c5cc3bd00d5885ed6d864f
expected_v13_wrapper_sha256=1411c27bcc0c868bf8a8b6e135324980589b96ffcdccacf1e7091edbe38d1554
expected_recovery_sha256=ee950be58363bd499c43af37464453ed6af8d3a50cf102855cc1b8ca5b63f079
expected_minui_sha256=84ce54a1df62e76ef58838edb3b94a200f0eb3f4ce05aeaad68265783826b0ed
expected_adbd_sha256=881013de700ebba49ca8d9dd5670601b140e61a6365770ac0a7226b0f74de08f
expected_default_prop_sha256=527525283a0fa42d074e0d48f78b00c50b9a0cf24246f2765fe942ee49ba331e
expected_busybox_sha256=2cb28c8935e3218ed3559bf4b50f89beaa113751f40459ee2f059c1e6324199f
expected_shell_sha256=831ff2fa3b4f4e30e676a7a9130f3576e27ab293538a0298eb71e3e120778781
expected_recovery_fstab_sha256=e493296b929734453dce9740503c66070f7cdf911b88df3e89a049bf0e062e48
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

require_text() {
  local expected="$1"
  local source_file="$2"

  if ! grep -Fq -- "$expected" "$source_file"; then
    printf 'Required text is absent from %s: %s\n' \
      "$source_file" "$expected" >&2
    exit 1
  fi
}

for required_file in \
  "$boot_image_inspector" \
  "$boot_image_repacker" \
  "$ramdisk_rewriter" \
  "$v13_init" \
  "$v13_wrapper" \
  "$decon_source"; do
  if [[ ! -s "$required_file" ]]; then
    printf 'Required v13 build input is absent: %s\n' "$required_file" >&2
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
require_sha256 "$expected_v13_init_sha256" "$v13_init"
require_sha256 "$expected_v13_wrapper_sha256" "$v13_wrapper"

require_text 'Keep PAN as a lightweight command-mode refresh.' "$decon_source"
if sed -n '/int decon_pan_display(/,/^}/p' "$decon_source" | \
    grep -Eq '^[[:space:]]*decon_set_par\(info\);'; then
  printf 'The Note5-style PAN source still calls decon_set_par(info).\n' >&2
  exit 1
fi
require_line '    write /sys/class/android_usb/android0/idVendor 2A45' "$v13_init"
require_line '    write /sys/class/android_usb/android0/idProduct 0C01' "$v13_init"
require_line '    write /sys/class/android_usb/android0/iSerial PRO5TWRPV13' "$v13_init"
require_line '    start adbd' "$v13_init"
require_line 'service recovery /sbin/sh /sbin/permissive.sh' "$v13_init"
require_line 'service adbd /sbin/adbd' "$v13_init"
if grep -Eq '^[[:space:]]*mount[[:space:]]+functionfs' "$v13_init"; then
  printf 'The v13 init unexpectedly mounts FunctionFS.\n' >&2
  exit 1
fi
if grep -Eq '^[[:space:]]*write[[:space:]]+.*/functions[[:space:]]+adb' \
    "$v13_init"; then
  printf 'The v13 init enables ADB before the ready-first wrapper.\n' >&2
  exit 1
fi
require_text "grep -q 'adb_open'" "$v13_wrapper"
require_text 'echo adb >/sys/class/android_usb/android0/functions' "$v13_wrapper"
require_text 'echo 1 >/sys/class/android_usb/android0/enable' "$v13_wrapper"
require_text 'pro5-twrp-diag-v13-' "$v13_wrapper"
require_text 'periodic_usb_snapshot' "$v13_wrapper"

inspector_sha256="$(sha256_of "$boot_image_inspector")"
repacker_sha256="$(sha256_of "$boot_image_repacker")"
rewriter_sha256="$(sha256_of "$ramdisk_rewriter")"
builder_sha256="$(sha256_of "${BASH_SOURCE[0]}")"

stage_root="$(mktemp -d "$output_parent/.pro5-twrp-v13.XXXXXX")"
cleanup() {
  if [[ -n "${stage_root:-}" && -d "$stage_root" && \
      "$stage_root" == "$output_parent/.pro5-twrp-v13."* ]]; then
    rm -r -- "$stage_root"
  fi
}
trap cleanup EXIT

work_dir="$stage_root/work"
pass_one="$work_dir/pass-one"
pass_two="$work_dir/pass-two"
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
  --expect-ramdisk-file-sha256 "init.rc=$expected_base_init_sha256" \
  --expect-ramdisk-file-sha256 \
    "init.recovery.m86.rc=$expected_device_init_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/permissive.sh=$expected_base_wrapper_sha256" \
  --expect-ramdisk-file-sha256 "sbin/recovery=$expected_recovery_sha256" \
  --expect-ramdisk-file-sha256 "sbin/libminuitwrp.so=$expected_minui_sha256" \
  --expect-ramdisk-file-sha256 "sbin/adbd=$expected_adbd_sha256" \
  --expect-ramdisk-file-sha256 "default.prop=$expected_default_prop_sha256" \
  --expect-ramdisk-file-sha256 "sbin/busybox=$expected_busybox_sha256" \
  --expect-ramdisk-file-sha256 "sbin/sh=$expected_shell_sha256" \
  --expect-ramdisk-file-sha256 \
    "etc/recovery.fstab=$expected_recovery_fstab_sha256" \
  --expect-ramdisk-elf sbin/recovery \
  --expect-ramdisk-elf sbin/libminuitwrp.so \
  --expect-ramdisk-elf sbin/adbd \
  --expect-ramdisk-elf sbin/busybox \
  --expect-ramdisk-elf sbin/sh \
  --max-size "$conservative_image_limit" >"$base_header"
require_line "file_size=$expected_base_size" "$base_header"
require_line "kernel_sha256=$expected_base_kernel_sha256" "$base_header"
require_line "ramdisk_sha256=$expected_base_ramdisk_sha256" "$base_header"
require_line 'image_id_scheme=conditional-dtb' "$base_header"

donor_header="$staged_artifact/DONOR-RECOVERY-HEADER.txt"
python3 "$boot_image_inspector" "$donor_image" \
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

for pass_spec in "ONE:$pass_one" "TWO:$pass_two"; do
  pass_name="${pass_spec%%:*}"
  pass_dir="${pass_spec#*:}"
  rewrite_log="$staged_artifact/RAMDISK-REWRITE-PASS-$pass_name.txt"

  python3 "$ramdisk_rewriter" \
    --base-boot-image "$base_image" \
    --expect-base-sha256 "$expected_base_sha256" \
    --replace-data "init.rc=$v13_init" \
    --replace-data "sbin/permissive.sh=$v13_wrapper" \
    --compression gzip \
    --output "$pass_dir/ramdisk.gzip" >"$rewrite_log"
  require_line 'base_entry_count_including_trailer=489' "$rewrite_log"
  require_line 'output_entry_count_including_trailer=489' "$rewrite_log"
  require_line 'added_paths=' "$rewrite_log"
  require_line 'removed_paths=' "$rewrite_log"
  require_line 'changed_data_paths=init.rc,sbin/permissive.sh' "$rewrite_log"
  require_line 'changed_metadata_paths=' "$rewrite_log"
  require_line 'entry_order_identical=yes' "$rewrite_log"
  require_line 'archive_tail_identical=yes' "$rewrite_log"

  python3 "$boot_image_repacker" "$base_image" \
    --kernel-from-image "$donor_image" \
    --ramdisk "$pass_dir/ramdisk.gzip" \
    --image-id-scheme conditional-dtb \
    --output "$pass_dir/recovery.img"
done

if ! cmp --silent "$pass_one/ramdisk.gzip" "$pass_two/ramdisk.gzip" || \
    ! cmp --silent "$pass_one/recovery.img" "$pass_two/recovery.img"; then
  printf 'The two clean v13 repacks are not byte-identical.\n' >&2
  exit 1
fi

cp "$pass_one/ramdisk.gzip" "$staged_artifact/ramdisk.gzip"
cp "$pass_one/recovery.img" "$staged_artifact/recovery.img"
cp "$v13_init" "$staged_artifact/provenance/recovery-ready-first-adb-v13.rc"
cp "$v13_wrapper" \
  "$staged_artifact/provenance/recovery-ready-first-wrapper-v13.sh"
cp "$decon_source" "$staged_artifact/provenance/decon-int_drv.c"
cp "$boot_image_inspector" \
  "$staged_artifact/provenance/inspect-android-boot-image.py"
cp "$boot_image_repacker" \
  "$staged_artifact/provenance/repack-android-boot-image.py"
cp "$ramdisk_rewriter" \
  "$staged_artifact/provenance/rewrite-newc-ramdisk.py"
cp "${BASH_SOURCE[0]}" \
  "$staged_artifact/provenance/build-pro5-twrp-note5-pan-ready-adb-v13.sh"

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
  --expect-ramdisk-file-sha256 "init.rc=$expected_v13_init_sha256" \
  --expect-ramdisk-file-sha256 \
    "init.recovery.m86.rc=$expected_device_init_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/permissive.sh=$expected_v13_wrapper_sha256" \
  --expect-ramdisk-file-sha256 "sbin/recovery=$expected_recovery_sha256" \
  --expect-ramdisk-file-sha256 "sbin/libminuitwrp.so=$expected_minui_sha256" \
  --expect-ramdisk-file-sha256 "sbin/adbd=$expected_adbd_sha256" \
  --expect-ramdisk-file-sha256 "default.prop=$expected_default_prop_sha256" \
  --expect-ramdisk-file-sha256 "sbin/busybox=$expected_busybox_sha256" \
  --expect-ramdisk-file-sha256 "sbin/sh=$expected_shell_sha256" \
  --expect-ramdisk-file-sha256 \
    "etc/recovery.fstab=$expected_recovery_fstab_sha256" \
  --expect-ramdisk-elf sbin/recovery \
  --expect-ramdisk-elf sbin/libminuitwrp.so \
  --expect-ramdisk-elf sbin/adbd \
  --expect-ramdisk-elf sbin/busybox \
  --expect-ramdisk-elf sbin/sh \
  --max-size "$conservative_image_limit" >"$output_header"
require_line "kernel_size=$expected_kernel_size" "$output_header"
require_line "kernel_sha256=$expected_kernel_sha256" "$output_header"
require_line 'image_id_scheme=conditional-dtb' "$output_header"
require_line 'dt_size=0' "$output_header"

require_sha256 "$inspector_sha256" "$boot_image_inspector"
require_sha256 "$repacker_sha256" "$boot_image_repacker"
require_sha256 "$rewriter_sha256" "$ramdisk_rewriter"
require_sha256 "$builder_sha256" "${BASH_SOURCE[0]}"
require_sha256 "$expected_base_sha256" "$base_image"
require_sha256 "$expected_donor_sha256" "$donor_image"
require_sha256 "$expected_v13_init_sha256" "$v13_init"
require_sha256 "$expected_v13_wrapper_sha256" "$v13_wrapper"

artifact_size="$(wc -c <"$staged_artifact/recovery.img" | tr -d ' ')"
artifact_sha256="$(sha256_of "$staged_artifact/recovery.img")"
ramdisk_size="$(wc -c <"$staged_artifact/ramdisk.gzip" | tr -d ' ')"
ramdisk_sha256="$(sha256_of "$staged_artifact/ramdisk.gzip")"
conservative_margin=$((conservative_image_limit - artifact_size))
partition_margin=$((recovery_partition_size - artifact_size))
source_revision="$(git -C "$project_root" rev-parse HEAD)"
source_state=clean
if [[ -n "$(git -C "$project_root" \
    status --porcelain --untracked-files=normal)" ]]; then
  source_state=dirty
fi
built_at="$(date '+%Y-%m-%dT%H:%M:%S%z')"

{
  printf 'artifact_role=test-only PRO 5 TWRP Note5-style PAN and ready-first ADB v13\n'
  printf 'artifact_generation=v13\n'
  printf 'artifact_file=recovery.img\n'
  printf 'artifact_size=%s\n' "$artifact_size"
  printf 'artifact_sha256=%s\n' "$artifact_sha256"
  printf 'built_at=%s\n' "$built_at"
  printf 'source_revision=%s\n' "$source_revision"
  printf 'source_worktree=%s\n' "$source_state"
  printf 'base_image=%s\n' "$base_image"
  printf 'base_recovery_sha256=%s\n' "$expected_base_sha256"
  printf 'base_device_result=v11 blacks out under continuous interaction and never enumerates ADB; v12 is display-only intermediate\n'
  printf 'kernel_donor_image=%s\n' "$donor_image"
  printf 'kernel_donor_recovery_sha256=%s\n' "$expected_donor_sha256"
  printf 'changed_components=kernel,init.rc,sbin/permissive.sh\n'
  printf 'changed_ramdisk_data_paths=init.rc,sbin/permissive.sh\n'
  printf 'changed_ramdisk_metadata_paths=none\n'
  printf 'ramdisk_entry_count_including_trailer=489\n'
  printf 'ramdisk_order=byte-identical path order\n'
  printf 'ramdisk_compression=gzip\n'
  printf 'ramdisk_size=%s\n' "$ramdisk_size"
  printf 'ramdisk_sha256=%s\n' "$ramdisk_sha256"
  printf 'base_kernel_sha256=%s\n' "$expected_base_kernel_sha256"
  printf 'kernel_sha256=%s\n' "$expected_kernel_sha256"
  printf 'kernel_pan=Note5-style lightweight address/trigger/VSYNC path; no per-PAN decon_set_par\n'
  printf 'minuitwrp_sha256=%s\n' "$expected_minui_sha256"
  printf 'minuitwrp_contract=forced page-zero single buffer; pre-copy VSYNC; PAN refresh; no init FBIOPUT_VSCREENINFO\n'
  printf 'recovery_elf_sha256=%s\n' "$expected_recovery_sha256"
  printf 'adbd_sha256=%s\n' "$expected_adbd_sha256"
  printf 'adb_transport=native /dev/android_adb; no FunctionFS mount\n'
  printf 'adb_usb_identity=2A45:0C01 serial PRO5TWRPV13\n'
  printf 'adb_usb_mode=start adbd with gadget disabled; wait for kernel adb_open; then enable ADB-only gadget; one disconnected retry\n'
  printf 'init_sha256=%s\n' "$expected_v13_init_sha256"
  printf 'wrapper_sha256=%s\n' "$expected_v13_wrapper_sha256"
  printf 'persistent_write=cache mounted rw,sync; pro5-twrp-diag-v13 recovery, dmesg and periodic USB evidence files\n'
  printf 'image_id_scheme=conditional-dtb\n'
  printf 'embedded_dtb_size=0\n'
  printf 'required_external_dtb=Flyme 8.0.5.0A stock DTB\n'
  printf 'required_external_dtb_sha256=%s\n' "$expected_stock_dtb_sha256"
  printf 'conservative_image_limit=%s\n' "$conservative_image_limit"
  printf 'conservative_image_margin=%s\n' "$conservative_margin"
  printf 'recovery_partition_size=%s\n' "$recovery_partition_size"
  printf 'recovery_partition_margin=%s\n' "$partition_margin"
  printf 'reproducibility=two byte-identical kernel source builds and two byte-identical hybrid repacks\n'
  printf 'final_acceptance=no; controlled device test required\n'
} >"$staged_artifact/METADATA.txt"

{
  printf 'source_revision=%s\n' "$source_revision"
  printf 'source_worktree=%s\n' "$source_state"
  printf 'inspector_sha256=%s\n' "$inspector_sha256"
  printf 'repacker_sha256=%s\n' "$repacker_sha256"
  printf 'rewriter_sha256=%s\n' "$rewriter_sha256"
  printf 'builder_sha256=%s\n' "$builder_sha256"
  printf 'v13_init_sha256=%s\n' "$expected_v13_init_sha256"
  printf 'v13_wrapper_sha256=%s\n' "$expected_v13_wrapper_sha256"
  printf 'base_recovery_sha256=%s\n' "$expected_base_sha256"
  printf 'kernel_donor_recovery_sha256=%s\n' "$expected_donor_sha256"
  printf '\nworktree_status:\n'
  git -C "$project_root" status --short --untracked-files=normal
} >"$staged_artifact/SOURCE-STATE.txt"

{
  printf 'kernel_source_build_pass_one_recovery_sha256=%s\n' \
    "$expected_donor_sha256"
  printf 'kernel_source_build_pass_two_recovery_sha256=%s\n' \
    "$expected_donor_sha256"
  printf 'kernel_source_build_byte_identical=yes\n'
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

{
  printf '# PRO 5 TWRP Note5-style PAN and ready-first ADB diagnostic v13\n\n'
  printf 'V13 starts from the audited v12 ramdisk. It replaces the kernel with '\
'the two-clean-build candidate whose framebuffer PAN path follows the '\
'contemporary Exynos 7420 Galaxy Note 5 implementation: update the scanout '\
'address, trigger the command-mode transfer and wait for VSYNC without '\
'calling decon_set_par() for every touch-driven frame.\n\n'
  printf 'The v12 display library remains unchanged. It uses framebuffer page '\
'zero, waits for VSYNC before copying, requests PAN after each changed frame, '\
'and preserves the kernel framebuffer geometry instead of issuing an '\
'initial FBIOPUT_VSCREENINFO.\n\n'
  printf 'ADB remains on the old native /dev/android_adb transport. Init starts '\
'adbd while the gadget is disabled; the wrapper waits for the kernel '\
'adb_open marker and only then publishes 2A45:0C01 / PRO5TWRPV13. It records '\
'the gadget state every five seconds and performs one reconnect edge only '\
'when the first state remains DISCONNECTED.\n\n'
  printf 'Exact artifact: %s bytes, SHA-256 %s. It embeds no DTB and requires '\
'the unchanged Flyme 8.0.5.0A stock DTB with SHA-256 %s.\n\n' \
    "$artifact_size" "$artifact_sha256" "$expected_stock_dtb_sha256"
  printf 'This is a test-only recovery, not final acceptance. Its wrapper '\
'deliberately mounts cache rw,sync and creates pro5-twrp-diag-v13 files. '\
'Do not mount, wipe, format, install, restore, or write boot, DTB, firmware, '\
'parameter, calibration or identity partitions.\n'
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

printf 'Built PRO 5 TWRP Note5-style PAN and ready-first ADB v13.\n'
printf 'artifact_dir=%s\n' "$artifact_dir"
printf 'recovery_size=%s\n' "$artifact_size"
printf 'recovery_sha256=%s\n' "$artifact_sha256"
printf 'changed_components=kernel,init.rc,sbin/permissive.sh\n'
printf 'adb_usb_identity=2A45:0C01 PRO5TWRPV13\n'
