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
gps_conf="$device_root/gps/gps.conf"
gps_xml="$device_root/gps/gps.xml"
gps_bp="$device_root/gps/Android.bp"
gps_shim="$device_root/gps/GpsCompat.cpp"
nfc_config="$device_root/nfc/libnfc-nxp.conf"
sensors_service_rc="$device_root/sensors/android.hardware.sensors@1.0-service.rc"
camera_bp="$device_root/camera/Android.bp"
camera_shim="$device_root/camera/CameraCompat.cpp"
lights_bp="$device_root/lights/Android.bp"
lights_source="$device_root/lights/lights.c"
power_bp="$device_root/power/Android.bp"
power_source="$device_root/power/PowerHAL.c"
fingerprint_makefile="$device_root/fingerprint/Android.mk"
fingerprint_source="$device_root/fingerprint/FingerprintHAL.c"
wifi_sta_overlay="$device_root/wifi/wpa_supplicant_overlay.conf"
wifi_p2p_overlay="$device_root/wifi/p2p_supplicant_overlay.conf"
usb_rc="$device_root/rootdir/etc/init.m86.usb.rc"
init_rc="$device_root/rootdir/etc/init.m86.rc"
sensors_init_rc="$device_root/rootdir/etc/init.m86.sensors.rc"
ueventd_rc="$device_root/rootdir/etc/ueventd.m86.rc"
recovery_fstab="$device_root/rootdir/etc/recovery.fstab"
releasetools="$device_root/releasetools/releasetools.py"
device_file_contexts="$device_root/sepolicy/file_contexts"
kernel_config="$project_root/kernel/meizu/m86/arch/arm64/configs/cm_pro5_defconfig"
kernel_fs_kconfig="$project_root/kernel/meizu/m86/fs/Kconfig"
kernel_fs_makefile="$project_root/kernel/meizu/m86/fs/Makefile"
kernel_exfat_provenance="$project_root/kernel/meizu/m86/fs/exfat/PROVENANCE.md"
kernel_exfat_lock="$project_root/locks/kernel-exfat-exynos7420.sha256"
kernel_fcntl="$project_root/kernel/meizu/m86/include/uapi/asm-generic/fcntl.h"
kernel_uapi_kbuild="$project_root/kernel/meizu/m86/include/uapi/linux/Kbuild"
kernel_mfc_uapi="$project_root/kernel/meizu/m86/include/uapi/linux/videodev2_exynos_media.h"
kernel_decon_header="$project_root/kernel/meizu/m86/drivers/video/exynos/decon/decon.h"
platform_patch="$project_root/patches/device-samsung-universal7420-common/0001-target-add-meizu-m86.patch"
bluetooth_patch="$project_root/patches/device-samsung-universal7420-common/0002-bluetooth-add-m86-address-fallback.patch"
full_ota_patch="$project_root/patches/build-make/0001-releasetools-allow-full-ota-without-cache-size.patch"
glib_patch="$project_root/patches/external-glib/0001-build-libglib-for-m86-vendor.patch"
glib_stub_patch="$project_root/patches/external-glib/0003-clang-port-legacy-android-stubs.patch"
audio_metadata_patch="$project_root/patches/hardware-interfaces/0001-audio-ignore-invalid-legacy-metadata-callback.patch"
audio_headphone_framework_patch="$project_root/patches/frameworks-av/0001-audioflinger-restore-meizu-headphone-volume.patch"
audio_hifi_output_patch="$project_root/patches/frameworks-av/0002-audioflinger-route-meizu-hifi-state-to-output.patch"
audio_hifi_service_patch="$project_root/patches/frameworks-base/0003-audio-restore-meizu-hifi-routing.patch"
settings_hifi_patch="$project_root/patches/packages-apps-settings/0001-system-add-meizu-hifi-sound.patch"
audio_headphone_hal_patch="$project_root/patches/hardware-interfaces/0004-audio-call-meizu-headphone-volume-hook.patch"
libfprint_patch="$project_root/patches/legacy-m86-libfprint/0001-port-m86-fpc-to-android10.patch"
patch_series="$project_root/patches/series.tsv"
platform_manifest="$project_root/manifests/pro5.xml"
build_worker="$project_root/remote/worker-build.sh"
kernel_build_worker="$project_root/remote/worker-build-kernel.sh"
start_build="$project_root/remote/start-build.sh"
fetch_artifacts="$project_root/remote/fetch-lineage-artifacts.sh"
install_worker="$project_root/remote/install-local-trees.sh"
push_worker="$project_root/remote/push-local.sh"
platform_sync_worker="$project_root/remote/worker-sync-platform.sh"
vendor_worker="$project_root/remote/prepare-vendor.sh"
camera_audit_tool="$project_root/tools/audit-camera-abi.sh"
fingerprint_audit_tool="$project_root/tools/audit-fingerprint-output.sh"
ota_audit_tool="$project_root/tools/audit-lineage-ota.sh"
blob_list="$device_root/proprietary-files.txt"
vendor_definition_root="$project_root/vendor/meizu/m86"
vendor_android_makefile="$vendor_definition_root/Android.mk"
vendor_board_config="$vendor_definition_root/BoardConfigVendor.mk"
vendor_product_makefile="$vendor_definition_root/m86-vendor.mk"
legacy_fprint="$project_root/legacy/device-meizu-m86-cm14/libfprint/fpc1150.c"
legacy_upstream="$project_root/legacy/device-meizu-m86-cm14/UPSTREAM.md"

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
  "$gps_conf" \
  "$gps_xml" \
  "$gps_bp" \
  "$gps_shim" \
  "$nfc_config" \
  "$sensors_service_rc" \
  "$camera_bp" \
  "$camera_shim" \
  "$lights_bp" \
  "$lights_source" \
  "$power_bp" \
  "$power_source" \
  "$fingerprint_makefile" \
  "$fingerprint_source" \
  "$wifi_sta_overlay" \
  "$wifi_p2p_overlay" \
  "$usb_rc" \
  "$init_rc" \
  "$sensors_init_rc" \
  "$ueventd_rc" \
  "$recovery_fstab" \
  "$releasetools" \
  "$device_file_contexts" \
  "$kernel_config" \
  "$kernel_fs_kconfig" \
  "$kernel_fs_makefile" \
  "$kernel_exfat_provenance" \
  "$kernel_exfat_lock" \
  "$kernel_fcntl" \
  "$kernel_uapi_kbuild" \
  "$kernel_mfc_uapi" \
  "$kernel_decon_header" \
  "$platform_patch" \
  "$bluetooth_patch" \
  "$full_ota_patch" \
  "$glib_patch" \
  "$glib_stub_patch" \
  "$audio_metadata_patch" \
  "$audio_headphone_framework_patch" \
  "$audio_hifi_output_patch" \
  "$audio_hifi_service_patch" \
  "$settings_hifi_patch" \
  "$audio_headphone_hal_patch" \
  "$libfprint_patch" \
  "$patch_series" \
  "$platform_manifest" \
  "$build_worker" \
  "$kernel_build_worker" \
  "$start_build" \
  "$fetch_artifacts" \
  "$install_worker" \
  "$push_worker" \
  "$platform_sync_worker" \
  "$vendor_worker" \
  "$camera_audit_tool" \
  "$fingerprint_audit_tool" \
  "$ota_audit_tool" \
  "$blob_list" \
  "$vendor_android_makefile" \
  "$vendor_board_config" \
  "$vendor_product_makefile" \
  "$legacy_fprint" \
  "$legacy_upstream"; do
  if [[ ! -s "$required_file" ]]; then
    printf 'Missing required LineageOS source: %s\n' "$required_file" >&2
    exit 1
  fi
done

if ! (
  cd "$project_root/kernel/meizu/m86"
  sha256sum --quiet -c "$kernel_exfat_lock"
); then
  printf 'The locked Exynos 7420 exFAT source import changed.\n' >&2
  exit 1
fi
if [[ "$(find "$project_root/kernel/meizu/m86/fs/exfat" -maxdepth 1 \
    -type f ! -name PROVENANCE.md | wc -l | tr -d ' ')" != "25" ]]; then
  printf 'Expected exactly 25 locked exFAT donor files.\n' >&2
  exit 1
fi

require_fixed() {
  local pattern="$1"
  local source_file="$2"

  if ! rg -F -q -- "$pattern" "$source_file"; then
    printf 'Required LineageOS setting is absent from %s: %s\n' \
      "$source_file" "$pattern" >&2
    exit 1
  fi
}

require_absent() {
  local pattern="$1"
  local source_file="$2"

  if rg -F -q -- "$pattern" "$source_file"; then
    printf 'Unsupported LineageOS setting is present in %s: %s\n' \
      "$source_file" "$pattern" >&2
    exit 1
  fi
}

require_fixed 'jobs="${PRO5_BUILD_JOBS:-8}"' "$start_build"
require_fixed 'jobs="${2:-8}"' "$build_worker"
require_fixed 'artifacts/lineage-latest' "$fetch_artifacts"
require_fixed 'sha256sum --quiet -c SHA256SUMS' "$fetch_artifacts"
require_fixed "'target=lineage_m86-userdebug bacon'" "$fetch_artifacts"
require_fixed 'ota_packages=(lineage-17.1-*.zip)' "$fetch_artifacts"
require_fixed 'target_files_packages=(*-target_files-*.zip)' \
  "$fetch_artifacts"
require_fixed 'partial_artifact_dir="${local_artifact_dir}.partial"' \
  "$fetch_artifacts"
require_fixed 'jobs="${PRO5_KERNEL_BUILD_JOBS:-8}"' \
  "$project_root/remote/start-kernel-build.sh"
require_fixed 'local_commit="${local_commit}-dirty"' \
  "$project_root/remote/start-kernel-build.sh"
require_fixed 'jobs="${1:-8}"' "$kernel_build_worker"
require_fixed 'audit-camera-abi.sh' "$build_worker"
require_fixed 'audit-fingerprint-output.sh' "$build_worker"
require_fixed 'fingerprint output audit passed.' "$fingerprint_audit_tool"
require_fixed 'CONFIG_EXFAT_FS=y' "$kernel_config"
require_fixed 'CONFIG_EXFAT_VIRTUAL_XATTR=y' "$kernel_config"
require_fixed 'CONFIG_EXFAT_VIRTUAL_XATTR_SELINUX_LABEL="u:object_r:sdcard_external:s0"' \
  "$kernel_config"
for stale_fs_option in \
  CONFIG_FAT_VIRTUAL_XATTR \
  CONFIG_FAT_VIRTUAL_XATTR_SELINUX_LABEL \
  CONFIG_FAT_SUPPORT_STLOG \
  CONFIG_EXFAT_SUPPORT_STLOG; do
  require_absent "$stale_fs_option" "$kernel_config"
done
require_fixed 'source "fs/exfat/Kconfig"' "$kernel_fs_kconfig"
require_fixed 'obj-$(CONFIG_EXFAT_FS)' "$kernel_fs_makefile"
require_fixed 'fs/exfat/exfat_core.o' "$build_worker"
require_fixed 'fs/exfat/exfat_fs.o' "$build_worker"
require_fixed 'CONFIG_EXFAT_VIRTUAL_XATTR=y' "$build_worker"
require_fixed 'CONFIG_EXFAT_VIRTUAL_XATTR_SELINUX_LABEL=' "$build_worker"
require_fixed 'fs/exfat/exfat_core.o' "$kernel_build_worker"
require_fixed 'fs/exfat/exfat_fs.o' "$kernel_build_worker"
require_fixed 'CONFIG_EXFAT_VIRTUAL_XATTR=y' "$kernel_build_worker"
require_fixed 'CONFIG_EXFAT_VIRTUAL_XATTR_SELINUX_LABEL=' \
  "$kernel_build_worker"
require_fixed 'kernel-exfat-exynos7420.sha256' "$kernel_build_worker"

require_empty_assignment() {
  local variable_name="$1"
  local source_file="$2"

  if ! rg -q "^${variable_name}[[:space:]]*:=[[:space:]]*$" "$source_file"; then
    printf 'Required empty LineageOS override is absent from %s: %s\n' \
      "$source_file" "$variable_name" >&2
    exit 1
  fi
}

require_sha256() {
  local expected="$1"
  local source_file="$2"
  local actual

  actual="$(python3 - "$source_file" <<'PY'
import hashlib
import sys

with open(sys.argv[1], "rb") as source:
    print(hashlib.sha256(source.read()).hexdigest())
PY
)"
  if [[ "$actual" != "$expected" ]]; then
    printf 'SHA-256 mismatch for %s: expected %s, got %s\n' \
      "$source_file" "$expected" "$actual" >&2
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

require_manifest_instance() {
  local name="$1"
  local version="$2"
  local interface="$3"
  local instance="$4"
  local xpath="count(/manifest/hal[name='$name' and version='$version' and transport='hwbinder' and interface/name='$interface' and interface/instance='$instance'])"

  if [[ "$(xmllint --xpath "$xpath" "$device_manifest")" != "1" ]]; then
    printf 'Missing or invalid m86 VINTF HAL: %s@%s::%s/%s\n' \
      "$name" "$version" "$interface" "$instance" >&2
    exit 1
  fi
}

require_fixed 'BOARD_KERNEL_BASE := 0x40000000' "$board_config"
require_fixed '#define __O_TMPFILE' "$kernel_fcntl"
require_fixed '#define O_TMPFILE (' "$kernel_fcntl"
require_fixed '#define O_TMPFILE_MASK (' "$kernel_fcntl"
require_fixed 'header-y += m2m1shot.h' "$kernel_uapi_kbuild"
require_fixed 'V4L2_CID_MPEG_MFC_GET_DRIVER_INFO' "$kernel_mfc_uapi"
require_fixed 'V4L2_CID_MPEG_MFC_CONFIG_QP_ENABLE' "$kernel_mfc_uapi"
require_fixed 'struct decon_win_rect		transparent_area;' \
  "$kernel_decon_header"
require_fixed 'struct decon_win_rect		opaque_area;' \
  "$kernel_decon_header"
require_fixed 'BOARD_KERNEL_PAGESIZE := 4096' "$board_config"
require_fixed '--kernel_offset 0x00080000' "$board_config"
require_fixed '--ramdisk_offset 0x02000000' "$board_config"
require_fixed '--second_offset 0x00f00000' "$board_config"
require_fixed '--tags_offset 0x00000100' "$board_config"
require_fixed 'BOARD_PACK_RADIOIMAGES += dtb' "$board_config"
require_fixed 'BOARD_ROOT_EXTRA_FOLDERS += custom mnv' "$board_config"
require_fixed 'BOARD_SEPOLICY_DIRS := device/meizu/m86/sepolicy' \
  "$board_config"
require_fixed '/custom    u:object_r:rootfs:s0' "$device_file_contexts"
require_fixed '/mnv       u:object_r:rootfs:s0' "$device_file_contexts"
require_fixed 'mkdir /custom 0555 root root' "$init_rc"
require_fixed 'mkdir /mnv 0555 root root' "$init_rc"
require_fixed '/by-name/custom    /custom' \
  "$device_root/rootdir/etc/fstab.m86"
require_fixed '/by-name/mnv       /mnv' \
  "$device_root/rootdir/etc/fstab.m86"
require_fixed '/by-name/cache     /cache' \
  "$device_root/rootdir/etc/fstab.m86"
require_fixed 'encryptable=/cache/metadata' \
  "$device_root/rootdir/etc/fstab.m86"
require_absent '/mnt/vendor/cache' \
  "$device_root/rootdir/etc/fstab.m86"
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
require_fixed 'Installing the Flyme-based AP fingerprint DTB' "$releasetools"
require_fixed 'BOARD_VENDOR := meizu' "$board_config"
require_fixed 'VENDOR_SECURITY_PATCH := 2019-08-01' "$board_config"
require_fixed 'BOARD_BATTERY_DEVICE_NAME := bq2753x-0' \
  "$board_config"
require_fixed 'TARGET_SLSI_VARIANT := bsp' "$board_config"
require_fixed 'AUDIOSERVER_MULTILIB := 32' "$board_config"
require_fixed 'TARGET_PROCESS_SDK_VERSION_OVERRIDE := /system/bin/gpsd=27' \
  "$board_config"
require_fixed 'WIFI_DRIVER_FW_PATH_PARAM := /sys/module/bcmdhd/parameters/firmware_path' \
  "$board_config"
require_fixed 'BOARD_BLUETOOTH_BDROID_BUILDCFG_INCLUDE_DIR := $(M86_PATH)/bluetooth' \
  "$board_config"
require_fixed 'BOARD_HAVE_BLUETOOTH := true' "$board_config"
require_fixed 'BOARD_CACHEIMAGE_PARTITION_SIZE := 536870912' "$board_config"
require_fixed 'BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE := ext4' "$board_config"
require_absent 'BOARD_CACHEIMAGE_PARTITION_SIZE := 209715200' "$board_config"
require_absent 'PRODUCT_BUILD_CACHE_IMAGE := false' \
  "$device_root/lineage_m86.mk"
require_fixed '/system/lib/libexynoscamera.so|/system/lib/libm86camera_shim.so' \
  "$board_config"
require_fixed '/system/bin/gpsd|/system/lib64/libm86gps_shim.so' "$board_config"
require_fixed 'libncurses5 \' "$project_root/remote/bootstrap-builder.sh"
require_fixed 'libtinfo5 \' "$project_root/remote/bootstrap-builder.sh"
require_fixed 'RenderScript Clang is missing host libraries:' "$build_worker"
require_fixed 'Removed stale generated /cache symlink before incremental build.' \
  "$build_worker"
require_fixed 'ion_is_legacy" { found=1 }' "$build_worker"
require_fixed 'source_built_libion_count=2' "$build_worker"
require_fixed 'm86 camera ABI closure passed.' "$camera_audit_tool"
require_fixed 'sys.usb.ffs.aio_compat=1' "$system_prop"
require_fixed 'TARGET_SYSTEM_PROP := device/meizu/m86/system.prop' \
  "$device_makefile"
require_fixed 'ro.adb.nonblocking_ffs=false' "$device_makefile"
require_fixed 'persist.sys.usb.config=none' "$device_makefile"
require_absent 'persist.sys.usb.config=adb' "$device_makefile"
require_absent 'ro.adb.secure=0' "$device_makefile"
require_absent 'WITH_ADB_INSECURE := true' "$device_root/lineage_m86.mk"
require_fixed 'android.hardware.bluetooth_le.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.bluetooth_le.xml' \
  "$device_makefile"
require_fixed 'android.hardware.fingerprint.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.fingerprint.xml' \
  "$device_makefile"
for camera_feature in camera camera.flash-autofocus camera.front; do
  require_fixed "android.hardware.${camera_feature}.xml:\$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.${camera_feature}.xml" \
    "$device_makefile"
done
require_fixed 'android.hardware.wifi.direct.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.direct.xml' \
  "$device_makefile"
require_fixed 'android.hardware.wifi.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.xml' \
  "$device_makefile"
require_fixed 'android.hardware.telephony.gsm.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.telephony.gsm.xml' \
  "$device_makefile"
for sensor_feature in accelerometer compass gyroscope light proximity stepcounter stepdetector; do
  require_fixed "android.hardware.sensor.${sensor_feature}.xml:\$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.${sensor_feature}.xml" \
    "$device_makefile"
done
require_fixed 'android.hardware.location.gps.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.location.gps.xml' \
  "$device_makefile"
require_fixed 'android.hardware.nfc.hce.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.nfc.hce.xml' \
  "$device_makefile"
require_fixed 'android.hardware.nfc.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.nfc.xml' \
  "$device_makefile"
require_fixed 'com.android.nfc_extras.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/com.android.nfc_extras.xml' \
  "$device_makefile"
require_fixed 'android.hardware.bluetooth@1.0-impl.zero' "$device_makefile"
require_fixed 'android.hardware.bluetooth@1.0-service' "$device_makefile"
require_fixed '$(LOCAL_PATH)/bluetooth/bt_vendor.conf:$(TARGET_COPY_OUT_SYSTEM)/etc/bluetooth/bt_vendor.conf' \
  "$device_makefile"
require_fixed 'android.hardware.graphics.allocator@2.0-service' "$device_makefile"
require_fixed 'android.hardware.graphics.composer@2.1-impl' "$device_makefile"
require_fixed 'android.hardware.graphics.mapper@2.0-impl' "$device_makefile"
require_fixed 'android.hardware.memtrack@1.0-impl' "$device_makefile"
require_fixed 'libcec' "$device_makefile"
require_fixed 'hwcomposer.exynos5' "$device_makefile"
require_fixed 'libexynosdisplay' "$device_makefile"
require_fixed 'libhdmi' "$device_makefile"
require_fixed 'libhwc2on1adapter' "$device_makefile"
require_fixed 'on property:sys.usb.config=adb && property:sys.usb.configfs=0' \
  "$device_root/rootdir/etc/init.m86.usb.rc"
require_fixed 'android.hardware.audio@5.0-impl' "$device_makefile"
require_fixed 'android.hardware.audio.effect@5.0-impl' "$device_makefile"
require_fixed 'audio.r_submix.default' "$device_makefile"
require_fixed 'audio.usb.default' "$device_makefile"
require_fixed 'android.hardware.keymaster@4.0-service' "$device_makefile"
require_fixed 'configs/seccomp/mediacodec.policy:$(TARGET_COPY_OUT_VENDOR)/etc/seccomp_policy/mediacodec.policy' \
  "$device_makefile"
require_fixed '$(LOCAL_PATH)/audio/audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_policy_configuration.xml' \
  "$device_makefile"
require_fixed '$(LOCAL_PATH)/audio/mixer_paths.xml:$(TARGET_COPY_OUT_SYSTEM)/etc/mixer_paths.xml' \
  "$device_makefile"
require_fixed 'android.hardware.camera.provider@2.4-impl' "$device_makefile"
require_fixed 'android.hardware.camera.provider@2.4-service' "$device_makefile"
require_fixed 'libm86camera_shim' "$device_makefile"
require_fixed 'name: "libm86camera_shim"' "$camera_bp"
require_fixed 'compile_multilib: "32"' "$camera_bp"
require_fixed '"libsensor"' "$camera_bp"
require_fixed '"-Wl,--no-as-needed"' "$camera_bp"
require_fixed 'extern "C" pid_t androidGetTid()' "$camera_shim"
require_fixed 'extern "C" void set_value()' "$camera_shim"
require_fixed '_ZN7android5FenceD1Ev' "$camera_shim"
require_fixed '_ZNK7android10GLConsumer16getCurrentBufferEv' "$camera_shim"
require_fixed '_ZN7android13GraphicBuffer4lockEjPPv' "$camera_shim"
require_fixed 'EFFECT_POINT_BLUE[] = "point-blue"' "$camera_shim"
require_fixed 'PIXEL_FORMAT_YUV420SP_NV21[] = "nv21"' "$camera_shim"
require_fixed 'android.hardware.wifi@1.0-service.legacy' "$device_makefile"
require_fixed '$(LOCAL_PATH)/wifi/p2p_supplicant_overlay.conf:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/p2p_supplicant_overlay.conf' \
  "$device_makefile"
require_fixed '$(LOCAL_PATH)/wifi/wpa_supplicant_overlay.conf:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/wpa_supplicant_overlay.conf' \
  "$device_makefile"
require_fixed 'SIM_COUNT := 2' "$board_config"
require_fixed 'android.hardware.radio@1.1' "$device_makefile"
require_fixed 'android.hardware.radio.deprecated@1.0' "$device_makefile"
require_fixed 'rild.libpath=/system/lib64/libsitril.so' "$system_prop"
require_fixed 'rild.libargs=-d /dev/umts_ipc0' "$system_prop"
require_fixed 'persist.radio.multisim.config=dsds' "$system_prop"
require_fixed 'exynos.modempath=/system/vendor/firmware/modem.bin' "$system_prop"
require_fixed 'android.hardware.gnss@1.0-impl.zero' "$device_makefile"
require_fixed 'android.hardware.gnss@1.0-service' "$device_makefile"
require_fixed 'libm86gps_shim' "$device_makefile"
require_fixed 'name: "libm86gps_shim"' "$gps_bp"
require_fixed 'SSLv3_client_method' "$gps_shim"
require_fixed '$(LOCAL_PATH)/gps/gps.conf:$(TARGET_COPY_OUT_SYSTEM)/etc/gps.conf' \
  "$device_makefile"
require_fixed '$(LOCAL_PATH)/gps/gps.xml:$(TARGET_COPY_OUT_SYSTEM)/etc/gps.xml' \
  "$device_makefile"
for nfc_package in \
  android.hardware.nfc@1.1-service \
  com.android.nfc_extras \
  nfc_nci_nxp \
  NfcNci \
  Tag; do
  require_fixed "$nfc_package" "$device_makefile"
done
require_fixed '$(LOCAL_PATH)/nfc/libnfc-nxp.conf:$(TARGET_COPY_OUT_VENDOR)/etc/libnfc-nxp.conf' \
  "$device_makefile"
require_fixed 'hardware/nxp/nfc/halimpl/libnfc-nci.conf:$(TARGET_COPY_OUT_VENDOR)/etc/libnfc-nci.conf' \
  "$device_makefile"
require_fixed 'ro.nfc.platform=nxppn547' "$system_prop"
require_fixed 'ro.nfc.port=I2C' "$system_prop"
require_fixed 'NXP_NFC_DEV_NODE="/dev/pn544"' "$nfc_config"
require_fixed 'NXP_FW_NAME="libpn547_fw.so"' "$nfc_config"
require_fixed 'NXP_NFC_CHIP=0x02' "$nfc_config"
require_fixed 'NXP_RF_CONF_BLK_1={' "$nfc_config"
require_fixed 'NXP_RF_CONF_BLK_5={' "$nfc_config"
require_fixed 'NXP_P61_JCOP_DEFAULT_INTERFACE=0x01' "$nfc_config"
require_fixed 'android.hardware.sensors@1.0-impl' "$device_makefile"
require_fixed 'android.hardware.sensors@1.0-service' "$device_makefile"
require_fixed 'group system wakelock input' "$sensors_service_rc"
require_fixed 'android.hardware.usb@1.0-service.basic' "$device_makefile"
require_fixed 'android.hardware.vibrator@1.0-impl' "$device_makefile"
require_fixed 'android.hardware.vibrator@1.0-service' "$device_makefile"
require_fixed 'vibrator.default' "$device_makefile"
require_fixed 'android.hardware.light@2.0-impl' "$device_makefile"
require_fixed 'android.hardware.light@2.0-service' "$device_makefile"
require_fixed 'lights.m86' "$device_makefile"
require_fixed 'name: "lights.m86"' "$lights_bp"
require_fixed '#define M86_LED_MODE_CURRENT 0x100' "$lights_source"
require_fixed '#define M86_LED_MODE_BREATH 0x200' "$lights_source"
require_fixed '#define M86_LED_MODE_TIMED_BLINK 0x400' "$lights_source"
require_fixed '/sys/class/leds/m86_led/brightness' "$lights_source"
require_fixed '/sys/class/backlight/pwm-backlight.0/brightness' \
  "$lights_source"
require_fixed 'android.hardware.power@1.0-impl' "$device_makefile"
require_fixed 'android.hardware.power@1.0-service' "$device_makefile"
require_fixed 'power.m86' "$device_makefile"
require_fixed 'name: "power.m86"' "$power_bp"
require_fixed 'POWER_MODULE_API_VERSION_0_2' "$power_source"
require_fixed '/sys/devices/system/cpu/cpu0/cpufreq/interactive/boostpulse' \
  "$power_source"
require_fixed '/sys/devices/system/cpu/cpu4/cpufreq/interactive/boostpulse' \
  "$power_source"
require_fixed '/sys/module/exynos_march_cpu_hotplug/parameters/current_profile_no' \
  "$power_source"
require_fixed '#define NAVIGATION_SWITCH "/proc/nav_switch"' "$power_source"
for fingerprint_package in \
  android.hardware.biometrics.fingerprint@2.1-service \
  fingerprint.m86 \
  libglib; do
  require_fixed "$fingerprint_package" "$device_makefile"
done
require_fixed 'LOCAL_MODULE := libm86fprint' "$fingerprint_makefile"
require_fixed 'LOCAL_MODULE := fingerprint.m86' "$fingerprint_makefile"
require_fixed 'LOCAL_MULTILIB := 64' "$fingerprint_makefile"
require_fixed 'LOCAL_VENDOR_MODULE := true' "$fingerprint_makefile"
require_fixed 'FINGERPRINT_MODULE_API_VERSION_2_1' "$fingerprint_source"
require_fixed 'struct fp_print_data *templates[MAX_TEMPLATES + 1];' \
  "$fingerprint_source"
require_fixed 'no TEE-backed' "$fingerprint_source"
require_fixed 'sizeof(authenticated.data.authenticated.hat.hmac)' \
  "$fingerprint_source"
require_fixed 'start_worker_locked' "$fingerprint_source"
require_fixed 'message.data.enumerated.remaining_templates' "$fingerprint_source"
require_fixed 'message.data.removed.remaining_templates' "$fingerprint_source"
require_fixed 'LOCAL_VENDOR_MODULE := true' "$glib_patch"
require_fixed 'LOCAL_MULTILIB := 64' "$glib_patch"
require_fixed '-Wno-expansion-to-defined' "$glib_patch"
for glib_legacy_warning in \
  missing-field-initializers \
  switch \
  unused-parameter \
  unused-value \
  unused-variable; do
  require_fixed "-Wno-error=${glib_legacy_warning}" "$glib_patch"
done
require_fixed 'G_GNUC_NORETURN static gpointer' "$glib_stub_patch"
require_fixed '#ifndef ANDROID_STUB' "$glib_stub_patch"
require_fixed 'patches/external-glib/0003-clang-port-legacy-android-stubs.patch' \
  "$patch_series"
require_fixed 'hardware/interfaces' "$patch_series"
require_fixed 'patches/hardware-interfaces/0001-audio-ignore-invalid-legacy-metadata-callback.patch' \
  "$patch_series"
require_fixed 'reinterpret_cast<uintptr_t>(callback)' \
  "$audio_metadata_patch"
require_fixed 'patches/frameworks-av/0001-audioflinger-restore-meizu-headphone-volume.patch' \
  "$patch_series"
require_fixed 'patches/hardware-interfaces/0004-audio-call-meizu-headphone-volume-hook.patch' \
  "$patch_series"
require_fixed 'vendor.meizu.set_headphone_volume=1' \
  "$audio_headphone_framework_patch"
require_fixed 'mDevice->set_headphone_volume(mDevice, 1.0f)' \
  "$audio_headphone_hal_patch"
require_fixed 'patches/frameworks-av/0002-audioflinger-route-meizu-hifi-state-to-output.patch' \
  "$patch_series"
require_fixed 'patches/frameworks-base/0003-audio-restore-meizu-hifi-routing.patch' \
  "$patch_series"
require_fixed 'patches/packages-apps-settings/0001-system-add-meizu-hifi-sound.patch' \
  "$patch_series"
require_fixed 'primaryPlaybackThread_l()' "$audio_hifi_output_patch"
require_fixed 'hifi_state=on' "$audio_hifi_service_patch"
require_fixed 'MSG_APPLY_MEIZU_HIFI' "$audio_hifi_service_patch"
require_fixed 'HifiSoundSettings' "$settings_hifi_patch"
require_fixed 'hifi_line_out_warning_message' "$settings_hifi_patch"
require_fixed 'ro.meizu.hardware.hifi=true' "$system_prop"
require_fixed 'ro.hardware.hifi.support=true' "$system_prop"
require_fixed 'git -C "$build_fprint" apply --check "$fprint_patch"' \
  "$install_worker"
require_fixed 'Expected 42 archived m86 libfprint build files.' \
  "$install_worker"
require_fixed "--include '/legacy/device-meizu-m86-cm14/libfprint/***'" \
  "$push_worker"
require_fixed 'external/glib' "$platform_sync_worker"
require_fixed 'external/glib' "$patch_series"
require_fixed 'patches/legacy-m86-libfprint/0001-port-m86-fpc-to-android10.patch' \
  "$install_worker"
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
require_fixed 'write /sys/class/android_usb/android0/functions adb' "$usb_rc"
require_fixed 'write /sys/class/android_usb/android0/idProduct 200B' "$usb_rc"
require_fixed 'write /sys/class/android_usb/android0/idProduct 200C' "$usb_rc"
require_fixed 'write /sys/class/android_usb/android0/idProduct 6863' "$usb_rc"
require_fixed 'write /sys/class/android_usb/android0/idProduct 6864' "$usb_rc"
require_absent '/mnt/vendor/cache' "$init_rc"
require_fixed 'write /cache/m86-lineage-boot-stage boot' "$init_rc"
require_fixed 'setprop logd.logpersistd.enable true' "$init_rc"
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
require_fixed '/dev/m2m1shot_scaler0        0660   cameraserver graphics' \
  "$ueventd_rc"
require_fixed '/dev/m2m1shot_jpeg           0660   cameraserver media' \
  "$ueventd_rc"
require_fixed '/dev/video101                0660   cameraserver cameraserver' \
  "$ueventd_rc"
require_fixed '/dev/video160                0660   cameraserver cameraserver' \
  "$ueventd_rc"
require_fixed '/dev/pn544                   0660   nfc         nfc' \
  "$ueventd_rc"
require_fixed '/dev/p61                     0660   nfc         nfc' \
  "$ueventd_rc"
require_fixed 'chown bluetooth bluetooth /sys/class/rfkill/rfkill0/state' \
  "$device_root/rootdir/etc/init.m86.rc"
require_fixed 'chmod 0660 /sys/class/rfkill/rfkill0/state' \
  "$init_rc"
require_fixed 'chown system system /sys/class/timed_output/vibrator/enable' \
  "$init_rc"
require_fixed 'chmod 0660 /sys/class/timed_output/vibrator/enable' \
  "$init_rc"
require_fixed 'chmod 0660 /proc/nav_switch' "$init_rc"
for fingerprint_node in capture_mode capture_count pxl_ctrl; do
  require_fixed "chown system system /sys/devices/14d70000.spi/spi_master/spi4/spi4.0/setup/${fingerprint_node}" \
    "$init_rc"
  require_fixed "chmod 0660 /sys/devices/14d70000.spi/spi_master/spi4/spi4.0/setup/${fingerprint_node}" \
    "$init_rc"
done
require_fixed '/dev/fpc1020                 0660   system      system' \
  "$ueventd_rc"
require_fixed 'chmod 0660 /sys/devices/system/cpu/cpu0/cpufreq/interactive/boostpulse' \
  "$init_rc"
require_fixed 'chmod 0660 /sys/devices/system/cpu/cpu4/cpufreq/interactive/boostpulse' \
  "$init_rc"
require_fixed 'chmod 0660 /sys/module/exynos_march_cpu_hotplug/parameters/current_profile_no' \
  "$init_rc"
require_fixed 'chmod 0660 /sys/module/exynos_march_cpu_hotplug/parameters/cl1_booster' \
  "$init_rc"
require_fixed 'chmod 0660 /sys/module/exynos_march_cpu_hotplug/parameters/min_cpu_boosted' \
  "$init_rc"
require_fixed 'chown system system /sys/class/leds/m86_led/brightness' \
  "$init_rc"
require_fixed 'chmod 0660 /sys/class/leds/m86_led/brightness' \
  "$init_rc"
require_fixed 'chown cameraserver camera /sys/class/leds/torch0/hwen' \
  "$init_rc"
require_fixed 'chmod 0660 /sys/class/leds/torch1/enable' "$init_rc"
require_fixed 'chown system system /sys/class/backlight/pwm-backlight.0/brightness' \
  "$init_rc"
require_fixed 'chmod 0660 /sys/class/backlight/pwm-backlight.0/brightness' \
  "$init_rc"
require_fixed 'mkdir /data/vendor/wifi/wpa/sockets 0770 wifi wifi' "$init_rc"
require_fixed 'chown wifi wifi /sys/module/bcmdhd/parameters/firmware_path' \
  "$init_rc"
require_fixed 'service wpa_supplicant /vendor/bin/hw/wpa_supplicant \' \
  "$init_rc"
require_fixed 'interface android.hardware.wifi.supplicant@1.2::ISupplicant default' \
  "$init_rc"
require_fixed 'service cpboot-daemon /system/bin/cbd -m user' "$init_rc"
require_fixed 'service gpsd /system/bin/gpsd /system/etc/gps.xml' "$init_rc"
require_fixed 'socket gps seqpacket 0660 gps system' "$init_rc"
require_fixed 'socket rilgps.socket seqpacket 0660 gps system' "$init_rc"
require_fixed 'mkdir /data/system/gps 0770 system system' "$init_rc"
require_fixed 'mkdir /data/nfc 0770 nfc nfc' "$init_rc"
require_fixed 'mkdir /data/nfc/param 0770 nfc nfc' "$init_rc"
require_fixed 'mkdir /data/vendor/nfc 0770 nfc nfc' "$init_rc"
require_fixed 'chown nfc nfc /dev/pn544' "$init_rc"
require_fixed 'chmod 0660 /dev/pn544' "$init_rc"
require_fixed 'chown nfc nfc /dev/p61' "$init_rc"
require_fixed 'chmod 0660 /dev/p61' "$init_rc"
require_fixed 'chmod 0600 /dev/ttySAC1' "$init_rc"
require_fixed 'chmod 0770 /sys/class/misc/gps/device/pwr' "$init_rc"
require_fixed 'chmod 0660 /sys/class/meizu/mx_hub/enable' "$sensors_init_rc"
require_fixed 'chmod 0600 /dev/iio:device0' "$sensors_init_rc"
require_fixed 'chown system system /sys/class/meizu/als/als_enable' \
  "$sensors_init_rc"
require_fixed 'chown system system /sys/class/meizu/ps/ps_enable' \
  "$sensors_init_rc"
require_fixed 'stop vendor.ril-daemon' "$init_rc"
require_fixed '/dev/umts_boot0              0660   radio      radio' "$ueventd_rc"
require_fixed '/dev/umts_ipc0               0660   radio      radio' "$ueventd_rc"
require_fixed '/dev/umts_ipc1               0660   radio      radio' "$ueventd_rc"
require_fixed '/dev/umts_rfs0               0660   radio      radio' "$ueventd_rc"
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
require_fixed 'build/make' "$patch_series"
require_fixed 'patches/build-make/0001-releasetools-allow-full-ota-without-cache-size.patch' \
  "$patch_series"
require_fixed 'if not isinstance(self.src, EmptyImage):' "$full_ota_patch"
require_fixed 'cache size is required for incremental block OTA generation' \
  "$full_ota_patch"
require_fixed 'test_FindTransfers_fullOtaWithoutCacheSize' "$full_ota_patch"
require_fixed 'test_FindTransfers_incrementalRequiresCacheSize' \
  "$full_ota_patch"
require_fixed '#define BTM_DEF_LOCAL_NAME "Meizu PRO 5"' "$bluetooth_buildcfg"
require_fixed 'UartPort = /dev/ttySAC4' "$bluetooth_vendor_conf"
require_fixed 'FwPatchFilePath = /vendor/firmware/' "$bluetooth_vendor_conf"
require_fixed 'CONFIG_CMDLINE="androidboot.hardware=m86 androidboot.selinux=permissive"' \
  "$kernel_config"
require_fixed 'CONFIG_CMDLINE_EXTEND=y' "$kernel_config"
require_fixed 'CONFIG_RD_GZIP=y' "$kernel_config"
require_fixed '# CONFIG_PSTORE is not set' "$kernel_config"
require_fixed 'CONFIG_BCMDHD=y' "$kernel_config"
require_fixed 'CONFIG_BCMDHD_PCIE=y' "$kernel_config"
require_fixed 'CONFIG_BCMDHD_FW_PATH="/system/vendor/firmware/fw_bcmdhd.bin"' \
  "$kernel_config"
require_fixed 'CONFIG_BCMDHD_NVRAM_PATH="/system/etc/wifi/bcmdhd.cal"' \
  "$kernel_config"
require_fixed 'export BUILD_DATETIME=1786017600' "$build_worker"
require_fixed 'ART_BOOT_IMAGE_EXTRA_ARGS="-j$jobs"' "$build_worker"
require_fixed 'git -C "$webview_project" lfs pull' "$build_worker"
require_fixed 'unzip -tq "$webview_apk"' "$build_worker"
require_fixed 'local caller_shell_flags="$-"' \
  "$project_root/remote/builder-network.sh"
require_fixed 'if [[ "$caller_shell_flags" == *u* ]]' \
  "$project_root/remote/builder-network.sh"
require_fixed 'vendor_blob_count="$(wc -l < "$vendor_blob_lock"' \
  "$build_worker"
require_fixed 'sha256sum --quiet -c "$vendor_blob_lock"' "$build_worker"
require_fixed 'm86-proprietary-sha256s.txt' "$build_worker"
require_fixed 'cd "$product_out/system"' "$build_worker"
require_fixed 'PROPRIETARY-OUTPUT.txt' "$build_worker"
require_fixed 'ota-required-cache=0' "$ota_audit_tool"
require_fixed 'transfer_operations=' "$ota_audit_tool"
require_fixed 'block_targets=bootimg,dtb,system' "$ota_audit_tool"
require_fixed 'OTA-AUDIT.txt' "$build_worker"
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
require_fixed 'bin/cbd' "$blob_list"
require_fixed 'lib64/libsitril.so' "$blob_list"
require_fixed 'vendor/firmware/modem.bin' "$blob_list"
require_fixed 'vendor/firmware/libpn547_fw.so' "$blob_list"
require_fixed 'bin/gpsd' "$blob_list"
require_fixed 'lib64/hw/gps.default.so' "$blob_list"
require_fixed 'lib64/hw/sensors.m86.so' "$blob_list"
require_fixed 'copy_rule_count="$(' "$vendor_worker"
require_fixed 'expected_rule="vendor/meizu/m86/proprietary/$relative_path:$output_path"' \
  "$vendor_worker"
require_fixed '\$(TARGET_COPY_OUT_VENDOR)/vendor/' "$vendor_worker"
require_fixed 'This file is generated by device/meizu/m86/setup-makefiles.sh' \
  "$vendor_android_makefile"
require_fixed 'This file is generated by device/meizu/m86/setup-makefiles.sh' \
  "$vendor_board_config"
require_fixed 'PRODUCT_SOONG_NAMESPACES += \' "$vendor_product_makefile"
require_fixed 'manifest_tmp="${manifest_lock}.tmp"' \
  "$project_root/remote/worker-sync-source.sh"
require_fixed 'mv "$manifest_tmp" "$manifest_lock"' \
  "$project_root/remote/worker-sync-source.sh"
require_fixed '[[ ! -s "$log_dir/lineage-17.1-manifest.xml" ]]' \
  "$project_root/remote/worker-sync-platform.sh"
require_fixed '--force-sync' "$project_root/remote/worker-sync-platform.sh"
require_fixed 'Refusing to replace dirty platform checkout' \
  "$project_root/remote/worker-sync-platform.sh"
require_fixed 'remove_reviewed_project_patches "$project"' \
  "$project_root/remote/worker-sync-platform.sh"
require_fixed 'Reviewed platform patch series is missing' \
  "$project_root/remote/worker-sync-platform.sh"
require_fixed 'git -C "$project" apply --reverse "$patch_file"' \
  "$project_root/remote/worker-sync-platform.sh"
require_fixed 'mv "$manifest_tmp" "$manifest_lock"' \
  "$project_root/remote/worker-sync-platform.sh"
require_fixed 'set +u' "$device_root/extract-files.sh"
require_fixed '  "$clean_vendor" \' "$device_root/extract-files.sh"
require_fixed '  "$device"' "$device_root/extract-files.sh"
require_fixed 'set +u' "$device_root/setup-makefiles.sh"
require_fixed '  true \' "$device_root/setup-makefiles.sh"
require_fixed '  "$DEVICE"' "$device_root/setup-makefiles.sh"

expected_blob_count="$(
  awk 'NF && $1 !~ /^#/ { count++ } END { print count + 0 }' "$blob_list"
)"
generated_copy_count="$(
  rg -c '^    vendor/meizu/m86/proprietary/' "$vendor_product_makefile"
)"
excluded_vendor_copy_paths=(
  lib/hw/gralloc.exynos5.so
  lib64/hw/gralloc.exynos5.so
  lib/hw/hwcomposer.exynos5.so
  lib64/hw/hwcomposer.exynos5.so
  lib/libdisplay.so
  lib64/libdisplay.so
  lib/libhdmi.so
  lib64/libhdmi.so
  lib/libion.so
  lib64/libion.so
)
expected_generated_copy_count="$((
  expected_blob_count - ${#excluded_vendor_copy_paths[@]}
))"
if [[ "$expected_blob_count" != "219" ]] || \
    [[ "$generated_copy_count" != "$expected_generated_copy_count" ]]; then
  printf 'Expected 219 verified blobs and %s install mappings, found list=%s generated=%s.\n' \
    "$expected_generated_copy_count" "$expected_blob_count" \
    "$generated_copy_count" >&2
  exit 1
fi

for relative_path in "${excluded_vendor_copy_paths[@]}"; do
  if rg -F -q -- "vendor/meizu/m86/proprietary/$relative_path:" \
      "$vendor_product_makefile"; then
    printf 'Source-built module is still overridden by: %s\n' \
      "$relative_path" >&2
    exit 1
  fi
done

while IFS= read -r relative_path; do
  excluded_copy=false
  for excluded_path in "${excluded_vendor_copy_paths[@]}"; do
    if [[ "$relative_path" == "$excluded_path" ]]; then
      excluded_copy=true
      break
    fi
  done
  if [[ "$excluded_copy" == true ]]; then
    continue
  fi
  if [[ "$relative_path" == vendor/* ]]; then
    output_path="\$(TARGET_COPY_OUT_VENDOR)/${relative_path#vendor/}"
  else
    output_path="\$(TARGET_COPY_OUT_SYSTEM)/$relative_path"
  fi
  expected_rule="vendor/meizu/m86/proprietary/$relative_path:$output_path"
  if ! rg -F -q -- "$expected_rule" "$vendor_product_makefile"; then
    printf 'Local generated vendor mapping is missing: %s\n' \
      "$expected_rule" >&2
    exit 1
  fi
done < <(awk 'NF && $1 !~ /^#/ { print }' "$blob_list")

if rg -F -q -- '\$(TARGET_COPY_OUT_VENDOR)/vendor/' \
    "$vendor_product_makefile"; then
  printf 'Local generated vendor mapping contains vendor/vendor.\n' >&2
  exit 1
fi

if ! command -v xmllint >/dev/null 2>&1; then
  printf 'xmllint is required for m86 VINTF validation.\n' >&2
  exit 1
fi
xmllint --noout "$device_manifest"
xmllint --noout "$platform_manifest"
xmllint --noout "$audio_policy"
xmllint --noout "$audio_effects"
xmllint --noout "$gps_xml"
require_sha256 \
  44a960aec8d8322cba8386779fa54355e10d976c19871c45fe44547c4ccb11d0 \
  "$gps_conf"
require_sha256 \
  eab2ec1b4b2c2855e0fc38f27a59e84522570020192925f63b11fd7ab7f75e5d \
  "$gps_xml"
require_sha256 \
  b59aac5c985e7756dda4a8b71eddd515ccb722edfe0c39c6f249617b3a8125ac \
  "$nfc_config"

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
  android.hardware.biometrics.fingerprint 2.1 hwbinder '' IBiometricsFingerprint
require_manifest_instance \
  android.hardware.camera.provider 2.4 ICameraProvider legacy/0
require_manifest_hal \
  android.hardware.configstore 1.1 hwbinder '' ISurfaceFlingerConfigs
require_manifest_hal \
  android.hardware.graphics.allocator 2.0 hwbinder '' IAllocator
require_manifest_hal \
  android.hardware.graphics.composer 2.1 passthrough 32+64 IComposer
require_manifest_hal \
  android.hardware.graphics.mapper 2.0 passthrough 32+64 IMapper
require_manifest_hal \
  android.hardware.gnss 1.0 hwbinder '' IGnss
require_manifest_hal \
  android.hardware.light 2.0 hwbinder '' ILight
require_manifest_hal \
  android.hardware.keymaster 4.0 hwbinder '' IKeymasterDevice
require_manifest_hal \
  android.hardware.memtrack 1.0 passthrough 32+64 IMemtrack
require_manifest_hal \
  android.hardware.nfc 1.1 hwbinder '' INfc
require_manifest_hal \
  android.hardware.power 1.0 hwbinder '' IPower
for radio_slot in slot1 slot2; do
  require_manifest_instance \
    android.hardware.radio 1.1 IRadio "$radio_slot"
  require_manifest_instance \
    android.hardware.radio.deprecated 1.0 IOemHook "$radio_slot"
done
require_manifest_hal \
  android.hardware.sensors 1.0 hwbinder '' ISensors
require_manifest_hal \
  android.hardware.usb 1.0 hwbinder '' IUsb
require_manifest_hal \
  android.hardware.vibrator 1.0 hwbinder '' IVibrator
require_manifest_hal \
  android.hardware.wifi 1.3 hwbinder '' IWifi
require_manifest_hal \
  android.hardware.wifi.hostapd 1.1 hwbinder '' IHostapd
require_manifest_hal \
  android.hardware.wifi.supplicant 1.2 hwbinder '' ISupplicant
require_manifest_hal \
  vendor.nxp.nxpnfc 1.0 hwbinder '' INxpNfc

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
  JAVA_SOURCE_OVERLAYS \
  BOARD_NFC_HAL_SUFFIX \
  BOARD_PROVIDES_LIBRIL \
  ENABLE_VENDOR_RIL_SERVICE \
  TARGET_EXFAT_DRIVER \
  TARGET_FS_CONFIG_GEN \
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
if rg -q 'kernel/samsung/universal7420' \
    "$platform_manifest" "$project_root/remote/worker-sync-platform.sh"; then
  printf 'The research-only Galaxy kernel must not enter the m86 build manifest.\n' >&2
  exit 1
fi
if rg -q 'android\.hardware\.sensor\.(barometer|heartrate)' "$device_makefile"; then
  printf 'm86 must not advertise Galaxy-only pressure or heart-rate sensors.\n' >&2
  exit 1
fi
if rg -q 'android\.hardware\.camera\.(full|raw)\.xml|camera\.exynos5' \
    "$device_makefile"; then
  printf 'm86 must not advertise unverified FULL/RAW camera or use the Galaxy wrapper.\n' >&2
  exit 1
fi
if rg -q 'android\.hardware\.nfc\.hcef\.xml|NQNfcNci|sec-nfc|/dev/pn54x' \
    "$device_makefile" "$nfc_config"; then
  printf 'm86 must not advertise unverified HCE-F or use the wrong NFC generation/node.\n' >&2
  exit 1
fi
if rg -q '(^|[[:space:]\\])fingerprintd([[:space:]\\]|$)|android\.hardware\.biometrics\.fingerprint@2\.1-impl' \
    "$device_makefile"; then
  printf 'm86 must use the Android 10 fingerprint HIDL service, not obsolete daemons/modules.\n' >&2
  exit 1
fi
if [[ "$(xmllint --xpath "count(/manifest/project[@path='external/glib' and @name='platform/external/bluetooth/glib' and @remote='aosp' and @revision='1143b9918eab068401b604eb11c3f651f4e38b25'])" "$platform_manifest")" != "1" ]]; then
  printf 'The exact AOSP legacy glib source is not pinned in the m86 manifest.\n' >&2
  exit 1
fi
if rg -q 'gpioi2c|led_pattern|my_pattern|fopen' "$lights_source"; then
  printf 'm86 lights must use stable class nodes and checked file I/O.\n' >&2
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
if rg -q '^on property:sys\.usb\.config=none([[:space:]]|$)' \
    "$usb_rc"; then
  printf 'm86 must not duplicate Android 10 generic none USB handler.\n' >&2
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
