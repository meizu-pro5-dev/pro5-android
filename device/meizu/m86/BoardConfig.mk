# Copyright (C) 2015 The CyanogenMod Project
# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

M86_PATH := device/meizu/m86

# Reuse the Android 10 Exynos 7420 platform definitions, then override every
# boot-chain and partition value that is specific to Meizu.
-include device/samsung/universal7420-common/BoardConfigCommon.mk

# The common tree is a same-SoC build reference, not a Galaxy device parent.
# Keep its Exynos graphics/media and Android 10 build integration, but remove
# model-specific HAL selection, compatibility shims, policy, and identity.
# Subsystems are enabled again only with an m86 package and ABI audit.
LOCAL_PATH := $(M86_PATH)
BOARD_VENDOR := meizu
TARGET_UNOFFICIAL_BUILD_ID :=
PRODUCT_SKIP_FINGERPRINT_FROM_FILE :=
TARGET_BUILD_DEBUGGABLE :=

TARGET_AUDIOHAL_VARIANT :=
# The verified Flyme primary HAL has matching 32/64-bit builds. Keep the
# Android 10 audio process on the donor-proven 32-bit ABI first, which also
# matches every required m86 TFA/SITRIL dependency.
AUDIOSERVER_MULTILIB := 32

BOARD_BLUETOOTH_BDROID_BUILDCFG_INCLUDE_DIR :=
BOARD_CUSTOM_BT_CONFIG :=
BOARD_HAVE_SAMSUNG_BLUETOOTH :=

BOARD_USE_SAMSUNG_CAMERAFORMAT_NV21 :=
TARGET_KEEP_LEGACY_CAMERA_PACKAGE :=
BOARD_BACK_CAMERA_SENSOR :=
BOARD_BACK_CAMERA_ROTATION :=
BOARD_FRONT_CAMERA_SENSOR :=
BOARD_FRONT_CAMERA_ROTATION :=

TARGET_SEC_FP_CALL_NOTIFY_ON_CANCEL :=
TARGET_SEC_FP_CALL_CANCEL_ON_ENROLL_COMPLETION :=
TARGET_SEC_FP_USES_PERCENTAGE_SAMPLES :=

TARGET_LD_SHIM_LIBS :=
# Flyme gpsd predates Q and still uses legacy linker greylist/APEX behavior.
# Scope the compatibility level to this one audited executable.
TARGET_PROCESS_SDK_VERSION_OVERRIDE := /system/bin/gpsd=27
JAVA_SOURCE_OVERLAYS :=
BOARD_NFC_HAL_SUFFIX :=
BOARD_PROVIDES_LIBRIL :=
ENABLE_VENDOR_RIL_SERVICE :=
# Android 10's AOSP libril remains the HIDL-facing compatibility layer. The
# verified Flyme SITRIL implements the Android 7 RIL v12 callback ABI and
# handles both m86 SIM sockets inside one process.
SIM_COUNT := 2

TARGET_EXFAT_DRIVER :=
TARGET_FS_CONFIG_GEN :=
BOARD_USE_CUSTOM_RECOVERY_FONT :=

BOARD_SEPOLICY_DIRS :=
BOARD_SEPOLICY_VERS :=
SELINUX_IGNORE_NEVERALLOWS :=
BOARD_SECCOMP_POLICY :=
TARGET_NO_SENSOR_PERMISSION_CHECK :=

BOARD_HAVE_SAMSUNG_WIFI :=
TARGET_GAPPS_OVERRIDE :=

# Architecture
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := cortex-a57

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv8-a
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := generic
TARGET_2ND_CPU_VARIANT_RUNTIME := cortex-a53

# Assert
TARGET_OTA_ASSERT_DEVICE := m86,PRO5,pro5,mx5pro,niux,NIUX

# Bootloader
TARGET_BOOTLOADER_BOARD_NAME := PRO5
TARGET_NO_BOOTLOADER := true

# Display
TARGET_SCREEN_HEIGHT := 1920
TARGET_SCREEN_WIDTH := 1080
BACKLIGHT_PATH := /sys/devices/13930000.decon_fb/backlight/pwm-backlight.0/brightness

# Charger paths are independently present in the historical booting m86 tree;
# state them here instead of relying on the identical Galaxy defaults.
WITH_LINEAGE_CHARGER := false
BOARD_BATTERY_DEVICE_NAME := battery
BOARD_CHARGER_ENABLE_SUSPEND := true
BOARD_CHARGING_MODE_BOOTING_LPM := /sys/class/power_supply/battery/batt_lp_charging
CHARGING_ENABLED_PATH := "/sys/class/power_supply/battery/batt_lp_charging"

# Kernel and stock v0 boot-image geometry. Explicit positive offsets reproduce
# all four addresses in the verified Flyme header without relying on overflow.
TARGET_KERNEL_ARCH := arm64
TARGET_KERNEL_HEADER_ARCH := arm64
TARGET_KERNEL_SOURCE := kernel/meizu/m86
TARGET_KERNEL_CONFIG := cm_pro5_defconfig
TARGET_LINUX_KERNEL_VERSION := 3.10
TARGET_USES_UNCOMPRESSED_KERNEL := true
TARGET_KERNEL_CLANG_COMPILE := false

BOARD_KERNEL_BASE := 0x40000000
# androidboot.hardware is compiled into cm_pro5_defconfig. Keep the v0 header
# command line empty to match the verified Flyme boot image byte-for-byte.
BOARD_KERNEL_CMDLINE :=
BOARD_KERNEL_IMAGE_NAME := Image
BOARD_KERNEL_PAGESIZE := 4096
BOARD_MKBOOTIMG_ARGS := \
    --kernel_offset 0x00080000 \
    --ramdisk_offset 0x02000000 \
    --second_offset 0x00f00000 \
    --tags_offset 0x00000100

# PRO 5 stores its raw DTB in a dedicated partition. Samsung's custom boot
# image and dtbhtool container must not be used.
BOARD_CUSTOM_BOOTIMG :=
BOARD_CUSTOM_BOOTIMG_MK :=
BOARD_KERNEL_SEPARATED_DT :=
TARGET_CUSTOM_DTBTOOL :=
BOARD_PACK_RADIOIMAGES += dtb

# The common Samsung init library performs model unification that does not
# apply to Meizu's bootloader properties.
TARGET_INIT_VENDOR_LIB :=
TARGET_UNIFIED_DEVICE :=

# Partitions, taken from the last booting m86 community tree and checked
# against the verified Flyme updater paths.
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS :=
BOARD_FLASH_BLOCK_SIZE := 131072
BOARD_BOOTIMAGE_PARTITION_SIZE := 25161728
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 33550336
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 2684350464
BOARD_USERDATAIMAGE_PARTITION_SIZE := 27241979904
# Do not inherit Samsung's cache geometry. Its exact size will be recorded
# when the deferred GPT backup is performed; no cache image is built meanwhile.
BOARD_CACHEIMAGE_PARTITION_SIZE :=
BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE :=
BOARD_ROOT_EXTRA_FOLDERS += custom mnv

# Legacy non-Treble layout: vendor files live below system/vendor.
TARGET_COPY_OUT_VENDOR := system/vendor

# Recovery
TARGET_RECOVERY_FSTAB := $(M86_PATH)/rootdir/etc/recovery.fstab
BOARD_HAS_NO_SELECT_BUTTON := true
BOARD_HAS_LARGE_FILESYSTEM := true
# universal7420-common disables misc for Samsung devices, but the verified
# Meizu ramdisk and recovery fstab both address the UFS misc partition.
BOARD_HAS_NO_MISC_PARTITION :=
BOARD_SUPPRESS_SECURE_ERASE := true
TARGET_RECOVERY_PIXEL_FORMAT := RGBA_8888
BOARD_HAS_DOWNLOAD_MODE :=
TARGET_RELEASETOOLS_EXTENSIONS := $(M86_PATH)/releasetools

# Hardware
TARGET_BOARD_PLATFORM := exynos5
TARGET_SOC := exynos7420
BOARD_MODEM_TYPE := ss333

# These are platform integration switches, not permission to package the
# universal7420-common product or any Galaxy proprietary implementation.
TARGET_SLSI_VARIANT := bsp
TARGET_NEEDS_NETD_DIRECT_CONNECT_RULE := true

# Broadcom connectivity
BOARD_WLAN_DEVICE := bcmdhd
WPA_SUPPLICANT_VERSION := VER_0_8_X
WPA_SUPPLICANT_USE_HIDL := true
BOARD_WPA_SUPPLICANT_DRIVER := NL80211
BOARD_WPA_SUPPLICANT_PRIVATE_LIB := lib_driver_cmd_bcmdhd
BOARD_HOSTAPD_DRIVER := NL80211
BOARD_HOSTAPD_PRIVATE_LIB := lib_driver_cmd_bcmdhd
WIFI_DRIVER_FW_PATH_PARAM := /sys/module/bcmdhd/parameters/firmware_path
WIFI_DRIVER_FW_PATH_STA := /system/vendor/firmware/fw_bcmdhd.bin
WIFI_DRIVER_FW_PATH_AP := /system/vendor/firmware/fw_bcmdhd_apsta.bin
WIFI_BAND := 802_11_ABG
BOARD_BLUETOOTH_BDROID_BUILDCFG_INCLUDE_DIR := $(M86_PATH)/bluetooth
BOARD_HAVE_BLUETOOTH := true
# Flyme 8 supplies the m86-specific Broadcom vendor interface. Do not also
# define hardware/broadcom's same-named source module and depend on duplicate
# install-rule ordering.
BOARD_HAVE_BLUETOOTH_BCM :=

# Use a deliberately minimal manifest until each stock HAL has a validated
# Android 10 wrapper or replacement.
DEVICE_MANIFEST_FILE := $(M86_PATH)/manifest.xml
BOARD_USES_TRUST_KEYMASTER :=

# Verified from Flyme 8.0.5.0A /system/build.prop, not the Galaxy donor.
VENDOR_SECURITY_PATCH := 2019-08-01

-include vendor/meizu/m86/BoardConfigVendor.mk
