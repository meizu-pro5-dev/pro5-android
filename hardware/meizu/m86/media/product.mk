# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

# m86 media/OMX product owner.
#
# The PRO 5 codec stack uses the source-built Exynos OpenMAX implementation,
# but its native_handle ABI is owned by gralloc.m86 for compatibility with the
# Flyme Mali userspace. BoardConfigPlatform.mk therefore binds OMX to the M86
# gralloc contract in addition to selecting the codec feature flags. This file
# only owns the installed package set and XML/configuration contract.

PRODUCT_PACKAGES += \
    libExynosOMX_Core \
    libExynosOMX_Resourcemanager \
    libOMX.Exynos.AVC.Decoder \
    libOMX.Exynos.AVC.Encoder \
    libOMX.Exynos.HEVC.Decoder \
    libOMX.Exynos.HEVC.Encoder \
    libOMX.Exynos.MPEG4.Decoder \
    libOMX.Exynos.MPEG4.Encoder \
    libOMX.Exynos.VP8.Decoder \
    libOMX.Exynos.VP8.Encoder \
    libOMX.Exynos.VP9.Decoder \
    libcsc \
    libstagefrighthw
