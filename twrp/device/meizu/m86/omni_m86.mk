# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

$(call inherit-product, $(SRC_TARGET_DIR)/product/aosp_base_telephony.mk)
$(call inherit-product, vendor/omni/config/common.mk)
$(call inherit-product, device/meizu/m86/device.mk)

PRODUCT_DEVICE := m86
PRODUCT_NAME := omni_m86
PRODUCT_BRAND := Meizu
PRODUCT_MODEL := PRO 5
PRODUCT_MANUFACTURER := Meizu
