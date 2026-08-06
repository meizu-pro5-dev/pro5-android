# Copyright (C) 2015 The CyanogenMod Project
# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

$(call inherit-product, device/meizu/m86/device.mk)
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

PRODUCT_NAME := lineage_m86
PRODUCT_DEVICE := m86
PRODUCT_BRAND := Meizu
PRODUCT_MANUFACTURER := Meizu
PRODUCT_MODEL := PRO 5

PRODUCT_BUILD_PROP_OVERRIDES += \
    PRODUCT_NAME=meizu_PRO5 \
    TARGET_DEVICE=PRO5 \
    PRIVATE_BUILD_DESC="meizu_PRO5-user 7.0 NRD90M m86.Flyme_8.0.1594148303 release-keys"

BUILD_FINGERPRINT := Meizu/meizu_PRO5/PRO5:7.0/NRD90M/m86.Flyme_8.0.1594148303:user/release-keys
