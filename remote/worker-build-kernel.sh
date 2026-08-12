#!/usr/bin/env bash

set -eo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
local_root="$(cd "$script_dir/.." && pwd)"
remote_root="$(cd "$local_root/.." && pwd)"
source_root="$remote_root/src/lineage-17.1"
kernel_root="$source_root/kernel/meizu/m86"
out_root="$remote_root/out/kernel-m86"
run_root="$remote_root/run"
artifact_root="$remote_root/artifacts"

jobs="${1:-8}"
requested_jobs="$jobs"
status_file="${2:-$run_root/kernel-latest.status}"
log_file="${3:-$run_root/kernel-latest.log}"
build_stamp="${4:-$(date +%Y%m%d-%H%M%S)}"
local_commit="${5:-unknown}"

if [[ ! "$jobs" =~ ^[1-9][0-9]*$ ]] || ((jobs > 64)); then
  printf 'Invalid kernel build job count: %s\n' "$jobs" >&2
  exit 2
fi

mkdir -p "$run_root" "$artifact_root" "$(dirname "$log_file")"
exec > >(tee -a "$log_file") 2>&1

write_status() {
  local exit_code="$1"
  local status_tmp="${status_file}.tmp"

  {
    printf 'target=kernel-standalone\n'
    printf 'exit_code=%d\n' "$exit_code"
    printf 'finished_at=%s\n' "$(date --iso-8601=seconds)"
  } > "$status_tmp"
  mv "$status_tmp" "$status_file"

  trap - EXIT
  exit "$exit_code"
}
trap 'write_status $?' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
trap 'exit 129' HUP

memory_plan_file="$run_root/kernel-$build_stamp-memory-plan.txt"
"$script_dir/prepare-builder-memory.sh" \
  "$requested_jobs" kernel "$out_root" "$memory_plan_file"
jobs="$(awk -F= '$1 == "effective_jobs" { print $2 }' "$memory_plan_file")"
if [[ ! "$jobs" =~ ^[1-9][0-9]*$ ]]; then
  printf 'Builder memory plan produced an invalid job count: %s\n' \
    "$jobs" >&2
  exit 1
fi

aarch64_toolchain="$source_root/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9"
arm_toolchain="$source_root/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9"
aarch64_prefix="$aarch64_toolchain/bin/aarch64-linux-android-"
arm_prefix="$arm_toolchain/bin/arm-linux-androideabi-"
kernel_exfat_lock="$local_root/locks/kernel-exfat-exynos7420.sha256"

for required in \
  "$kernel_root/arch/arm64/configs/cm_pro5_defconfig" \
  "$kernel_exfat_lock" \
  "${aarch64_prefix}gcc" \
  "${arm_prefix}gcc"; do
  if [[ ! -e "$required" ]]; then
    printf 'Required kernel input is missing: %s\n' "$required" >&2
    exit 1
  fi
done
if ! (
  cd "$kernel_root"
  sha256sum --quiet -c "$kernel_exfat_lock"
); then
  printf 'The installed Exynos 7420 exFAT source does not match its lock.\n' >&2
  exit 1
fi

export KBUILD_BUILD_USER=pro5-port
export KBUILD_BUILD_HOST=autodl
export KBUILD_BUILD_VERSION=1
export KBUILD_BUILD_TIMESTAMP='Sat Sep 29 16:28:54 UTC 2018'

make_args=(
  -C "$kernel_root"
  "O=$out_root"
  ARCH=arm64
  "CROSS_COMPILE=$aarch64_prefix"
  "CROSS_COMPILE_ARM32=$arm_prefix"
)

printf 'Standalone kernel build started at %s\n' "$(date --iso-8601=seconds)"
printf 'Kernel: %s\nOutput: %s\nRequested jobs: %s\nJobs: %s\nLocal commit: %s\n' \
  "$kernel_root" "$out_root" "$requested_jobs" "$jobs" "$local_commit"

if [[ "$remote_root" == "/" ]] || \
    [[ "$out_root" != "$remote_root/out/kernel-m86" ]]; then
  printf 'Refusing to clear an unexpected kernel output path: %s\n' \
    "$out_root" >&2
  exit 1
fi
rm -rf -- "$out_root"
mkdir -p "$out_root"
make "${make_args[@]}" cm_pro5_defconfig
make "${make_args[@]}" -j"$jobs" Image dtbs

kernel_image="$out_root/arch/arm64/boot/Image"
kernel_dtb="$out_root/arch/arm64/boot/dts/exynos7420-m86-codegen.dtb"
for artifact in "$kernel_image" "$kernel_dtb" "$out_root/.config"; do
  if [[ ! -s "$artifact" ]]; then
    printf 'Expected kernel artifact is missing or empty: %s\n' "$artifact" >&2
    exit 1
  fi
done
for required_exfat_setting in \
  CONFIG_EXFAT_FS=y \
  CONFIG_EXFAT_VIRTUAL_XATTR=y \
  'CONFIG_EXFAT_VIRTUAL_XATTR_SELINUX_LABEL="u:object_r:sdcard_external:s0"'; do
  if ! grep -F -x -q "$required_exfat_setting" "$out_root/.config"; then
    printf 'The generated m86 kernel config omitted %s.\n' \
      "$required_exfat_setting" >&2
    exit 1
  fi
done
if grep -E -q \
    'CONFIG_(FAT_VIRTUAL_XATTR|FAT_VIRTUAL_XATTR_SELINUX_LABEL|FAT_SUPPORT_STLOG|EXFAT_SUPPORT_STLOG)' \
    "$out_root/.config"; then
  printf 'The generated m86 kernel config retained a stale filesystem option.\n' >&2
  exit 1
fi
for required_exfat_object in \
  fs/exfat/exfat_core.o \
  fs/exfat/exfat_fs.o; do
  if [[ ! -s "$out_root/$required_exfat_object" ]]; then
    printf 'The standalone build omitted kernel object %s.\n' \
      "$required_exfat_object" >&2
    exit 1
  fi
done
artifact_dir="$artifact_root/$build_stamp-kernel-standalone"
mkdir -p "$artifact_dir"
install -m 0644 "$kernel_image" "$artifact_dir/Image"
install -m 0644 "$kernel_dtb" "$artifact_dir/exynos7420-m86-codegen.dtb"
install -m 0644 "$out_root/.config" "$artifact_dir/kernel.config"
install -m 0644 "$kernel_exfat_lock" \
  "$artifact_dir/kernel-exfat-exynos7420.sha256"
install -m 0644 "$memory_plan_file" "$artifact_dir/BUILD-MEMORY.txt"
(
  cd "$out_root"
  sha256sum fs/exfat/exfat_core.o fs/exfat/exfat_fs.o
) > "$artifact_dir/EXFAT-KERNEL.txt"
aarch64_revision="$(git -C "$aarch64_toolchain" rev-parse HEAD)"
arm_revision="$(git -C "$arm_toolchain" rev-parse HEAD)"
{
  printf 'local_commit=%s\n' "$local_commit"
  printf 'kernel_source=67699d9442a9557eca24ba7a489ffa1b0601e806\n'
  printf 'aarch64_toolchain=%s\n' "$aarch64_revision"
  printf 'arm_toolchain=%s\n' "$arm_revision"
  printf 'jobs=%s\n' "$jobs"
  printf 'built_at=%s\n' "$(date --iso-8601=seconds)"
} > "$artifact_dir/BUILD-METADATA"

(
  cd "$artifact_dir"
  sha256sum \
    BUILD-METADATA \
    EXFAT-KERNEL.txt \
    Image \
    exynos7420-m86-codegen.dtb \
    kernel-exfat-exynos7420.sha256 \
    kernel.config > SHA256SUMS
)
stat -c '%n %s bytes' "$artifact_dir"/Image "$artifact_dir"/*.dtb
printf 'Standalone kernel build completed at %s\n' "$(date --iso-8601=seconds)"
printf 'Artifacts: %s\n' "$artifact_dir"
