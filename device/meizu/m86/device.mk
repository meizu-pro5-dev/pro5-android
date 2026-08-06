# Copyright (C) 2015 The CyanogenMod Project
# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

LOCAL_PATH := device/meizu/m86

# PRO 5 launched on Android 5.1. This keeps Android 10 compatibility checks in
# legacy, non-Treble mode while the stock vendor ABI is brought up.
PRODUCT_SHIPPING_API_LEVEL := 22
PRODUCT_ENFORCE_VINTF_MANIFEST := false

PRODUCT_AAPT_CONFIG := normal
PRODUCT_AAPT_PREF_CONFIG := xxhdpi

TARGET_SCREEN_HEIGHT := 1920
TARGET_SCREEN_WIDTH := 1080

PRODUCT_SOONG_NAMESPACES += \
    device/samsung/universal7420-common \
    hardware/samsung \
    hardware/samsung_slsi/exynos \
    hardware/samsung_slsi/exynos5 \
    hardware/samsung_slsi/exynos7420 \
    hardware/samsung_slsi/openmax

# Ramdisk
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/fstab.m86:root/fstab.m86 \
    $(LOCAL_PATH)/rootdir/etc/init.m86.rc:root/init.m86.rc \
    $(LOCAL_PATH)/rootdir/etc/init.m86.usb.rc:root/init.m86.usb.rc \
    $(LOCAL_PATH)/rootdir/etc/ueventd.m86.rc:root/ueventd.m86.rc

# Input
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/keylayout/fpc1020.kl:system/usr/keylayout/fpc1020.kl \
    $(LOCAL_PATH)/keylayout/fts.kl:system/usr/keylayout/fts.kl \
    $(LOCAL_PATH)/keylayout/gpio-keys.kl:system/usr/keylayout/gpio-keys.kl

# Minimum feature declaration for the first boot/recovery milestone.
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.touchscreen.multitouch.jazzhand.xml:system/etc/permissions/android.hardware.touchscreen.multitouch.jazzhand.xml \
    frameworks/native/data/etc/android.hardware.usb.accessory.xml:system/etc/permissions/android.hardware.usb.accessory.xml \
    frameworks/native/data/etc/android.hardware.usb.host.xml:system/etc/permissions/android.hardware.usb.host.xml \
    frameworks/native/data/etc/handheld_core_hardware.xml:system/etc/permissions/handheld_core_hardware.xml

TARGET_SYSTEM_PROP += $(LOCAL_PATH)/system.prop

# Android's build logic appends adb for userdebug/eng. User builds retain MTP.
PRODUCT_DEFAULT_PROPERTY_OVERRIDES += \
    persist.sys.usb.config=mtp

$(call inherit-product-if-exists, vendor/meizu/m86/m86-vendor.mk)
