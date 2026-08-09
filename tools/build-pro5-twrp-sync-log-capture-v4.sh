#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s BASE_V3_RECOVERY_IMG OUTPUT_DIRECTORY\n' \
    "$(basename "$0")" >&2
}

if (( $# != 2 )); then
  usage
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
boot_image_inspector="$script_dir/inspect-android-boot-image.py"
boot_image_repacker="$script_dir/repack-android-boot-image.py"
ramdisk_rewriter="$script_dir/rewrite-newc-ramdisk.py"
recovery_wrapper="$project_root/patches/twrp-diagnostics/recovery-sync-log-wrapper-v4.sh"

expected_base_sha256=61c7e16e706ab04cddc9801b6fa30f6f23683108591e9446dbf66e69e2594ea7
expected_base_size=29335552
expected_kernel_sha256=5df2fd06a58635c0299f10686c715a35fbc7ba0169bf9ffccdb292bba42c7d04
expected_base_ramdisk_sha256=f6d840c8fa929180bdffb77743e644bbc2317ec665ed053c23f3704317518699
expected_init_sha256=f1e17f7d93dad91efa607098495debda771429a8ba326c0ab6ba9e883811ee70
expected_v3_wrapper_sha256=fa1b422d4e5a92ba833a6d0458413be656bf5800537b22628d95625bc6b388b4
expected_v4_wrapper_sha256=136b881e587df48ddb9e272d41beb888a05c36fce0c5cc3bd00d5885ed6d864f
expected_recovery_elf_sha256=0b31d94944fe11b1bf2ead63753b0ad2bfd3358073755150b3a6c900b6179e51
expected_busybox_sha256=2cb28c8935e3218ed3559bf4b50f89beaa113751f40459ee2f059c1e6324199f
expected_shell_sha256=831ff2fa3b4f4e30e676a7a9130f3576e27ab293538a0298eb71e3e120778781
expected_device_init_sha256=2550cabe02e6c711f905e180729ba5760b2cb9a608a8363a16e1ed02d4da2ded
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

for required_file in \
  "$boot_image_inspector" \
  "$boot_image_repacker" \
  "$ramdisk_rewriter" \
  "$recovery_wrapper"; do
  if [[ ! -s "$required_file" ]]; then
    printf 'Required v4 build input is absent: %s\n' "$required_file" >&2
    exit 1
  fi
done

base_input="$1"
if [[ ! -f "$base_input" ]]; then
  printf 'The v3 base image is absent: %s\n' "$base_input" >&2
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
require_sha256 "$expected_v4_wrapper_sha256" "$recovery_wrapper"

inspector_sha256="$(sha256_of "$boot_image_inspector")"
repacker_sha256="$(sha256_of "$boot_image_repacker")"
rewriter_sha256="$(sha256_of "$ramdisk_rewriter")"
builder_sha256="$(sha256_of "${BASH_SOURCE[0]}")"

stage_root="$(mktemp -d "$output_parent/.pro5-twrp-v4.XXXXXX")"
cleanup() {
  if [[ -n "${stage_root:-}" && -d "$stage_root" && \
      "$stage_root" == "$output_parent/.pro5-twrp-v4."* ]]; then
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
  --expect-ramdisk-file-sha256 \
    "init.rc=$expected_init_sha256" \
  --expect-ramdisk-file-sha256 \
    "init.recovery.m86.rc=$expected_device_init_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/permissive.sh=$expected_v3_wrapper_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/recovery=$expected_recovery_elf_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/busybox=$expected_busybox_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/sh=$expected_shell_sha256" \
  --expect-ramdisk-file-sha256 \
    "etc/recovery.fstab=$expected_recovery_fstab_sha256" \
  --expect-ramdisk-elf sbin/recovery \
  --expect-ramdisk-elf sbin/busybox \
  --expect-ramdisk-elf sbin/sh \
  --expect-ramdisk-file sbin/dmesg \
  --expect-ramdisk-file sbin/mount \
  --max-size "$conservative_image_limit" >"$base_header"
require_line "file_size=$expected_base_size" "$base_header"
require_line "kernel_sha256=$expected_kernel_sha256" "$base_header"
require_line "ramdisk_sha256=$expected_base_ramdisk_sha256" "$base_header"
require_line 'image_id_scheme=conditional-dtb' "$base_header"

for pass_spec in "ONE:$pass_one" "TWO:$pass_two"; do
  pass_name="${pass_spec%%:*}"
  pass_dir="${pass_spec#*:}"
  rewrite_log="$staged_artifact/RAMDISK-REWRITE-PASS-$pass_name.txt"

  python3 "$ramdisk_rewriter" \
    --base-boot-image "$base_image" \
    --expect-base-sha256 "$expected_base_sha256" \
    --replace-data "sbin/permissive.sh=$recovery_wrapper" \
    --compression gzip \
    --output "$pass_dir/ramdisk.gzip" >"$rewrite_log"
  require_line 'base_entry_count_including_trailer=489' "$rewrite_log"
  require_line 'output_entry_count_including_trailer=489' "$rewrite_log"
  require_line 'added_paths=' "$rewrite_log"
  require_line 'removed_paths=' "$rewrite_log"
  require_line 'changed_data_paths=sbin/permissive.sh' "$rewrite_log"
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
  printf 'The two clean v4 repacks are not byte-identical.\n' >&2
  exit 1
fi

cp "$pass_one/ramdisk.gzip" "$staged_artifact/ramdisk.gzip"
cp "$pass_one/recovery.img" "$staged_artifact/recovery.img"
cp "$recovery_wrapper" \
  "$staged_artifact/provenance/recovery-sync-log-wrapper-v4.sh"
cp "$boot_image_inspector" \
  "$staged_artifact/provenance/inspect-android-boot-image.py"
cp "$boot_image_repacker" \
  "$staged_artifact/provenance/repack-android-boot-image.py"
cp "$ramdisk_rewriter" \
  "$staged_artifact/provenance/rewrite-newc-ramdisk.py"
cp "${BASH_SOURCE[0]}" \
  "$staged_artifact/provenance/build-pro5-twrp-sync-log-capture-v4.sh"

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
    "sbin/permissive.sh=$expected_v4_wrapper_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/recovery=$expected_recovery_elf_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/busybox=$expected_busybox_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/sh=$expected_shell_sha256" \
  --expect-ramdisk-file-sha256 \
    "etc/recovery.fstab=$expected_recovery_fstab_sha256" \
  --expect-ramdisk-elf sbin/recovery \
  --expect-ramdisk-elf sbin/busybox \
  --expect-ramdisk-elf sbin/sh \
  --expect-ramdisk-file sbin/dmesg \
  --expect-ramdisk-file sbin/mount \
  --max-size "$conservative_image_limit" >"$output_header"
require_line "kernel_sha256=$expected_kernel_sha256" "$output_header"
require_line 'image_id_scheme=conditional-dtb' "$output_header"
require_line 'dt_size=0' "$output_header"

require_sha256 "$inspector_sha256" "$boot_image_inspector"
require_sha256 "$repacker_sha256" "$boot_image_repacker"
require_sha256 "$rewriter_sha256" "$ramdisk_rewriter"
require_sha256 "$builder_sha256" "${BASH_SOURCE[0]}"
require_sha256 "$expected_v4_wrapper_sha256" "$recovery_wrapper"
require_sha256 "$expected_base_sha256" "$base_image"

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
  printf 'artifact_role=test-only synchronous TWRP log-capture diagnostic v4\n'
  printf 'artifact_file=recovery.img\n'
  printf 'artifact_size=%s\n' "$artifact_size"
  printf 'artifact_sha256=%s\n' "$artifact_sha256"
  printf 'built_at=%s\n' "$built_at"
  printf 'source_revision=%s\n' "$source_revision"
  printf 'source_worktree=%s\n' "$source_state"
  printf 'base_image=%s\n' "$base_image"
  printf 'base_recovery_sha256=%s\n' "$expected_base_sha256"
  printf 'base_device_result=wrapper reached cache; post-launch writes were not durable before reset\n'
  printf 'changed_data_paths=sbin/permissive.sh\n'
  printf 'changed_metadata_paths=none\n'
  printf 'ramdisk_entry_count_including_trailer=489\n'
  printf 'ramdisk_order=byte-identical path order\n'
  printf 'ramdisk_compression=gzip\n'
  printf 'ramdisk_size=%s\n' "$ramdisk_size"
  printf 'ramdisk_sha256=%s\n' "$ramdisk_sha256"
  printf 'kernel_sha256=%s\n' "$expected_kernel_sha256"
  printf 'recovery_elf_sha256=%s\n' "$expected_recovery_elf_sha256"
  printf 'init_sha256=%s\n' "$expected_init_sha256"
  printf 'wrapper_sha256=%s\n' "$expected_v4_wrapper_sha256"
  printf 'image_id_scheme=conditional-dtb\n'
  printf 'embedded_dtb_size=0\n'
  printf 'required_external_dtb=Flyme 8.0.5.0A stock DTB\n'
  printf 'required_external_dtb_sha256=%s\n' "$expected_stock_dtb_sha256"
  printf 'conservative_image_limit=%s\n' "$conservative_image_limit"
  printf 'conservative_image_margin=%s\n' "$conservative_margin"
  printf 'recovery_partition_size=%s\n' "$recovery_partition_size"
  printf 'recovery_partition_margin=%s\n' "$partition_margin"
  printf 'reproducibility=two byte-identical ramdisk and recovery repacks\n'
  printf 'persistent_write=mount cache rw,sync and create unique pro5-twrp-diag-v4 files under /cache/recovery\n'
  printf 'persistent_sync_interval_seconds=1\n'
  printf 'cache_failure_policy=do not start TWRP; retain init and ADB environment\n'
  printf 'final_acceptance=no; diagnostic evidence collector only\n'
} >"$staged_artifact/METADATA.txt"

{
  printf 'source_revision=%s\n' "$source_revision"
  printf 'source_worktree=%s\n' "$source_state"
  printf 'inspector_sha256=%s\n' "$inspector_sha256"
  printf 'repacker_sha256=%s\n' "$repacker_sha256"
  printf 'rewriter_sha256=%s\n' "$rewriter_sha256"
  printf 'builder_sha256=%s\n' "$builder_sha256"
  printf 'wrapper_sha256=%s\n' "$expected_v4_wrapper_sha256"
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

cat >"$staged_artifact/README.md" <<EOF
# PRO 5 synchronous TWRP log-capture diagnostic v4

This image is a test-only evidence collector, not an accepted recovery. It is
built from the exact handset-tested v3 image. Only the data payload of the
existing executable \`sbin/permissive.sh\` entry changes; all 489 cpio paths,
path order and metadata, plus the kernel, init, patched TWRP ELF, dependencies,
resources, fstab and boot geometry remain identical.

V3 proved that its wrapper mounted cache and saved the pre-launch dmesg, but
the first post-sync marker and all TWRP output were lost before the next
two-second sync. V4 mounts cache with the VFS \`sync\` flag before any
diagnostic file is created. It then records and flushes explicit stages before
launching TWRP; TWRP's unbuffered \`/tmp/recovery.log\` writes resolve directly
to the synchronous cache file. A one-second sync loop remains as a secondary
guard. This is intended to retain the final line even if graphics startup
hard-locks the kernel before another process can run.

## Exact artifact

- size: $artifact_size bytes
- SHA-256: \`$artifact_sha256\`
- embedded DTB: none
- required external DTB: unchanged Flyme 8.0.5.0A stock DTB,
  SHA-256 \`$expected_stock_dtb_sha256\`

Do not flash this image until the exact artifact and command are explicitly
approved. The test deliberately mounts cache read-write with synchronous I/O
and creates \`/cache/recovery/pro5-twrp-diag-v4-*\` files. It must never be
written to \`bootimg\`, \`dtb\`, \`/dev/block/sdb\`, firmware, parameter or
identity partitions. Do not mount, wipe, format, install, restore or perform
any other recovery write test.

After a test, collect every \`pro5-twrp-diag-v4-*\` file before changing the
recovery image. The recovery log should contain \`wrapper_stage=launching_recovery\`
followed by TWRP's own unbuffered output. If the handset returns to Flyme, use
the established rooted, read-only collection route for those cache files.
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

printf 'Built PRO 5 TWRP synchronous log-capture v4.\n'
printf 'artifact_dir=%s\n' "$artifact_dir"
printf 'recovery_size=%s\n' "$artifact_size"
printf 'recovery_sha256=%s\n' "$artifact_sha256"
printf 'persistent_device_write=/cache/recovery/pro5-twrp-diag-v4-*\n'
printf 'flash_authorized=no\n'
