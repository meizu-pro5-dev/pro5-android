# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

M86_TWRP_PATH := device/meizu/m86

# Bootloader and platform
BOARD_VENDOR := meizu
TARGET_BOARD_PLATFORM := exynos5
TARGET_SOC := exynos7420
TARGET_BOOTLOADER_BOARD_NAME := PRO5
TARGET_NO_BOOTLOADER := true
TARGET_NO_RADIOIMAGE := true

# CPU architecture
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := cortex-a53
TARGET_CPU_SMP := true

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv7-a-neon
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := cortex-a53

# Maintained m86 kernel. androidboot.hardware is built into the defconfig, so
# the boot header command line remains empty like the verified Flyme image.
TARGET_KERNEL_ARCH := arm64
TARGET_KERNEL_HEADER_ARCH := arm64
TARGET_KERNEL_SOURCE := kernel/meizu/m86
TARGET_KERNEL_CONFIG := cm_pro5_defconfig
TARGET_KERNEL_CLANG_COMPILE := false
TARGET_USES_UNCOMPRESSED_KERNEL := true
BOARD_KERNEL_IMAGE_NAME := Image
BOARD_KERNEL_CMDLINE :=

# Stock v0 boot-image geometry. The raw DTB is flashed separately and must not
# be appended to recovery.img or packed in a Samsung dtbhtool container.
BOARD_KERNEL_BASE := 0x40000000
BOARD_KERNEL_PAGESIZE := 4096
# TWRP's Android 9 build core also appends buildvariant=<variant>. A final
# empty value keeps the recovery header identical to the verified m86 ABI.
BOARD_MKBOOTIMG_ARGS := \
    --cmdline "" \
    --kernel_offset 0x00080000 \
    --ramdisk_offset 0x02000000 \
    --second_offset 0x00f00000 \
    --tags_offset 0x00000100
BOARD_KERNEL_SEPARATED_DT := false
BOARD_CUSTOM_BOOTIMG_MK :=
TARGET_CUSTOM_DTBTOOL :=

# Verified partition limits. The recovery limit intentionally reserves one
# 4096-byte page below the 32 MiB raw partition size until the GPT backup is
# resumed and reconfirmed from the current handset.
BOARD_FLASH_BLOCK_SIZE := 131072
BOARD_BOOTIMAGE_PARTITION_SIZE := 25161728
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 33550336
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 2684350464
BOARD_USERDATAIMAGE_PARTITION_SIZE := 27241979904

# Filesystems and mount roots
BOARD_HAS_LARGE_FILESYSTEM := true
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := false
BOARD_ROOT_EXTRA_FOLDERS += custom efs mnv external_sd usb-otg
TARGET_RECOVERY_FSTAB := $(M86_TWRP_PATH)/recovery.fstab
BOARD_SUPPRESS_SECURE_ERASE := true

# Display and input
TARGET_SCREEN_HEIGHT := 1920
TARGET_SCREEN_WIDTH := 1080
TARGET_RECOVERY_PIXEL_FORMAT := "RGBA_8888"
BOARD_HAS_NO_SELECT_BUTTON := true

# TWRP 3.7.0_9 feature set. m86 has legacy full-disk-encryption metadata in
# /cache/metadata, data/media internal storage, removable microSD, and OTG.
RECOVERY_VARIANT := twrp
TW_THEME := portrait_hdpi
TW_INCLUDE_CRYPTO := true
RECOVERY_SDCARD_ON_DATA := true
BOARD_HAS_NO_REAL_SDCARD := true
TW_INTERNAL_STORAGE_PATH := "/data/media/0"
TW_INTERNAL_STORAGE_MOUNT_POINT := "data"
TW_EXTERNAL_STORAGE_PATH := "/external_sd"
TW_EXTERNAL_STORAGE_MOUNT_POINT := "external_sd"

# Core recovery services and filesystem tools. Android vold requires the
# restored same-SoC kernel exFAT driver, while recovery retains TWRP's
# open-source FUSE path so its removable-media implementation is explicit and
# independently gated. NTFS is also userspace-based. Python and the install
# prompt app are excluded to preserve the recovery size margin.
TW_USE_NEW_MINADBD := true
TW_INCLUDE_NTFS_3G := true
TW_EXCLUDE_PYTHON := true
TW_EXCLUDE_TWRPAPP := true
# Keep the recovery below the legacy bootloader's practical image boundary
# without dropping Chinese support. The reviewed upstream patch copies only
# these language resources and the one CJK fallback font zh_CN references.
TW_EXTRA_LANGUAGES := false
TW_LANGUAGE_ALLOWLIST := en zh_CN

# The panel driver registers this stable class path with a 0..255 range.
TW_BRIGHTNESS_PATH := "/sys/class/backlight/pwm-backlight.0/brightness"
TW_MAX_BRIGHTNESS := 255
TW_DEFAULT_BRIGHTNESS := 134
