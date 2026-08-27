/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef EXYNOS_CAMERA3_FRAME_FACTORY_PREVIEW_M86_H
#define EXYNOS_CAMERA3_FRAME_FACTORY_PREVIEW_M86_H

#include "ExynosCamera3FrameFactoryPreview.h"
#include "ExynosCamera3HwCapsM86.h"

namespace android {

/*
 * Product-owned entry point for the PRO 5 preview graph. The first bring-up
 * keeps the proven 34xx factory mechanics, while topology-affecting donor
 * branches are compiled out by M86_NATIVE_HAL3 in the platform patch.
 */
class ExynosCamera3FrameFactoryPreviewM86 final
    : public ExynosCamera3FrameFactoryPreview {
public:
    ExynosCamera3FrameFactoryPreviewM86(
        int cameraId, ExynosCamera3Parameters *parameters);
    virtual ~ExynosCamera3FrameFactoryPreviewM86() = default;

    virtual status_t create(bool active = true) override;
};

} // namespace android

#endif /* EXYNOS_CAMERA3_FRAME_FACTORY_PREVIEW_M86_H */
