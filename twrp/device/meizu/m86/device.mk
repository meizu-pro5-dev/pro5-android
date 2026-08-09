# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

M86_TWRP_DEVICE_PATH := device/meizu/m86

PRODUCT_COPY_FILES += \
    $(M86_TWRP_DEVICE_PATH)/recovery/root/init.recovery.m86.rc:recovery/root/init.recovery.m86.rc \
    $(M86_TWRP_DEVICE_PATH)/recovery/root/ueventd.m86.rc:recovery/root/ueventd.m86.rc \
    $(M86_TWRP_DEVICE_PATH)/rootdir/fstab.m86:recovery/root/fstab.m86 \
    $(M86_TWRP_DEVICE_PATH)/recovery/root/etc/firmware/st_fts.bin:recovery/root/etc/firmware/st_fts.bin

PRODUCT_DEFAULT_PROPERTY_OVERRIDES += \
    ro.build.product=m86 \
    ro.product.device=m86 \
    ro.product.manufacturer=Meizu \
    usb.vendor=18D1 \
    usb.product.adb=4EE7 \
    usb.product.mtpadb=4EE2 \
    persist.sys.usb.config=mtp,adb
