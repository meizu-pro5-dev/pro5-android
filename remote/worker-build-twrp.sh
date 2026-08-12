#!/usr/bin/env bash

set -eo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
local_root="$(cd "$script_dir/.." && pwd)"
remote_root="$(cd "$local_root/.." && pwd)"
source_root="$remote_root/src/twrp-9.0"
build_out="$remote_root/out/twrp-9.0"
snapshot_root="$remote_root/out/twrp-9.0-repro-pass1"
run_root="$remote_root/run"
artifact_root="$remote_root/artifacts"
twrp_patch_series="$local_root/patches/twrp-series.tsv"

jobs="${1:-8}"
requested_jobs="$jobs"
status_file="${2:-$run_root/twrp-build-latest.status}"
log_file="${3:-$run_root/twrp-build-latest.log}"
build_stamp="${4:-$(date +%Y%m%d-%H%M%S)}"
local_revision="${5:-unknown}"
kernel_profile="${6:-maintained}"

if [[ ! "$jobs" =~ ^[1-9][0-9]*$ ]] || ((jobs > 64)); then
  printf 'Invalid TWRP build job count: %s\n' "$jobs" >&2
  exit 2
fi
if [[ "$kernel_profile" != "maintained" && \
    "$kernel_profile" != "pre-pstore-note5-pan" && \
    "$kernel_profile" != "pre-pstore-usb-vbus" && \
    "$kernel_profile" != "pre-pstore-usb-vbus-no-lpd" ]]; then
  printf 'Invalid TWRP kernel profile: %s\n' "$kernel_profile" >&2
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

memory_plan_file="$run_root/twrp-$build_stamp-memory-plan.txt"
"$script_dir/prepare-builder-memory.sh" \
  "$requested_jobs" twrp "$build_out" "$memory_plan_file"
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
if [[ ! -s "$twrp_patch_series" ]]; then
  printf 'The reviewed TWRP patch series is missing.\n' >&2
  exit 1
fi
while IFS=$'\t' read -r repository patch_path; do
  [[ -z "$repository" || "$repository" == \#* ]] && continue
  patch_file="$local_root/$patch_path"
  if [[ ! -f "$patch_file" ]] || \
      ! git -C "$source_root/$repository" apply --reverse --check \
        "$patch_file" 2>/dev/null; then
    printf 'Reviewed TWRP patch is not applied: %s\n' "$patch_path" >&2
    exit 1
  fi
done < "$twrp_patch_series"

stock_lock="$local_root/locks/stock-flyme-8.0.5.0A.sha256"
kernel_exfat_lock="$local_root/locks/kernel-exfat-exynos7420.sha256"
if [[ ! -s "$kernel_exfat_lock" ]] || ! (
  cd "$source_root/kernel/meizu/m86"
  sha256sum --quiet -c "$kernel_exfat_lock"
); then
  printf 'The installed Exynos 7420 exFAT source does not match its lock.\n' >&2
  exit 1
fi
touch_firmware="$source_root/device/meizu/m86/recovery/root/etc/firmware/st_fts.bin"
expected_touch_hash="$(
  awk '$2 == "system.img/vendor/firmware/st_fts.bin" { print $1 }' \
    "$stock_lock"
)"
if [[ ! "$expected_touch_hash" =~ ^[0-9a-f]{64}$ ]]; then
  printf 'The stock lock has no unique STM touch firmware hash.\n' >&2
  exit 1
fi
if [[ ! -f "$touch_firmware" ]] || \
    [[ "$(stat -c %s "$touch_firmware")" != "65568" ]] || \
    [[ "$(sha256sum "$touch_firmware" | awk '{ print $1 }')" != \
       "$expected_touch_hash" ]]; then
  printf 'The injected Flyme 8 STM recovery firmware is absent or invalid.\n' >&2
  exit 1
fi

python2_root="$source_root/prebuilts/python/linux-x86/2.7.5"
python2_dir="$python2_root/bin"
python2_source="$source_root/external/python/cpython2"
python2_overlay="$remote_root/work/twrp-python2-host"
if [[ ! -x "$python2_dir/python2.7" ]]; then
  printf 'TWRP 9.0 requires its synchronized Python 2.7 prebuilt.\n' >&2
  exit 1
fi
if ! command -v lzma >/dev/null 2>&1; then
  printf 'TWRP recovery compression requires the host lzma tool.\n' >&2
  exit 1
fi
for python2_zlib_input in \
  "$python2_source/Include/Python.h" \
  "$python2_source/Modules/zlibmodule.c" \
  "$python2_root/include/python2.7/pyconfig.h"; do
  if [[ ! -s "$python2_zlib_input" ]]; then
    printf 'Pinned Python 2 zlib build input is missing: %s\n' \
      "$python2_zlib_input" >&2
    exit 1
  fi
done

# AOSP's pinned 32-bit Python 2.7.5 runtime omits its zlib extension, but Pie
# host tools import compressed Python modules. Build only that extension from
# the manifest-pinned CPython 2 source against the builder's 32-bit zlib ABI.
# Both required host development packages are provisioned by bootstrap-builder.
mkdir -p "$python2_overlay"
gcc -m32 -O2 -fPIC -shared \
  -I"$python2_source/Include" \
  -I"$python2_root/include/python2.7" \
  "$python2_source/Modules/zlibmodule.c" \
  -lz \
  -o "$python2_overlay/zlib.so.tmp"
mv "$python2_overlay/zlib.so.tmp" "$python2_overlay/zlib.so"
export PYTHONPATH="$python2_overlay"
export PATH="$python2_dir:$PATH"
if ! python2.7 -c \
    'import zlib; assert zlib.decompress(zlib.compress("m86")) == "m86"'; then
  printf 'Pinned Python 2 host zlib extension failed its round-trip test.\n' >&2
  exit 1
fi

export ALLOW_MISSING_DEPENDENCIES=true
export USE_CCACHE=1
export CCACHE_DIR="$remote_root/ccache"
export CCACHE_BASEDIR="$source_root"
export CCACHE_EXEC="$(command -v ccache)"
export LC_ALL=C
export BUILD_DATETIME=1538238534
export BUILD_NUMBER=pro5-twrp-9-repro
export BUILD_USERNAME=pro5-port
export BUILD_HOSTNAME=autodl
export SOURCE_DATE_EPOCH=1538238534
export KBUILD_BUILD_USER=pro5-port
export KBUILD_BUILD_HOST=autodl
export KBUILD_BUILD_VERSION=1
export KBUILD_BUILD_TIMESTAMP='Sat Sep 29 16:28:54 UTC 2018'

# Android 9 Soong accepts C.UTF-8, en_US.UTF-8, or en_US.utf8, while this
# builder exposes only the equivalent C.utf8 spelling. Materialize the
# standard en_US locale once so the unmodified, pinned TWRP source can select a
# UTF-8 build locale. This is deterministic host setup, not a source patch.
if ! locale -a | grep -Eq '^(C\.UTF-8|en_US\.UTF-8|en_US\.utf8)$'; then
  if ! command -v localedef >/dev/null 2>&1; then
    printf 'TWRP requires localedef to provide an Android-compatible UTF-8 locale.\n' >&2
    exit 1
  fi
  localedef -i en_US -f UTF-8 en_US.UTF-8
fi
if ! locale -a | grep -Eq '^(C\.UTF-8|en_US\.UTF-8|en_US\.utf8)$'; then
  printf 'Unable to provide C.UTF-8 or en_US.UTF-8 for TWRP Soong.\n' >&2
  exit 1
fi

ccache --max-size=25G
ccache --zero-stats

printf 'TWRP build started at %s\n' "$(date --iso-8601=seconds)"
printf 'Source: %s\nRequested jobs: %s\nJobs: %s\nStable output for both passes: %s\n' \
  "$source_root" "$requested_jobs" "$jobs" "$build_out"
printf 'Local revision: %s\n' "$local_revision"
printf 'Kernel profile: %s\n' "$kernel_profile"
printf 'Python: %s\n' "$(python2.7 --version 2>&1)"
printf 'Python zlib: %s\n' \
  "$(python2.7 -c 'import zlib; print(zlib.ZLIB_VERSION)')"

kernel_root="$source_root/kernel/meizu/m86"
aarch64_prefix="$source_root/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-"
arm_prefix="$source_root/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/bin/arm-linux-androideabi-"
if [[ "$kernel_profile" == "pre-pstore-note5-pan" || \
    "$kernel_profile" == "pre-pstore-usb-vbus" || \
    "$kernel_profile" == "pre-pstore-usb-vbus-no-lpd" ]]; then
  pre_pstore_defconfig_sha256=11683809ee51d42d6a3c7a9e0e9ff6e2bfd9fd12b4f2b58b19cc31d562b057ae
  if [[ "$kernel_profile" == "pre-pstore-usb-vbus-no-lpd" ]]; then
    pre_pstore_defconfig_sha256=3ed5fa4bc2303541df9b26de1dfd96737562b604c967d8615d66e27f5677d996
  fi
  for locked_source in \
    "$pre_pstore_defconfig_sha256 arch/arm64/configs/cm_pro5_defconfig" \
    'ff6b08939a17c25cd26a3e9fee919a2a52acc75a916fd7b3a1b86f4b75dd9b95 drivers/of/of_reserved_mem.c' \
    'bfcf91cc6a8f2c2bc1c9e8fb8f0bed74566a801e5b5b1728f9c997af6a725fe5 drivers/platform/exynos/exynos_ramoops.c' \
    '6174ccaf5ac2d8dfb8711a7dcf057dd53ca90478006ee8b88a3ace1c0d6d0349 include/linux/of_reserved_mem.h'; do
    expected_source_sha256="${locked_source%% *}"
    relative_source="${locked_source#* }"
    actual_source_sha256="$(
      sha256sum "$kernel_root/$relative_source" | awk '{ print $1 }'
    )"
    if [[ "$actual_source_sha256" != "$expected_source_sha256" ]]; then
      printf 'Pre-pstore source mismatch: %s\n' "$relative_source" >&2
      exit 1
    fi
  done
  if [[ "$kernel_profile" == "pre-pstore-note5-pan" ]]; then
    if ! grep -F -q 'Keep PAN as a lightweight command-mode refresh.' \
        "$kernel_root/drivers/video/exynos/decon/decon-int_drv.c" || \
        sed -n '/int decon_pan_display(/,/^}/p' \
          "$kernel_root/drivers/video/exynos/decon/decon-int_drv.c" | \
          grep -Eq '^[[:space:]]*decon_set_par\(info\);'; then
      printf 'The pre-pstore profile omits the isolated Note5 PAN change.\n' >&2
      exit 1
    fi
  else
    for locked_usb_source in \
      '455f1e7f71eafb4f4516c789a28fa3c90f3880a3a484c54d3a8dfd19f44112d0 drivers/video/exynos/decon/decon-int_drv.c' \
      'e0058fc84b4043aef966932507a190c655ef51b2f7c6e0d2c610dda64f1961ce drivers/usb/gadget/android.c'; do
      expected_usb_sha256="${locked_usb_source%% *}"
      relative_usb_source="${locked_usb_source#* }"
      actual_usb_sha256="$(
        sha256sum "$kernel_root/$relative_usb_source" | awk '{ print $1 }'
      )"
      if [[ "$actual_usb_sha256" != "$expected_usb_sha256" ]]; then
        printf 'USB diagnostic source mismatch: %s\n' \
          "$relative_usb_source" >&2
        exit 1
      fi
    done
    if ! grep -F -q \
        'android_usb: forcing DWC3 gadget VBUS session' \
        "$kernel_root/drivers/usb/gadget/android.c"; then
      printf 'The USB diagnostic profile omits the forced DWC3 session.\n' >&2
      exit 1
    fi
  fi
  if [[ "$kernel_profile" == "pre-pstore-usb-vbus-no-lpd" ]]; then
    if ! grep -F -x -q '# CONFIG_DECON_LPD_DISPLAY is not set' \
        "$kernel_root/arch/arm64/configs/cm_pro5_defconfig"; then
      printf 'The no-LPD profile still enables DECON low-power display.\n' >&2
      exit 1
    fi
  fi
fi
for required_toolchain in "${aarch64_prefix}gcc" "${arm_prefix}gcc"; do
  if [[ ! -x "$required_toolchain" ]]; then
    printf 'Required kernel toolchain is missing: %s\n' \
      "$required_toolchain" >&2
    exit 1
  fi
done

build_twrp_pass() {
  local pass_name="$1"
  local product_out="$build_out/target/product/m86"
  local recovery_image="$product_out/recovery.img"
  local staged_touch_firmware="$product_out/recovery/root/etc/firmware/st_fts.bin"
  local kernel_out="$product_out/obj/KERNEL_OBJ"
  local generated_dtb="$kernel_out/arch/arm64/boot/dts/exynos7420-m86-codegen.dtb"

  case "$build_out" in
    "$remote_root/out/twrp-9.0") ;;
    *)
      printf 'Refusing to clear an unexpected TWRP output: %s\n' \
        "$build_out" >&2
      return 1
      ;;
  esac

  rm -rf -- "$build_out"
  mkdir -p "$build_out"
  printf 'Starting clean TWRP reproducibility pass %s at %s\n' \
    "$pass_name" "$(date --iso-8601=seconds)"

  (
    export OUT_DIR="$build_out"
    cd "$source_root"
    # Android 9 envsetup and shell functions are not nounset-safe.
    # shellcheck disable=SC1091
    source build/envsetup.sh
    lunch omni_m86-eng
    mka recoveryimage -j"$jobs"
  )

  if [[ ! -s "$recovery_image" ]]; then
    printf 'TWRP pass %s did not produce recovery.img.\n' \
      "$pass_name" >&2
    return 1
  fi
  if [[ ! -f "$staged_touch_firmware" ]] || \
      [[ "$(stat -c %s "$staged_touch_firmware")" != "65568" ]] || \
      [[ "$(sha256sum "$staged_touch_firmware" | awk '{ print $1 }')" != \
         "$expected_touch_hash" ]]; then
    printf 'TWRP pass %s omitted or changed st_fts.bin.\n' \
      "$pass_name" >&2
    return 1
  fi
  if [[ ! -s "$kernel_out/.config" ]]; then
    printf 'TWRP pass %s omitted the generated kernel config.\n' \
      "$pass_name" >&2
    return 1
  fi
  for required_kernel_setting in \
    CONFIG_DM_CRYPT=y \
    CONFIG_FMP=y \
    CONFIG_UFS_FMP_DM_CRYPT=y \
    CONFIG_RD_GZIP=y \
    CONFIG_RD_LZMA=y \
    CONFIG_DECOMPRESS_LZMA=y \
    CONFIG_INPUT_EVDEV=y \
    CONFIG_TOUCHSCREEN_FTS=y \
    CONFIG_USB_DWC3_DUAL_ROLE=y \
    CONFIG_USB_G_ANDROID=y \
    CONFIG_USB_STORAGE=y \
    CONFIG_MMC_DW_EXYNOS=y \
    CONFIG_EXT4_FS=y \
    CONFIG_VFAT_FS=y \
    CONFIG_EXFAT_FS=y \
    CONFIG_EXFAT_VIRTUAL_XATTR=y \
    'CONFIG_EXFAT_VIRTUAL_XATTR_SELINUX_LABEL="u:object_r:sdcard_external:s0"'; do
    if ! grep -F -x -q "$required_kernel_setting" "$kernel_out/.config"; then
      printf 'TWRP pass %s kernel config omitted %s.\n' \
        "$pass_name" "$required_kernel_setting" >&2
      return 1
    fi
  done
  if [[ "$kernel_profile" == "maintained" ]]; then
    for required_diagnostic_setting in \
      CONFIG_PSTORE=y \
      CONFIG_PSTORE_CONSOLE=y \
      CONFIG_PSTORE_RAM=y; do
      if ! grep -F -x -q "$required_diagnostic_setting" \
          "$kernel_out/.config"; then
        printf 'TWRP pass %s kernel config omitted %s.\n' \
          "$pass_name" "$required_diagnostic_setting" >&2
        return 1
      fi
    done
  elif ! grep -F -x -q '# CONFIG_PSTORE is not set' \
      "$kernel_out/.config"; then
    printf 'TWRP pass %s pre-pstore kernel unexpectedly enables pstore.\n' \
      "$pass_name" >&2
    return 1
  fi
  if [[ "$kernel_profile" == "pre-pstore-usb-vbus-no-lpd" ]]; then
    if ! grep -F -x -q '# CONFIG_DECON_LPD_DISPLAY is not set' \
        "$kernel_out/.config"; then
      printf 'TWRP pass %s kernel unexpectedly enables DECON LPD.\n' \
        "$pass_name" >&2
      return 1
    fi
  elif [[ "$kernel_profile" == "pre-pstore-usb-vbus" ]] && \
      ! grep -F -x -q 'CONFIG_DECON_LPD_DISPLAY=y' \
        "$kernel_out/.config"; then
    printf 'TWRP pass %s USB baseline unexpectedly disables DECON LPD.\n' \
      "$pass_name" >&2
    return 1
  fi
  if grep -E -q \
      'CONFIG_(FAT_VIRTUAL_XATTR|FAT_VIRTUAL_XATTR_SELINUX_LABEL|FAT_SUPPORT_STLOG|EXFAT_SUPPORT_STLOG)' \
      "$kernel_out/.config"; then
    printf 'TWRP pass %s retained a stale filesystem config option.\n' \
      "$pass_name" >&2
    return 1
  fi
  for required_exfat_object in \
    fs/exfat/exfat_core.o \
    fs/exfat/exfat_fs.o; do
    if [[ ! -s "$kernel_out/$required_exfat_object" ]]; then
      printf 'TWRP pass %s omitted kernel object %s.\n' \
        "$pass_name" "$required_exfat_object" >&2
      return 1
    fi
  done
  if [[ "$kernel_profile" == "maintained" ]]; then
    for required_diagnostic_object in \
      fs/pstore/ramoops.o \
      drivers/platform/exynos/exynos_ramoops.o; do
      if [[ ! -s "$kernel_out/$required_diagnostic_object" ]]; then
        printf 'TWRP pass %s omitted kernel object %s.\n' \
          "$pass_name" "$required_diagnostic_object" >&2
        return 1
      fi
    done
  fi

  # recoveryimage correctly contains no DT section. Build the matching raw
  # partition image from the same configured kernel output for each pass.
  make \
    -C "$kernel_root" \
    "O=$kernel_out" \
    ARCH=arm64 \
    "CROSS_COMPILE=$aarch64_prefix" \
    "CROSS_COMPILE_ARM32=$arm_prefix" \
    -j"$jobs" \
    dtbs
  if [[ ! -s "$generated_dtb" ]]; then
    printf 'TWRP pass %s omitted the raw m86 DTB.\n' \
      "$pass_name" >&2
    return 1
  fi
}

product_out="$build_out/target/product/m86"
recovery_image="$product_out/recovery.img"
kernel_out="$product_out/obj/KERNEL_OBJ"
generated_dtb="$kernel_out/arch/arm64/boot/dts/exynos7420-m86-codegen.dtb"

# Android host and target ELF build IDs include absolute intermediate paths.
# Use the same clean OUT_DIR for both passes, preserving only the three pass-1
# acceptance inputs outside that directory before clearing it again.
build_twrp_pass 1
case "$snapshot_root" in
  "$remote_root/out/twrp-9.0-repro-pass1") ;;
  *)
    printf 'Refusing to clear an unexpected TWRP snapshot: %s\n' \
      "$snapshot_root" >&2
    exit 1
    ;;
esac
rm -rf -- "$snapshot_root"
mkdir -p "$snapshot_root"
cp -a "$recovery_image" "$snapshot_root/recovery.img"
cp -a "$generated_dtb" "$snapshot_root/exynos7420-m86-codegen.dtb"
cp -a "$kernel_out/.config" "$snapshot_root/kernel.config"

build_twrp_pass 2

recovery_image_pass1="$snapshot_root/recovery.img"
generated_dtb_pass1="$snapshot_root/exynos7420-m86-codegen.dtb"
kernel_config_pass1="$snapshot_root/kernel.config"

for comparison in \
  "$recovery_image_pass1|$recovery_image|recovery.img" \
  "$generated_dtb_pass1|$generated_dtb|exynos7420-m86-codegen.dtb" \
  "$kernel_config_pass1|$kernel_out/.config|kernel.config"; do
  first_file="${comparison%%|*}"
  comparison_remainder="${comparison#*|}"
  second_file="${comparison_remainder%%|*}"
  comparison_name="${comparison_remainder#*|}"
  if ! cmp --silent "$first_file" "$second_file"; then
    printf 'TWRP clean builds differ: %s\n' "$comparison_name" >&2
    sha256sum "$first_file" "$second_file" >&2
    exit 1
  fi
done

artifact_dir="$artifact_root/twrp-$build_stamp-recoveryimage"
mkdir -p "$artifact_dir"
cp -a "$recovery_image" "$artifact_dir/recovery.img"
cp -a "$generated_dtb" \
  "$artifact_dir/exynos7420-m86-codegen.dtb"
cp -a "$source_root/kernel/meizu/m86/arch/arm64/configs/cm_pro5_defconfig" \
  "$artifact_dir/cm_pro5_defconfig"
cp -a "$kernel_out/.config" "$artifact_dir/kernel.config"
cp -a "$local_root/twrp/FLASHING.md" "$artifact_dir/FLASHING.md"
cp -a "$local_root/locks/stock-flyme-8.0.5.0A.sha256" \
  "$artifact_dir/stock-flyme-8.0.5.0A.sha256"
cp -a "$kernel_exfat_lock" "$artifact_dir/kernel-exfat-exynos7420.sha256"
cp -a "$memory_plan_file" "$artifact_dir/BUILD-MEMORY.txt"
(
  cd "$kernel_out"
  sha256sum fs/exfat/exfat_core.o fs/exfat/exfat_fs.o
) > "$artifact_dir/EXFAT-KERNEL.txt"
(
  if [[ "$kernel_profile" == "maintained" ]]; then
    cd "$kernel_out"
    sha256sum \
      fs/pstore/ramoops.o \
      drivers/platform/exynos/exynos_ramoops.o
  else
    printf 'kernel_profile=%s\n' "$kernel_profile"
    printf 'pstore_config=disabled to match proven v11 kernel baseline\n'
    sha256sum \
      "$kernel_root/arch/arm64/configs/cm_pro5_defconfig" \
      "$kernel_root/drivers/of/of_reserved_mem.c" \
      "$kernel_root/drivers/platform/exynos/exynos_ramoops.c" \
      "$kernel_root/include/linux/of_reserved_mem.h"
    if [[ "$kernel_profile" == "pre-pstore-usb-vbus" || \
        "$kernel_profile" == "pre-pstore-usb-vbus-no-lpd" ]]; then
      sha256sum \
        "$kernel_root/drivers/video/exynos/decon/decon-int_drv.c" \
        "$kernel_root/drivers/usb/gadget/android.c"
    fi
  fi
) > "$artifact_dir/PSTORE-KERNEL.txt"
if [[ "$kernel_profile" == "pre-pstore-usb-vbus" || \
    "$kernel_profile" == "pre-pstore-usb-vbus-no-lpd" ]]; then
  install -D -m 0644 \
    "$local_root/patches/twrp-kernel-m86/0001-usb-force-gadget-vbus-on-enable.patch" \
    "$artifact_dir/patches/twrp-kernel-m86/0001-usb-force-gadget-vbus-on-enable.patch"
fi
if [[ "$kernel_profile" == "pre-pstore-usb-vbus-no-lpd" ]]; then
  install -D -m 0644 \
    "$local_root/patches/twrp-kernel-m86/0002-display-disable-decon-lpd.patch" \
    "$artifact_dir/patches/twrp-kernel-m86/0002-display-disable-decon-lpd.patch"
fi
cp -a "$twrp_patch_series" "$artifact_dir/twrp-series.tsv"
while IFS=$'\t' read -r repository patch_path; do
  [[ -z "$repository" || "$repository" == \#* ]] && continue
  install -D -m 0644 \
    "$local_root/$patch_path" "$artifact_dir/$patch_path"
done < "$twrp_patch_series"

{
  printf 'result=byte-identical\n'
  printf 'clean_build_passes=2\n'
  printf 'recovery_pass1_sha256=%s\n' \
    "$(sha256sum "$recovery_image_pass1" | awk '{ print $1 }')"
  printf 'recovery_pass2_sha256=%s\n' \
    "$(sha256sum "$recovery_image" | awk '{ print $1 }')"
  printf 'dtb_pass1_sha256=%s\n' \
    "$(sha256sum "$generated_dtb_pass1" | awk '{ print $1 }')"
  printf 'dtb_pass2_sha256=%s\n' \
    "$(sha256sum "$generated_dtb" | awk '{ print $1 }')"
  printf 'kernel_config_pass1_sha256=%s\n' \
    "$(sha256sum "$kernel_config_pass1" | awk '{ print $1 }')"
  printf 'kernel_config_pass2_sha256=%s\n' \
    "$(sha256sum "$kernel_out/.config" | awk '{ print $1 }')"
} > "$artifact_dir/REPRODUCIBILITY.txt"

recovery_fstab_hash="$(
  sha256sum "$source_root/device/meizu/m86/recovery.fstab" | awk '{ print $1 }'
)"
root_fstab_hash="$(
  sha256sum "$source_root/device/meizu/m86/rootdir/fstab.m86" | awk '{ print $1 }'
)"
recovery_init_hash="$(
  sha256sum \
    "$source_root/device/meizu/m86/recovery/root/init.recovery.m86.rc" |
    awk '{ print $1 }'
)"
pigz_link_hash="$(printf pigz | sha256sum | awk '{ print $1 }')"
python3 "$local_root/tools/inspect-android-boot-image.py" \
  "$artifact_dir/recovery.img" \
  --expect-valid-image-id \
  --expect-page-size 4096 \
  --expect-kernel-addr 0x40080000 \
  --expect-ramdisk-addr 0x42000000 \
  --expect-second-addr 0x40f00000 \
  --expect-tags-addr 0x40000100 \
  --expect-second-size 0 \
  --expect-dt-size 0 \
  --expect-empty-cmdline \
  --expect-ramdisk-compression lzma \
  --expect-ramdisk-elf sbin/recovery \
  --expect-ramdisk-elf sbin/adbd \
  --expect-ramdisk-elf sbin/libminadbd.so \
  --expect-ramdisk-elf sbin/libfusesideload.so \
  --expect-ramdisk-elf sbin/libtwrpmtp-ffs.so \
  --expect-ramdisk-elf sbin/libcryptfsfde.so \
  --expect-ramdisk-elf sbin/libe4crypt.so \
  --expect-ramdisk-elf sbin/exfat-fuse \
  --expect-ramdisk-elf sbin/fsck.exfat \
  --expect-ramdisk-elf sbin/mkfs.ntfs \
  --expect-ramdisk-elf sbin/mount.ntfs \
  --expect-ramdisk-file-sha256 \
    "etc/recovery.fstab=$recovery_fstab_hash" \
  --expect-ramdisk-file-sha256 "fstab.m86=$root_fstab_hash" \
  --expect-ramdisk-file-sha256 \
    "init.recovery.m86.rc=$recovery_init_hash" \
  --expect-ramdisk-file-sha256 "sbin/gzip=$pigz_link_hash" \
  --expect-ramdisk-file-sha256 "sbin/gunzip=$pigz_link_hash" \
  --expect-ramdisk-file-sha256 \
    "etc/firmware/st_fts.bin=$expected_touch_hash" \
  --expect-ramdisk-directory-files \
    "twres/languages=en.xml,zh_CN.xml" \
  --expect-ramdisk-directory-files \
    "twres/fonts=DroidSansFallback.ttf,DroidSansMono.ttf,RobotoCondensed-Regular.ttf" \
  --max-size 33550336 | tee "$artifact_dir/RECOVERY-HEADER.txt"

python3 "$local_root/tools/inspect-dtb.py" \
  "$artifact_dir/exynos7420-m86-codegen.dtb" \
  --expect-string 'Meizu, M86' \
  --require-no-trailing-data | tee "$artifact_dir/DTB-HEADER.txt"

(
  cd "$source_root"
  repo manifest -r -o "$artifact_dir/twrp-9.0-m86-lock.xml"
)
twrp_version="$(
  sed -n 's/^#define TW_MAIN_VERSION_STR[[:space:]]*"\([^"]*\)"/\1/p' \
    "$source_root/bootable/recovery/variables.h"
)"

{
  printf 'built_at=%s\n' "$(date --iso-8601=seconds)"
  printf 'target=omni_m86-eng recoveryimage\n'
  printf 'local_revision=%s\n' "$local_revision"
  printf 'kernel_profile=%s\n' "$kernel_profile"
  printf 'twrp_version=%s\n' "$twrp_version"
  printf 'source_root=%s\n' "$source_root"
  printf 'out_root_pass1=%s\n' "$build_out"
  printf 'out_root_pass2=%s\n' "$build_out"
  printf 'pass1_snapshot=%s\n' "$snapshot_root"
  printf 'output_path_policy=same absolute OUT_DIR for both clean passes\n'
  printf 'jobs=%s\n' "$jobs"
  printf 'requested_jobs=%s\n' "$requested_jobs"
  printf 'build_datetime=%s\n' "$BUILD_DATETIME"
  printf 'build_number=%s\n' "$BUILD_NUMBER"
  printf 'clean_build_passes=2\n'
  printf 'reproducibility=byte-identical recovery.img dtb kernel.config\n'
  printf 'stock_base=Flyme 8.0.5.0A / Android 7 / API 24\n'
  printf 'proprietary_recovery_blobs=etc/firmware/st_fts.bin\n'
  printf 'st_fts_sha256=%s\n' "$expected_touch_hash"
  if [[ "$kernel_profile" == "maintained" ]]; then
    printf 'source_checkout_validation=HEAD tree equals index and clean worktree\n'
  elif [[ "$kernel_profile" == "pre-pstore-usb-vbus" ]]; then
    printf 'source_checkout_validation=SHA-locked v11 kernel baseline plus only the android_usb forced-VBUS patch\n'
  elif [[ "$kernel_profile" == "pre-pstore-usb-vbus-no-lpd" ]]; then
    printf 'source_checkout_validation=SHA-locked v11 kernel baseline plus android_usb forced-VBUS and DECON LPD-disable patches\n'
  else
    printf 'source_checkout_validation=maintained tree with four SHA-locked pre-pstore files and Note5 PAN change\n'
  fi
  printf 'recovery_partition_limit=33550336\n'
  printf 'dtb_packaging=raw separate partition\n'
  printf 'ramdisk_compression=lzma-alone recovery; gzip decoder retained\n'
  printf 'ramdisk_inventory_order=LC_ALL=C sorted\n'
  printf 'file_contexts_regex_payload=omitted host PCRE2 bytecode\n'
  printf 'gzip_symlink_owner=pigz\n'
  printf 'lzma_runtime=%s\n' "$(lzma --version | head -n 1)"
  printf 'python_runtime=%s\n' "$(python2.7 --version 2>&1)"
  printf 'python_zlib_runtime=%s\n' \
    "$(python2.7 -c 'import zlib; print(zlib.ZLIB_VERSION)')"
  printf 'python_zlib_source_revision=%s\n' \
    "$(git -C "$python2_source" rev-parse HEAD)"
} > "$artifact_dir/BUILD-METADATA"

printf 'TWRP build completed at %s\n' "$(date --iso-8601=seconds)"
printf 'Artifacts: %s\n' "$artifact_dir"
ccache --show-stats
cp -a "$log_file" "$artifact_dir/"

(
  cd "$artifact_dir"
  find . -type f ! -name SHA256SUMS -print0 |
    LC_ALL=C sort -z |
    xargs -0 sha256sum
) > "$artifact_dir/SHA256SUMS"
ln -sfn "$(basename "$artifact_dir")" "$artifact_root/twrp-latest"
