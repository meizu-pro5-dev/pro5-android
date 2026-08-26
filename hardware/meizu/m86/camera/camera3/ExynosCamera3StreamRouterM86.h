/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef EXYNOS_CAMERA3_STREAM_ROUTER_M86_H
#define EXYNOS_CAMERA3_STREAM_ROUTER_M86_H

#include <hardware/camera3.h>

namespace android {

class ExynosCamera3StreamRouterM86 final {
public:
    static int validateConfiguration(
            int cameraId,
            const camera3_stream_configuration_t *configuration);
    static int validateRequest(
            int cameraId, const camera3_capture_request_t *request);

private:
    enum StreamRole {
        ROLE_INVALID = 0,
        ROLE_PREVIEW,
        ROLE_VIDEO,
        ROLE_CALLBACK,
        ROLE_JPEG,
    };

    static StreamRole classify(int cameraId, const camera3_stream_t *stream);
};

} // namespace android

#endif // EXYNOS_CAMERA3_STREAM_ROUTER_M86_H
