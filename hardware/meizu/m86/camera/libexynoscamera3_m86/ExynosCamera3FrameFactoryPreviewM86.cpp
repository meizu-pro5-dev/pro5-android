/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#define LOG_TAG "ExynosCamera3FactoryM86"
#include <cutils/log.h>

#include "ExynosCamera3FrameFactoryPreviewM86.h"

namespace android {

ExynosCamera3FrameFactoryPreviewM86::ExynosCamera3FrameFactoryPreviewM86(
    int cameraId, ExynosCamera3Parameters *parameters)
    : ExynosCamera3FrameFactoryPreview(cameraId, parameters)
{
}

status_t ExynosCamera3FrameFactoryPreviewM86::create(bool active)
{
    static_assert(!ExynosCamera3HwCapsM86::hasMcsc,
                  "m86 must not instantiate MCSC");
    static_assert(!ExynosCamera3HwCapsM86::hasVra,
                  "m86 must not instantiate VRA");
    static_assert(!ExynosCamera3HwCapsM86::hasHwfc,
                  "m86 must not instantiate HWFC");
    static_assert(ExynosCamera3HwCapsM86::previewOutputPipe == PIPE_SCP,
                  "m86 preview output must be SCP");

    ALOGI("create rear graph SS0->30S->I0S->DIS->SCP active=%d", active);
    return ExynosCamera3FrameFactoryPreview::create(active);
}

} // namespace android
