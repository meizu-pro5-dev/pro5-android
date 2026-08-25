/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 *
 * Definitions for the legacy CameraParameters constants consumed by the SLSI
 * Exynos7420 camera engines. This is shared by the source-built engines and the
 * Route A donor compatibility bridge so every implementation uses one ABI
 * table. A12 removed the declarations from CameraParameters.h; the matching
 * m86 declaration block is restored by patch.
 */

#include <camera/CameraParameters.h>

namespace android {

const char CameraParameters::PIXEL_FORMAT_YUV420SP_NV21[] = "nv21";
const char CameraParameters::EFFECT_CARTOONIZE[] = "cartoonize";
const char CameraParameters::EFFECT_POINT_RED_YELLOW[] = "point-red-yellow";
const char CameraParameters::EFFECT_POINT_GREEN[] = "point-green";
const char CameraParameters::EFFECT_POINT_BLUE[] = "point-blue";
const char CameraParameters::EFFECT_VINTAGE_COLD[] = "vintage-cold";
const char CameraParameters::EFFECT_VINTAGE_WARM[] = "vintage-warm";
const char CameraParameters::EFFECT_WASHED[] = "washed";
const char CameraParameters::ISO_AUTO[] = "auto";
const char CameraParameters::ISO_NIGHT[] = "night";
const char CameraParameters::ISO_SPORTS[] = "sports";
const char CameraParameters::ISO_6400[] = "6400";
const char CameraParameters::ISO_3200[] = "3200";
const char CameraParameters::ISO_1600[] = "1600";
const char CameraParameters::ISO_800[] = "800";
const char CameraParameters::ISO_400[] = "400";
const char CameraParameters::ISO_200[] = "200";
const char CameraParameters::ISO_100[] = "100";
const char CameraParameters::ISO_80[] = "80";
const char CameraParameters::ISO_50[] = "50";
const char CameraParameters::KEY_SUPPORTED_METERING_MODE[] = "metering-values";
const char CameraParameters::METERING_CENTER[] = "center";
const char CameraParameters::METERING_MATRIX[] = "matrix";
const char CameraParameters::METERING_SPOT[] = "spot";
const char CameraParameters::METERING_OFF[] = "off";
const char CameraParameters::KEY_DYNAMIC_RANGE_CONTROL[] = "dynamic-range-control";
const char CameraParameters::KEY_SUPPORTED_PHASE_AF[] = "phase-af-values";
const char CameraParameters::KEY_PHASE_AF[] = "phase-af";
const char CameraParameters::KEY_SUPPORTED_RT_HDR[] = "rt-hdr-values";
const char CameraParameters::KEY_RT_HDR[] = "rt-hdr";
const char CameraParameters::KEY_ISO_MODE[] = "iso";
const char CameraParameters::KEY_SUPPORTED_ISO_MODES[] = "iso-values";

}  // namespace android
