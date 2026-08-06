#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
device_root="$project_root/device/meizu/m86"
board_config="$device_root/BoardConfig.mk"
android_makefile="$device_root/Android.mk"
device_makefile="$device_root/device.mk"
system_prop="$device_root/system.prop"
usb_rc="$device_root/rootdir/etc/init.m86.usb.rc"
recovery_fstab="$device_root/rootdir/etc/recovery.fstab"
releasetools="$device_root/releasetools/releasetools.py"
kernel_config="$project_root/kernel/meizu/m86/arch/arm64/configs/cm_pro5_defconfig"
platform_patch="$project_root/patches/device-samsung-universal7420-common/0001-target-add-meizu-m86.patch"
build_worker="$project_root/remote/worker-build.sh"

for required_file in \
  "$board_config" \
  "$android_makefile" \
  "$device_makefile" \
  "$system_prop" \
  "$usb_rc" \
  "$recovery_fstab" \
  "$releasetools" \
  "$kernel_config" \
  "$platform_patch" \
  "$build_worker"; do
  if [[ ! -s "$required_file" ]]; then
    printf 'Missing required LineageOS source: %s\n' "$required_file" >&2
    exit 1
  fi
done

require_fixed() {
  local pattern="$1"
  local source_file="$2"

  if ! rg -F -q -- "$pattern" "$source_file"; then
    printf 'Required LineageOS setting is absent from %s: %s\n' \
      "$source_file" "$pattern" >&2
    exit 1
  fi
}

require_empty_assignment() {
  local variable_name="$1"
  local source_file="$2"

  if ! rg -q "^${variable_name}[[:space:]]*:=[[:space:]]*$" "$source_file"; then
    printf 'Required empty LineageOS override is absent from %s: %s\n' \
      "$source_file" "$variable_name" >&2
    exit 1
  fi
}

require_fixed 'BOARD_KERNEL_BASE := 0x40000000' "$board_config"
require_fixed 'BOARD_KERNEL_PAGESIZE := 4096' "$board_config"
require_fixed '--kernel_offset 0x00080000' "$board_config"
require_fixed '--ramdisk_offset 0x02000000' "$board_config"
require_fixed '--second_offset 0x00f00000' "$board_config"
require_fixed '--tags_offset 0x00000100' "$board_config"
require_fixed 'BOARD_PACK_RADIOIMAGES += dtb' "$board_config"
require_fixed 'TARGET_RELEASETOOLS_EXTENSIONS := $(M86_PATH)/releasetools' \
  "$board_config"
require_fixed 'INSTALLED_RADIOIMAGE_TARGET += $(M86_INSTALLED_DTB)' \
  "$android_makefile"
require_fixed 'DTB_TARGET_FILES_ENTRY = "RADIO/dtb.img"' "$releasetools"
require_fixed 'info.script.WriteRawImage("/dtb", DTB_OTA_ENTRY)' "$releasetools"
require_fixed 'BOARD_VENDOR := meizu' "$board_config"
require_fixed 'VENDOR_SECURITY_PATCH := 2019-08-01' "$board_config"
require_fixed 'BOARD_CHARGING_MODE_BOOTING_LPM := /sys/class/power_supply/battery/batt_lp_charging' \
  "$board_config"
require_fixed 'TARGET_SLSI_VARIANT := bsp' "$board_config"
require_fixed 'WIFI_DRIVER_FW_PATH_PARAM := /sys/module/bcmdhd/parameters/firmware_path' \
  "$board_config"
require_fixed 'sys.usb.ffs.aio_compat=1' "$system_prop"
require_fixed 'persist.sys.usb.config=mtp' "$device_makefile"
require_fixed 'mount functionfs adb /dev/usb-ffs/adb uid=2000,gid=2000' \
  "$usb_rc"
require_fixed 'write /sys/class/android_usb/android0/f_ffs/aliases adb' \
  "$usb_rc"
require_fixed 'write /sys/class/android_usb/android0/idProduct 2008' "$usb_rc"
require_fixed 'write /sys/class/android_usb/android0/idProduct 0C02' "$usb_rc"
require_fixed 'write /sys/class/android_usb/android0/idProduct 200B' "$usb_rc"
require_fixed 'write /sys/class/android_usb/android0/idProduct 200C' "$usb_rc"
require_fixed 'write /sys/class/android_usb/android0/idProduct 6863' "$usb_rc"
require_fixed 'write /sys/class/android_usb/android0/idProduct 6864' "$usb_rc"
require_fixed 'ifneq ($(filter samsung meizu,$(BOARD_VENDOR)),)' "$platform_patch"
require_fixed 'ifneq ($(TARGET_DEVICE_IS_M86),true)' "$platform_patch"
require_fixed 'CONFIG_CMDLINE="androidboot.hardware=m86 androidboot.selinux=permissive"' \
  "$kernel_config"
require_fixed 'CONFIG_CMDLINE_EXTEND=y' "$kernel_config"
require_fixed 'CONFIG_RD_GZIP=y' "$kernel_config"
require_fixed 'export BUILD_DATETIME=1786017600' "$build_worker"
require_fixed 'vendor_blob_count="$(wc -l < "$vendor_blob_lock"' \
  "$build_worker"
require_fixed 'sha256sum --quiet -c "$vendor_blob_lock"' "$build_worker"
require_fixed 'm86-proprietary-sha256s.txt' "$build_worker"
require_fixed 'set +u' "$device_root/extract-files.sh"
require_fixed '  "$clean_vendor" \' "$device_root/extract-files.sh"
require_fixed '  "$device"' "$device_root/extract-files.sh"
require_fixed 'set +u' "$device_root/setup-makefiles.sh"
require_fixed '  true \' "$device_root/setup-makefiles.sh"
require_fixed '  "$DEVICE"' "$device_root/setup-makefiles.sh"

for inherited_variable in \
  TARGET_UNOFFICIAL_BUILD_ID \
  TARGET_BUILD_DEBUGGABLE \
  TARGET_AUDIOHAL_VARIANT \
  BOARD_BLUETOOTH_BDROID_BUILDCFG_INCLUDE_DIR \
  BOARD_CUSTOM_BT_CONFIG \
  BOARD_HAVE_SAMSUNG_BLUETOOTH \
  BOARD_USE_SAMSUNG_CAMERAFORMAT_NV21 \
  TARGET_KEEP_LEGACY_CAMERA_PACKAGE \
  TARGET_SEC_FP_CALL_NOTIFY_ON_CANCEL \
  TARGET_SEC_FP_CALL_CANCEL_ON_ENROLL_COMPLETION \
  TARGET_SEC_FP_USES_PERCENTAGE_SAMPLES \
  TARGET_LD_SHIM_LIBS \
  TARGET_PROCESS_SDK_VERSION_OVERRIDE \
  JAVA_SOURCE_OVERLAYS \
  BOARD_NFC_HAL_SUFFIX \
  BOARD_PROVIDES_LIBRIL \
  ENABLE_VENDOR_RIL_SERVICE \
  SIM_COUNT \
  TARGET_EXFAT_DRIVER \
  TARGET_FS_CONFIG_GEN \
  BOARD_SEPOLICY_DIRS \
  BOARD_SEPOLICY_VERS \
  SELINUX_IGNORE_NEVERALLOWS \
  BOARD_SECCOMP_POLICY \
  TARGET_NO_SENSOR_PERMISSION_CHECK \
  BOARD_HAVE_SAMSUNG_WIFI; do
  require_empty_assignment "$inherited_variable" "$board_config"
done

if ! rg -q '^BOARD_KERNEL_CMDLINE :=[[:space:]]*$' "$board_config"; then
  printf 'The verified m86 v0 boot header must have an empty command line.\n' >&2
  exit 1
fi
if rg -q '^[[:space:]]*BOARD_INCLUDE_DTB_IN_BOOTIMG[[:space:]]*:=' \
    "$board_config"; then
  printf 'The m86 DTB must not be embedded in boot or recovery images.\n' >&2
  exit 1
fi

if rg -q 'inherit-product[^\n]*universal7420-common\.mk' "$device_makefile"; then
  printf 'The Galaxy universal7420 product must not be inherited by m86.\n' >&2
  exit 1
fi
if rg -q '^on property:sys\.usb\.config=(none|adb)([[:space:]]|$)' \
    "$usb_rc"; then
  printf 'm86 must not duplicate Android 10 generic none/adb USB handlers.\n' >&2
  exit 1
fi

active_fstab="$(rg -v '^[[:space:]]*(#|$)' "$recovery_fstab")"
if rg -q '/dev/block/sdb|by-name/(ldfw|param|proinfo|private|rstinfo|bootloader)([[:space:]]|$)' \
    <<<"$active_fstab"; then
  printf 'A forbidden bootloader, firmware, or identity target is active.\n' >&2
  exit 1
fi

for mount_point in /system /data /cache /boot /recovery /dtb /misc; do
  if ! rg -q "[[:space:]]${mount_point}[[:space:]]" <<<"$active_fstab"; then
    printf 'Required LineageOS recovery mount is absent: %s\n' \
      "$mount_point" >&2
    exit 1
  fi
done

python3 - "$releasetools" <<'PY'
import sys

with open(sys.argv[1], "rb") as source_file:
    compile(source_file.read(), sys.argv[1], "exec")
PY
printf 'LineageOS source validation passed: %s\n' "$device_root"
