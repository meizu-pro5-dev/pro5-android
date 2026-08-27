/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 *
 * Native HAL3 topology overrides. Reuse the Exynos7420 Camera3 contract,
 * but do not inherit the S6 MCSC/VRA/HWFC assumptions on m86.
 */

#ifndef EXYNOS_CAMERA3_M86_CONFIG_H
#define EXYNOS_CAMERA3_M86_CONFIG_H

/* Use the Exynos7420 Camera3 product contract from the 18camera branch.
 * This wrapper then removes blocks which do not exist in the m86 graph. */
#include "ExynosCamera3Config.h"

/* The old 34xx HAL3 sources use the APP4 index directly.  Their historical
 * ExynosExif include is not consistently visible through the mixed
 * common_v2 include graph on Android 12, so keep the product contract local. */
#ifndef APP_MARKER_4
#define APP_MARKER_4 4
#endif

/* Keep the 7420 FHD camera table branch: common_v2 only includes the
 * product-added IMX230 LUT from that branch. This is independent of the
 * physical 2560x1440 panel mode. */
#undef CAMERA_LCD_SIZE
#define CAMERA_LCD_SIZE LCD_SIZE_1920_1080

#undef OWN_MCSC_HW
#define OWN_MCSC_HW (false)

#undef USE_JPEG_HWFC
#define USE_JPEG_HWFC (false)

#undef USE_YUV_REPROCESSING
#define USE_YUV_REPROCESSING (false)

#undef USE_YUV_REPROCESSING_FOR_THUMBNAIL
#define USE_YUV_REPROCESSING_FOR_THUMBNAIL (false)

/* First checkpoint is preview-only. Do not construct a donor reprocessing
 * graph until the m86 ISPC/GSC/JPEG route is implemented. */
#undef MAIN_CAMERA_SINGLE_REPROCESSING
#define MAIN_CAMERA_SINGLE_REPROCESSING (false)
#undef FRONT_CAMERA_SINGLE_REPROCESSING
#define FRONT_CAMERA_SINGLE_REPROCESSING (false)

/* video150 is an always-present inline block on m86 even though Android HW
 * video stabilization is not exposed. */
#define M86_HAS_INLINE_DIS (true)
#define M86_SUPPORTS_HW_VDIS (false)
#define M86_HAS_VRA (false)
#define M86_HAS_HWFC (false)

/* common_v2 SensorInfo includes ExynosCameraConfig.h directly, while the
 * 34xx engine includes ExynosCamera3Config.h. Keep the queue contract visible
 * through both historical include paths. */
#ifndef NUM_REQUEST_BLOCK_MAX
#define NUM_REQUEST_BLOCK_MAX 9
#endif
#ifndef NUM_REQUEST_BLOCK_MIN
#define NUM_REQUEST_BLOCK_MIN 6
#endif

#endif /* EXYNOS_CAMERA3_M86_CONFIG_H */
