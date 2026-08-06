#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
device_root="$project_root/device/meizu/m86"
board_config="$device_root/BoardConfig.mk"
android_makefile="$device_root/Android.mk"
device_makefile="$device_root/device.mk"
device_manifest="$device_root/manifest.xml"
system_prop="$device_root/system.prop"
bluetooth_buildcfg="$device_root/bluetooth/bdroid_buildcfg.h"
bluetooth_vendor_conf="$device_root/bluetooth/bt_vendor.conf"
audio_policy="$device_root/audio/audio_policy_configuration.xml"
audio_effects="$device_root/audio/audio_effects.xml"
audio_mixer="$device_root/audio/mixer_paths.xml"
wifi_sta_overlay="$device_root/wifi/wpa_supplicant_overlay.conf"
wifi_p2p_overlay="$device_root/wifi/p2p_supplicant_overlay.conf"
usb_rc="$device_root/rootdir/etc/init.m86.usb.rc"
init_rc="$device_root/rootdir/etc/init.m86.rc"
ueventd_rc="$device_root/rootdir/etc/ueventd.m86.rc"
recovery_fstab="$device_root/rootdir/etc/recovery.fstab"
releasetools="$device_root/releasetools/releasetools.py"
kernel_config="$project_root/kernel/meizu/m86/arch/arm64/configs/cm_pro5_defconfig"
platform_patch="$project_root/patches/device-samsung-universal7420-common/0001-target-add-meizu-m86.patch"
bluetooth_patch="$project_root/patches/device-samsung-universal7420-common/0002-bluetooth-add-m86-address-fallback.patch"
patch_series="$project_root/patches/series.tsv"
build_worker="$project_root/remote/worker-build.sh"
vendor_worker="$project_root/remote/prepare-vendor.sh"
blob_list="$device_root/proprietary-files.txt"

for required_file in \
  "$board_config" \
  "$android_makefile" \
  "$device_makefile" \
  "$device_manifest" \
  "$system_prop" \
  "$bluetooth_buildcfg" \
  "$bluetooth_vendor_conf" \
  "$audio_policy" \
  "$audio_effects" \
  "$audio_mixer" \
  "$wifi_sta_overlay" \
  "$wifi_p2p_overlay" \
  "$usb_rc" \
  "$init_rc" \
  "$ueventd_rc" \
  "$recovery_fstab" \
  "$releasetools" \
  "$kernel_config" \
  "$platform_patch" \
  "$bluetooth_patch" \
  "$patch_series" \
  "$build_worker" \
  "$vendor_worker" \
  "$blob_list"; do
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

require_manifest_hal() {
  local name="$1"
  local version="$2"
  local transport="$3"
  local arch="$4"
  local interface="$5"
  local transport_predicate="transport[text()='$transport']"

  if [[ -n "$arch" ]]; then
    transport_predicate="transport[text()='$transport' and @arch='$arch']"
  fi

  local xpath="count(/manifest/hal[name='$name' and version='$version' and $transport_predicate and interface/name='$interface' and interface/instance='default'])"
  if [[ "$(xmllint --xpath "$xpath" "$device_manifest")" != "1" ]]; then
    printf 'Missing or invalid m86 VINTF HAL: %s@%s::%s/default\n' \
      "$name" "$version" "$interface" >&2
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
require_fixed 'M86_VULKAN_HAL32 := $(TARGET_OUT_VENDOR)/lib/hw/vulkan.exynos5.so' \
  "$android_makefile"
require_fixed 'M86_VULKAN_HAL64 := $(TARGET_OUT_VENDOR)/lib64/hw/vulkan.exynos5.so' \
  "$android_makefile"
require_fixed 'ALL_DEFAULT_INSTALLED_MODULES += $(M86_VULKAN_HAL_SYMLINKS)' \
  "$android_makefile"
require_fixed 'ln -sf ../egl/libGLES_mali.so $@' "$android_makefile"
require_fixed 'DTB_TARGET_FILES_ENTRY = "RADIO/dtb.img"' "$releasetools"
require_fixed 'info.script.WriteRawImage("/dtb", DTB_OTA_ENTRY)' "$releasetools"
require_fixed 'BOARD_VENDOR := meizu' "$board_config"
require_fixed 'VENDOR_SECURITY_PATCH := 2019-08-01' "$board_config"
require_fixed 'BOARD_CHARGING_MODE_BOOTING_LPM := /sys/class/power_supply/battery/batt_lp_charging' \
  "$board_config"
require_fixed 'TARGET_SLSI_VARIANT := bsp' "$board_config"
require_fixed 'AUDIOSERVER_MULTILIB := 32' "$board_config"
require_fixed 'WIFI_DRIVER_FW_PATH_PARAM := /sys/module/bcmdhd/parameters/firmware_path' \
  "$board_config"
require_fixed 'BOARD_BLUETOOTH_BDROID_BUILDCFG_INCLUDE_DIR := $(M86_PATH)/bluetooth' \
  "$board_config"
require_fixed 'BOARD_HAVE_BLUETOOTH := true' "$board_config"
require_fixed 'sys.usb.ffs.aio_compat=1' "$system_prop"
require_fixed 'persist.sys.usb.config=mtp' "$device_makefile"
require_fixed 'android.hardware.bluetooth_le.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.bluetooth_le.xml' \
  "$device_makefile"
require_fixed 'android.hardware.wifi.direct.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.direct.xml' \
  "$device_makefile"
require_fixed 'android.hardware.wifi.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.xml' \
  "$device_makefile"
require_fixed 'android.hardware.bluetooth@1.0-impl.zero' "$device_makefile"
require_fixed 'android.hardware.bluetooth@1.0-service' "$device_makefile"
require_fixed '$(LOCAL_PATH)/bluetooth/bt_vendor.conf:$(TARGET_COPY_OUT_SYSTEM)/etc/bluetooth/bt_vendor.conf' \
  "$device_makefile"
require_fixed 'android.hardware.graphics.allocator@2.0-service' "$device_makefile"
require_fixed 'android.hardware.graphics.composer@2.1-impl' "$device_makefile"
require_fixed 'android.hardware.graphics.mapper@2.0-impl' "$device_makefile"
require_fixed 'android.hardware.memtrack@1.0-impl' "$device_makefile"
require_fixed 'libhwc2on1adapter' "$device_makefile"
require_fixed 'android.hardware.audio@5.0-impl' "$device_makefile"
require_fixed 'android.hardware.audio.effect@5.0-impl' "$device_makefile"
require_fixed 'audio.r_submix.default' "$device_makefile"
require_fixed 'audio.usb.default' "$device_makefile"
require_fixed '$(LOCAL_PATH)/audio/audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_policy_configuration.xml' \
  "$device_makefile"
require_fixed '$(LOCAL_PATH)/audio/mixer_paths.xml:$(TARGET_COPY_OUT_SYSTEM)/etc/mixer_paths.xml' \
  "$device_makefile"
require_fixed 'android.hardware.wifi@1.0-service.legacy' "$device_makefile"
require_fixed '$(LOCAL_PATH)/wifi/p2p_supplicant_overlay.conf:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/p2p_supplicant_overlay.conf' \
  "$device_makefile"
require_fixed '$(LOCAL_PATH)/wifi/wpa_supplicant_overlay.conf:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/wpa_supplicant_overlay.conf' \
  "$device_makefile"
for wifi_package in hostapd wpa_supplicant wpa_supplicant.conf; do
  if ! rg -q "^[[:space:]]*${wifi_package}( \\\\)?$" "$device_makefile"; then
    printf 'Required m86 Wi-Fi package is absent: %s\n' "$wifi_package" >&2
    exit 1
  fi
done
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
require_fixed '/dev/mali0                   0666   system      system' \
  "$ueventd_rc"
require_fixed '/dev/ion                     0666   system      system' \
  "$ueventd_rc"
require_fixed '/dev/video23                 0660   media       graphics' \
  "$ueventd_rc"
require_fixed '/dev/i2c-7                   0660   system      audio' \
  "$ueventd_rc"
require_fixed '/dev/adnc2                   0660   system      audio' \
  "$ueventd_rc"
require_fixed '/dev/video16                 0660   system      audio' \
  "$ueventd_rc"
require_fixed 'chown bluetooth bluetooth /sys/class/rfkill/rfkill0/state' \
  "$device_root/rootdir/etc/init.m86.rc"
require_fixed 'chmod 0660 /sys/class/rfkill/rfkill0/state' \
  "$init_rc"
require_fixed 'mkdir /data/vendor/wifi/wpa/sockets 0770 wifi wifi' "$init_rc"
require_fixed 'chown wifi wifi /sys/module/bcmdhd/parameters/firmware_path' \
  "$init_rc"
require_fixed 'service wpa_supplicant /vendor/bin/hw/wpa_supplicant \' \
  "$init_rc"
require_fixed 'interface android.hardware.wifi.supplicant@1.2::ISupplicant default' \
  "$init_rc"
require_fixed 'p2p_disabled=1' "$wifi_sta_overlay"
require_fixed 'disable_scan_offload=1' "$wifi_sta_overlay"
require_fixed 'manufacturer=SAMSUNG_ELECTRONICS' "$wifi_p2p_overlay"
require_fixed 'model_name=SYSTEM_LSI' "$wifi_p2p_overlay"
require_fixed 'ifneq ($(filter samsung meizu,$(BOARD_VENDOR)),)' "$platform_patch"
require_fixed 'ifneq ($(TARGET_DEVICE_IS_M86),true)' "$platform_patch"
require_fixed 'derive_m86_address_from_serial' "$bluetooth_patch"
require_fixed 'strcmp(hardware, "m86") != 0' "$bluetooth_patch"
require_fixed 'local_addr[0] = 0x02;' "$bluetooth_patch"
require_fixed 'patches/device-samsung-universal7420-common/0002-bluetooth-add-m86-address-fallback.patch' \
  "$patch_series"
require_fixed '#define BTM_DEF_LOCAL_NAME "Meizu PRO 5"' "$bluetooth_buildcfg"
require_fixed 'UartPort = /dev/ttySAC4' "$bluetooth_vendor_conf"
require_fixed 'FwPatchFilePath = /vendor/firmware/' "$bluetooth_vendor_conf"
require_fixed 'CONFIG_CMDLINE="androidboot.hardware=m86 androidboot.selinux=permissive"' \
  "$kernel_config"
require_fixed 'CONFIG_CMDLINE_EXTEND=y' "$kernel_config"
require_fixed 'CONFIG_RD_GZIP=y' "$kernel_config"
require_fixed 'CONFIG_BCMDHD=y' "$kernel_config"
require_fixed 'CONFIG_BCMDHD_PCIE=y' "$kernel_config"
require_fixed 'CONFIG_BCMDHD_FW_PATH="/system/vendor/firmware/fw_bcmdhd.bin"' \
  "$kernel_config"
require_fixed 'CONFIG_BCMDHD_NVRAM_PATH="/system/etc/wifi/bcmdhd.cal"' \
  "$kernel_config"
require_fixed 'export BUILD_DATETIME=1786017600' "$build_worker"
require_fixed 'vendor_blob_count="$(wc -l < "$vendor_blob_lock"' \
  "$build_worker"
require_fixed 'sha256sum --quiet -c "$vendor_blob_lock"' "$build_worker"
require_fixed 'm86-proprietary-sha256s.txt' "$build_worker"
require_fixed 'vendor/lib/libbt-vendor.so' "$blob_list"
require_fixed 'vendor/lib/egl/libGLES_mali.so' "$blob_list"
require_fixed 'vendor/lib64/egl/libGLES_mali.so' "$blob_list"
require_fixed 'etc/wifi/bcmdhd.cal' "$blob_list"
require_fixed 'vendor/firmware/fw_bcmdhd.bin' "$blob_list"
require_fixed 'vendor/firmware/fw_bcmdhd_apsta.bin' "$blob_list"
require_fixed 'lib/hw/audio.primary.m86.so' "$blob_list"
require_fixed 'lib64/hw/audio.primary.m86.so' "$blob_list"
require_fixed 'lib/libtfa9890.so' "$blob_list"
require_fixed 'lib/libsitril-audio.so' "$blob_list"
require_fixed 'copy_rule_count="$(' "$vendor_worker"
require_fixed 'expected_rule="vendor/meizu/m86/proprietary/$relative_path:$output_path"' \
  "$vendor_worker"
require_fixed '\$(TARGET_COPY_OUT_VENDOR)/vendor/' "$vendor_worker"
require_fixed 'manifest_tmp="${manifest_lock}.tmp"' \
  "$project_root/remote/worker-sync-source.sh"
require_fixed 'mv "$manifest_tmp" "$manifest_lock"' \
  "$project_root/remote/worker-sync-source.sh"
require_fixed '[[ ! -s "$log_dir/lineage-17.1-manifest.xml" ]]' \
  "$project_root/remote/worker-sync-platform.sh"
require_fixed 'mv "$manifest_tmp" "$manifest_lock"' \
  "$project_root/remote/worker-sync-platform.sh"
require_fixed 'set +u' "$device_root/extract-files.sh"
require_fixed '  "$clean_vendor" \' "$device_root/extract-files.sh"
require_fixed '  "$device"' "$device_root/extract-files.sh"
require_fixed 'set +u' "$device_root/setup-makefiles.sh"
require_fixed '  true \' "$device_root/setup-makefiles.sh"
require_fixed '  "$DEVICE"' "$device_root/setup-makefiles.sh"

if ! command -v xmllint >/dev/null 2>&1; then
  printf 'xmllint is required for m86 VINTF validation.\n' >&2
  exit 1
fi
xmllint --noout "$device_manifest"
xmllint --noout "$audio_policy"
xmllint --noout "$audio_effects"

# A local source-only checkout does not contain the Android schemas. On the
# builder, expand the standard XIncludes against the pinned LineageOS source
# and validate the complete Android 10 policy rather than only well-formedness.
lineage_source_root="${PRO5_LINEAGE_SOURCE_ROOT:-$(cd "$project_root/.." && pwd)/src/lineage-17.1}"
audio_policy_schema="$lineage_source_root/hardware/interfaces/audio/5.0/config/audio_policy_configuration.xsd"
audio_effects_schema="$lineage_source_root/hardware/interfaces/audio/effect/2.0/xml/audio_effects_conf.xsd"
audio_config_root="$lineage_source_root/frameworks/av/services/audiopolicy/config"
if [[ -s "$audio_policy_schema" ]] && [[ -s "$audio_effects_schema" ]]; then
  sed \
    -e "s#/vendor/etc/a2dp_audio_policy_configuration.xml#$audio_config_root/a2dp_audio_policy_configuration.xml#" \
    -e "s#/vendor/etc/usb_audio_policy_configuration.xml#$audio_config_root/usb_audio_policy_configuration.xml#" \
    -e "s#/vendor/etc/r_submix_audio_policy_configuration.xml#$audio_config_root/r_submix_audio_policy_configuration.xml#" \
    -e "s#/vendor/etc/audio_policy_volumes.xml#$audio_config_root/audio_policy_volumes.xml#" \
    -e "s#/vendor/etc/default_volume_tables.xml#$audio_config_root/default_volume_tables.xml#" \
    "$audio_policy" | \
    xmllint --xinclude --noxincludenode --format - | \
    sed -E 's/ xml:base="[^"]*"//g' | \
    xmllint --noout --schema "$audio_policy_schema" -
  xmllint --noout --schema "$audio_effects_schema" "$audio_effects"
fi

require_manifest_hal \
  android.hardware.audio 5.0 passthrough 32 IDevicesFactory
require_manifest_hal \
  android.hardware.audio.effect 5.0 passthrough 32 IEffectsFactory
require_manifest_hal \
  android.hardware.bluetooth 1.0 hwbinder '' IBluetoothHci
require_manifest_hal \
  android.hardware.configstore 1.1 hwbinder '' ISurfaceFlingerConfigs
require_manifest_hal \
  android.hardware.graphics.allocator 2.0 hwbinder '' IAllocator
require_manifest_hal \
  android.hardware.graphics.composer 2.1 passthrough 32+64 IComposer
require_manifest_hal \
  android.hardware.graphics.mapper 2.0 passthrough 32+64 IMapper
require_manifest_hal \
  android.hardware.memtrack 1.0 passthrough 32+64 IMemtrack
require_manifest_hal \
  android.hardware.wifi 1.3 hwbinder '' IWifi
require_manifest_hal \
  android.hardware.wifi.hostapd 1.1 hwbinder '' IHostapd
require_manifest_hal \
  android.hardware.wifi.supplicant 1.2 hwbinder '' ISupplicant

for inherited_variable in \
  TARGET_UNOFFICIAL_BUILD_ID \
  TARGET_BUILD_DEBUGGABLE \
  TARGET_AUDIOHAL_VARIANT \
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
require_empty_assignment BOARD_HAVE_BLUETOOTH_BCM "$board_config"

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
if rg -q '^[[:space:]]*(wifiloader|macloader)([[:space:]]*\\)?$' \
    "$device_makefile"; then
  printf 'm86 must not package Samsung /efs Wi-Fi loader utilities.\n' >&2
  exit 1
fi
if rg -q '(^|/)egl\.cfg([:;|]|$)' "$blob_list"; then
  printf 'Android 10 loads m86 Mali directly; the obsolete egl.cfg must not be packaged.\n' >&2
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
