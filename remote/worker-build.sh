#!/usr/bin/env bash

set -eo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
local_root="$(cd "$script_dir/.." && pwd)"
remote_root="$(cd "$local_root/.." && pwd)"
source_root="$remote_root/src/lineage-17.1"
out_root="$remote_root/out/lineage-17.1"
run_root="$remote_root/run"
artifact_root="$remote_root/artifacts"

target="${1:-bootimage}"
jobs="${2:-8}"
status_file="${3:-$run_root/build-latest.status}"
log_file="${4:-$run_root/build-latest.log}"
build_stamp="${5:-$(date +%Y%m%d-%H%M%S)}"
local_revision="${6:-unknown}"

case "$target" in
  kernel | bootimage | recoveryimage | bacon) ;;
  *)
    printf 'Unsupported build target: %s\n' "$target" >&2
    exit 2
    ;;
esac

if [[ ! "$jobs" =~ ^[1-9][0-9]*$ ]] || ((jobs > 64)); then
  printf 'Invalid build job count: %s\n' "$jobs" >&2
  exit 2
fi

mkdir -p "$run_root" "$artifact_root" "$(dirname "$log_file")"
exec > >(tee -a "$log_file") 2>&1

write_status() {
  local exit_code="$1"
  local status_tmp="${status_file}.tmp"

  {
    printf 'target=%s\n' "$target"
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
  printf 'LineageOS source is incomplete: %s\n' "$source_root" >&2
  exit 1
fi

if [[ ! -f "$source_root/kernel/meizu/m86/arch/arm64/configs/cm_pro5_defconfig" ]]; then
  printf 'The maintained m86 kernel tree is not installed.\n' >&2
  exit 1
fi
kernel_exfat_lock="$local_root/locks/kernel-exfat-exynos7420.sha256"
if [[ ! -s "$kernel_exfat_lock" ]] || ! (
  cd "$source_root/kernel/meizu/m86"
  sha256sum --quiet -c "$kernel_exfat_lock"
); then
  printf 'The installed Exynos 7420 exFAT source does not match its lock.\n' >&2
  exit 1
fi

# Android 10 still invokes this older Clang for RenderScript bitcode. Check
# its host ABI before Ninja starts thousands of jobs so a missing compatibility
# library produces one actionable error instead of many failed commands.
renderscript_clang="$source_root/prebuilts/clang/host/linux-x86/clang-3289846/bin/clang.real"
if [[ -x "$renderscript_clang" ]]; then
  missing_host_libraries="$(
    ldd "$renderscript_clang" 2>/dev/null |
      awk '/not found/ { print $1 }' |
      LC_ALL=C sort -u
  )"
  if [[ -n "$missing_host_libraries" ]]; then
    printf 'RenderScript Clang is missing host libraries:\n%s\n' \
      "$missing_host_libraries" >&2
    printf 'Run remote/bootstrap-builder.sh before building.\n' >&2
    exit 1
  fi
fi

# repo intentionally leaves Git LFS pointers in place when smudge is skipped.
# The arm64 WebView prebuilt is required by this product and must be a verified
# APK before Ninja starts. Derive the expected object ID from the pinned Git
# object, materialize only that file, then verify both its digest and ZIP
# structure. This keeps the build reproducible and catches partial downloads.
webview_project="$source_root/external/chromium-webview/prebuilt/arm64"
webview_apk="$webview_project/webview.apk"
if [[ "$target" == bacon ]]; then
  if ! git -C "$webview_project" rev-parse --verify HEAD >/dev/null 2>&1; then
    printf 'Pinned arm64 WebView project is missing: %s\n' \
      "$webview_project" >&2
    exit 1
  fi
  webview_pointer="$(git -C "$webview_project" show HEAD:webview.apk)"
  webview_oid="$(sed -n 's/^oid sha256:\([0-9a-f]\{64\}\)$/\1/p' \
    <<<"$webview_pointer")"
  webview_size="$(sed -n 's/^size \([0-9][0-9]*\)$/\1/p' \
    <<<"$webview_pointer")"
  if [[ ! "$webview_oid" =~ ^[0-9a-f]{64}$ ]] || \
      [[ ! "$webview_size" =~ ^[1-9][0-9]*$ ]]; then
    printf 'Pinned arm64 WebView has no valid Git LFS pointer metadata.\n' >&2
    exit 1
  fi
  if [[ ! -f "$webview_apk" ]] || \
      [[ "$(stat -c %s "$webview_apk")" != "$webview_size" ]] || \
      [[ "$(sha256sum "$webview_apk" | awk '{ print $1 }')" != \
         "$webview_oid" ]]; then
    printf 'Materializing pinned arm64 WebView Git LFS object %s.\n' \
      "$webview_oid"
    git -C "$webview_project" lfs pull \
      --include=webview.apk \
      --exclude=''
  fi
  if [[ ! -f "$webview_apk" ]] || \
      [[ "$(stat -c %s "$webview_apk")" != "$webview_size" ]] || \
      [[ "$(sha256sum "$webview_apk" | awk '{ print $1 }')" != \
         "$webview_oid" ]] || \
      ! unzip -tq "$webview_apk" >/dev/null; then
    printf 'The pinned arm64 WebView APK is absent, incomplete, or invalid.\n' >&2
    exit 1
  fi
  printf 'Verified pinned arm64 WebView APK: sha256=%s size=%s\n' \
    "$webview_oid" "$webview_size"
fi

export USE_CCACHE=1
export CCACHE_DIR="$remote_root/ccache"
export CCACHE_BASEDIR="$source_root"
export CCACHE_EXEC="$(command -v ccache)"
export OUT_DIR="$out_root"
export LC_ALL=C
export BUILD_DATETIME=1786017600
export BUILD_NUMBER=pro5-a10-20260806
export BUILD_USERNAME=pro5-port
export BUILD_HOSTNAME=autodl
export SOURCE_DATE_EPOCH=1786017600
export KBUILD_BUILD_USER=pro5-port
export KBUILD_BUILD_HOST=autodl
export KBUILD_BUILD_VERSION=1
export KBUILD_BUILD_TIMESTAMP='Sat Sep 29 16:28:54 UTC 2018'

ccache --max-size=25G
ccache --zero-stats

printf 'Build started at %s\n' "$(date --iso-8601=seconds)"
printf 'Source: %s\nTarget: %s\nJobs: %s\nOutput: %s\nLocal revision: %s\n' \
  "$source_root" "$target" "$jobs" "$out_root" "$local_revision"

vendor_blob_count=0
vendor_blob_lock="$remote_root/logs/m86-proprietary-sha256s.txt"
if [[ "$target" == bacon ]]; then
  vendor_proprietary="$source_root/vendor/meizu/m86/proprietary"
  for vendor_input in "$vendor_blob_lock" "$vendor_proprietary"; do
    if [[ ! -e "$vendor_input" ]]; then
      printf 'Verified m86 vendor input is missing: %s\n' \
        "$vendor_input" >&2
      exit 1
    fi
  done

  vendor_blob_count="$(wc -l < "$vendor_blob_lock" | tr -d ' ')"
  if [[ "$vendor_blob_count" != "219" ]]; then
    printf 'Expected 219 locked m86 blobs, found %s.\n' \
      "$vendor_blob_count" >&2
    exit 1
  fi
  (
    cd "$vendor_proprietary"
    sha256sum --quiet -c "$vendor_blob_lock"
  )
  printf 'Verified %s Flyme 8 proprietary inputs before full build.\n' \
    "$vendor_blob_count"
fi

cd "$source_root"
# Android's envsetup and shell functions are not nounset-safe.
# shellcheck disable=SC1091
source build/envsetup.sh
lunch lineage_m86-userdebug
mka "$target" -j"$jobs"

product_out="$out_root/target/product/m86"
artifact_dir="$artifact_root/$build_stamp-$target"
mkdir -p "$artifact_dir"

kernel_out="$product_out/obj/KERNEL_OBJ"
kernel_dtb="$kernel_out/arch/arm64/boot/dts/exynos7420-m86-codegen.dtb"
if [[ ! -s "$kernel_dtb" ]]; then
  printf 'The Android build did not produce the m86 raw DTB.\n' >&2
  exit 1
fi
for required_exfat_setting in \
  CONFIG_EXFAT_FS=y \
  CONFIG_EXFAT_VIRTUAL_XATTR=y \
  'CONFIG_EXFAT_VIRTUAL_XATTR_SELINUX_LABEL="u:object_r:sdcard_external:s0"'; do
  if ! grep -F -x -q "$required_exfat_setting" "$kernel_out/.config"; then
    printf 'The generated m86 kernel config omitted %s.\n' \
      "$required_exfat_setting" >&2
    exit 1
  fi
done
for required_diagnostic_setting in \
  CONFIG_PSTORE=y \
  CONFIG_PSTORE_CONSOLE=y \
  CONFIG_PSTORE_RAM=y; do
  if ! grep -F -x -q "$required_diagnostic_setting" "$kernel_out/.config"; then
    printf 'The generated m86 kernel config omitted %s.\n' \
      "$required_diagnostic_setting" >&2
    exit 1
  fi
done
if grep -E -q \
    'CONFIG_(FAT_VIRTUAL_XATTR|FAT_VIRTUAL_XATTR_SELINUX_LABEL|FAT_SUPPORT_STLOG|EXFAT_SUPPORT_STLOG)' \
    "$kernel_out/.config"; then
  printf 'The generated m86 kernel config retained a stale filesystem option.\n' >&2
  exit 1
fi
for required_exfat_object in \
  fs/exfat/exfat_core.o \
  fs/exfat/exfat_fs.o; do
  if [[ ! -s "$kernel_out/$required_exfat_object" ]]; then
    printf 'The Android build omitted kernel object %s.\n' \
      "$required_exfat_object" >&2
    exit 1
  fi
done
for required_diagnostic_object in \
  fs/pstore/ramoops.o \
  drivers/platform/exynos/exynos_ramoops.o; do
  if [[ ! -s "$kernel_out/$required_diagnostic_object" ]]; then
    printf 'The Android build omitted kernel object %s.\n' \
      "$required_diagnostic_object" >&2
    exit 1
  fi
done
sha256sum \
  "$kernel_out/fs/exfat/exfat_core.o" \
  "$kernel_out/fs/exfat/exfat_fs.o" > "$artifact_dir/EXFAT-KERNEL.txt"
sha256sum \
  "$kernel_out/fs/pstore/ramoops.o" \
  "$kernel_out/drivers/platform/exynos/exynos_ramoops.o" \
  > "$artifact_dir/PSTORE-KERNEL.txt"
cp -a "$kernel_dtb" "$artifact_dir/dtb.img"

copy_required() {
  local source_file="$1"
  if [[ ! -s "$source_file" ]]; then
    printf 'Required build artifact is missing: %s\n' "$source_file" >&2
    exit 1
  fi
  cp -a "$source_file" "$artifact_dir/"
}

case "$target" in
  kernel)
    copy_required "$product_out/kernel"
    ;;
  bootimage)
    copy_required "$product_out/boot.img"
    ;;
  recoveryimage)
    copy_required "$product_out/recovery.img"
    ;;
  bacon)
    copy_required "$product_out/boot.img"
    copy_required "$product_out/recovery.img"
    copy_required "$product_out/dtb.img"

    mapfile -t target_files_packages < <(
      find "$product_out/obj/PACKAGING/target_files_intermediates" \
        -maxdepth 1 -type f -name '*-target_files-*.zip' -print 2>/dev/null |
        LC_ALL=C sort
    )
    if [[ "${#target_files_packages[@]}" -ne 1 ]]; then
      printf 'Expected one target-files ZIP, found %s.\n' \
        "${#target_files_packages[@]}" >&2
      printf '  %s\n' "${target_files_packages[@]}" >&2
      exit 1
    fi

    # Android 10's bacon target retains the canonical sparse system image
    # under the expanded target-files directory instead of PRODUCT_OUT. Copy
    # that exact packaged image so the retained evidence matches the image
    # used to generate the block OTA.
    packaged_system_image="${target_files_packages[0]%.zip}/IMAGES/system.img"
    copy_required "$packaged_system_image"

    mapfile -t ota_packages < <(
      find "$product_out" -maxdepth 1 -type f \
        -name 'lineage-17.1-*.zip' -print | LC_ALL=C sort
    )
    if [[ "${#ota_packages[@]}" -ne 1 ]]; then
      printf 'Expected one LineageOS OTA ZIP, found %s.\n' \
        "${#ota_packages[@]}" >&2
      printf '  %s\n' "${ota_packages[@]}" >&2
      exit 1
    fi
    copy_required "${ota_packages[0]}"
    copy_required "${target_files_packages[0]}"
    ;;
esac

python3 "$local_root/tools/inspect-dtb.py" \
  "$artifact_dir/dtb.img" \
  --expect-string 'Meizu, M86' \
  --require-no-trailing-data | tee "$artifact_dir/DTB-HEADER.txt"

validate_boot_image() {
  local image_name="$1"
  local max_size="$2"
  local report_name="$3"

  python3 "$local_root/tools/inspect-android-boot-image.py" \
    "$artifact_dir/$image_name" \
    --expect-page-size 4096 \
    --expect-kernel-addr 0x40080000 \
    --expect-ramdisk-addr 0x42000000 \
    --expect-second-addr 0x40f00000 \
    --expect-tags-addr 0x40000100 \
    --expect-second-size 0 \
    --expect-dt-size 0 \
    --expect-empty-cmdline \
    --expect-ramdisk-compression gzip \
    --max-size "$max_size" | tee "$artifact_dir/$report_name"
}

if [[ -s "$artifact_dir/boot.img" ]]; then
  validate_boot_image boot.img 25161728 BOOT-HEADER.txt
fi
if [[ -s "$artifact_dir/recovery.img" ]]; then
  validate_boot_image recovery.img 33550336 RECOVERY-HEADER.txt
fi
if [[ -s "$artifact_dir/system.img" ]] && \
    (( $(stat -c '%s' "$artifact_dir/system.img") > 2684350464 )); then
  printf 'system.img exceeds its verified partition limit.\n' >&2
  exit 1
fi

if [[ "$target" == bacon ]]; then
  if ! cmp --quiet "$product_out/dtb.img" "$kernel_dtb"; then
    printf 'Packaged product DTB differs from the configured kernel DTB.\n' >&2
    exit 1
  fi

  ota_package="${ota_packages[0]}"
  "$local_root/tools/audit-lineage-ota.sh" \
    "$ota_package" \
    "$artifact_dir/boot.img" \
    "$kernel_dtb" |
    tee "$artifact_dir/OTA-AUDIT.txt"

  if ! (
    cd "$product_out/system"
    sha256sum --quiet -c "$vendor_blob_lock"
  ); then
    printf 'Installed system tree differs from the 219 locked Flyme inputs.\n' >&2
    exit 1
  fi
  printf 'verified_installed_blob_count=%s\n' "$vendor_blob_count" |
    tee "$artifact_dir/PROPRIETARY-OUTPUT.txt"

  "$local_root/tools/audit-camera-abi.sh" \
    "$source_root" \
    "$out_root" \
    "$product_out/system/lib/libm86camera_shim.so" |
    tee "$artifact_dir/CAMERA-ABI.txt"
  "$local_root/tools/audit-fingerprint-output.sh" "$product_out" |
    tee "$artifact_dir/FINGERPRINT-OUTPUT.txt"
fi

copy_required \
  "$source_root/kernel/meizu/m86/arch/arm64/configs/cm_pro5_defconfig"
cp -a "$kernel_out/.config" "$artifact_dir/kernel.config"
copy_required "$local_root/locks/stock-flyme-8.0.5.0A.sha256"
copy_required "$local_root/locks/kernel-exfat-exynos7420.sha256"
if [[ "$target" == bacon ]]; then
  cp -a "$vendor_blob_lock" "$artifact_dir/m86-proprietary-sha256s.txt"
fi
repo manifest -r -o "$artifact_dir/lineage-17.1-m86-lock.xml"

{
  printf 'built_at=%s\n' "$(date --iso-8601=seconds)"
  printf 'target=lineage_m86-userdebug %s\n' "$target"
  printf 'local_revision=%s\n' "$local_revision"
  printf 'source_root=%s\n' "$source_root"
  printf 'out_root=%s\n' "$out_root"
  printf 'jobs=%s\n' "$jobs"
  printf 'build_datetime=%s\n' "$BUILD_DATETIME"
  printf 'build_number=%s\n' "$BUILD_NUMBER"
  printf 'stock_base=Flyme 8.0.5.0A / Android 7 / API 24\n'
  printf 'verified_vendor_blob_count=%s\n' "$vendor_blob_count"
  printf 'boot_header_cmdline=empty\n'
  printf 'dtb_packaging=raw separate partition\n'
  printf 'ramdisk_compression=gzip\n'
  if [[ "$target" == bacon ]]; then
    printf 'system_image_source=target-files IMAGES/system.img\n'
  fi
} > "$artifact_dir/BUILD-METADATA"

printf 'Build completed at %s\n' "$(date --iso-8601=seconds)"
printf 'Artifacts: %s\n' "$artifact_dir"
ccache --show-stats
cp -a "$log_file" "$artifact_dir/"

(
  cd "$artifact_dir"
  find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 |
    LC_ALL=C sort -z |
    xargs -0 sha256sum
) > "$artifact_dir/SHA256SUMS"
ln -sfn "$(basename "$artifact_dir")" "$artifact_root/lineage-latest"
