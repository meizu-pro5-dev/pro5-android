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
}

bool ExynosCamera3StreamRouterM86::isStage1Output(
        const camera3_stream_t *stream)
{
    return stream != nullptr &&
           stream->stream_type == CAMERA3_STREAM_OUTPUT &&
           stream->width == kPreviewWidth &&
           stream->height == kPreviewHeight &&
           (stream->format == HAL_PIXEL_FORMAT_IMPLEMENTATION_DEFINED ||
            stream->format == HAL_PIXEL_FORMAT_YCbCr_420_888);
}

int ExynosCamera3StreamRouterM86::validateConfiguration(
        const camera3_stream_configuration_t *configuration)
{
    if (configuration == nullptr || configuration->streams == nullptr ||
        configuration->num_streams != 1) {
        ALOGE("reject stream count=%u",
              configuration == nullptr ? 0 : configuration->num_streams);
        return -EINVAL;
    }

    const camera3_stream_t *stream = configuration->streams[0];
    if (!isStage1Output(stream)) {
        ALOGE("reject type=%d size=%ux%u format=0x%x",
              stream == nullptr ? -1 : stream->stream_type,
              stream == nullptr ? 0 : stream->width,
              stream == nullptr ? 0 : stream->height,
              stream == nullptr ? 0 : stream->format);
        return -EINVAL;
    }

    ALOGI("accept SCP preview %ux%u format=0x%x usage=0x%" PRIx64,
          stream->width, stream->height, stream->format,
          static_cast<uint64_t>(stream->usage));
    return 0;
}

int ExynosCamera3StreamRouterM86::validateRequest(
        const camera3_capture_request_t *request)
{
    if (request == nullptr || request->output_buffers == nullptr ||
        request->num_output_buffers != 1 || request->input_buffer != nullptr) {
        ALOGE("reject request frame=%u outputs=%u input=%p",
              request == nullptr ? 0 : request->frame_number,
              request == nullptr ? 0 : request->num_output_buffers,
              request == nullptr ? nullptr : request->input_buffer);
        return -EINVAL;
    }

    const camera3_stream_buffer_t &output = request->output_buffers[0];
    if (!isStage1Output(output.stream) || output.buffer == nullptr) {
        ALOGE("reject output frame=%u stream=%p buffer=%p",
              request->frame_number, output.stream, output.buffer);
        return -EINVAL;
    }
    return 0;
}

} // namespace android
