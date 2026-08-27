/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef EXYNOS_CAMERA3_HW_CAPS_M86_H
#define EXYNOS_CAMERA3_HW_CAPS_M86_H

#include "ExynosCameraConfig.h"

namespace android {

struct ExynosCamera3HwCapsM86 {
    static constexpr bool hasMcsc = false;
    static constexpr bool hasVra = false;
    static constexpr bool hasHwfc = false;
    static constexpr bool hasInlineDis = true;
    static constexpr bool supportsHwVdis = false;
    static constexpr bool flite3aaOtf = true;
    static constexpr bool aa3IspOtf = true;
    static constexpr bool dirtyBayerReprocessing = true;
    static constexpr bool pureBayerReprocessing = false;
    static constexpr int previewLeaderPipe = PIPE_3AA;
    static constexpr int previewOutputPipe = PIPE_SCP;
    static constexpr int reprocessingLeaderPipe = PIPE_ISP_REPROCESSING;
    static constexpr int reprocessingYuvPipe = PIPE_ISPC_REPROCESSING;
};

} // namespace android

#endif /* EXYNOS_CAMERA3_HW_CAPS_M86_H */
