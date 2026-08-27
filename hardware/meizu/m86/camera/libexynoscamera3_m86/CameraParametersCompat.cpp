/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 *
 * Android 12 no longer exports a few legacy CameraParameters constants used
 * by the published SLSI Camera3 source.  Keep the compatibility definitions
 * private to the m86 native Camera3 engine.
 */

#include <camera/CameraParameters.h>

namespace android {

const char CameraParameters::PIXEL_FORMAT_YUV420SP_NV21[] = "yuv420sp_nv21";

} // namespace android
