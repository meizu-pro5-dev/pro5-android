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
# The builder exposes 128 configured CPUs through sysconf but grants this job
# 32 CPUs. Android 10 dex2oat uses the configured count by default, creating
# 128 compiler workers and exhausting its mmap arena. Match dex2oat to Ninja's
# reviewed job count instead of the host-wide configured CPU count.
export ART_BOOT_IMAGE_EXTRA_ARGS="-j$jobs"

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

product_out="$out_root/target/product/m86"
root_cache="$product_out/root/cache"
if [[ -L "$root_cache" ]]; then
  # BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE now makes /cache a real mountpoint.
  # An incremental tree can retain Android's old /data/cache symlink, and
  # rootdir's mkdir -p cannot replace it. Remove only that generated link and
  # the post-install owner so Ninja recreates the directory idempotently.
  rm -f -- "$root_cache" "$product_out/root/init.environ.rc"
  printf 'Removed stale generated /cache symlink before incremental build.\n'
fi

# An incremental tree can retain the Flyme HWC1/libdisplay/libhdmi copies after
# their generated vendor mappings are removed. Delete only an installed output
# that is byte-identical to the corresponding immutable vendor input so the
# current Android 10 source module owns the destination on this build.
for relative_path in \
  lib/hw/hwcomposer.exynos5.so \
  lib64/hw/hwcomposer.exynos5.so \
  lib/libdisplay.so \
  lib64/libdisplay.so \
  lib/libhdmi.so \
  lib64/libhdmi.so; do
  installed_graphics="$product_out/system/$relative_path"
  vendor_graphics="$source_root/vendor/meizu/m86/proprietary/$relative_path"
  if [[ -f "$installed_graphics" ]] && \
      [[ -f "$vendor_graphics" ]] && \
      cmp --quiet "$installed_graphics" "$vendor_graphics"; then
    rm -f -- "$installed_graphics"
  fi
done
if [[ "$target" == bacon && -d "$product_out/system" ]]; then
  # Earlier m86 product definitions copied Flyme's libion over Android 10's
  # source-built library. Remove only a stale destination that does not export
  # ion_is_legacy so Ninja reinstalls the current module. Keep already-correct
  # outputs intact for idempotent incremental builds.
  for installed_ion in \
    "$product_out/system/lib/libion.so" \
    "$product_out/system/lib64/libion.so"; do
    if [[ -f "$installed_ion" ]] && \
        ! nm -D --defined-only "$installed_ion" 2>/dev/null | \
          awk '$NF == "ion_is_legacy" { found=1 } END { exit !found }'; then
      rm -f -- "$installed_ion"
    fi
  done

  # Earlier bring-up packages selected the generic 64-bit Bluetooth service.
  # The current product selects only the m86 32-bit service, but Android's
  # incremental PRODUCT_OUT can retain the generic init rc and package both
  # definitions of vendor.bluetooth-1-0. Remove only that generated stale rc;
  # Ninja will recreate it if a future product intentionally selects it.
  stale_bluetooth_rc="$product_out/system/vendor/etc/init/android.hardware.bluetooth@1.0-service.rc"
  if [[ -f "$stale_bluetooth_rc" ]]; then
    rm -f -- "$stale_bluetooth_rc"
    printf 'Removed stale generic Bluetooth service rc before packaging.\n'
  fi
fi
if [[ "$target" == bacon && -d "$product_out" ]]; then
  # bacon leaves dated release ZIPs from earlier runs in PRODUCT_OUT. Remove
  # only those generated m86 release packages so the retained artifact cannot
  # be confused with a stale build; Ninja recreates the current output below.
  find "$product_out" -maxdepth 1 -type f \
    -name 'lineage-17.1-*-m86.zip' -delete
fi
mka "$target" -j"$jobs"

artifact_dir="$artifact_root/$build_stamp-$target"
mkdir -p "$artifact_dir"

kernel_out="$product_out/obj/KERNEL_OBJ"
kernel_dtb="$kernel_out/arch/arm64/boot/dts/exynos7420-m86-codegen.dtb"
if [[ ! -s "$kernel_dtb" ]]; then
  printf 'The Android build did not produce the m86 raw DTB.\n' >&2
  exit 1
fi
release_dtb="$kernel_dtb"
if [[ "$target" == bacon ]]; then
  stock_dtb="$remote_root/stock/flyme-8.0.5.0A/stock-boot.dtb"
  release_dtb="$product_out/dtb-hybrid.img"
  python3 "$local_root/tools/build-pro5-hybrid-dtb.py" \
    --dtc "$kernel_out/scripts/dtc/dtc" \
    --stock "$stock_dtb" \
    --output "$release_dtb"
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
sha256sum \
  "$kernel_out/fs/exfat/exfat_core.o" \
  "$kernel_out/fs/exfat/exfat_fs.o" > "$artifact_dir/EXFAT-KERNEL.txt"
cp -a "$release_dtb" "$artifact_dir/dtb.img"

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

    target_files_dir="${target_files_packages[0]%.zip}"
    cp -a "$release_dtb" "$target_files_dir/RADIO/dtb.img"
    (
      cd "$target_files_dir"
      zip -q -u "${target_files_packages[0]}" RADIO/dtb.img
    )

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

    # bacon first generated the OTA with the kernel tree's diagnostic DTB.
    # Re-run releasetools after replacing RADIO/dtb.img so both the signed OTA
    # and retained target-files package contain the reviewed Flyme-based
    # fingerprint hybrid.
    ota_package="${ota_packages[0]}"
    rm -f -- "$ota_package"
    python3 "$source_root/build/make/tools/releasetools/ota_from_target_files.py" \
      -p "$out_root/host/linux-x86" \
      -k "$source_root/build/target/product/security/testkey" \
      "${target_files_packages[0]}" \
      "$ota_package"
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
  if ! unzip -p "${target_files_packages[0]}" RADIO/dtb.img | \
      cmp --quiet - "$release_dtb"; then
    printf 'Packaged target-files DTB differs from the reviewed hybrid.\n' >&2
    exit 1
  fi

  ota_package="${ota_packages[0]}"
  "$local_root/tools/audit-lineage-ota.sh" \
    "$ota_package" \
    "$artifact_dir/boot.img" \
    "$release_dtb" |
    tee "$artifact_dir/OTA-AUDIT.txt"

  installed_vendor_blob_count="$((vendor_blob_count - 10))"
  if ! (
    cd "$product_out/system"
    awk '$2 != "./lib/hw/gralloc.exynos5.so" &&
         $2 != "./lib64/hw/gralloc.exynos5.so" &&
         $2 != "./lib/hw/hwcomposer.exynos5.so" &&
         $2 != "./lib64/hw/hwcomposer.exynos5.so" &&
         $2 != "./lib/libdisplay.so" &&
         $2 != "./lib64/libdisplay.so" &&
         $2 != "./lib/libhdmi.so" &&
         $2 != "./lib64/libhdmi.so" &&
         $2 != "./lib/libion.so" &&
         $2 != "./lib64/libion.so"' \
      "$vendor_blob_lock" |
      sha256sum --quiet -c -
  ); then
    printf 'Installed system tree differs from the %s selected Flyme inputs.\n' \
      "$installed_vendor_blob_count" >&2
    exit 1
  fi

  source_gralloc_32="$product_out/obj_arm/SHARED_LIBRARIES/gralloc.exynos5_intermediates/gralloc.exynos5.so"
  source_gralloc_64="$product_out/obj/SHARED_LIBRARIES/gralloc.exynos5_intermediates/gralloc.exynos5.so"
  if ! cmp --quiet \
      "$product_out/system/lib/hw/gralloc.exynos5.so" \
      "$source_gralloc_32" || \
      ! cmp --quiet \
      "$product_out/system/lib64/hw/gralloc.exynos5.so" \
      "$source_gralloc_64"; then
    printf 'Installed gralloc modules are not the source-built Exynos outputs.\n' >&2
    exit 1
  fi

  source_ion_32="$out_root/soong/.intermediates/system/core/libion/libion/android_arm_armv8-a_core_shared/libion.so"
  source_ion_64="$out_root/soong/.intermediates/system/core/libion/libion/android_arm64_armv8-a_core_shared/libion.so"
  if ! cmp --quiet "$product_out/system/lib/libion.so" "$source_ion_32" || \
      ! cmp --quiet "$product_out/system/lib64/libion.so" "$source_ion_64"; then
    printf 'Installed libion libraries are not the Android 10 outputs.\n' >&2
    exit 1
  fi

  source_hdmi_32="$product_out/obj_arm/SHARED_LIBRARIES/libhdmi_intermediates/libhdmi.so"
  source_hdmi_64="$product_out/obj/SHARED_LIBRARIES/libhdmi_intermediates/libhdmi.so"
  if ! cmp --quiet "$product_out/system/lib/libhdmi.so" "$source_hdmi_32" || \
      ! cmp --quiet "$product_out/system/lib64/libhdmi.so" "$source_hdmi_64"; then
    printf 'Installed libhdmi libraries are not the Android 10 outputs.\n' >&2
    exit 1
  fi
  if readelf -d "$product_out/system/lib/libhdmi.so" | \
      grep -Fq 'Shared library: [libdisplay.so]' || \
      readelf -d "$product_out/system/lib64/libhdmi.so" | \
      grep -Fq 'Shared library: [libdisplay.so]'; then
    printf 'Installed libhdmi still depends on the removed Flyme libdisplay.\n' >&2
    exit 1
  fi

  {
    printf 'verified_locked_blob_count=%s\n' "$vendor_blob_count"
    printf 'verified_installed_blob_count=%s\n' \
      "$installed_vendor_blob_count"
    printf 'source_built_gralloc_count=2\n'
    printf 'source_built_libhdmi_count=2\n'
    printf 'source_built_libion_count=2\n'
  } |
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
  printf 'dtb_artifact=Flyme-based AP fingerprint hybrid\n'
  printf 'dtb_ota_action=write reviewed hybrid to dtb\n'
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
