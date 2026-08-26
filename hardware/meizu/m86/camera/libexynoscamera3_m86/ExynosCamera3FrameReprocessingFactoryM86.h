/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef EXYNOS_CAMERA3_FRAME_REPROCESSING_FACTORY_M86_H
#define EXYNOS_CAMERA3_FRAME_REPROCESSING_FACTORY_M86_H

#include "ExynosCamera3FrameFactory.h"
#include "ExynosCamera3HwCapsM86.h"

namespace android {

/* Exynos7420/m86 has no MCSC or HWFC capture block.  Dirty Bayer from 30C is
 * fed to the second ISP chain (I1S), emitted as YUYV by I1C, then converted
 * and encoded by the product GSC/JPEG pipes. */
class ExynosCamera3FrameReprocessingFactoryM86 final
    : public ExynosCamera3FrameFactory {
public:
    ExynosCamera3FrameReprocessingFactoryM86(
            int cameraId, ExynosCamera3Parameters *parameters);
    virtual ~ExynosCamera3FrameReprocessingFactoryM86();

    virtual status_t create(bool active = true) override;
    virtual ExynosCameraFrame *createNewFrame(uint32_t frameCount = 0) override;
    virtual status_t initPipes(void) override;
    virtual status_t preparePipes(void) override;
    virtual status_t startPipes(void) override;
    virtual status_t stopPipes(void) override;
    virtual status_t startInitialThreads(void) override;
    virtual status_t setStopFlag(void) override;
    virtual enum NODE_TYPE getNodeType(uint32_t pipeId) override;

protected:
    virtual status_t m_setupConfig(void) override;
    virtual status_t m_fillNodeGroupInfo(ExynosCameraFrame *frame) override;
};

} // namespace android

#endif /* EXYNOS_CAMERA3_FRAME_REPROCESSING_FACTORY_M86_H */
