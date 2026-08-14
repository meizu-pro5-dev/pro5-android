#!/usr/bin/env bash

set -eo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$script_dir/assert-builder-dev-null.sh"
local_root="$(cd "$script_dir/.." && pwd)"
remote_root="$(cd "$local_root/.." && pwd)"
source_root="$remote_root/src/lineage-17.1"
out_root="$remote_root/out/lineage-17.1"
run_root="$remote_root/run"
artifact_root="$remote_root/artifacts"

target="${1:-bootimage}"
jobs="${2:-8}"
requested_jobs="$jobs"
status_file="${3:-$run_root/build-latest.status}"
log_file="${4:-$run_root/build-latest.log}"
build_stamp="${5:-$(date +%Y%m%d-%H%M%S)}"
local_revision="${6:-unknown}"
device_revision="${7:-unknown}"
kernel_revision="${8:-unknown}"
vendor_revision="${9:-unknown}"
local_input_hash="${10:-unknown}"
product="${11:-lineage_m86}"
force_boot_dexpreopt="${12:-0}"

case "$target" in
  kernel | graphics | wifi | bluetooth | nfc | bootimage | recoveryimage | systemimage | testzip | bacon) ;;
  *)
    printf 'Unsupported build target: %s\n' "$target" >&2
    exit 2
    ;;
esac

case "$product" in
  lineage_m86 | lineage_m86_nfc_experiment | lineage_m86_fingerprint_experiment) ;;
  *)
    printf 'Unsupported build product: %s\n' "$product" >&2
    exit 2
    ;;
esac

case "$force_boot_dexpreopt" in
  0 | 1) ;;
  *)
    printf 'Forced boot dexpreopt must be 0 or 1: %s\n' \
      "$force_boot_dexpreopt" >&2
    exit 2
    ;;
esac

nfc_experiment=0
if [[ "$product" == lineage_m86_nfc_experiment ]]; then
  nfc_experiment=1
fi
fingerprint_experiment=0
if [[ "$product" == lineage_m86_fingerprint_experiment ]]; then
  fingerprint_experiment=1
fi
ota_product_suffix="${product#lineage_}"
if [[ "$target" == nfc ]] && (( !nfc_experiment )); then
  printf 'The nfc target is available only for lineage_m86_nfc_experiment.\n' >&2
  exit 2
fi
if [[ "$target" == bacon ]] && ((nfc_experiment || fingerprint_experiment)); then
  printf 'A release bacon build is available only for the default product.\n' >&2
  exit 2
fi
if [[ "$force_boot_dexpreopt" == 1 ]] && \
    { (( !nfc_experiment )) || [[ "$target" != testzip ]]; }; then
  printf 'Forced boot dexpreopt is available only for an NFC experiment testzip.\n' >&2
  exit 2
fi

full_zip_target=0
android_build_target="$target"
if [[ "$target" == bacon || "$target" == testzip ]]; then
  full_zip_target=1
  android_build_target=bacon
fi
module_only_target=0
if [[ "$target" == graphics || "$target" == wifi || \
      "$target" == bluetooth || "$target" == nfc ]]; then
  module_only_target=1
fi

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
    printf 'product=%s\n' "$product"
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

memory_plan_file="$run_root/build-$build_stamp-memory-plan.txt"
"$script_dir/prepare-builder-memory.sh" \
  "$requested_jobs" android "$out_root" "$memory_plan_file"
jobs="$(awk -F= '$1 == "effective_jobs" { print $2 }' "$memory_plan_file")"
if [[ ! "$jobs" =~ ^[1-9][0-9]*$ ]]; then
  printf 'Builder memory plan produced an invalid job count: %s\n' \
    "$jobs" >&2
  exit 1
fi

# shellcheck source=builder-network.sh
source "$script_dir/builder-network.sh"
configure_builder_network

if [[ ! -f "$source_root/build/envsetup.sh" ]]; then
  printf 'LineageOS source is incomplete: %s\n' "$source_root" >&2
  exit 1
fi

if ((!module_only_target)) && \
    [[ ! -f "$source_root/kernel/meizu/m86/arch/arm64/configs/cm_pro5_defconfig" ]]; then
  printf 'The maintained m86 kernel tree is not installed.\n' >&2
  exit 1
fi
kernel_exfat_lock="$local_root/locks/kernel-exfat-exynos7420.sha256"
if ((!module_only_target)); then
  if [[ ! -s "$kernel_exfat_lock" ]] || ! (
    cd "$source_root/kernel/meizu/m86"
    sha256sum --quiet -c "$kernel_exfat_lock"
  ); then
    printf 'The installed Exynos 7420 exFAT source does not match its lock.\n' >&2
    exit 1
  fi
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
if [[ "$target" == systemimage ]] || ((full_zip_target)); then
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
# reviewed job count instead of the host-wide configured CPU count. Full
# system builds generate both architecture boot images; keep each dex2oat
# process single-threaded and serialize the two output edges below.
art_boot_image_jobs="$jobs"
if [[ "$target" == systemimage ]] || ((full_zip_target)); then
  art_boot_image_jobs=1
fi
export ART_BOOT_IMAGE_EXTRA_ARGS="-j$art_boot_image_jobs"
# Lineage 17.1 otherwise uses `nproc --all` for the nested kernel make and
# exposes the builder's 128 configured CPUs. Keep that sub-build inside the
# same reviewed concurrency boundary as Ninja and dex2oat.
export M86_KERNEL_BUILD_JOBS="$jobs"

ccache --max-size=25G
ccache --zero-stats

printf 'Build started at %s\n' "$(date --iso-8601=seconds)"
printf 'Source: %s\nProduct: %s\nTarget: %s\nRequested jobs: %s\nJobs: %s\nOutput: %s\n' \
  "$source_root" "$product" "$target" "$requested_jobs" "$jobs" "$out_root"
printf 'Workspace: %s\nDevice: %s\nKernel: %s\nVendor: %s\n' \
  "$local_revision" "$device_revision" "$kernel_revision" "$vendor_revision"
printf 'Authoritative input snapshot: %s\n' "$local_input_hash"

vendor_blob_count=0
vendor_blob_lock="$remote_root/logs/m86-proprietary-sha256s.txt"
if ((full_zip_target)); then
  vendor_proprietary="$source_root/vendor/meizu/m86/proprietary"
  for vendor_input in "$vendor_blob_lock" "$vendor_proprietary"; do
    if [[ ! -e "$vendor_input" ]]; then
      printf 'Verified m86 vendor input is missing: %s\n' \
        "$vendor_input" >&2
      exit 1
    fi
  done

  vendor_blob_count="$(wc -l < "$vendor_blob_lock" | tr -d ' ')"
  if [[ "$vendor_blob_count" != "224" ]]; then
    printf 'Expected 224 locked m86 blobs, found %s.\n' \
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
lunch "$product-userdebug"
actual_product="$(get_build_var TARGET_PRODUCT)"
actual_kernel_config="$(get_build_var TARGET_KERNEL_CONFIG)"
actual_fpc_backend="$(get_build_var M86_FPC_BACKEND)"
expected_kernel_config=cm_pro5_defconfig
expected_fpc_backend=raw-navigation
if ((fingerprint_experiment)); then
  expected_kernel_config=cm_pro5_fingerprint_experiment_defconfig
  expected_fpc_backend=tee
fi
if [[ "$actual_product" != "$product" || \
      "$actual_kernel_config" != "$expected_kernel_config" || \
      "$actual_fpc_backend" != "$expected_fpc_backend" ]]; then
  printf 'Selected product has an unsafe build graph: product=%s config=%s backend=%s\n' \
    "$actual_product" "$actual_kernel_config" \
    "$actual_fpc_backend" >&2
  exit 1
fi

product_out="$out_root/target/product/m86"
if ((full_zip_target)); then
  # Product ownership changed: remove only installed/generated outputs before
  # packaging so deferred experiment files cannot survive an incremental run.
  mka installclean -j"$jobs"
  # PRODUCT_COPY_FILES keylayouts can survive installclean when the source is
  # an untracked device-owned file and its generated copy predates the current
  # snapshot. Remove only the four M3-owned outputs so Ninja must materialize
  # the sealed source bytes before target-files packaging.
  for stale_m3_keylayout in \
      fts.kl gpio-keys.kl fpc1020.kl uinput-fpc.kl; do
    rm -f -- "$product_out/system/usr/keylayout/$stale_m3_keylayout"
  done
fi

# Android 10 represents the ARM and ARM64 boot jars as independent high-memory
# Ninja edges. Running them together can exhaust this builder's 60 GiB cgroup
# through anonymous mappings plus build-output page cache. Generate the graph
# and build the two exact edges serially. A narrowly matched anonymous-mmap
# failure gets one cache-release retry; other failures stop immediately. The
# following normal mka sees current outputs and regains safe parallelism.
boot_art_logs=()
if [[ "$target" == systemimage ]] || ((full_zip_target)); then
  mka nothing -j1
  combined_ninja="$out_root/combined-$product.ninja"
  ninja_binary="$source_root/prebuilts/build-tools/linux-x86/bin/ninja"

  record_boot_art_memory_snapshot() {
    local prefix="$1"

    {
      printf '%s_timestamp=%s\n' "$prefix" "$(date --iso-8601=ns)"
      printf '%s_cgroup_memory_current_bytes=%s\n' \
        "$prefix" "$(</sys/fs/cgroup/memory.current)"
      printf '%s_cgroup_memory_max_bytes=%s\n' \
        "$prefix" "$(</sys/fs/cgroup/memory.max)"
      awk -v prefix="$prefix" \
        '{ printf "%s_cgroup_memory_stat_%s=%s\n", prefix, $1, $2 }' \
        /sys/fs/cgroup/memory.stat
      awk -v prefix="$prefix" \
        '{ printf "%s_cgroup_memory_event_%s=%s\n", prefix, $1, $2 }' \
        /sys/fs/cgroup/memory.events
      awk -v prefix="$prefix" '
        /^MemAvailable:/ {
          printf "%s_host_mem_available_kib=%s\n", prefix, $2
        }
        /^CommitLimit:/ {
          printf "%s_host_commit_limit_kib=%s\n", prefix, $2
        }
        /^Committed_AS:/ {
          printf "%s_host_committed_as_kib=%s\n", prefix, $2
        }
      ' /proc/meminfo
    } >> "$memory_plan_file"
  }

  for boot_arch in arm arm64; do
    boot_art="$out_root/soong/m86/dex_bootjars/system/framework/$boot_arch/boot.art"
    if ((force_boot_dexpreopt)); then
      # This is a generated Ninja output, never a source input. Removing this
      # sole primary output forces its normal edge to execute so the retained
      # attempt log proves a real dex2oat run rather than a cache hit.
      rm -f -- "$boot_art"
      printf 'boot_%s_forced_regeneration=1\n' "$boot_arch" >> \
        "$memory_plan_file"
    fi
    boot_art_succeeded=0
    for boot_art_attempt in 1 2; do
      boot_art_prefix="boot_${boot_arch}_attempt_${boot_art_attempt}"
      boot_art_log="$run_root/build-$build_stamp-$boot_arch-boot-art-attempt-$boot_art_attempt.log"
      boot_art_logs+=("$boot_art_log")
      record_boot_art_memory_snapshot "${boot_art_prefix}_before"
      printf '%s_log=%s\n' "$boot_art_prefix" "$boot_art_log" >> \
        "$memory_plan_file"
      set +e
      "$ninja_binary" -f "$combined_ninja" -j1 "$boot_art" 2>&1 | \
        tee "$boot_art_log"
      boot_art_pipeline_status=("${PIPESTATUS[@]}")
      boot_art_status="${boot_art_pipeline_status[0]}"
      boot_art_tee_status="${boot_art_pipeline_status[1]}"
      set -e
      record_boot_art_memory_snapshot "${boot_art_prefix}_after"
      printf '%s_ninja_exit=%s\n' "$boot_art_prefix" \
        "$boot_art_status" >> "$memory_plan_file"
      printf '%s_tee_exit=%s\n' "$boot_art_prefix" \
        "$boot_art_tee_status" >> "$memory_plan_file"
      if [[ "$boot_art_tee_status" != 0 ]]; then
        printf 'Failed to save the %s boot ART attempt log: %s\n' \
          "$boot_arch" "$boot_art_log" >&2
        exit 1
      fi
      if [[ "$boot_art_status" == 0 ]]; then
        if ((force_boot_dexpreopt)) && \
            ! grep -E -q 'dex2oat took .*\(threads: 1\)' "$boot_art_log"; then
          printf 'Forced %s boot ART did not execute single-threaded dex2oat.\n' \
            "$boot_arch" >&2
          exit 1
        fi
        boot_art_succeeded=1
        break
      fi
      if [[ "$boot_art_attempt" == 1 ]] && \
          grep -E -q 'Failed anonymous mmap.*Cannot allocate memory' \
            "$boot_art_log"; then
        python3 "$script_dir/release-build-cache.py" \
          "$out_root" --min-size $((1024 * 1024)) | \
          sed "s/^/${boot_art_prefix}_retry_/" | \
          tee -a "$memory_plan_file"
        printf '%s_retry_reason=transient_anonymous_mmap_failure\n' \
          "$boot_art_prefix" >> "$memory_plan_file"
        sleep 2
        continue
      fi
      printf 'Serialized %s boot ART attempt %s failed with exit %s.\n' \
        "$boot_arch" "$boot_art_attempt" "$boot_art_status" >&2
      exit "$boot_art_status"
    done
    if ((boot_art_succeeded == 0)); then
      printf 'Serialized %s boot ART failed after two attempts.\n' \
        "$boot_arch" >&2
      exit "$boot_art_status"
    fi
    if [[ ! -s "$boot_art" ]]; then
      printf 'Serialized %s boot image was not produced: %s\n' \
        "$boot_arch" "$boot_art" >&2
      exit 1
    fi
  done
fi
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
  lib64/libhdmi.so \
  lib/hw/memtrack.exynos5.so \
  lib64/hw/memtrack.exynos5.so \
  lib/libexynosgscaler.so \
  lib64/libexynosgscaler.so \
  lib/libexynosscaler.so \
  lib64/libexynosscaler.so \
  lib/libexynosutils.so \
  lib64/libexynosutils.so \
  lib/libexynosv4l2.so \
  lib64/libexynosv4l2.so \
  lib/libhwcutils.so \
  lib64/libhwcutils.so \
  lib/libmpp.so \
  lib64/libmpp.so; do
  installed_graphics="$product_out/system/$relative_path"
  vendor_graphics="$source_root/vendor/meizu/m86/proprietary/$relative_path"
  if [[ -f "$installed_graphics" ]] && \
      [[ -f "$vendor_graphics" ]] && \
      cmp --quiet "$installed_graphics" "$vendor_graphics"; then
    rm -f -- "$installed_graphics"
  fi
done

# M2 replaces the patched platform gralloc with the uniquely named m86-owned
# module. Remove only byte-identical outputs left by the former source module;
# an unknown file at either destination remains untouched and fails the later
# owner audit.
for multilib in 32 64; do
  if [[ "$multilib" == 32 ]]; then
    old_installed_gralloc="$product_out/system/lib/hw/gralloc.exynos5.so"
    old_source_gralloc="$product_out/obj_arm/SHARED_LIBRARIES/gralloc.exynos5_intermediates/gralloc.exynos5.so"
  else
    old_installed_gralloc="$product_out/system/lib64/hw/gralloc.exynos5.so"
    old_source_gralloc="$product_out/obj/SHARED_LIBRARIES/gralloc.exynos5_intermediates/gralloc.exynos5.so"
  fi
  if [[ -f "$old_installed_gralloc" ]] && \
      [[ -f "$old_source_gralloc" ]] && \
      cmp --quiet "$old_installed_gralloc" "$old_source_gralloc"; then
    rm -f -- "$old_installed_gralloc"
    printf 'Removed retired source gralloc output: %s\n' \
      "$old_installed_gralloc"
  fi
done

# M2 no longer installs the unused Exynos HWC service or the unreferenced CEC
# and FIMG modules. Remove only known former owners from an incremental output;
# an unknown file is retained and rejected by the post-build absence audit.
for multilib in 32 64; do
  installed_root="$product_out/system/lib"
  object_root="$product_out/obj_arm"
  if [[ "$multilib" == 64 ]]; then
    installed_root="$product_out/system/lib64"
    object_root="$product_out/obj"
  fi
  deferred_hwc_service="$installed_root/libExynosHWCService.so"
  vendor_hwc_service="$source_root/vendor/meizu/m86/proprietary/${installed_root#"$product_out/system/"}/libExynosHWCService.so"
  if [[ -f "$deferred_hwc_service" ]] && \
      [[ -f "$vendor_hwc_service" ]] && \
      cmp --quiet "$deferred_hwc_service" "$vendor_hwc_service"; then
    rm -f -- "$deferred_hwc_service"
  fi
  for optional_module in libcec libfimg; do
    optional_installed="$installed_root/$optional_module.so"
    optional_source="$object_root/SHARED_LIBRARIES/${optional_module}_intermediates/${optional_module}.so"
    if [[ -f "$optional_installed" ]] && \
        [[ -f "$optional_source" ]] && \
        cmp --quiet "$optional_installed" "$optional_source"; then
      rm -f -- "$optional_installed"
    fi
  done
done

# M4 owns platform rild and SITRIL. Remove only byte-identical stale copies of
# the unused pre-HIDL helpers from an incremental output; target-files audits
# reject either helper if a product mapping accidentally reinstalls it.
for relative_path in bin/rild_exynos bin/radiooptions_exynos; do
  installed_radio="$product_out/system/$relative_path"
  vendor_radio="$source_root/vendor/meizu/m86/proprietary/$relative_path"
  if [[ -f "$installed_radio" ]] && [[ -f "$vendor_radio" ]] && \
      cmp --quiet "$installed_radio" "$vendor_radio"; then
    rm -f -- "$installed_radio"
    printf 'Removed deferred radio output: %s\n' "$installed_radio"
  fi
done

if ((full_zip_target)) && [[ -d "$product_out/system" ]]; then
  # The retired source-built libfprint HAL installs under /vendor and wins
  # hw_get_module's search order over Flyme 8's secure /system HAL.  Older
  # incremental trees can retain it after PRODUCT_PACKAGES stops selecting it,
  # so remove only these exact generated shadow destinations before packaging.
  for stale_fingerprint_hal in \
    "$product_out/vendor/lib64/hw/fingerprint.m86.so" \
    "$product_out/system/vendor/lib64/hw/fingerprint.m86.so"; do
    if [[ -f "$stale_fingerprint_hal" ]]; then
      rm -f -- "$stale_fingerprint_hal"
      printf 'Removed stale raw fingerprint HAL: %s\n' \
        "$stale_fingerprint_hal"
    fi
  done

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

fi

# M4 gives the service and passthrough implementation unique m86-owned names.
# Remove only the exact retired install destinations so an incremental output
# cannot retain the generic service or either impl.zero bitness. The current
# graph recreates none of these paths and the post-build audit rejects them.
if [[ "$target" == bluetooth || "$target" == systemimage ]] || \
    ((full_zip_target)); then
  for stale_bluetooth_output in \
    "$product_out/system/vendor/bin/hw/android.hardware.bluetooth@1.0-service" \
    "$product_out/system/vendor/etc/init/android.hardware.bluetooth@1.0-service.rc" \
    "$product_out/system/vendor/lib/hw/android.hardware.bluetooth@1.0-impl.zero.so" \
    "$product_out/system/vendor/lib64/hw/android.hardware.bluetooth@1.0-impl.zero.so"; do
    if [[ -e "$stale_bluetooth_output" ]]; then
      rm -f -- "$stale_bluetooth_output"
      printf 'Removed retired Bluetooth output: %s\n' \
        "$stale_bluetooth_output"
    fi
  done
fi
# The Flyme 64-bit primary HAL is inventory-only after the m86 wrapper handoff.
# installclean does not reliably remove a previously copied PRODUCT_OUT file,
# so remove this exact retired destination before every systemimage/full build
# and verify it again after Ninja.  Never broaden this cleanup to other outputs.
if [[ "$target" == systemimage ]] || ((full_zip_target)); then
  rm -f -- "$product_out/system/lib64/hw/audio.primary.m86.so"
fi
if ((full_zip_target)) && [[ -d "$product_out" ]]; then
  # bacon leaves dated packages from earlier runs in PRODUCT_OUT. Keep default
  # and experiment products isolated so a stale package cannot be mistaken for
  # the current selected product; Ninja recreates the current output below.
  find "$product_out" -maxdepth 1 -type f \
    -name "lineage-17.1-*-$ota_product_suffix.zip" -delete
fi
if [[ "$target" == graphics ]]; then
  build_targets=(
    gralloc.m86-target32
    gralloc.m86-target64
    hwcomposer.exynos5-target32
    hwcomposer.exynos5-target64
    memtrack.exynos5-target32
    memtrack.exynos5-target64
    libexynosdisplay-target32
    libexynosdisplay-target64
    libexynosgscaler-target32
    libexynosgscaler-target64
    libexynosscaler-target32
    libexynosscaler-target64
    libexynosutils-target32
    libexynosutils-target64
    libexynosv4l2-target32
    libexynosv4l2-target64
    libhwcutils-target32
    libhwcutils-target64
    libmpp-target32
    libmpp-target64
    libhdmi-target32
    libhdmi-target64
    libion-target32
    libion-target64
    libhwc2on1adapter-target32
    libhwc2on1adapter-target64
    libhwc2onfbadapter-target32
    libhwc2onfbadapter-target64
    android.hardware.graphics.allocator@2.0-impl
    android.hardware.graphics.allocator@2.0-service
    android.hardware.graphics.composer@2.1-impl
    android.hardware.graphics.mapper@2.0-impl
    android.hardware.memtrack@1.0-impl
  )
elif [[ "$target" == bluetooth ]]; then
  build_targets=(
    android.hardware.bluetooth@1.0-impl.m86
    android.hardware.bluetooth@1.0-service.m86
  )
elif [[ "$target" == wifi ]]; then
  build_targets=(
    android.hardware.wifi@1.0-service.legacy
    hostapd
    wpa_supplicant
  )
elif [[ "$target" == nfc ]]; then
  build_targets=(
    android.hardware.nfc@1.1-service
    nfc_nci_nxp
    NfcNci
    Tag
  )
else
  build_targets=("$android_build_target" m86-dtbimage)
  if [[ "$target" == systemimage ]]; then
    build_targets+=(bootimage)
  fi
fi
mback_policy_log="$run_root/build-$build_stamp-mback-key-policy.txt"
"$local_root/tools/test-mback-key-policy.sh" | tee "$mback_policy_log"
mka "${build_targets[@]}" -j"$jobs"

artifact_dir="$artifact_root/$build_stamp-$product-$target"
mkdir -p "$artifact_dir"
if [[ "$target" == systemimage ]]; then
  audio_wrapper="$product_out/system/lib/hw/audio.primary.m86.so"
  audio_flyme32="$product_out/system/lib/hw/audio.primary.m86.flyme.so"
  audio_flyme32_source="$source_root/vendor/meizu/m86/proprietary/lib/hw/audio.primary.m86.so"
  if [[ ! -s "$audio_wrapper" ]] || [[ ! -s "$audio_flyme32" ]] || \
      ! cmp --quiet "$audio_flyme32" "$audio_flyme32_source" || \
      [[ -e "$product_out/system/lib64/hw/audio.primary.m86.so" ]]; then
    printf 'M5 systemimage audio ownership is incomplete: expected 32-bit wrapper + raw input and no 64-bit raw HAL.\n' >&2
    exit 1
  fi
  printf 'M5 systemimage audio ownership: wrapper=32-bit, flyme32=source-equal, flyme64=absent\n' \
    > "$artifact_dir/M5-AUDIO-TARGET-FILES.txt"
fi
for boot_art_log in "${boot_art_logs[@]}"; do
  cp -a "$boot_art_log" "$artifact_dir/"
done
cp -a "$mback_policy_log" "$artifact_dir/M3-MBACK-POLICY-TEST.txt"

kernel_out="$product_out/obj/KERNEL_OBJ"
kernel_dtb="$kernel_out/arch/arm64/boot/dts/exynos7420-m86-codegen.dtb"
release_dtb="$product_out/dtb.img"
expected_dtb_hash="8b9121f25a78716ac1710536cea562967bd77ad0cf2df283ae25715808cff1cc"
actual_dtb_hash="not-audited-for-$target"
if ((!module_only_target)); then
  if [[ ! -s "$kernel_dtb" ]]; then
    printf 'The Android build did not produce the m86 raw DTB.\n' >&2
    exit 1
  fi
  if [[ ! -s "$release_dtb" ]]; then
    printf 'The build graph did not install the locked m86 DTB.\n' >&2
    exit 1
  fi
  actual_dtb_hash="$(sha256sum "$release_dtb" | awk '{ print $1 }')"
  if ((fingerprint_experiment)); then
    if ! cmp --quiet "$release_dtb" \
        "$source_root/device/meizu/m86/prebuilt/dtb.img"; then
      printf 'Installed fingerprint experiment DTB differs from the stock secure-mode DTB.\n' >&2
      exit 1
    fi
    printf 'fingerprint_dtb=stock-secure-mode\n' \
      | tee "$artifact_dir/M8-FP-DTB.txt"
    for required_fp_kernel_setting in \
      '# CONFIG_FINGERPRINT_FPC_FPC1020_FAMILY is not set' \
      CONFIG_FINGERPRINT_FPC_TEE=y \
      '# CONFIG_SECURE_OS_BOOSTER_API is not set'; do
      if ! grep -F -x -q "$required_fp_kernel_setting" \
          "$kernel_out/.config"; then
        printf 'The generated fingerprint kernel config omitted %s.\n' \
          "$required_fp_kernel_setting" >&2
        exit 1
      fi
    done
  else
    if [[ "$actual_dtb_hash" != "$expected_dtb_hash" ]]; then
      printf 'Installed m86 mBack DTB hash mismatch: %s\n' "$actual_dtb_hash" >&2
      exit 1
    fi
    python3 "$source_root/device/meizu/m86/tools/build-mback-dtb.py" \
      --stock "$source_root/device/meizu/m86/prebuilt/dtb.img" \
      --verify "$release_dtb" | tee "$artifact_dir/M3-DTB.txt"
    for required_mback_kernel_setting in \
      CONFIG_FINGERPRINT_FPC_FPC1020_FAMILY=y \
      '# CONFIG_FINGERPRINT_FPC_TEE is not set' \
      '# CONFIG_SECURE_OS_BOOSTER_API is not set'; do
      if ! grep -F -x -q "$required_mback_kernel_setting" \
          "$kernel_out/.config"; then
        printf 'The generated m86 kernel config omitted %s.\n' \
          "$required_mback_kernel_setting" >&2
        exit 1
      fi
    done
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
  cp -a "$kernel_dtb" "$artifact_dir/kernel-generated.dtb"
fi

copy_required() {
  local source_file="$1"
  if [[ ! -s "$source_file" ]]; then
    printf 'Required build artifact is missing: %s\n' "$source_file" >&2
    exit 1
  fi
  cp -a "$source_file" "$artifact_dir/"
}

graphics_relative_paths=(
  lib/hw/gralloc.m86.so
  lib64/hw/gralloc.m86.so
  lib/hw/hwcomposer.exynos5.so
  lib64/hw/hwcomposer.exynos5.so
  lib/hw/memtrack.exynos5.so
  lib64/hw/memtrack.exynos5.so
  lib/libexynosdisplay.so
  lib64/libexynosdisplay.so
  lib/libexynosgscaler.so
  lib64/libexynosgscaler.so
  lib/libexynosscaler.so
  lib64/libexynosscaler.so
  lib/libexynosutils.so
  lib64/libexynosutils.so
  lib/libexynosv4l2.so
  lib64/libexynosv4l2.so
  lib/libhwcutils.so
  lib64/libhwcutils.so
  lib/libmpp.so
  lib64/libmpp.so
  lib/libhdmi.so
  lib64/libhdmi.so
  lib/libion.so
  lib64/libion.so
  vendor/lib/libhwc2on1adapter.so
  vendor/lib64/libhwc2on1adapter.so
  vendor/lib/libhwc2onfbadapter.so
  vendor/lib64/libhwc2onfbadapter.so
)

graphics_interface_relative_paths=(
  vendor/bin/hw/android.hardware.graphics.allocator@2.0-service
  vendor/lib/hw/android.hardware.graphics.allocator@2.0-impl.so
  vendor/lib64/hw/android.hardware.graphics.allocator@2.0-impl.so
  vendor/lib/hw/android.hardware.graphics.composer@2.1-impl.so
  vendor/lib64/hw/android.hardware.graphics.composer@2.1-impl.so
  vendor/lib/hw/android.hardware.graphics.mapper@2.0-impl.so
  vendor/lib64/hw/android.hardware.graphics.mapper@2.0-impl.so
  vendor/lib/hw/android.hardware.memtrack@1.0-impl.so
  vendor/lib64/hw/android.hardware.memtrack@1.0-impl.so
)

assert_single_ninja_owner() {
  local installed_file="$1"
  local ninja_file="$out_root/build-$product.ninja"
  local ninja_output="${installed_file#"$out_root/"}"
  local producer_count

  [[ -s "$ninja_file" ]] || {
    printf 'Generated Ninja graph is missing: %s\n' "$ninja_file" >&2
    exit 1
  }
  # Kati records installed outputs as absolute paths in this graph.  Keep the
  # relative form only for the diagnostic so the audit cannot silently report
  # zero producers for every valid installed file.
  producer_count="$(grep -F -c "build $installed_file:" "$ninja_file" || true)"
  if [[ "$producer_count" != 1 ]]; then
    printf 'Expected one Ninja producer for %s, found %s.\n' \
      "$ninja_output" "$producer_count" >&2
    exit 1
  fi
}

assert_graphics_elf_identity() {
  local elf_file="$1"
  local expected_class="$2"
  local expected_soname="$3"
  local expected_machine=ARM
  local actual_class
  local actual_machine
  local actual_soname

  if [[ ! -s "$elf_file" ]]; then
    printf 'Required graphics ELF is missing: %s\n' "$elf_file" >&2
    exit 1
  fi
  if [[ "$expected_class" == ELF64 ]]; then
    expected_machine=AArch64
  fi
  actual_class="$(
    readelf -h "$elf_file" |
      awk -F: '$1 ~ /Class$/ { gsub(/^[[:space:]]+/, "", $2); print $2; exit }'
  )"
  actual_machine="$(
    readelf -h "$elf_file" |
      awk -F: '$1 ~ /Machine$/ { gsub(/^[[:space:]]+/, "", $2); print $2; exit }'
  )"
  actual_soname=not-required
  if [[ "$expected_soname" != not-required ]]; then
    actual_soname="$(
      readelf -d "$elf_file" |
        sed -n 's/.*Library soname: \[\([^]]*\)\].*/\1/p' |
        awk 'NR == 1 { print; exit }'
    )"
  fi
  if [[ "$actual_class" != "$expected_class" || \
        "$actual_machine" != "$expected_machine" || \
        "$actual_soname" != "$expected_soname" ]]; then
    printf 'Unexpected graphics ELF identity for %s: class=%s machine=%s soname=%s\n' \
      "$elf_file" "${actual_class:-missing}" "${actual_machine:-missing}" \
      "${actual_soname:-missing}" >&2
    exit 1
  fi
}

assert_source_graphics_outputs() {
  local multilib
  local object_root
  local installed_root
  local module
  local installed_file
  local vendor_installed_root
  local source_file
  local relative_path
  local expected_class

  for multilib in 32 64; do
    object_root="$product_out/obj_arm"
    installed_root="$product_out/system/lib"
    expected_class=ELF32
    if [[ "$multilib" == 64 ]]; then
      object_root="$product_out/obj"
      installed_root="$product_out/system/lib64"
      expected_class=ELF64
    fi
    vendor_installed_root="$product_out/system/vendor/lib"
    if [[ "$multilib" == 64 ]]; then
      vendor_installed_root="$product_out/system/vendor/lib64"
    fi
    for module in \
      gralloc.m86 \
      hwcomposer.exynos5 \
      memtrack.exynos5 \
      libexynosdisplay \
      libexynosgscaler \
      libexynosscaler \
      libexynosutils \
      libexynosv4l2 \
      libhwcutils \
      libmpp \
      libhdmi; do
      case "$module" in
        gralloc.m86 | hwcomposer.exynos5 | memtrack.exynos5)
          relative_path="hw/$module.so"
          ;;
        *)
          relative_path="$module.so"
          ;;
      esac
      installed_file="$installed_root/$relative_path"
      source_file="$object_root/SHARED_LIBRARIES/${module}_intermediates/${module}.so"
      if ! cmp --quiet "$installed_file" "$source_file"; then
        printf 'Installed graphics output is not source-owned: %s\n' \
          "$installed_file" >&2
        exit 1
      fi
      assert_graphics_elf_identity \
        "$installed_file" "$expected_class" "$module.so"
      if [[ "$(readelf -d "$installed_file")" == \
          *'Shared library: [libdisplay.so]'* ]]; then
        printf 'Source-owned graphics output still depends on retired libdisplay: %s\n' \
          "$installed_file" >&2
        exit 1
      fi
      assert_single_ninja_owner "$installed_file"
    done

    relative_path=libion.so
    installed_file="$installed_root/$relative_path"
    source_file="$out_root/soong/.intermediates/system/core/libion/libion/android_arm_armv8-a_core_shared/libion.so"
    if [[ "$multilib" == 64 ]]; then
      source_file="$out_root/soong/.intermediates/system/core/libion/libion/android_arm64_armv8-a_core_shared/libion.so"
    fi
    if ! cmp --quiet "$installed_file" "$source_file"; then
      printf 'Installed libion is not the Android source output: %s\n' \
        "$installed_file" >&2
      exit 1
    fi
    assert_graphics_elf_identity \
      "$installed_file" "$expected_class" libion.so
    assert_single_ninja_owner "$installed_file"

    for module in libhwc2on1adapter libhwc2onfbadapter; do
      installed_file="$vendor_installed_root/$module.so"
      source_file="$object_root/SHARED_LIBRARIES/${module}_intermediates/${module}.so"
      if ! cmp --quiet "$installed_file" "$source_file"; then
        printf 'Installed graphics adapter is not source-owned: %s\n' \
          "$installed_file" >&2
        exit 1
      fi
      assert_graphics_elf_identity \
        "$installed_file" "$expected_class" "$module.so"
      assert_single_ninja_owner "$installed_file"
    done

    for module in \
      android.hardware.graphics.allocator@2.0-impl \
      android.hardware.graphics.composer@2.1-impl \
      android.hardware.graphics.mapper@2.0-impl \
      android.hardware.memtrack@1.0-impl; do
      installed_file="$vendor_installed_root/hw/$module.so"
      source_file="$object_root/SHARED_LIBRARIES/${module}_intermediates/${module}.so"
      if ! cmp --quiet "$installed_file" "$source_file"; then
        printf 'Installed graphics interface is not source-owned: %s\n' \
          "$installed_file" >&2
        exit 1
      fi
      assert_graphics_elf_identity \
        "$installed_file" "$expected_class" "$module.so"
      assert_single_ninja_owner "$installed_file"
    done
  done

  installed_file="$product_out/system/vendor/bin/hw/android.hardware.graphics.allocator@2.0-service"
  source_file="$product_out/obj/EXECUTABLES/android.hardware.graphics.allocator@2.0-service_intermediates/android.hardware.graphics.allocator@2.0-service"
  if ! cmp --quiet "$installed_file" "$source_file"; then
    printf 'Installed graphics allocator service is not source-owned: %s\n' \
      "$installed_file" >&2
    exit 1
  fi
  assert_graphics_elf_identity \
    "$installed_file" ELF64 not-required
  assert_single_ninja_owner "$installed_file"
  for retired_gralloc in \
    "$product_out/system/lib/hw/gralloc.exynos5.so" \
    "$product_out/system/lib64/hw/gralloc.exynos5.so"; do
    if [[ -e "$retired_gralloc" ]]; then
      printf 'Retired Exynos gralloc destination is still installed: %s\n' \
        "$retired_gralloc" >&2
      exit 1
    fi
  done
}

write_source_graphics_report() {
  local report_file="$1"
  local relative_path
  local graphics_elf

  {
    printf 'source_owned_graphics_family_destination_count=%s\n' \
      "${#graphics_relative_paths[@]}"
    printf 'source_owned_graphics_family_soname_count=14\n'
    printf 'source_owned_graphics_interface_destination_count=%s\n' \
      "${#graphics_interface_relative_paths[@]}"
    printf 'source_owned_graphics_runtime_destination_count=%s\n' \
      "$((${#graphics_relative_paths[@]} + ${#graphics_interface_relative_paths[@]}))"
    for relative_path in "${graphics_relative_paths[@]}"; do
      graphics_elf="$product_out/system/$relative_path"
      printf 'file=%s\n' "system/$relative_path"
      file "$graphics_elf"
      sha256sum "$graphics_elf"
      readelf -d "$graphics_elf" | grep -E 'NEEDED|SONAME' || true
    done
    for relative_path in "${graphics_interface_relative_paths[@]}"; do
      graphics_elf="$product_out/system/$relative_path"
      printf 'file=%s\n' "system/$relative_path"
      file "$graphics_elf"
      sha256sum "$graphics_elf"
      readelf -d "$graphics_elf" | grep -E 'NEEDED|SONAME' || true
    done
  } > "$report_file"
}

assert_deferred_graphics_absent() {
  local forbidden_graphics
  for forbidden_graphics in \
    "$product_out/system/lib/libdisplay.so" \
    "$product_out/system/lib64/libdisplay.so" \
    "$product_out/system/lib/libExynosHWCService.so" \
    "$product_out/system/lib64/libExynosHWCService.so" \
    "$product_out/system/lib/libcec.so" \
    "$product_out/system/lib64/libcec.so" \
    "$product_out/system/lib/libfimg.so" \
    "$product_out/system/lib64/libfimg.so"; do
    if [[ -e "$forbidden_graphics" ]]; then
      printf 'Deferred graphics output is still installed: %s\n' \
        "$forbidden_graphics" >&2
      exit 1
    fi
  done
}

assert_elf32_arm() {
  local elf_file="$1"
  if ! readelf -h "$elf_file" | \
      grep -F -q 'Class:                             ELF32' || \
      ! readelf -h "$elf_file" | \
      grep -F -q 'Machine:                           ARM'; then
    printf 'Expected a 32-bit ARM Bluetooth ELF: %s\n' "$elf_file" >&2
    exit 1
  fi
}

assert_wifi_outputs() {
  local service_file="$product_out/system/vendor/bin/hw/android.hardware.wifi@1.0-service.legacy"
  local hostapd_file="$product_out/system/vendor/bin/hw/hostapd"
  local supplicant_file="$product_out/system/vendor/bin/hw/wpa_supplicant"
  local vendor_proprietary="$source_root/vendor/meizu/m86/proprietary"
  local expected_hash
  local actual_hash
  local relative_path
  local installed_path
  local source_path
  local wifi_init_count
  local -a service_files

  for required_wifi_output in \
    "$service_file" \
    "$hostapd_file" \
    "$supplicant_file" \
    "$vendor_blob_lock"; do
    if [[ ! -s "$required_wifi_output" ]]; then
      printf 'Required Wi-Fi output is missing: %s\n' \
        "$required_wifi_output" >&2
      exit 1
    fi
  done
  mapfile -t service_files < <(
    find "$product_out/system/vendor/bin/hw" -maxdepth 1 -type f \
      -name 'android.hardware.wifi@1.0-service*' -print 2>/dev/null |
      LC_ALL=C sort
  )
  if [[ "${#service_files[@]}" -ne 1 || \
        "${service_files[0]:-}" != "$service_file" ]]; then
    printf 'Wi-Fi HAL service ownership is not the unique legacy service.\n' >&2
    printf '  %s\n' "${service_files[@]:-none}" >&2
    exit 1
  fi
  for wifi_binary in "$service_file" "$hostapd_file" "$supplicant_file"; do
    assert_single_ninja_owner "$wifi_binary"
  done
  wifi_init_count="$(count_regular_file_matches \
    "$product_out/system/vendor/etc/init" \
    'service vendor.wifi_hal_legacy /vendor/bin/hw/android.hardware.wifi@1.0-service.legacy')"
  if [[ "$wifi_init_count" != 1 ]]; then
    printf 'Wi-Fi HAL init ownership is not unique: count=%s\n' \
      "$wifi_init_count" >&2
    exit 1
  fi

  for relative_path in \
    etc/wifi/bcmdhd.cal \
    vendor/firmware/fw_bcmdhd.bin \
    vendor/firmware/fw_bcmdhd_apsta.bin; do
    source_path="$vendor_proprietary/$relative_path"
    expected_hash="$(awk -v path="./$relative_path" \
      '$2 == path { print $1 }' "$vendor_blob_lock")"
    actual_hash="$(sha256sum "$source_path" 2>/dev/null | awk '{ print $1 }')"
    if [[ ! "$expected_hash" =~ ^[0-9a-f]{64}$ || \
          "$actual_hash" != "$expected_hash" ]]; then
      printf 'Locked m86 Wi-Fi input mismatch: %s\n' "$relative_path" >&2
      exit 1
    fi
    installed_path="$product_out/system/$relative_path"
    if [[ "$target" != wifi ]]; then
      if ! cmp --quiet "$installed_path" "$source_path"; then
        printf 'Installed Wi-Fi input differs from its locked source: %s\n' \
          "$relative_path" >&2
        exit 1
      fi
      assert_single_ninja_owner "$installed_path"
    fi
  done

  cp -a "$service_file" "$hostapd_file" "$supplicant_file" "$artifact_dir/"
  {
    printf 'service=%s\n' "${service_file#"$product_out/"}"
    printf 'hostapd=%s\n' "${hostapd_file#"$product_out/"}"
    printf 'supplicant=%s\n' "${supplicant_file#"$product_out/"}"
    printf 'service_owner_count=%s\n' "${#service_files[@]}"
    printf 'init_owner_count=%s\n' "$wifi_init_count"
    for relative_path in \
      etc/wifi/bcmdhd.cal \
      vendor/firmware/fw_bcmdhd.bin \
      vendor/firmware/fw_bcmdhd_apsta.bin; do
      source_path="$vendor_proprietary/$relative_path"
      printf 'locked_input=%s\n' "$relative_path"
      sha256sum "$source_path"
    done
  } > "$artifact_dir/WIFI-OUTPUT.txt"
}

assert_bluetooth_outputs() {
  local service_file
  local impl_file
  local blob_file
  local source_blob
  local service_object
  local impl_object
  local expected_blob_hash
  local actual_blob_hash
  local installed_blob_file
  local expected_manifest_file
  local source_manifest_file
  local -a service_files
  local -a impl32_files
  local -a impl64_files
  local -a bluetooth_rc_files
  local -a bluetooth_manifest_files

  service_file="$product_out/system/vendor/bin/hw/android.hardware.bluetooth@1.0-service.m86"
  impl_file="$product_out/system/vendor/lib/hw/android.hardware.bluetooth@1.0-impl.m86.so"
  blob_file="$product_out/system/vendor/lib/libbt-vendor.so"
  source_blob="$source_root/vendor/meizu/m86/proprietary/vendor/lib/libbt-vendor.so"
  service_object="$product_out/obj_arm/EXECUTABLES/android.hardware.bluetooth@1.0-service.m86_intermediates/android.hardware.bluetooth@1.0-service.m86"
  impl_object="$product_out/obj_arm/SHARED_LIBRARIES/android.hardware.bluetooth@1.0-impl.m86_intermediates/android.hardware.bluetooth@1.0-impl.m86.so"

  for required_bluetooth_output in \
    "$service_file" "$impl_file" "$service_object" "$impl_object" \
    "$source_blob" "$vendor_blob_lock"; do
    if [[ ! -s "$required_bluetooth_output" ]]; then
      printf 'Required Bluetooth output is missing: %s\n' \
        "$required_bluetooth_output" >&2
      exit 1
    fi
  done
  if ! cmp --quiet "$service_file" "$service_object" || \
      ! cmp --quiet "$impl_file" "$impl_object"; then
    printf 'Installed Bluetooth service or implementation is not source-owned.\n' >&2
    exit 1
  fi
  assert_elf32_arm "$service_file"
  assert_elf32_arm "$impl_file"
  assert_elf32_arm "$source_blob"
  if ! nm -D --defined-only "$impl_file" 2>/dev/null | \
      awk '$NF == "HIDL_FETCH_IBluetoothHci" { found=1 } END { exit !found }'; then
    printf 'm86 Bluetooth implementation does not export HIDL_FETCH_IBluetoothHci.\n' >&2
    exit 1
  fi
  assert_single_ninja_owner "$service_file"
  assert_single_ninja_owner "$impl_file"

  expected_blob_hash="$(
    awk '$2 == "./vendor/lib/libbt-vendor.so" { print $1 }' "$vendor_blob_lock"
  )"
  actual_blob_hash="$(sha256sum "$source_blob" | awk '{ print $1 }')"
  if [[ ! "$expected_blob_hash" =~ ^[0-9a-f]{64}$ ]] || \
      [[ "$actual_blob_hash" != "$expected_blob_hash" ]]; then
    printf 'm86 libbt-vendor.so does not match the locked Flyme input.\n' >&2
    exit 1
  fi
  installed_blob_file="$source_blob"
  if [[ -e "$blob_file" ]]; then
    if ! cmp --quiet "$blob_file" "$source_blob"; then
      printf 'Installed libbt-vendor.so differs from the locked input.\n' >&2
      exit 1
    fi
    assert_elf32_arm "$blob_file"
    assert_single_ninja_owner "$blob_file"
    installed_blob_file="$blob_file"
  elif [[ "$target" != bluetooth ]]; then
    printf 'Installed libbt-vendor.so is missing from the system image.\n' >&2
    exit 1
  fi

  mapfile -t service_files < <(
    find "$product_out/system/vendor/bin/hw" -maxdepth 1 -type f \
      -name 'android.hardware.bluetooth@1.0-service*' -print 2>/dev/null |
      LC_ALL=C sort
  )
  mapfile -t impl32_files < <(
    find "$product_out/system/vendor/lib/hw" -maxdepth 1 -type f \
      -name 'android.hardware.bluetooth@1.0-impl*.so' -print 2>/dev/null |
      LC_ALL=C sort
  )
  mapfile -t impl64_files < <(
    find "$product_out/system/vendor/lib64/hw" -maxdepth 1 -type f \
      -name 'android.hardware.bluetooth@1.0-impl*.so' -print 2>/dev/null |
      LC_ALL=C sort
  )
  if [[ "${#service_files[@]}" -ne 1 || \
        "${service_files[0]:-}" != "$service_file" || \
        "${#impl32_files[@]}" -ne 1 || \
        "${impl32_files[0]:-}" != "$impl_file" || \
        "${#impl64_files[@]}" -ne 0 ]]; then
    printf 'Bluetooth installed-set ownership is not unique.\n' >&2
    printf '  service: %s\n' "${service_files[@]:-none}" >&2
    printf '  impl32: %s\n' "${impl32_files[@]:-none}" >&2
    printf '  impl64: %s\n' "${impl64_files[@]:-none}" >&2
    exit 1
  fi

  mapfile -t bluetooth_rc_files < <(
    find "$product_out/system/vendor/etc/init" -type f \
      -exec grep -F -a -l -- 'service vendor.bluetooth-m86 ' {} + \
      2>/dev/null | LC_ALL=C sort
  )
  if [[ "${#bluetooth_rc_files[@]}" -ne 1 ]] || \
      ! grep -F -x -q \
        '    interface android.hardware.bluetooth@1.0::IBluetoothHci default' \
        "${bluetooth_rc_files[0]:-}"; then
    printf 'Bluetooth init service/interface owner is not unique.\n' >&2
    exit 1
  fi
  if [[ "$(count_regular_file_matches \
      "$product_out/system/vendor/etc/init" \
      'service vendor.bluetooth-1-0 ')" != 0 ]]; then
    printf 'Retired generic Bluetooth init service is still installed.\n' >&2
    exit 1
  fi

  mapfile -t bluetooth_manifest_files < <(
    find "$product_out/system/vendor/etc/vintf" -type f \
      -exec grep -F -a -l -- \
        '<name>android.hardware.bluetooth</name>' {} + \
      2>/dev/null | LC_ALL=C sort
  )
  expected_manifest_file="$product_out/system/vendor/etc/vintf/manifest/android.hardware.bluetooth@1.0-service.m86.xml"
  source_manifest_file="$source_root/hardware/meizu/m86/bluetooth/android.hardware.bluetooth@1.0-service.m86.xml"
  if [[ "$target" == bluetooth ]]; then
    # A module-only build does not regenerate the assembled device manifest,
    # so PRODUCT_OUT can still hold the preceding full build's monolithic
    # manifest. Validate the newly installed, uniquely named fragment here;
    # systemimage/target-files perform the complete cross-file count below.
    if ! cmp --quiet "$expected_manifest_file" "$source_manifest_file"; then
      printf 'Installed Bluetooth VINTF fragment differs from its source.\n' >&2
      exit 1
    fi
    bluetooth_manifest_files=("$expected_manifest_file")
  fi
  if [[ "${#bluetooth_manifest_files[@]}" -ne 1 ]]; then
    printf 'Bluetooth VINTF instance must have exactly one installed owner.\n' >&2
    printf '  manifest: %s\n' "${bluetooth_manifest_files[@]:-none}" >&2
    exit 1
  fi

  if grep -E -i -q \
      '(overriding|ignoring old) commands.*android\.hardware\.bluetooth' \
      "$log_file"; then
    printf 'Bluetooth output has multiple build-graph producers.\n' >&2
    exit 1
  fi

  cp -a "$service_file" "$impl_file" "$installed_blob_file" "$artifact_dir/"
  {
    printf 'service=%s\n' "${service_file#"$product_out/"}"
    printf 'implementation=%s\n' "${impl_file#"$product_out/"}"
    printf 'vendor_blob=%s\n' "${installed_blob_file#"$product_out/"}"
    printf 'vendor_blob_sha256=%s\n' "$actual_blob_hash"
    printf 'service_owner_count=%s\n' "${#service_files[@]}"
    printf 'impl32_owner_count=%s\n' "${#impl32_files[@]}"
    printf 'impl64_owner_count=%s\n' "${#impl64_files[@]}"
    printf 'init_owner=%s\n' "${bluetooth_rc_files[0]}"
    printf 'vintf_owner=%s\n' "${bluetooth_manifest_files[0]}"
    for bluetooth_elf in "$service_file" "$impl_file" "$installed_blob_file"; do
      file "$bluetooth_elf"
      sha256sum "$bluetooth_elf"
      readelf -d "$bluetooth_elf" | grep -E 'NEEDED|SONAME' || true
    done
  } > "$artifact_dir/BLUETOOTH-OUTPUT.txt"
}

count_regular_file_matches() {
  local root="$1"
  local pattern="$2"

  # target-files contains compatibility symlinks, including intentionally
  # dangling links.  Recursive grep follows enough of that graph to return 2,
  # which is fatal under pipefail even when the expected match was found.
  # Limit evidence scans to materialized regular files and neutralize grep's
  # expected no-match status before counting lines.
  {
    find "$root" -type f \
      -exec grep -F -a -h -- "$pattern" {} + 2>/dev/null || true
  } | awk 'END { print NR + 0 }'
}

assert_graphics_target_files() {
  local target_files_tree="$1"
  local target_system="$target_files_tree/SYSTEM"
  local relative_path
  local installed_file
  local packaged_file
  local expected_class
  local module
  local manifest_count
  local allocator_init_count
  local forbidden_name
  local -a graphics_search_roots
  local -a packaged_matches

  graphics_search_roots=("$target_system/lib" "$target_system/lib64")
  if [[ -d "$target_system/vendor" ]]; then
    graphics_search_roots+=("$target_system/vendor")
  fi

  for relative_path in "${graphics_relative_paths[@]}"; do
    installed_file="$product_out/system/$relative_path"
    packaged_file="$target_system/$relative_path"
    expected_class=ELF32
    if [[ "$relative_path" == lib64/* || \
          "$relative_path" == vendor/lib64/* ]]; then
      expected_class=ELF64
    fi
    if ! cmp --quiet "$packaged_file" "$installed_file"; then
      printf 'Packaged graphics output differs from PRODUCT_OUT: %s\n' \
        "$relative_path" >&2
      exit 1
    fi
    assert_graphics_elf_identity \
      "$packaged_file" "$expected_class" "${relative_path##*/}"
  done

  for module in \
    gralloc.m86 \
    hwcomposer.exynos5 \
    memtrack.exynos5 \
    libexynosdisplay \
    libexynosgscaler \
    libexynosscaler \
    libexynosutils \
    libexynosv4l2 \
    libhwcutils \
    libmpp \
    libhdmi \
    libion \
    libhwc2on1adapter \
    libhwc2onfbadapter; do
    mapfile -t packaged_matches < <(
      find "${graphics_search_roots[@]}" -type f \
        -name "$module.so" -print 2>/dev/null | LC_ALL=C sort
    )
    if [[ "${#packaged_matches[@]}" -ne 2 ]]; then
      printf 'Packaged graphics SONAME owner is not the unique 32/64 pair: %s\n' \
        "$module.so" >&2
      printf '  %s\n' "${packaged_matches[@]:-none}" >&2
      exit 1
    fi
  done

  for relative_path in "${graphics_interface_relative_paths[@]}"; do
    installed_file="$product_out/system/$relative_path"
    packaged_file="$target_system/$relative_path"
    expected_class=ELF32
    if [[ "$relative_path" == vendor/bin/* || \
          "$relative_path" == vendor/lib64/* ]]; then
      expected_class=ELF64
    fi
    if ! cmp --quiet "$packaged_file" "$installed_file"; then
      printf 'Packaged graphics interface differs from PRODUCT_OUT: %s\n' \
        "$relative_path" >&2
      exit 1
    fi
    module="${relative_path##*/}"
    if [[ "$relative_path" == vendor/bin/* ]]; then
      module=not-required
    fi
    assert_graphics_elf_identity \
      "$packaged_file" "$expected_class" "$module"
  done

  for module in \
    android.hardware.graphics.allocator@2.0-impl \
    android.hardware.graphics.composer@2.1-impl \
    android.hardware.graphics.mapper@2.0-impl \
    android.hardware.memtrack@1.0-impl; do
    mapfile -t packaged_matches < <(
      find "$target_system/vendor" -type f \
        -name "$module.so" -print 2>/dev/null | LC_ALL=C sort
    )
    if [[ "${#packaged_matches[@]}" -ne 2 ]]; then
      printf 'Packaged graphics interface owner is not the unique 32/64 pair: %s\n' \
        "$module.so" >&2
      printf '  %s\n' "${packaged_matches[@]:-none}" >&2
      exit 1
    fi
  done
  mapfile -t packaged_matches < <(
    find "$target_system/vendor" -type f \
      -name 'android.hardware.graphics.allocator@2.0-service' \
      -print 2>/dev/null | LC_ALL=C sort
  )
  if [[ "${#packaged_matches[@]}" -ne 1 ]]; then
    printf 'Packaged graphics allocator service owner is not unique.\n' >&2
    printf '  %s\n' "${packaged_matches[@]:-none}" >&2
    exit 1
  fi

  for forbidden_name in \
    gralloc.exynos5.so \
    libdisplay.so \
    libExynosHWCService.so \
    libcec.so \
    libfimg.so; do
    mapfile -t packaged_matches < <(
      find "${graphics_search_roots[@]}" -type f \
        -name "$forbidden_name" -print 2>/dev/null | LC_ALL=C sort
    )
    if [[ "${#packaged_matches[@]}" -ne 0 ]]; then
      printf 'Packaged target-files retained retired graphics output: %s\n' \
        "$forbidden_name" >&2
      printf '  %s\n' "${packaged_matches[@]}" >&2
      exit 1
    fi
  done

  for module in \
    android.hardware.graphics.allocator \
    android.hardware.graphics.composer \
    android.hardware.graphics.mapper \
    android.hardware.memtrack; do
    manifest_count="$(count_regular_file_matches \
      "$target_system/vendor/etc/vintf" "<name>$module</name>")"
    if [[ "$manifest_count" != 1 ]]; then
      printf 'Packaged graphics VINTF owner is not unique: %s count=%s\n' \
        "$module" "$manifest_count" >&2
      exit 1
    fi
  done
  allocator_init_count="$(count_regular_file_matches \
    "$target_system/vendor/etc/init" \
    'interface android.hardware.graphics.allocator@2.0::IAllocator default')"
  if [[ "$allocator_init_count" != 1 ]]; then
    printf 'Packaged graphics allocator init owner is not unique: count=%s\n' \
      "$allocator_init_count" >&2
    exit 1
  fi
  if [[ "$(count_regular_file_matches \
      "$target_system/vendor/etc/init" 'libExynosHWCService')" != 0 ]]; then
    printf 'Packaged target-files retained a dead Exynos HWC service owner.\n' >&2
    exit 1
  fi

  {
    printf 'source_owned_graphics_family_destination_count=%s\n' \
      "${#graphics_relative_paths[@]}"
    printf 'source_owned_graphics_family_soname_count=14\n'
    printf 'source_owned_graphics_interface_destination_count=%s\n' \
      "${#graphics_interface_relative_paths[@]}"
    printf 'source_owned_graphics_runtime_destination_count=%s\n' \
      "$((${#graphics_relative_paths[@]} + ${#graphics_interface_relative_paths[@]}))"
    printf 'allocator_init_owner_count=%s\n' "$allocator_init_count"
    for relative_path in "${graphics_relative_paths[@]}"; do
      packaged_file="$target_system/$relative_path"
      printf 'packaged_file=%s\n' "SYSTEM/$relative_path"
      sha256sum "$packaged_file"
    done
    for relative_path in "${graphics_interface_relative_paths[@]}"; do
      packaged_file="$target_system/$relative_path"
      printf 'packaged_file=%s\n' "SYSTEM/$relative_path"
      sha256sum "$packaged_file"
    done
  } > "$artifact_dir/GRAPHICS-TARGET-FILES.txt"
}

assert_wifi_target_files() {
  local target_files_tree="$1"
  local target_system="$target_files_tree/SYSTEM"
  local target_vendor_init="$target_system/vendor/etc/init"
  local target_vendor_vintf="$target_system/vendor/etc/vintf"
  local target_vendor_sepolicy_cil="$target_system/vendor/etc/selinux/vendor_sepolicy.cil"
  local source_device="$source_root/device/meizu/m86"
  local source_wifi_rc="$source_device/wifi/rootdir/etc/init.m86.wifi.rc"
  local source_init_rc="$source_device/rootdir/etc/init.m86.rc"
  local source_ueventd="$source_device/rootdir/etc/ueventd.m86.rc"
  local packaged_wifi_rc="$target_files_tree/ROOT/init.m86.wifi.rc"
  local packaged_init_rc="$target_files_tree/ROOT/init.m86.rc"
  local packaged_ueventd="$target_files_tree/ROOT/ueventd.m86.rc"
  local vendor_proprietary="$source_root/vendor/meizu/m86/proprietary"
  local expected_hash
  local actual_hash
  local relative_path
  local packaged_path
  local source_path
  local wifi_hal_count
  local hostapd_count
  local supplicant_count
  local wifi_init_count
  local wifi_genfs_count
  local forbidden_wifi_owner
  local -a packaged_services

  mapfile -t packaged_services < <(
    find "$target_files_tree" -type f \
      -path '*/vendor/bin/hw/android.hardware.wifi@1.0-service*' \
      -print | LC_ALL=C sort
  )
  if [[ "${#packaged_services[@]}" -ne 1 || \
        "${packaged_services[0]##*/}" != \
          android.hardware.wifi@1.0-service.legacy ]]; then
    printf 'Packaged Wi-Fi HAL is not the unique legacy service.\n' >&2
    printf '  %s\n' "${packaged_services[@]:-none}" >&2
    exit 1
  fi
  for required_wifi_file in \
    "$target_system/vendor/bin/hw/hostapd" \
    "$target_system/vendor/bin/hw/wpa_supplicant" \
    "$target_system/vendor/etc/permissions/android.hardware.wifi.xml" \
    "$target_system/vendor/etc/permissions/android.hardware.wifi.direct.xml" \
    "$target_vendor_sepolicy_cil"; do
    if [[ ! -s "$required_wifi_file" ]]; then
      printf 'Packaged Wi-Fi closure is missing: %s\n' \
        "$required_wifi_file" >&2
      exit 1
    fi
  done
  if ! cmp --quiet "$packaged_wifi_rc" "$source_wifi_rc" || \
      ! cmp --quiet "$packaged_init_rc" "$source_init_rc" || \
      ! cmp --quiet "$packaged_ueventd" "$source_ueventd"; then
    printf 'Packaged Wi-Fi init/ueventd bytes differ from m86 source.\n' >&2
    exit 1
  fi
  if [[ "$(grep -F -c -- \
      'chown wifi wifi /sys/module/bcmdhd/parameters/firmware_path' \
      "$packaged_init_rc" || true)" != 1 || \
      "$(grep -F -c -- \
      'chmod 0660 /sys/module/bcmdhd/parameters/firmware_path' \
      "$packaged_init_rc" || true)" != 1 ]]; then
    printf 'Packaged Wi-Fi firmware_path DAC owner is incomplete.\n' >&2
    exit 1
  fi
  wifi_init_count="$(count_regular_file_matches \
    "$target_vendor_init" \
    'service vendor.wifi_hal_legacy /vendor/bin/hw/android.hardware.wifi@1.0-service.legacy')"
  wifi_hal_count="$(count_regular_file_matches \
    "$target_vendor_vintf" '<name>android.hardware.wifi</name>')"
  hostapd_count="$(count_regular_file_matches \
    "$target_vendor_vintf" '<name>android.hardware.wifi.hostapd</name>')"
  supplicant_count="$(count_regular_file_matches \
    "$target_vendor_vintf" '<name>android.hardware.wifi.supplicant</name>')"
  if [[ "$wifi_init_count" != 1 || "$wifi_hal_count" != 1 || \
        "$hostapd_count" != 1 || "$supplicant_count" != 1 ]]; then
    printf 'Packaged Wi-Fi init/VINTF ownership is incomplete or ambiguous.\n' >&2
    exit 1
  fi
  wifi_genfs_count="$(grep -F -x -c -- \
    '(genfscon sysfs /module/bcmdhd/parameters/firmware_path (u object_r sysfs_wlan_fwpath ((s0) (s0))))' \
    "$target_vendor_sepolicy_cil" || true)"
  if [[ "$wifi_genfs_count" != 1 ]]; then
    printf 'Packaged Wi-Fi firmware_path genfs owner count is %s.\n' \
      "$wifi_genfs_count" >&2
    exit 1
  fi

  for relative_path in \
    etc/wifi/bcmdhd.cal \
    vendor/firmware/fw_bcmdhd.bin \
    vendor/firmware/fw_bcmdhd_apsta.bin; do
    source_path="$vendor_proprietary/$relative_path"
    packaged_path="$target_system/$relative_path"
    expected_hash="$(awk -v path="./$relative_path" \
      '$2 == path { print $1 }' "$vendor_blob_lock")"
    actual_hash="$(sha256sum "$source_path" 2>/dev/null | awk '{ print $1 }')"
    if [[ ! "$expected_hash" =~ ^[0-9a-f]{64}$ || \
          "$actual_hash" != "$expected_hash" || \
          ! -s "$packaged_path" ]] || \
        ! cmp --quiet "$packaged_path" "$source_path"; then
      printf 'Packaged Wi-Fi blob is absent or differs from its lock: %s\n' \
        "$relative_path" >&2
      exit 1
    fi
  done
  for forbidden_wifi_owner in wifiloader macloader; do
    if find "$target_files_tree" -type f \
        -name "*$forbidden_wifi_owner*" -print -quit | grep -q . || \
        [[ "$(count_regular_file_matches \
          "$target_files_tree/ROOT" "$forbidden_wifi_owner")" != 0 ]] || \
        [[ "$(count_regular_file_matches \
          "$target_vendor_init" "$forbidden_wifi_owner")" != 0 ]]; then
      printf 'Packaged target-files retained retired Wi-Fi owner: %s\n' \
        "$forbidden_wifi_owner" >&2
      exit 1
    fi
  done

  {
    printf 'packaged_service=%s\n' \
      "${packaged_services[0]#"$target_files_tree/"}"
    printf 'packaged_init_rc=ROOT/init.m86.rc\n'
    printf 'packaged_init_owner_count=%s\n' "$wifi_init_count"
    printf 'packaged_wifi_vintf_owner_count=%s\n' "$wifi_hal_count"
    printf 'packaged_hostapd_vintf_owner_count=%s\n' "$hostapd_count"
    printf 'packaged_supplicant_vintf_owner_count=%s\n' "$supplicant_count"
    printf 'compiled_firmware_path_genfs_count=%s\n' "$wifi_genfs_count"
    for relative_path in \
      etc/wifi/bcmdhd.cal \
      vendor/firmware/fw_bcmdhd.bin \
      vendor/firmware/fw_bcmdhd_apsta.bin; do
      packaged_path="$target_system/$relative_path"
      printf 'packaged_file=%s\n' "SYSTEM/$relative_path"
      sha256sum "$packaged_path"
    done
  } > "$artifact_dir/WIFI-TARGET-FILES.txt"
}

assert_radio_target_files() {
  local target_files_tree="$1"
  local target_system="$target_files_tree/SYSTEM"
  # Android 10's legacy RIL executable is installed in the vendor hw
  # namespace; the SITRIL ABI remains the system/lib64 provider.  Do not
  # accept a second system/bin producer or infer ownership from the basename.
  local rild="$target_system/vendor/bin/hw/rild"
  local sitril="$target_system/lib64/libsitril.so"
  local obsolete

  for required_radio_file in "$rild" "$sitril"; do
    if [[ ! -s "$required_radio_file" ]]; then
      printf 'Packaged radio closure is missing: %s\n' \
        "$required_radio_file" >&2
      exit 1
    fi
  done
  for obsolete in \
    "$target_system/bin/rild_exynos" \
    "$target_system/bin/radiooptions_exynos"; do
    if [[ -e "$obsolete" ]]; then
      printf 'Packaged target-files retained deferred radio helper: %s\n' \
        "$obsolete" >&2
      exit 1
    fi
  done
  {
    printf 'platform_rild=SYSTEM/vendor/bin/hw/rild\n'
    sha256sum "$rild"
    printf 'sitril=SYSTEM/lib64/libsitril.so\n'
    sha256sum "$sitril"
    printf 'deferred_rild_exynos=absent\n'
    printf 'deferred_radiooptions_exynos=absent\n'
  } > "$artifact_dir/RADIO-TARGET-FILES.txt"
}

assert_bluetooth_target_files() {
  local target_files_tree="$1"
  local target_vendor_init="$target_files_tree/SYSTEM/vendor/etc/init"
  local target_vendor_vintf="$target_files_tree/SYSTEM/vendor/etc/vintf"
  local target_vendor_file_contexts="$target_files_tree/SYSTEM/vendor/etc/selinux/vendor_file_contexts"
  local target_vendor_sepolicy_cil="$target_files_tree/SYSTEM/vendor/etc/selinux/vendor_sepolicy.cil"
  local target_combined_sepolicy="$target_files_tree/ROOT/sepolicy"
  local kernel_selinux_security="$source_root/kernel/meizu/m86/security/selinux/include/security.h"
  local kernel_selinux_hooks="$source_root/kernel/meizu/m86/security/selinux/hooks.c"
  local -a packaged_services
  local -a packaged_impl32
  local -a packaged_impl64
  local -a packaged_blobs
  local bluetooth_vintf_count
  local bluetooth_init_count
  local service_exec_context_count
  local rfkill_state_genfs_count
  local rfkill_type_writable_genfs_count
  local iserial_genfs_count

  mapfile -t packaged_services < <(
    find "$target_files_tree" -type f \
      -path '*/vendor/bin/hw/android.hardware.bluetooth@1.0-service*' \
      -print | LC_ALL=C sort
  )
  mapfile -t packaged_impl32 < <(
    find "$target_files_tree" -type f \
      -path '*/vendor/lib/hw/android.hardware.bluetooth@1.0-impl*.so' \
      -print | LC_ALL=C sort
  )
  mapfile -t packaged_impl64 < <(
    find "$target_files_tree" -type f \
      -path '*/vendor/lib64/hw/android.hardware.bluetooth@1.0-impl*.so' \
      -print | LC_ALL=C sort
  )
  mapfile -t packaged_blobs < <(
    find "$target_files_tree" -type f \
      -path '*/vendor/lib/libbt-vendor.so' -print | LC_ALL=C sort
  )
  if [[ "${#packaged_services[@]}" -ne 1 || \
        "${packaged_services[0]##*/}" != \
          android.hardware.bluetooth@1.0-service.m86 || \
        "${#packaged_impl32[@]}" -ne 1 || \
        "${packaged_impl32[0]##*/}" != \
          android.hardware.bluetooth@1.0-impl.m86.so || \
        "${#packaged_impl64[@]}" -ne 0 || \
        "${#packaged_blobs[@]}" -ne 1 ]]; then
    printf 'Packaged Bluetooth closure is not the unique 32-bit m86 set.\n' >&2
    exit 1
  fi
  bluetooth_init_count="$(count_regular_file_matches \
    "$target_vendor_init" 'service vendor.bluetooth-m86 ')"
  bluetooth_vintf_count="$(count_regular_file_matches \
    "$target_vendor_vintf" '<name>android.hardware.bluetooth</name>')"
  if [[ "$bluetooth_init_count" != 1 || "$bluetooth_vintf_count" != 1 ]]; then
    printf 'Packaged Bluetooth init/VINTF ownership is not unique.\n' >&2
    exit 1
  fi
  if [[ "$(count_regular_file_matches \
      "$target_vendor_init" 'service vendor.bluetooth-1-0 ')" != 0 ]]; then
    printf 'Packaged target-files retained the generic Bluetooth service.\n' >&2
    exit 1
  fi
  for required_policy_file in \
    "$target_vendor_file_contexts" \
    "$target_vendor_sepolicy_cil" \
    "$target_combined_sepolicy" \
    "$kernel_selinux_security" \
    "$kernel_selinux_hooks"; do
    if [[ ! -s "$required_policy_file" ]]; then
      printf 'Bluetooth SELinux audit input is missing: %s\n' \
        "$required_policy_file" >&2
      exit 1
    fi
  done
  service_exec_context_count="$(
    awk '$1 == "/(vendor|system/vendor)/bin/hw/android\\.hardware\\.bluetooth@1\\.0-service\\.m86" && \
         $2 == "u:object_r:hal_bluetooth_default_exec:s0" { count++ } \
         END { print count + 0 }' "$target_vendor_file_contexts"
  )"
  rfkill_state_genfs_count="$(
    grep -F -x -c -- \
      '(genfscon sysfs /devices/11460000.uart/bluetooth.13/rfkill/rfkill0/state (u object_r sysfs_bluetooth_writable ((s0) (s0))))' \
      "$target_vendor_sepolicy_cil" || true
  )"
  rfkill_type_writable_genfs_count="$(
    grep -F -x -c -- \
      '(genfscon sysfs /devices/11460000.uart/bluetooth.13/rfkill/rfkill0/type (u object_r sysfs_bluetooth_writable ((s0) (s0))))' \
      "$target_vendor_sepolicy_cil" || true
  )"
  iserial_genfs_count="$(
    grep -F -x -c -- \
      '(genfscon sysfs /devices/virtual/android_usb/android0/iSerial (u object_r sysfs_android_usb ((s0) (s0))))' \
      "$target_vendor_sepolicy_cil" || true
  )"
  if [[ "$service_exec_context_count" != 1 || \
        "$rfkill_state_genfs_count" != 1 || \
        "$rfkill_type_writable_genfs_count" != 0 || \
        "$iserial_genfs_count" != 1 ]]; then
    printf 'Packaged Bluetooth SELinux ownership is incomplete or ambiguous.\n' >&2
    exit 1
  fi
  if ! grep -F -q 'SE_SBGENFS' "$kernel_selinux_security" || \
      ! grep -F -q 'selinux_genfs_get_sid' "$kernel_selinux_hooks" || \
      ! grep -F -q '!strcmp(sb->s_type->name, "sysfs")' \
        "$kernel_selinux_hooks" || \
      ! grep -F -q 'sbsec->flags & SE_SBGENFS' "$kernel_selinux_hooks"; then
    printf 'The installed m86 kernel lacks sysfs genfscon inode labeling.\n' >&2
    exit 1
  fi
  {
    printf 'packaged_service=%s\n' "${packaged_services[0]#"$target_files_tree/"}"
    printf 'packaged_impl32=%s\n' "${packaged_impl32[0]#"$target_files_tree/"}"
    printf 'packaged_vendor_blob=%s\n' "${packaged_blobs[0]#"$target_files_tree/"}"
    printf 'packaged_impl64_count=%s\n' "${#packaged_impl64[@]}"
    printf 'packaged_init_owner_count=%s\n' "$bluetooth_init_count"
    printf 'packaged_vintf_owner_count=%s\n' "$bluetooth_vintf_count"
    printf 'packaged_service_exec_context_count=%s\n' \
      "$service_exec_context_count"
    printf 'compiled_rfkill_state_genfs_count=%s\n' \
      "$rfkill_state_genfs_count"
    printf 'compiled_rfkill_type_writable_genfs_count=%s\n' \
      "$rfkill_type_writable_genfs_count"
    printf 'compiled_iserial_genfs_count=%s\n' "$iserial_genfs_count"
    printf 'kernel_sysfs_genfs_inode_labeling=enabled\n'
    sha256sum "$target_combined_sepolicy"
  } > "$artifact_dir/BLUETOOTH-TARGET-FILES.txt"
}

assert_m5_audio_baseline_target_files() {
  local target_files_tree="$1"
  local target_system="$target_files_tree/SYSTEM"
  local audio_wrapper_source="$local_root/hardware/meizu/m86/audio/audio_primary_m86.cpp"
  local wrapper="$target_system/lib/hw/audio.primary.m86.so"
  local flyme32="$target_system/lib/hw/audio.primary.m86.flyme.so"
  local flyme64="$target_system/lib64/hw/audio.primary.m86.so"
  local audioserver="$target_system/bin/audioserver"
  local audio_impl32="$target_system/vendor/lib/hw/android.hardware.audio@5.0-impl.so"
  local audio_impl64="$target_system/vendor/lib64/hw/android.hardware.audio@5.0-impl.so"
  local vendor_manifest="$target_system/vendor/etc/vintf/manifest.xml"
  local audio_hal_block
  local installed_wrapper="$product_out/system/lib/hw/audio.primary.m86.so"
  local installed_flyme32="$product_out/system/lib/hw/audio.primary.m86.flyme.so"
  local source_flyme32="$source_root/vendor/meizu/m86/proprietary/lib/hw/audio.primary.m86.so"
  local wrapper_object="$product_out/obj_arm/SHARED_LIBRARIES/audio.primary.m86_intermediates/audio.primary.m86.so"

  for audio_wrapper_callback in \
    get_microphones \
    set_headphone_volume \
    set_master_mute \
    get_master_mute \
    create_audio_patch \
    release_audio_patch \
    get_audio_port \
    set_audio_port_config; do
    if ! grep -F --quiet \
        "wrapper->public_device.$audio_wrapper_callback = m86_$audio_wrapper_callback;" \
        "$audio_wrapper_source"; then
      printf 'M5 audio wrapper leaves optional callback NULL: %s\n' \
        "$audio_wrapper_callback" >&2
      exit 1
    fi
  done

  # The working direct Flyme HAL advertises API 2.0.  That is intentional:
  # AudioFlinger then uses its legacy routing fallback and sends
  # routing=N through the output stream's set_parameters callback.  A wrapper
  # that advertises API 3.0/current makes the framework call modern
  # create_audio_patch instead; this HAL does not select DAPM routes from its
  # device-level callback and the result is out_device=0/EBUSY.
  for audio_route_contract in \
    'M86StreamOut* active_output' \
    'm86_apply_output_device' \
    'sinks[i].type == AUDIO_PORT_TYPE_DEVICE' \
    'active_output->flyme_stream->common.set_parameters' \
    'routing=%u' \
    'AUDIO_DEVICE_API_VERSION_2_0' \
    'wrapper->public_device.common.version = AUDIO_DEVICE_API_VERSION_2_0'; do
    if ! grep -F --quiet "$audio_route_contract" "$audio_wrapper_source"; then
      printf 'M5 audio wrapper is missing route contract: %s\n' \
        "$audio_route_contract" >&2
      exit 1
    fi
  done
  for forbidden_audio_route_contract in \
    'parameter_result' \
    'result = m86_apply_output_device(wrapper, devices)' \
    'wrapper->flyme_device, routing'; do
    if grep -F --quiet "$forbidden_audio_route_contract" "$audio_wrapper_source"; then
      printf 'M5 wrapper still contains the retired device-level routing path: %s\n' \
        "$forbidden_audio_route_contract" >&2
      exit 1
    fi
  done

  for required_audio_file in \
    "$wrapper" \
    "$flyme32" \
    "$audioserver" \
    "$audio_impl32" \
    "$vendor_manifest"; do
    if [[ ! -s "$required_audio_file" ]]; then
      printf 'M5 audio baseline file is absent: %s\n' \
        "$required_audio_file" >&2
      exit 1
    fi
  done
  if [[ -e "$audio_impl64" || -e "$flyme64" ]]; then
    printf 'Unexpected 64-bit Android audio passthrough implementation: %s\n' \
      "${audio_impl64} or ${flyme64}" >&2
    exit 1
  fi
  if ! cmp --quiet "$wrapper" "$installed_wrapper" || \
      ! cmp --quiet "$wrapper" "$wrapper_object" || \
      ! cmp --quiet "$flyme32" "$installed_flyme32" || \
      ! cmp --quiet "$flyme32" "$source_flyme32"; then
    printf 'Packaged M5 wrapper or renamed Flyme input differs from its owner.\n' >&2
    exit 1
  fi
  if ! file "$wrapper" | grep -E -q 'ELF 32-bit.*ARM' || \
      ! readelf -d "$wrapper" | grep -E -q 'SONAME.*audio.primary.m86.so'; then
    printf 'Packaged m86 audio wrapper is not an ELF32 ARM audio.primary HAL.\n' >&2
    exit 1
  fi
  if ! readelf -h "$audioserver" | \
      grep -F -q 'Class:                             ELF32' || \
      ! readelf -h "$audioserver" | \
        grep -F -q 'Machine:                           ARM'; then
    printf 'Packaged audioserver is not the required 32-bit ARM process.\n' >&2
    exit 1
  fi
  audio_hal_block="$(
    awk 'BEGIN { RS="</hal>" } \
      /<name>android.hardware.audio<\/name>/ { print }' \
      "$vendor_manifest"
  )"
  if [[ "$(printf '%s\n' "$audio_hal_block" | \
      grep -F -c '<name>android.hardware.audio</name>' || true)" != 1 ]] || \
      [[ "$(printf '%s\n' "$audio_hal_block" | \
        grep -F -c '<transport arch="32">passthrough</transport>' || true)" != 1 ]]; then
    printf 'Packaged audio VINTF is not one 32-bit passthrough owner.\n' >&2
    exit 1
  fi

  {
    python3 "$local_root/tools/audit-m86-audio-abi.py" \
      "$source_root/vendor/meizu/m86/proprietary/lib/hw/audio.primary.m86.so" \
      "$source_root/vendor/meizu/m86/proprietary/lib64/hw/audio.primary.m86.so"
    printf 'wrapper=SYSTEM/lib/hw/audio.primary.m86.so\n'
    printf 'flyme32=SYSTEM/lib/hw/audio.primary.m86.flyme.so\n'
    printf 'flyme64=absent\n'
    printf 'audioserver=SYSTEM/bin/audioserver\n'
    printf 'audioserver_elf=ELF32-ARM\n'
    printf 'audio_vintf_owner_count=1\n'
    printf 'audio_vintf_transport=passthrough-32\n'
    printf 'audio_impl32=SYSTEM/vendor/lib/hw/android.hardware.audio@5.0-impl.so\n'
    printf 'audio_impl64=absent\n'
    printf 'primary64_removal=passed\n'
    sha256sum "$wrapper" "$flyme32" "$audioserver" "$audio_impl32" "$vendor_manifest"
  } > "$artifact_dir/M5-AUDIO-TARGET-FILES.txt"
}

assert_m5_hifi_target_files() {
  local target_files_tree="$1"
  local target_system="$target_files_tree/SYSTEM"
  local audio_wrapper_source="$local_root/hardware/meizu/m86/audio/audio_primary_m86.cpp"
  local hifi_fragment="$local_root/device/meizu/m86/parts/M86Parts/src/org/lineageos/settings/m86/hifi/HifiSettingsFragment.java"
  local patch_series="$local_root/patches/series.tsv"
  local packaged_apk="$target_system/priv-app/M86Parts/M86Parts.apk"
  local installed_apk="$product_out/system/priv-app/M86Parts/M86Parts.apk"
  local dexdump="$out_root/host/linux-x86/bin/dexdump"
  local apk_dexdump
  local activity_descriptor='Lorg/lineageos/settings/m86/hifi/HifiSettingsActivity;'
  local fragment_descriptor='Lorg/lineageos/settings/m86/hifi/HifiSettingsFragment;'
  local policy_descriptor='Lorg/lineageos/settings/m86/hifi/HifiPolicy;'
  local activity_count
  local fragment_count
  local policy_count

  if grep -F -q -- 'setStreamVolume' "$hifi_fragment" || \
      grep -F -q -- '4 / 5' "$hifi_fragment"; then
    printf 'M5 HiFi UI still changes or clamps the normal stream volume.\n' >&2
    exit 1
  fi
  if ! grep -F -q -- 'm86_apply_headphone_volume(out->owner)' \
      "$audio_wrapper_source" || \
      grep -F -q -- \
        'patches/frameworks-av/0001-audioflinger-restore-meizu-headphone-volume.patch' \
        "$patch_series" || \
      grep -F -q -- \
        'patches/hardware-interfaces/0004-audio-call-meizu-headphone-volume-hook.patch' \
        "$patch_series"; then
    printf 'M5 wrapper-only headphone-volume ownership is incomplete.\n' >&2
    exit 1
  fi

  if [[ ! -s "$packaged_apk" ]] || ! cmp --quiet "$packaged_apk" "$installed_apk"; then
    printf 'M5 HiFi target-files APK is missing or differs from PRODUCT_OUT.\n' >&2
    exit 1
  fi
  if [[ ! -x "$dexdump" ]]; then
    printf 'Host dexdump is unavailable for the M5 HiFi class audit: %s\n' \
      "$dexdump" >&2
    exit 1
  fi
  apk_dexdump="$(mktemp "$artifact_dir/.M86Parts-hifi-dexdump.XXXXXX")"
  trap 'rm -f -- "$apk_dexdump"' RETURN
  "$dexdump" -d "$packaged_apk" > "$apk_dexdump"
  activity_count="$(awk -v expected="  Class descriptor  : '$activity_descriptor'" \
    '$0 == expected { count++ } END { print count + 0 }' "$apk_dexdump")"
  fragment_count="$(awk -v expected="  Class descriptor  : '$fragment_descriptor'" \
    '$0 == expected { count++ } END { print count + 0 }' "$apk_dexdump")"
  policy_count="$(awk -v expected="  Class descriptor  : '$policy_descriptor'" \
    '$0 == expected { count++ } END { print count + 0 }' "$apk_dexdump")"
  if [[ "$activity_count" != 1 || "$fragment_count" != 1 || "$policy_count" != 1 ]]; then
    printf 'M5 HiFi classes are missing or duplicated in M86Parts: activity=%s fragment=%s policy=%s\n' \
      "$activity_count" "$fragment_count" "$policy_count" >&2
    exit 1
  fi
  rm -f -- "$apk_dexdump"
  trap - RETURN
  {
    printf 'hifi_ui_owner=SYSTEM/priv-app/M86Parts/M86Parts.apk\n'
    printf 'hifi_activity_descriptor_count=%s\n' "$activity_count"
    printf 'hifi_fragment_descriptor_count=%s\n' "$fragment_count"
    printf 'hifi_policy_descriptor_count=%s\n' "$policy_count"
    printf 'hifi_settings_store=Settings.Global\n'
    printf 'hifi_wrapper_owner=hardware/meizu/m86/audio\n'
    printf 'hifi_wrapper_restore=route-output-reopen-audioserver-restart\n'
    printf 'hifi_headphone_volume_owner=hardware/meizu/m86/audio\n'
    printf 'hifi_headphone_volume_restore=output-open-route-change-before-each-stream-volume\n'
    printf 'hifi_headphone_unity=1.0\n'
    printf 'framework_volume_transform=none\n'
    sha256sum "$packaged_apk"
  } > "$artifact_dir/M5-HIFI-TARGET-FILES.txt"
}

assert_m3_target_files() {
  local target_files_tree="$1"
  local target_system="$target_files_tree/SYSTEM"
  local source_device="$source_root/device/meizu/m86"
  local source_fstab="$source_device/storage/rootdir/etc/fstab.m86"
  local source_usb_rc="$source_device/usb/rootdir/etc/init.m86.usb.rc"
  local source_privapp_permissions="$source_device/parts/M86Parts/privapp-permissions-org.lineageos.settings.m86.xml"
  local source_stock_dtb="$source_device/prebuilt/dtb.img"
  local source_mback_dtb_tool="$source_device/tools/build-mback-dtb.py"
  local packaged_dtb="$target_files_tree/RADIO/dtb.img"
  local packaged_apk="$target_system/priv-app/M86Parts/M86Parts.apk"
  local installed_apk="$product_out/system/priv-app/M86Parts/M86Parts.apk"
  local m86parts_keyhandler_descriptor='Lorg/lineageos/settings/m86/mback/KeyHandler;'
  local dexdump="$out_root/host/linux-x86/bin/dexdump"
  local packaged_privapp_permissions="$target_system/etc/permissions/privapp-permissions-org.lineageos.settings.m86.xml"
  local packaged_usb_rc="$target_files_tree/ROOT/init.m86.usb.rc"
  local packaged_usb_helper="$target_system/bin/m86_usb_serial"
  local installed_usb_helper="$product_out/system/bin/m86_usb_serial"
  local packaged_usb_hal="$target_system/vendor/bin/hw/android.hardware.usb@1.0-service.basic"
  local installed_usb_hal="$product_out/system/vendor/bin/hw/android.hardware.usb@1.0-service.basic"
  local packaged_usb_hal_rc="$target_system/vendor/etc/init/android.hardware.usb@1.0-service.basic.rc"
  local installed_usb_hal_rc="$product_out/system/vendor/etc/init/android.hardware.usb@1.0-service.basic.rc"
  local keylayout_name
  local old_m3_owner_path
  local packaged_file
  local source_file
  local m86parts_keyhandler_count
  local forbidden_fingerprint_output
  local -a packaged_matches

  mapfile -t packaged_matches < <(
    find "$target_files_tree" -type f \
      -path '*/priv-app/M86Parts/M86Parts.apk' -print | LC_ALL=C sort
  )
  if [[ "${#packaged_matches[@]}" -ne 1 || \
        "${packaged_matches[0]}" != "$packaged_apk" ]] || \
      ! cmp --quiet "$packaged_apk" "$installed_apk"; then
    printf 'Packaged M86Parts APK is missing, duplicated, or differs from PRODUCT_OUT.\n' >&2
    printf '  %s\n' "${packaged_matches[@]:-none}" >&2
    exit 1
  fi
  if [[ ! -x "$dexdump" ]]; then
    printf 'Host dexdump is unavailable for the M86Parts class audit: %s\n' \
      "$dexdump" >&2
    exit 1
  fi
  if ! m86parts_keyhandler_count="$(
    set -e
    m86parts_dexdump="$(
      mktemp "$artifact_dir/.M86Parts-dexdump.XXXXXX"
    )"
    trap 'rm -f -- "$m86parts_dexdump"' EXIT
    "$dexdump" -d "$packaged_apk" > "$m86parts_dexdump"
    awk -v expected="  Class descriptor  : '$m86parts_keyhandler_descriptor'" \
      '$0 == expected { count++ } END { print count + 0 }' \
      "$m86parts_dexdump"
  )"; then
    printf 'Failed to inspect packaged M86Parts dex classes.\n' >&2
    exit 1
  fi
  if [[ "$m86parts_keyhandler_count" != 1 ]]; then
    printf 'Packaged M86Parts APK has %s reflected DeviceKeyHandler classes; expected 1.\n' \
      "$m86parts_keyhandler_count" >&2
    exit 1
  fi

  if ((fingerprint_experiment)); then
    if ! cmp --quiet "$packaged_dtb" "$source_stock_dtb"; then
      printf 'Packaged fingerprint DTB differs from the stock secure-mode DTB.\n' >&2
      exit 1
    fi
  else
    if ! cmp --quiet "$packaged_dtb" "$release_dtb"; then
      printf 'Packaged M3 DTB differs from the verified mBack DTB.\n' >&2
      exit 1
    fi
    python3 "$source_mback_dtb_tool" \
      --stock "$source_stock_dtb" \
      --verify "$packaged_dtb" >> "$artifact_dir/M3-DTB.txt"

    for forbidden_fingerprint_output in \
      SYSTEM/etc/permissions/android.hardware.fingerprint.xml \
      SYSTEM/vendor/etc/permissions/android.hardware.fingerprint.xml \
      SYSTEM/vendor/bin/hw/android.hardware.biometrics.fingerprint@2.1-service \
      SYSTEM/vendor/etc/init/android.hardware.biometrics.fingerprint@2.1-service.rc \
      SYSTEM/lib64/hw/fingerprint.m86.so \
      SYSTEM/vendor/lib64/hw/fingerprint.m86.so; do
      if [[ -e "$target_files_tree/$forbidden_fingerprint_output" ]]; then
        printf 'Default M3 product packaged fingerprint userspace: %s\n' \
          "$forbidden_fingerprint_output" >&2
        exit 1
      fi
    done
    if grep -F -q 'android.hardware.biometrics.fingerprint' \
        "$target_files_tree/META/system_manifest.xml"; then
      printf 'Default M3 product declared the fingerprint VINTF HAL.\n' >&2
      exit 1
    fi
  fi

  mapfile -t packaged_matches < <(
    find "$target_files_tree" -type f \
      -name 'privapp-permissions-org.lineageos.settings.m86.xml' -print |
      LC_ALL=C sort
  )
  if [[ "${#packaged_matches[@]}" -ne 1 || \
        "${packaged_matches[0]}" != "$packaged_privapp_permissions" ]] || \
      ! cmp --quiet \
        "$packaged_privapp_permissions" "$source_privapp_permissions"; then
    printf 'Packaged M86Parts privapp whitelist is missing, duplicated, or stale.\n' >&2
    printf '  %s\n' "${packaged_matches[@]:-none}" >&2
    exit 1
  fi

  for packaged_file in \
    "$target_files_tree/BOOT/RAMDISK/fstab.m86" \
    "$target_files_tree/ROOT/fstab.m86"; do
    if ! cmp --quiet "$packaged_file" "$source_fstab"; then
      printf 'Packaged M3 fstab differs from its storage owner: %s\n' \
        "$packaged_file" >&2
      exit 1
    fi
  done
  if ! cmp --quiet "$packaged_usb_rc" "$source_usb_rc"; then
    printf 'Packaged m86 USB rc differs from its device owner.\n' >&2
    exit 1
  fi

  mapfile -t packaged_matches < <(
    find "$target_files_tree" -type f -name m86_usb_serial -print |
      LC_ALL=C sort
  )
  if [[ "${#packaged_matches[@]}" -ne 1 || \
        "${packaged_matches[0]}" != "$packaged_usb_helper" ]] || \
      ! cmp --quiet "$packaged_usb_helper" "$installed_usb_helper"; then
    printf 'Packaged m86 USB identity helper is missing, duplicated, or stale.\n' >&2
    printf '  %s\n' "${packaged_matches[@]:-none}" >&2
    exit 1
  fi

  mapfile -t packaged_matches < <(
    find "$target_system" -type f \
      -path '*/bin/hw/android.hardware.usb@1.0-service*' -print |
      LC_ALL=C sort
  )
  if [[ "${#packaged_matches[@]}" -ne 1 || \
        "${packaged_matches[0]}" != "$packaged_usb_hal" ]] || \
      ! cmp --quiet "$packaged_usb_hal" "$installed_usb_hal" || \
      ! cmp --quiet "$packaged_usb_hal_rc" "$installed_usb_hal_rc"; then
    printf 'Packaged USB HAL is not the unique basic service and rc.\n' >&2
    printf '  %s\n' "${packaged_matches[@]:-none}" >&2
    exit 1
  fi

  for keylayout_name in fts.kl gpio-keys.kl fpc1020.kl uinput-fpc.kl; do
    packaged_file="$target_system/usr/keylayout/$keylayout_name"
    case "$keylayout_name" in
      fts.kl | gpio-keys.kl)
        source_file="$source_device/input/standard-keys/keylayout/$keylayout_name"
        ;;
      fpc1020.kl | uinput-fpc.kl)
        source_file="$source_device/parts/mback/keylayout/$keylayout_name"
        ;;
    esac
    mapfile -t packaged_matches < <(
      find "$target_files_tree" -type f -name "$keylayout_name" -print |
        LC_ALL=C sort
    )
    if [[ "${#packaged_matches[@]}" -ne 1 || \
          "${packaged_matches[0]}" != "$packaged_file" ]] || \
        ! cmp --quiet "$packaged_file" "$source_file"; then
      printf 'Packaged M3 keylayout is missing, duplicated, or stale: %s\n' \
        "$keylayout_name" >&2
      printf '  %s\n' "${packaged_matches[@]:-none}" >&2
      exit 1
    fi
  done

  for old_m3_owner_path in \
    rootdir/etc/fstab.m86 \
    rootdir/etc/recovery.fstab \
    rootdir/etc/init.m86.usb.rc \
    keylayout/fts.kl \
    keylayout/gpio-keys.kl \
    keylayout/fpc1020.kl; do
    if [[ -e "$source_device/$old_m3_owner_path" ]]; then
      printf 'Retired M3 owner path still exists: %s\n' \
        "$source_device/$old_m3_owner_path" >&2
      exit 1
    fi
  done

  {
    printf 'm86parts_apk=SYSTEM/priv-app/M86Parts/M86Parts.apk\n'
    printf 'm86parts_keyhandler=%s\n' "$m86parts_keyhandler_descriptor"
    printf 'm86parts_keyhandler_descriptor_count=%s\n' \
      "$m86parts_keyhandler_count"
    printf 'dtb=RADIO/dtb.img\n'
    printf 'dtb_sha256=%s\n' \
      "$(sha256sum "$packaged_dtb" | awk '{ print $1 }')"
    if ((fingerprint_experiment)); then
      printf 'fingerprint_userspace=present\n'
      printf 'fingerprint_feature=present\n'
      printf 'fingerprint_vintf=present\n'
    else
      printf 'default_fingerprint_userspace=absent\n'
      printf 'default_fingerprint_feature=absent\n'
      printf 'default_fingerprint_vintf=absent\n'
    fi
    printf 'privapp_permissions=SYSTEM/etc/permissions/privapp-permissions-org.lineageos.settings.m86.xml\n'
    printf 'first_stage_fstab=BOOT/RAMDISK/fstab.m86\n'
    printf 'second_stage_fstab=ROOT/fstab.m86\n'
    printf 'usb_rc=ROOT/init.m86.usb.rc\n'
    printf 'usb_identity_helper=SYSTEM/bin/m86_usb_serial\n'
    printf 'usb_hal=SYSTEM/vendor/bin/hw/android.hardware.usb@1.0-service.basic\n'
    printf 'usb_hal_rc=SYSTEM/vendor/etc/init/android.hardware.usb@1.0-service.basic.rc\n'
    printf 'keylayout=SYSTEM/usr/keylayout/fts.kl\n'
    printf 'keylayout=SYSTEM/usr/keylayout/gpio-keys.kl\n'
    printf 'keylayout=SYSTEM/usr/keylayout/fpc1020.kl\n'
    printf 'keylayout=SYSTEM/usr/keylayout/uinput-fpc.kl\n'
    for old_m3_owner_path in \
      rootdir/etc/fstab.m86 \
      rootdir/etc/recovery.fstab \
      rootdir/etc/init.m86.usb.rc \
      keylayout/fts.kl \
      keylayout/gpio-keys.kl \
      keylayout/fpc1020.kl; do
      printf 'retired_owner_path_absent=device/meizu/m86/%s\n' \
        "$old_m3_owner_path"
    done
    sha256sum \
      "$packaged_apk" \
      "$packaged_dtb" \
      "$packaged_privapp_permissions" \
      "$target_files_tree/BOOT/RAMDISK/fstab.m86" \
      "$target_files_tree/ROOT/fstab.m86" \
      "$packaged_usb_rc" \
      "$packaged_usb_helper" \
      "$packaged_usb_hal" \
      "$packaged_usb_hal_rc" \
      "$target_system/usr/keylayout/fts.kl" \
      "$target_system/usr/keylayout/gpio-keys.kl" \
      "$target_system/usr/keylayout/fpc1020.kl" \
      "$target_system/usr/keylayout/uinput-fpc.kl"
  } > "$artifact_dir/M3-TARGET-FILES.txt"
}

if [[ "$target" == wifi || "$target" == systemimage ]] || \
    ((full_zip_target)); then
  assert_wifi_outputs
fi
if [[ "$target" == bluetooth || "$target" == systemimage ]] || \
    ((full_zip_target)); then
  assert_bluetooth_outputs
fi
if [[ "$target" == systemimage ]] || ((full_zip_target)); then
  python3 "$local_root/tools/audit-m86-audio-abi.py" \
    "$source_root/vendor/meizu/m86/proprietary/lib/hw/audio.primary.m86.so" \
    "$source_root/vendor/meizu/m86/proprietary/lib64/hw/audio.primary.m86.so" |
    tee "$artifact_dir/M5-AUDIO-ABI.txt"
fi
if [[ "$target" == systemimage ]]; then
  assert_source_graphics_outputs
fi

case "$target" in
  kernel)
    copy_required "$product_out/kernel"
    ;;
  graphics)
    assert_source_graphics_outputs
    assert_deferred_graphics_absent
    mkdir -p "$artifact_dir/system/lib/hw" \
      "$artifact_dir/system/lib64/hw" \
      "$artifact_dir/system/lib" \
      "$artifact_dir/system/lib64" \
      "$artifact_dir/system/vendor/bin/hw" \
      "$artifact_dir/system/vendor/lib/hw" \
      "$artifact_dir/system/vendor/lib64/hw" \
      "$artifact_dir/system/vendor/lib" \
      "$artifact_dir/system/vendor/lib64"
    for relative_path in \
      "${graphics_relative_paths[@]}" \
      "${graphics_interface_relative_paths[@]}"; do
      source_file="$product_out/system/$relative_path"
      if [[ ! -s "$source_file" ]]; then
        printf 'Required graphics artifact is missing: %s\n' \
          "$source_file" >&2
        exit 1
      fi
      cp -a "$source_file" "$artifact_dir/system/$relative_path"
    done
    write_source_graphics_report "$artifact_dir/GRAPHICS-MODULES.txt"
    ;;
  nfc)
    {
      printf 'product=%s\n' "$product"
      printf 'module_target=android.hardware.nfc@1.1-service\n'
      printf 'module_target=nfc_nci_nxp\n'
      printf 'module_target=NfcNci\n'
      printf 'module_target=Tag\n'
      find "$product_out" -type f \
        \( -name 'android.hardware.nfc@1.1-service' -o \
           -name 'libnfc_nci_nxp.so' -o -name 'NfcNci.apk' -o \
           -name 'Tag.apk' \) -print 2>/dev/null | LC_ALL=C sort
    } > "$artifact_dir/NFC-MODULES.txt"
    ;;
  bootimage)
    copy_required "$product_out/boot.img"
    ;;
  recoveryimage)
    copy_required "$product_out/recovery.img"
    ;;
  systemimage)
    copy_required "$product_out/boot.img"
    copy_required "$product_out/system.img"
    write_source_graphics_report "$artifact_dir/GRAPHICS-OUTPUT.txt"
    ;;
  bacon | testzip)
    copy_required "$product_out/boot.img"
    copy_required "$product_out/recovery.img"

    mapfile -t target_files_packages < <(
      find "$product_out/obj/PACKAGING/target_files_intermediates" \
        -maxdepth 1 -type f -name "$product-target_files-*.zip" -print 2>/dev/null |
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
        -name "lineage-17.1-*-$ota_product_suffix.zip" -print |
        LC_ALL=C sort
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

if [[ "$target" == systemimage ]] || ((full_zip_target)); then
  assert_deferred_graphics_absent
fi

if ((!module_only_target)); then
  python3 "$local_root/tools/inspect-dtb.py" \
    "$artifact_dir/dtb.img" \
    --expect-string 'Meizu, M86' \
    --require-no-trailing-data | tee "$artifact_dir/DTB-HEADER.txt"
fi

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

if ((full_zip_target)); then
  assert_source_graphics_outputs
  target_files_tree="${target_files_packages[0]%.zip}"
  assert_graphics_target_files "$target_files_tree"
  assert_wifi_target_files "$target_files_tree"
  assert_radio_target_files "$target_files_tree"
  assert_bluetooth_target_files "$target_files_tree"
  assert_m5_audio_baseline_target_files "$target_files_tree"
  assert_m5_hifi_target_files "$target_files_tree"
  assert_m3_target_files "$target_files_tree"
  if ((nfc_experiment)); then
    bash "$local_root/tools/audit-nfc-experiment-output.sh" \
      "$target_files_tree" target-files "$source_root" |
      tee "$artifact_dir/NFC-TARGET-FILES.txt"
  fi
  source_fstab="$source_root/device/meizu/m86/storage/rootdir/etc/fstab.m86"
  for packaged_fstab in \
    "$target_files_tree/BOOT/RAMDISK/fstab.m86" \
    "$target_files_tree/ROOT/fstab.m86"; do
    if ! cmp --quiet "$packaged_fstab" "$source_fstab"; then
      printf 'Packaged fstab handoff input differs from the m86 source: %s\n' \
        "$packaged_fstab" >&2
      exit 1
    fi
  done
  if ! grep -F -x -q '    mount_all /fstab.m86' \
      "$target_files_tree/ROOT/init.m86.rc"; then
    printf 'Second-stage init does not consume the packaged root fstab.\n' >&2
    exit 1
  fi
  for mountpoint in cache custom data efs mnv; do
    if [[ ! -d "$target_files_tree/ROOT/$mountpoint" ]]; then
      printf 'Second-stage fstab mount point is absent from system root: ROOT/%s\n' \
        "$mountpoint" >&2
      exit 1
    fi
  done
  {
    printf 'first_stage_fstab=BOOT/RAMDISK/fstab.m86\n'
    printf 'second_stage_fstab=ROOT/fstab.m86\n'
    printf 'second_stage_consumer=ROOT/init.m86.rc:mount_all /fstab.m86\n'
    for mountpoint in cache custom data efs mnv; do
      printf 'second_stage_mountpoint=ROOT/%s\n' "$mountpoint"
    done
  } | tee "$artifact_dir/FSTAB-HANDOFF.txt"

  if ! unzip -p "${target_files_packages[0]}" RADIO/dtb.img | \
      cmp --quiet - "$release_dtb"; then
    printf 'Packaged target-files DTB differs from the verified mBack DTB.\n' >&2
    exit 1
  fi

  ota_package="${ota_packages[0]}"
  "$local_root/tools/audit-lineage-ota.sh" \
    "$ota_package" \
    "$artifact_dir/boot.img" \
    "$release_dtb" |
    tee "$artifact_dir/OTA-AUDIT.txt"

  # Twenty-four graphics destinations are source-built, two dead HWC-service
  # blobs, two legacy radio helpers, and the unused 64-bit primary audio input
  # are deferred. The NFC experiment restores one separately audited firmware
  # input while the remaining NFC/Trustonic inputs stay in their own scopes.
  # The 32-bit Flyme primary input is renamed to .flyme.so and audited below.
  installed_vendor_blob_count="$((vendor_blob_count - 43))"
  if ((nfc_experiment)); then
    installed_vendor_blob_count="$((vendor_blob_count - 42))"
  fi
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
         $2 != "./lib64/libion.so" &&
         $2 != "./lib/hw/memtrack.exynos5.so" &&
         $2 != "./lib64/hw/memtrack.exynos5.so" &&
         $2 != "./lib/libexynosgscaler.so" &&
         $2 != "./lib64/libexynosgscaler.so" &&
         $2 != "./lib/libexynosscaler.so" &&
         $2 != "./lib64/libexynosscaler.so" &&
         $2 != "./lib/libexynosutils.so" &&
         $2 != "./lib64/libexynosutils.so" &&
         $2 != "./lib/libexynosv4l2.so" &&
         $2 != "./lib64/libexynosv4l2.so" &&
         $2 != "./lib/libhwcutils.so" &&
         $2 != "./lib64/libhwcutils.so" &&
         $2 != "./lib/libmpp.so" &&
         $2 != "./lib64/libmpp.so" &&
         $2 != "./lib/libExynosHWCService.so" &&
         $2 != "./lib64/libExynosHWCService.so" &&
         $2 != "./app/020a0000000000000000000000000000.drbin" &&
         $2 != "./app/mcRegistry/04010000000000000000000000000000.tlbin" &&
         $2 != "./app/mcRegistry/04020000000000000000000000000000.tlbin" &&
         $2 != "./app/mcRegistry/07020000000000000000000000000000.tlbin" &&
         $2 != "./app/mcRegistry/07060000000000000000000000000000.tlbin" &&
         $2 != "./app/mcRegistry/07061000000000000000000000000000.tlbin" &&
         $2 != "./bin/mcDriverDaemon" &&
         $2 != "./bin/rild_exynos" &&
         $2 != "./bin/radiooptions_exynos" &&
         $2 != "./lib/hw/audio.primary.m86.so" &&
         $2 != "./lib64/hw/audio.primary.m86.so" &&
         $2 != "./lib64/hw/fingerprint.m86.so" &&
         $2 != "./lib64/lib_fpc_tac_shared.so" &&
         $2 != "./vendor/firmware/libpn547_fw.so" &&
         $2 != "./vendor/lib/libMcClient.so" &&
         $2 != "./vendor/lib/libMcRegistry.so" &&
         $2 != "./vendor/lib64/libMcClient.so" &&
         $2 != "./vendor/lib64/libMcRegistry.so"' \
      "$vendor_blob_lock" |
      sha256sum --quiet -c -
  ); then
    printf 'Installed system tree differs from the %s selected Flyme inputs.\n' \
      "$installed_vendor_blob_count" >&2
    exit 1
  fi
  if ((nfc_experiment)) && ! (
    cd "$product_out/system"
    awk '$2 == "./vendor/firmware/libpn547_fw.so"' "$vendor_blob_lock" |
      sha256sum --quiet -c -
  ); then
    printf 'NFC experiment firmware differs from the locked Flyme input.\n' >&2
    exit 1
  fi

  audio_wrapper="$product_out/system/lib/hw/audio.primary.m86.so"
  audio_flyme32="$product_out/system/lib/hw/audio.primary.m86.flyme.so"
  audio_flyme32_source="$source_root/vendor/meizu/m86/proprietary/lib/hw/audio.primary.m86.so"
  if [[ ! -s "$audio_wrapper" ]] || \
      [[ ! -s "$audio_flyme32" ]] || \
      ! cmp --quiet "$audio_flyme32" "$audio_flyme32_source" || \
      [[ -e "$product_out/system/lib64/hw/audio.primary.m86.so" ]]; then
    printf 'M5 audio wrapper/input ownership is incomplete in the installed tree.\n' >&2
    exit 1
  fi

  source_gralloc_32="$product_out/obj_arm/SHARED_LIBRARIES/gralloc.m86_intermediates/gralloc.m86.so"
  source_gralloc_64="$product_out/obj/SHARED_LIBRARIES/gralloc.m86_intermediates/gralloc.m86.so"
  if ! cmp --quiet \
      "$product_out/system/lib/hw/gralloc.m86.so" \
      "$source_gralloc_32" || \
      ! cmp --quiet \
      "$product_out/system/lib64/hw/gralloc.m86.so" \
      "$source_gralloc_64"; then
    printf 'Installed gralloc modules are not the m86-owned outputs.\n' >&2
    exit 1
  fi
  for retired_gralloc in \
    "$product_out/system/lib/hw/gralloc.exynos5.so" \
    "$product_out/system/lib64/hw/gralloc.exynos5.so"; do
    if [[ -e "$retired_gralloc" ]]; then
      printf 'Retired Exynos gralloc destination is still installed: %s\n' \
        "$retired_gralloc" >&2
      exit 1
    fi
  done

  source_hwc_32="$product_out/obj_arm/SHARED_LIBRARIES/hwcomposer.exynos5_intermediates/hwcomposer.exynos5.so"
  source_hwc_64="$product_out/obj/SHARED_LIBRARIES/hwcomposer.exynos5_intermediates/hwcomposer.exynos5.so"
  if ! cmp --quiet \
      "$product_out/system/lib/hw/hwcomposer.exynos5.so" \
      "$source_hwc_32" || \
      ! cmp --quiet \
      "$product_out/system/lib64/hw/hwcomposer.exynos5.so" \
      "$source_hwc_64"; then
    printf 'Installed hwcomposer modules are not the unmodified source outputs.\n' >&2
    exit 1
  fi

  for graphics_module in \
    memtrack.exynos5 \
    libexynosgscaler \
    libexynosscaler \
    libexynosutils \
    libexynosv4l2 \
    libhwcutils \
    libmpp; do
    module_relative_path="lib/${graphics_module}.so"
    if [[ "$graphics_module" == memtrack.exynos5 ]]; then
      module_relative_path="lib/hw/${graphics_module}.so"
    fi
    for multilib in 32 64; do
      object_root="$product_out/obj_arm"
      installed_relative_path="$module_relative_path"
      if [[ "$multilib" == 64 ]]; then
        object_root="$product_out/obj"
        installed_relative_path="${module_relative_path/lib\//lib64/}"
      fi
      source_graphics_module="$object_root/SHARED_LIBRARIES/${graphics_module}_intermediates/${graphics_module}.so"
      installed_graphics_module="$product_out/system/$installed_relative_path"
      if ! cmp --quiet \
          "$installed_graphics_module" "$source_graphics_module"; then
        printf 'Installed graphics dependency is not source-owned: %s\n' \
          "$installed_relative_path" >&2
        exit 1
      fi
    done
  done

  if ! grep -F -x -q 'ro.hardware.gralloc=m86' \
      "$product_out/system/build.prop"; then
    printf 'Built product does not select the m86 gralloc module.\n' >&2
    exit 1
  fi
  for vulkan_link in \
    "$product_out/system/vendor/lib/hw/vulkan.exynos5.so" \
    "$product_out/system/vendor/lib64/hw/vulkan.exynos5.so"; do
    if [[ ! -L "$vulkan_link" ]] || \
        [[ "$(readlink "$vulkan_link")" != ../egl/libGLES_mali.so ]]; then
      printf 'Invalid m86 Vulkan link: %s\n' "$vulkan_link" >&2
      exit 1
    fi
  done

  write_source_graphics_report "$artifact_dir/GRAPHICS-OUTPUT.txt"
  {
    for graphics_elf in \
      "$product_out/system/vendor/lib/egl/libGLES_mali.so" \
      "$product_out/system/vendor/lib64/egl/libGLES_mali.so"; do
      printf 'file=%s\n' "${graphics_elf#"$product_out/"}"
      file "$graphics_elf"
      sha256sum "$graphics_elf"
      readelf -d "$graphics_elf" | \
        grep -E 'Shared library:|Library soname:' || true
    done
  } >> "$artifact_dir/GRAPHICS-OUTPUT.txt"

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
    printf 'source_built_hwcomposer_count=2\n'
    printf 'source_built_libexynosdisplay_count=2\n'
    printf 'source_built_graphics_dependency_count=14\n'
    printf 'source_built_libhdmi_count=2\n'
    printf 'source_built_libion_count=2\n'
    printf 'source_built_replaced_graphics_destination_count=24\n'
    printf 'source_built_graphics_adapter_count=4\n'
    printf 'source_built_graphics_interface_count=9\n'
    printf 'source_built_graphics_runtime_destination_count=37\n'
    printf 'deferred_unused_graphics_blob_count=2\n'
  } |
    tee "$artifact_dir/PROPRIETARY-OUTPUT.txt"

  "$local_root/tools/audit-camera-abi.sh" \
    "$source_root" \
    "$out_root" \
    "$product_out/system/lib/libm86camera_shim.so" |
    tee "$artifact_dir/CAMERA-ABI.txt"
  if ((fingerprint_experiment)); then
    "$local_root/tools/audit-fingerprint-output.sh" "$product_out" experiment |
      tee "$artifact_dir/FINGERPRINT-OUTPUT.txt"
  else
    "$local_root/tools/audit-fingerprint-output.sh" "$product_out" absent |
      tee "$artifact_dir/FINGERPRINT-OUTPUT.txt"
  fi
  if ((nfc_experiment)); then
    bash "$local_root/tools/audit-nfc-experiment-output.sh" \
      "$product_out" product-out "$source_root" |
      tee "$artifact_dir/NFC-OUTPUT.txt"
  elif ((fingerprint_experiment)); then
    bash "$local_root/tools/audit-default-hidden-output.sh" \
      "$product_out" fingerprint |
      tee "$artifact_dir/DEFAULT-HIDDEN-OUTPUT.txt"
  else
    bash "$local_root/tools/audit-default-hidden-output.sh" "$product_out" |
      tee "$artifact_dir/DEFAULT-HIDDEN-OUTPUT.txt"
  fi
fi

if ((!module_only_target)); then
  kernel_config_ref="$source_root/kernel/meizu/m86/arch/arm64/configs/cm_pro5_defconfig"
  if ((fingerprint_experiment)); then
    kernel_config_ref="$source_root/kernel/meizu/m86/arch/arm64/configs/cm_pro5_fingerprint_experiment_defconfig"
  fi
  copy_required "$kernel_config_ref"
  cp -a "$kernel_out/.config" "$artifact_dir/kernel.config"
fi
copy_required "$local_root/locks/stock-flyme-8.0.5.0A.sha256"
copy_required "$local_root/locks/kernel-exfat-exynos7420.sha256"
copy_required "$local_root/patches/series.tsv"
copy_required "$local_root/docs/platform-debt.tsv"
cp -a "$memory_plan_file" "$artifact_dir/BUILD-MEMORY.txt"
copy_required "$remote_root/logs/reviewed-patch-state.txt"
if ((full_zip_target)); then
  cp -a "$vendor_blob_lock" "$artifact_dir/m86-proprietary-sha256s.txt"
fi
repo manifest -r -o "$artifact_dir/lineage-17.1-m86-lock.xml"

{
  printf 'built_at=%s\n' "$(date --iso-8601=seconds)"
  printf 'target=%s-userdebug %s\n' "$product" "$target"
  printf 'product=%s\n' "$product"
  printf 'nfc_experiment=%s\n' "$nfc_experiment"
  printf 'local_revision=%s\n' "$local_revision"
  printf 'device_revision=%s\n' "$device_revision"
  printf 'kernel_revision=%s\n' "$kernel_revision"
  printf 'vendor_revision=%s\n' "$vendor_revision"
  printf 'authoritative_input_sha256=%s\n' "$local_input_hash"
  printf 'source_root=%s\n' "$source_root"
  printf 'out_root=%s\n' "$out_root"
  printf 'jobs=%s\n' "$jobs"
  printf 'requested_jobs=%s\n' "$requested_jobs"
  printf 'art_boot_image_jobs=%s\n' "$art_boot_image_jobs"
  printf 'forced_boot_dexpreopt=%s\n' "$force_boot_dexpreopt"
  if [[ "$target" == systemimage ]] || ((full_zip_target)); then
    printf 'boot_dexpreopt=serialized arm then arm64\n'
  fi
  printf 'build_datetime=%s\n' "$BUILD_DATETIME"
  printf 'build_number=%s\n' "$BUILD_NUMBER"
  printf 'stock_base=Flyme 8.0.5.0A / Android 7 / API 24\n'
  if ((full_zip_target)); then
    printf 'verified_vendor_blob_count=%s\n' "$vendor_blob_count"
  else
    printf 'vendor_blob_audit=not-run-for-%s\n' "$target"
  fi
  if ((module_only_target)); then
    printf 'kernel_dtb_audit=not-run-for-%s\n' "$target"
  else
    printf 'boot_header_cmdline=empty\n'
    printf 'dtb_artifact=hash-locked Flyme DTB with SPI4 secure-mode NOP\n'
    printf 'dtb_sha256=%s\n' "$actual_dtb_hash"
    printf 'kernel_generated_dtb=diagnostic-only\n'
    printf 'dtb_ota_action=write verified mBack DTB to dtb\n'
    printf 'ramdisk_compression=gzip\n'
  fi
  if ((full_zip_target)); then
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
if [[ "$target" != testzip ]] && (( !nfc_experiment )) && \
    [[ "$local_revision" != *-dirty ]] && \
    [[ "$device_revision" != *-dirty ]] && \
    [[ "$kernel_revision" != *-dirty ]] && \
    [[ "$vendor_revision" != *-dirty ]]; then
  ln -sfn "$(basename "$artifact_dir")" "$artifact_root/lineage-latest"
else
  printf 'Development or experiment artifact was not promoted to lineage-latest.\n'
fi
