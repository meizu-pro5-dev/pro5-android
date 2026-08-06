# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

LOCAL_PATH := $(call my-dir)

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/recovery/root/init.recovery.m86.rc:recovery/root/init.recovery.m86.rc \
    $(LOCAL_PATH)/recovery/root/ueventd.m86.rc:recovery/root/ueventd.m86.rc \
    $(LOCAL_PATH)/rootdir/fstab.m86:recovery/root/fstab.m86

PRODUCT_DEFAULT_PROPERTY_OVERRIDES += \
    ro.build.product=m86 \
    ro.product.device=m86 \
    ro.product.manufacturer=Meizu \
    persist.sys.usb.config=mtp,adb
