/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 *
 * Native HAL3 topology overrides. Reuse the Exynos7420 Camera3 contract,
 * but do not inherit the S6 MCSC/VRA/HWFC assumptions on m86.
 */

#ifndef EXYNOS_CAMERA3_M86_CONFIG_H
#define EXYNOS_CAMERA3_M86_CONFIG_H

/*
 * Both m86 sensor modules transmit RAW10 over CSI, but the working 74xx HAL1
 * programs FLITE with the packed BG12 DMA contract. Select that product-proven
 * DMA packing before the shared Camera3 configuration is parsed.
 */
#ifndef CAMERA_PACKED_BAYER_ENABLE
#define CAMERA_PACKED_BAYER_ENABLE
#endif

/* Use the Exynos7420 Camera3 product contract from the 18camera branch.
 * This wrapper then removes blocks which do not exist in the m86 graph. */
#include "ExynosCamera3Config.h"

/* The m86 fimc-is2 metadata ABI predates camera2_uctl::opMode. */
#undef USE_FW_OPMODE

/* The HAL3 sources use the APP4 index directly. Their historical ExynosExif
 * include is not consistently visible through the mixed
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

/* I1C produces YUYV while the product JPEG encoder consumes the configured
 * JPEG input format.  Keep the proven 74xx software GSC conversion for both
 * IMX230 and OV5670 captures. */
#undef USE_GSC_FOR_CAPTURE_BACK
#define USE_GSC_FOR_CAPTURE_BACK (true)
#undef USE_GSC_FOR_CAPTURE_FRONT
#define USE_GSC_FOR_CAPTURE_FRONT (true)

/* Dirty Bayer is exported by 30C for the product-owned ISP reprocessing
 * graph.  It is never treated as an ISPC preview output. */
#undef USE_3AC_FOR_ISPC
#define USE_3AC_FOR_ISPC (false)

/* Both sensors use the 7420 dirty-Bayer ISP -> ISPC -> GSC -> JPEG route. */
#undef MAIN_CAMERA_SINGLE_REPROCESSING
#define MAIN_CAMERA_SINGLE_REPROCESSING (true)
#undef FRONT_CAMERA_SINGLE_REPROCESSING
#define FRONT_CAMERA_SINGLE_REPROCESSING (true)

/* The PRO 5 firmware expects the 3AA preview output to be BDS-sized before
 * entering the OTF ISP path. Keep this product-local; the legacy HAL1 config
 * remains unchanged. */
#undef CAMERA_HAS_OWN_BDS
#define CAMERA_HAS_OWN_BDS (true)

/* video150 is an always-present inline block on m86 even though Android HW
 * video stabilization is not exposed. */
#define M86_HAS_INLINE_DIS (true)
#define M86_SUPPORTS_HW_VDIS (false)
#define M86_HAS_VRA (false)
#define M86_HAS_HWFC (false)

/* common_v2 SensorInfo and the 74xx HAL3 core enter through different config
 * headers. Keep the queue contract visible through both include paths. */
#ifndef NUM_REQUEST_BLOCK_MAX
#define NUM_REQUEST_BLOCK_MAX 9
#endif
#ifndef NUM_REQUEST_BLOCK_MIN
#define NUM_REQUEST_BLOCK_MIN 6
#endif

#endif /* EXYNOS_CAMERA3_M86_CONFIG_H */
