# Copyright (C) 2015 The CyanogenMod Project
# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

M86_PATH := device/meizu/m86

# Reuse the Android 10 Exynos 7420 platform definitions, then override every
# boot-chain and partition value that is specific to Meizu.
-include device/samsung/universal7420-common/BoardConfigCommon.mk

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

# Kernel and stock boot image geometry. The base plus the default 0x8000
# kernel offset yields the verified stock kernel address 0x40080000.
TARGET_KERNEL_ARCH := arm64
TARGET_KERNEL_HEADER_ARCH := arm64
TARGET_KERNEL_SOURCE := kernel/meizu/m86
TARGET_KERNEL_CONFIG := cm_pro5_defconfig
TARGET_LINUX_KERNEL_VERSION := 3.10
TARGET_USES_UNCOMPRESSED_KERNEL := true
TARGET_KERNEL_CLANG_COMPILE := false

BOARD_KERNEL_BASE := 0x40078000
BOARD_KERNEL_CMDLINE := androidboot.hardware=m86
BOARD_KERNEL_IMAGE_NAME := Image
BOARD_KERNEL_PAGESIZE := 4096
BOARD_MKBOOTIMG_ARGS := --base $(BOARD_KERNEL_BASE) --ramdisk_offset 0x01f88000 --pagesize $(BOARD_KERNEL_PAGESIZE)

# PRO 5 stores its raw DTB in a dedicated partition. Samsung's custom boot
# image and dtbhtool container must not be used.
BOARD_CUSTOM_BOOTIMG :=
BOARD_CUSTOM_BOOTIMG_MK :=
BOARD_KERNEL_SEPARATED_DT :=
TARGET_CUSTOM_DTBTOOL :=

# The common Samsung init library performs model unification that does not
# apply to Meizu's bootloader properties.
TARGET_INIT_VENDOR_LIB :=
TARGET_UNIFIED_DEVICE :=

# Partitions, taken from the last booting m86 community tree and checked
# against the verified Flyme updater paths.
TARGET_USERIMAGES_USE_EXT4 := true
BOARD_FLASH_BLOCK_SIZE := 131072
BOARD_BOOTIMAGE_PARTITION_SIZE := 25161728
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 33550336
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 2684350464
BOARD_USERDATAIMAGE_PARTITION_SIZE := 27241979904
BOARD_ROOT_EXTRA_FOLDERS += custom mnv

# Legacy non-Treble layout: vendor files live below system/vendor.
TARGET_COPY_OUT_VENDOR := system/vendor

# Recovery
TARGET_RECOVERY_FSTAB := $(M86_PATH)/rootdir/etc/recovery.fstab
BOARD_HAS_NO_SELECT_BUTTON := true
BOARD_HAS_LARGE_FILESYSTEM := true
BOARD_HAS_NO_MISC_PARTITION := true
BOARD_SUPPRESS_SECURE_ERASE := true
TARGET_RECOVERY_PIXEL_FORMAT := RGBA_8888

# Hardware
TARGET_BOARD_PLATFORM := exynos5
TARGET_SOC := exynos7420
BOARD_MODEM_TYPE := ss333

# Broadcom connectivity
BOARD_WLAN_DEVICE := bcmdhd
WPA_SUPPLICANT_VERSION := VER_0_8_X
BOARD_WPA_SUPPLICANT_DRIVER := NL80211
BOARD_HOSTAPD_DRIVER := NL80211
WIFI_DRIVER_FW_PATH_PARAM := /sys/module/bcmdhd/parameters/firmware_path
WIFI_DRIVER_FW_PATH_STA := /system/vendor/firmware/fw_bcmdhd.bin
WIFI_DRIVER_FW_PATH_AP := /system/vendor/firmware/fw_bcmdhd_apsta.bin
BOARD_HAVE_BLUETOOTH := true
BOARD_HAVE_BLUETOOTH_BCM := true

# Use a deliberately minimal manifest until each stock HAL has a validated
# Android 10 wrapper or replacement.
DEVICE_MANIFEST_FILE := $(M86_PATH)/manifest.xml
BOARD_USES_TRUST_KEYMASTER :=

-include vendor/meizu/m86/BoardConfigVendor.mk
