/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#define LOG_TAG "M86_NATIVE3_GRAPH"

#include "ExynosCamera3StreamRouterM86.h"

#include <errno.h>
#include <inttypes.h>
#include <log/log.h>
#include <system/graphics.h>

namespace android {

namespace {
constexpr uint32_t kPreviewWidth = 1920;
constexpr uint32_t kPreviewHeight = 1080;
constexpr uint32_t kPreview43Width = 1440;
constexpr uint32_t kPreview43Height = 1080;
constexpr uint32_t kVideo720Width = 1280;
constexpr uint32_t kVideo720Height = 720;
constexpr uint32_t kRearJpegWidth = 4608;
constexpr uint32_t kRearJpegHeight = 2592;
constexpr uint32_t kFrontJpegWidth = 2560;
constexpr uint32_t kFrontJpegHeight = 1440;

bool isProcessedSize(uint32_t width, uint32_t height)
{
    return (width == kPreviewWidth && height == kPreviewHeight) ||
           (width == kPreview43Width && height == kPreview43Height) ||
           (width == kVideo720Width && height == kVideo720Height);
}
}

ExynosCamera3StreamRouterM86::StreamRole
ExynosCamera3StreamRouterM86::classify(
        int cameraId, const camera3_stream_t *stream)
{
    if (stream == nullptr || stream->stream_type != CAMERA3_STREAM_OUTPUT) {
        return ROLE_INVALID;
    }

    if (stream->format == HAL_PIXEL_FORMAT_BLOB) {
        const bool rear = cameraId == 0 &&
                stream->width == kRearJpegWidth &&
                stream->height == kRearJpegHeight;
        const bool front = cameraId == 1 &&
                stream->width == kFrontJpegWidth &&
                stream->height == kFrontJpegHeight;
        return rear || front ? ROLE_JPEG : ROLE_INVALID;
    }

    if (!isProcessedSize(stream->width, stream->height))
        return ROLE_INVALID;

    if ((stream->usage & GRALLOC_USAGE_HW_VIDEO_ENCODER) != 0 &&
        stream->format == HAL_PIXEL_FORMAT_IMPLEMENTATION_DEFINED) {
        return ROLE_VIDEO;
    }

    if (stream->format == HAL_PIXEL_FORMAT_YCbCr_420_888)
        return ROLE_CALLBACK;

    const uint64_t previewUsage = GRALLOC_USAGE_HW_TEXTURE |
                                  GRALLOC_USAGE_HW_COMPOSER;
    if (stream->format == HAL_PIXEL_FORMAT_IMPLEMENTATION_DEFINED &&
        (stream->usage & previewUsage) != 0) {
        return ROLE_PREVIEW;
    }

    return ROLE_INVALID;
}

int ExynosCamera3StreamRouterM86::validateConfiguration(
        int cameraId,
        const camera3_stream_configuration_t *configuration)
{
    if (configuration == nullptr || configuration->streams == nullptr ||
        configuration->num_streams < 1 || configuration->num_streams > 3 ||
        (cameraId != 0 && cameraId != 1)) {
        ALOGE("reject stream count=%u",
              configuration == nullptr ? 0 : configuration->num_streams);
        return -EINVAL;
    }

    unsigned int processedCount = 0;
    unsigned int jpegCount = 0;
    bool roles[ROLE_JPEG + 1] = {false};
    for (uint32_t i = 0; i < configuration->num_streams; ++i) {
        const camera3_stream_t *stream = configuration->streams[i];
        const StreamRole role = classify(cameraId, stream);
        if (role == ROLE_INVALID || roles[role]) {
            ALOGE("reject camera=%d index=%u role=%d type=%d size=%ux%u "
                  "format=0x%x usage=0x%" PRIx64,
                  cameraId, i, role,
                  stream == nullptr ? -1 : stream->stream_type,
                  stream == nullptr ? 0 : stream->width,
                  stream == nullptr ? 0 : stream->height,
                  stream == nullptr ? 0 : stream->format,
                  stream == nullptr ? 0 : static_cast<uint64_t>(stream->usage));
            return -EINVAL;
        }

        roles[role] = true;
        if (role == ROLE_JPEG)
            ++jpegCount;
        else
            ++processedCount;
    }

    if (processedCount < 1 || processedCount > 2 || jpegCount > 1) {
        ALOGE("reject camera=%d processed=%u jpeg=%u",
              cameraId, processedCount, jpegCount);
        return -EINVAL;
    }

    ALOGI("accept camera=%d streams=%u processed=%u jpeg=%u",
          cameraId, configuration->num_streams, processedCount, jpegCount);
    return 0;
}

int ExynosCamera3StreamRouterM86::validateRequest(
        int cameraId, const camera3_capture_request_t *request)
{
    if (request == nullptr || request->output_buffers == nullptr ||
        request->num_output_buffers < 1 || request->num_output_buffers > 3 ||
        request->input_buffer != nullptr) {
        ALOGE("reject request frame=%u outputs=%u input=%p",
              request == nullptr ? 0 : request->frame_number,
              request == nullptr ? 0 : request->num_output_buffers,
              request == nullptr ? nullptr : request->input_buffer);
        return -EINVAL;
    }

    unsigned int processedCount = 0;
    unsigned int jpegCount = 0;
    for (uint32_t i = 0; i < request->num_output_buffers; ++i) {
        const camera3_stream_buffer_t &output = request->output_buffers[i];
        const StreamRole role = classify(cameraId, output.stream);
        if (role == ROLE_INVALID || output.buffer == nullptr) {
            ALOGE("reject output camera=%d frame=%u index=%u role=%d "
                  "stream=%p buffer=%p",
                  cameraId, request->frame_number, i, role,
                  output.stream, output.buffer);
            return -EINVAL;
        }
        if (role == ROLE_JPEG)
            ++jpegCount;
        else
            ++processedCount;
    }
    if (processedCount > 2 || jpegCount > 1) {
        ALOGE("reject request camera=%d frame=%u processed=%u jpeg=%u",
              cameraId, request->frame_number, processedCount, jpegCount);
        return -EINVAL;
    }
    return 0;
}

} // namespace android
