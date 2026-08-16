# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

# m86 media/OMX product owner.
#
# The PRO 5 codec stack is the same source-built Exynos OpenMAX used by the
# maintained Exynos 7420 family. The modules below are defined by the
# unmodified hardware/samsung_slsi/openmax and hardware/samsung_slsi/exynos
# trees. BoardConfigPlatform.mk already selects the matching feature flags
# (DMA-BUF, ANB output sharing, HEVC/VP9 decode and encode, custom component
# registration), so this fragment only owns the installed package set and the
# XML/configuration contract.

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
