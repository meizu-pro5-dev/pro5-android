/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef EXYNOS_CAMERA3_HW_CAPS_M86_H
#define EXYNOS_CAMERA3_HW_CAPS_M86_H

#include "ExynosCameraConfig.h"

namespace android {

struct ExynosCamera3HwCapsM86 {
    /* Physical sensor and DMA format contract.
     *
     * IMX230 and OV5670 both expose RAW10 CSI virtual channels in the m86
     * kernel.  BG12 is the packed FIMC-IS DMA container used by the working
     * 74xx HAL1; BG16 is reserved for explicit raw dumps only. */
    static constexpr int sensorWireBitDepth = 10;
    static constexpr int fliteBayerFormat = V4L2_PIX_FMT_SBGGR12;
    static constexpr int previewBayerFormat = V4L2_PIX_FMT_SBGGR12;
    static constexpr int rawDumpBayerFormat = V4L2_PIX_FMT_SBGGR16;
    static constexpr int previewYuvFormat = V4L2_PIX_FMT_NV21M;
    static constexpr int flitePackedWidthAlign = 10;

    static constexpr int fliteBytesPerLine(int width)
    {
        return ((width + flitePackedWidthAlign - 1) /
                flitePackedWidthAlign * flitePackedWidthAlign) * 8 / 5;
    }

    /* Rear stage-1 geometry comes from the IMX230 kernel modes and the
     * product-owned SensorInfo LUT, not from the Galaxy S6 sensor table. */
    static constexpr int rearSensorWidth = 5328;
    static constexpr int rearSensorHeight = 3000;
    static constexpr int rearBcropWidth = 5316;
    static constexpr int rearBcropHeight = 2990;
    static constexpr int stage1BdsWidth = 1920;
    static constexpr int stage1BdsHeight = 1080;
    static constexpr int frontSensorWidth = 2592;
    static constexpr int frontSensorHeight = 1944;
    static constexpr int front16x9BcropWidth = 2560;
    static constexpr int front16x9BcropHeight = 1440;

    /* Match the stable 74xx HAL1 queue depth and stay below the m86 ION
     * pressure point observed with the donor's 32/6-buffer policy. */
    static constexpr int sensorBufferCount = 5;
    static constexpr int aa3BufferCount = 5;
    static constexpr int previewBufferCount = 12;

    static constexpr bool hasMcsc = false;
    static constexpr bool hasVra = false;
    static constexpr bool hasHwfc = false;
    static constexpr bool hasInlineDis = true;
    static constexpr bool supportsHwVdis = false;
    static constexpr bool flite3aaOtf = true;
    static constexpr bool aa3IspOtf = true;
    static constexpr bool dirtyBayerReprocessing = false;
    static constexpr bool pureBayerReprocessing = false;
    static constexpr int previewLeaderPipe = PIPE_3AA;
    static constexpr int previewOutputPipe = PIPE_SCP;
    static constexpr int reprocessingLeaderPipe = PIPE_ISP_REPROCESSING;
    static constexpr int reprocessingYuvPipe = PIPE_ISPC_REPROCESSING;
};

} // namespace android

#endif /* EXYNOS_CAMERA3_HW_CAPS_M86_H */
