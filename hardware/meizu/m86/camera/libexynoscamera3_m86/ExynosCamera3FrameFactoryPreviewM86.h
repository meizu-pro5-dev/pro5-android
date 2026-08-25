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
    virtual ExynosCameraFrame *createNewFrame(void) override;
    virtual ExynosCameraFrame *createNewFrame(uint32_t frameCount = 0) override;
    virtual status_t initPipes(void) override;
    virtual status_t preparePipes(void) override;
    virtual status_t startPipes(void) override;
    virtual status_t startInitialThreads(void) override;
    virtual status_t setStopFlag(void) override;
    virtual status_t stopPipes(void) override;

protected:
    virtual status_t m_fillNodeGroupInfo(ExynosCameraFrame *frame) override;
    virtual status_t m_setupConfig(void) override;
    virtual status_t m_setDeviceInfo(void) override;
    virtual status_t m_initPipes(void) override;

private:
    int resolveLeaderPipe(int pipeId) const;
};

} // namespace android

#endif /* EXYNOS_CAMERA3_FRAME_FACTORY_PREVIEW_M86_H */
