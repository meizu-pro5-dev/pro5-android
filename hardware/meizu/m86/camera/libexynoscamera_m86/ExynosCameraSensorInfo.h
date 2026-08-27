/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 *
 * m86 platform sensor selector for the open-source SLSI Exynos camera engine.
 *
 * The upstream linaro snapshot ships the shared sensor table in
 * libcamera/common_v2/SensorInfos/ExynosCameraSensorInfoBase.* but omits the
 * per-product factory header. PRO 5 uses:
 *   rear  = Sony IMX230  (SENSOR_NAME_IMX230 = 108)
 *   front = OmniVision OV5670 (SENSOR_NAME_OV5670 = 204)
 */

#ifndef EXYNOS_CAMERA_SENSOR_INFO_H
#define EXYNOS_CAMERA_SENSOR_INFO_H

#include "ExynosCameraConfig.h"
#include "ExynosCameraSensorInfoBase.h"

namespace android {

struct ExynosSensorInfoBase *createSensorInfo(int camId);
struct ExynosSensorInfoBase *createExynosCamera1SensorInfo(int camId);
bool needGSCForCapture(int camId);

static inline bool isOwnScc(int cameraId)
{
    return (cameraId == CAMERA_ID_BACK) ? MAIN_CAMERA_HAS_OWN_SCC
                                        : FRONT_CAMERA_HAS_OWN_SCC;
}

static inline bool isFastenAeStable(int /* cameraId */, bool /* useCompanion */)
{
    return USE_FASTEN_AE_STABLE;
}
static inline bool isCompanion(int /* cameraId */)
{
    return false;
}

extern int M86_PREVIEW_SIZE_LUT_OV5670[][SIZE_OF_LUT];
extern int M86_PICTURE_SIZE_LUT_OV5670[][SIZE_OF_LUT];
extern int M86_VIDEO_SIZE_LUT_OV5670[][SIZE_OF_LUT];
extern int M86_PREVIEW_SIZE_LUT_IMX230[][SIZE_OF_LUT];

struct ExynosSensorIMX230 : public ExynosSensorIMX230Base {
public:
    ExynosSensorIMX230();
};

/*
 * The upstream OV5670 table assumes a 2608x1960 sensor output with 16x12
 * alignment margins.  The PRO 5 kernel driver exposes exactly 2592x1944
 * (and 2592x1458 for 16:9), so FLITE VIDIOC_S_FMT fails with the generic
 * table.  Override the m86 front camera with the kernel-supported geometry.
 */
struct ExynosSensorOV5670 : public ExynosSensorOV5670Base {
public:
    ExynosSensorOV5670();
};

}  // namespace android

#endif  // EXYNOS_CAMERA_SENSOR_INFO_H
