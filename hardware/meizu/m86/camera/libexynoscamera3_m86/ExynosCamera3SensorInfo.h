/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef EXYNOS_CAMERA3_SENSOR_INFO_M86_H
#define EXYNOS_CAMERA3_SENSOR_INFO_M86_H

#include "ExynosCameraSensorInfo.h"
#include "ExynosCamera3SensorInfoBase.h"

namespace android {

struct ExynosCamera3SensorIMX230M86 : public ExynosCamera3SensorInfoBase {
    ExynosCamera3SensorIMX230M86();
};

struct ExynosCamera3SensorOV5670M86 : public ExynosCamera3SensorOV5670Base {
    ExynosCamera3SensorOV5670M86();
};

struct ExynosSensorInfoBase *createExynosCamera3SensorInfo(int cameraId);

} // namespace android

#endif /* EXYNOS_CAMERA3_SENSOR_INFO_M86_H */
