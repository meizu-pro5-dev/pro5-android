#!/usr/bin/env bash

set -eo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
local_root="$(cd "$script_dir/.." && pwd)"
remote_root="$(cd "$local_root/.." && pwd)"
source_root="$remote_root/src/twrp-9.0"
out_root="$remote_root/out/twrp-9.0"
run_root="$remote_root/run"
artifact_root="$remote_root/artifacts"

jobs="${1:-24}"
status_file="${2:-$run_root/twrp-build-latest.status}"
log_file="${3:-$run_root/twrp-build-latest.log}"
build_stamp="${4:-$(date +%Y%m%d-%H%M%S)}"
local_revision="${5:-unknown}"

if [[ ! "$jobs" =~ ^[1-9][0-9]*$ ]] || ((jobs > 64)); then
  printf 'Invalid TWRP build job count: %s\n' "$jobs" >&2
  exit 2
fi

mkdir -p "$run_root" "$artifact_root" "$(dirname "$log_file")"
exec > >(tee -a "$log_file") 2>&1

write_status() {
  local exit_code="$1"
  local status_tmp="${status_file}.tmp"

  {
    printf 'target=recoveryimage\n'
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

# shellcheck source=builder-network.sh
source "$script_dir/builder-network.sh"
configure_builder_network

if [[ ! -f "$source_root/build/envsetup.sh" ]]; then
  printf 'TWRP source is incomplete: %s\n' "$source_root" >&2
  exit 1
fi
if [[ ! -f "$source_root/device/meizu/m86/BoardConfig.mk" ]]; then
  printf 'The maintained m86 TWRP tree is not installed.\n' >&2
  exit 1
fi
if [[ ! -f "$source_root/kernel/meizu/m86/arch/arm64/configs/cm_pro5_defconfig" ]]; then
  printf 'The maintained m86 kernel tree is not installed.\n' >&2
  exit 1
fi

python2_dir="$source_root/prebuilts/python/linux-x86/2.7.5/bin"
if [[ ! -x "$python2_dir/python2.7" ]]; then
  printf 'TWRP 9.0 requires its synchronized Python 2.7 prebuilt.\n' >&2
  exit 1
fi
export PATH="$python2_dir:$PATH"

export ALLOW_MISSING_DEPENDENCIES=true
export USE_CCACHE=1
export CCACHE_DIR="$remote_root/ccache"
export CCACHE_BASEDIR="$source_root"
export CCACHE_EXEC="$(command -v ccache)"
export OUT_DIR="$out_root"
export LC_ALL=C
export KBUILD_BUILD_USER=pro5-port
export KBUILD_BUILD_HOST=autodl
export KBUILD_BUILD_VERSION=1
export KBUILD_BUILD_TIMESTAMP='Sat Sep 29 16:28:54 UTC 2018'

ccache --max-size=25G
ccache --zero-stats

printf 'TWRP build started at %s\n' "$(date --iso-8601=seconds)"
printf 'Source: %s\nJobs: %s\nOutput: %s\nLocal revision: %s\n' \
  "$source_root" "$jobs" "$out_root" "$local_revision"
printf 'Python: %s\n' "$(python2.7 --version 2>&1)"

cd "$source_root"
# Android 9 envsetup and shell functions are not nounset-safe.
# shellcheck disable=SC1091
source build/envsetup.sh
lunch omni_m86-eng
mka recoveryimage -j"$jobs"

product_out="$out_root/target/product/m86"
recovery_image="$product_out/recovery.img"
if [[ ! -s "$recovery_image" ]]; then
  printf 'TWRP did not produce recovery.img.\n' >&2
  exit 1
fi

kernel_root="$source_root/kernel/meizu/m86"
kernel_out="$product_out/obj/KERNEL_OBJ"
aarch64_prefix="$source_root/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-"
arm_prefix="$source_root/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/bin/arm-linux-androideabi-"
for required_kernel_input in \
  "$kernel_out/.config" \
  "${aarch64_prefix}gcc" \
  "${arm_prefix}gcc"; do
  if [[ ! -e "$required_kernel_input" ]]; then
    printf 'Required post-build kernel input is missing: %s\n' \
      "$required_kernel_input" >&2
    exit 1
  fi
done

# The boot image correctly contains no DT section, so Android's recoveryimage
# target need not build dtbs. Build the matching raw partition artifact from
# the exact same configured kernel output before collecting evidence.
make \
  -C "$kernel_root" \
  "O=$kernel_out" \
  ARCH=arm64 \
  "CROSS_COMPILE=$aarch64_prefix" \
  "CROSS_COMPILE_ARM32=$arm_prefix" \
  -j"$jobs" \
  dtbs

mapfile -t generated_dtbs < <(
  find "$out_root" -type f \
    -path '*/obj/KERNEL_OBJ/arch/arm64/boot/dts/exynos7420-m86-codegen.dtb' \
    -print
)
if [[ "${#generated_dtbs[@]}" -ne 1 ]]; then
  printf 'Expected one generated m86 DTB, found %s.\n' \
    "${#generated_dtbs[@]}" >&2
  printf '  %s\n' "${generated_dtbs[@]}" >&2
  exit 1
fi

artifact_dir="$artifact_root/twrp-$build_stamp-recoveryimage"
mkdir -p "$artifact_dir"
cp -a "$recovery_image" "$artifact_dir/recovery.img"
cp -a "${generated_dtbs[0]}" \
  "$artifact_dir/exynos7420-m86-codegen.dtb"
cp -a "$source_root/kernel/meizu/m86/arch/arm64/configs/cm_pro5_defconfig" \
  "$artifact_dir/cm_pro5_defconfig"
cp -a "$kernel_out/.config" "$artifact_dir/kernel.config"
cp -a "$local_root/twrp/FLASHING.md" "$artifact_dir/FLASHING.md"
cp -a "$local_root/locks/stock-flyme-8.0.5.0A.sha256" \
  "$artifact_dir/stock-flyme-8.0.5.0A.sha256"

python3 "$local_root/tools/inspect-android-boot-image.py" \
  "$artifact_dir/recovery.img" \
  --expect-page-size 4096 \
  --expect-kernel-addr 0x40080000 \
  --expect-ramdisk-addr 0x42000000 \
  --expect-second-addr 0x40f00000 \
  --expect-tags-addr 0x40000100 \
  --expect-second-size 0 \
  --expect-dt-size 0 \
  --expect-empty-cmdline \
  --expect-ramdisk-compression gzip \
  --max-size 33550336 | tee "$artifact_dir/RECOVERY-HEADER.txt"

python3 "$local_root/tools/inspect-dtb.py" \
  "$artifact_dir/exynos7420-m86-codegen.dtb" \
  --expect-string 'Meizu, M86' \
  --require-no-trailing-data | tee "$artifact_dir/DTB-HEADER.txt"

repo manifest -r -o "$artifact_dir/twrp-9.0-m86-lock.xml"
twrp_version="$(
  sed -n 's/^#define TW_MAIN_VERSION_STR[[:space:]]*"\([^"]*\)"/\1/p' \
    bootable/recovery/variables.h
)"

{
  printf 'built_at=%s\n' "$(date --iso-8601=seconds)"
  printf 'target=omni_m86-eng recoveryimage\n'
  printf 'local_revision=%s\n' "$local_revision"
  printf 'twrp_version=%s\n' "$twrp_version"
  printf 'source_root=%s\n' "$source_root"
  printf 'out_root=%s\n' "$out_root"
  printf 'jobs=%s\n' "$jobs"
  printf 'stock_base=Flyme 8.0.5.0A / Android 7 / API 24\n'
  printf 'proprietary_recovery_blobs=none\n'
  printf 'recovery_partition_limit=33550336\n'
  printf 'dtb_packaging=raw separate partition\n'
  printf 'ramdisk_compression=gzip only\n'
  printf 'python_runtime=%s\n' "$(python2.7 --version 2>&1)"
} > "$artifact_dir/BUILD-METADATA"

printf 'TWRP build completed at %s\n' "$(date --iso-8601=seconds)"
printf 'Artifacts: %s\n' "$artifact_dir"
cp -a "$log_file" "$artifact_dir/"

(
  cd "$artifact_dir"
  find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 |
    LC_ALL=C sort -z |
    xargs -0 sha256sum
) > "$artifact_dir/SHA256SUMS"
ln -sfn "$(basename "$artifact_dir")" "$artifact_root/twrp-latest"

ccache --show-stats
