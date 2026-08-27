/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef EXYNOS_CAMERA_SENSOR_INFO_M86_NATIVE3_H
#define EXYNOS_CAMERA_SENSOR_INFO_M86_NATIVE3_H

#include "ExynosCameraConfig.h"
#include "ExynosCameraSensorInfoBase.h"

namespace android {

/* common_v2 uses this product header as the public SensorInfo entry point.
 * The native3 library only defines createExynosCamera3SensorInfo(). */
struct ExynosSensorInfoBase *createExynosCamera1SensorInfo(int sensorName);
bool needGSCForCapture(int camId);

} // namespace android

#endif /* EXYNOS_CAMERA_SENSOR_INFO_M86_NATIVE3_H */
