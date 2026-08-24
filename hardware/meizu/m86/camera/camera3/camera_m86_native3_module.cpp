/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#define LOG_TAG "M86_NATIVE3_INTERFACE"

#include <errno.h>
#include <inttypes.h>
#include <new>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <hardware/camera.h>
#include <hardware/camera3.h>
#include <log/log.h>
#include <system/camera_metadata.h>

#include "ExynosCamera3.h"
#include "ExynosCameraMetadataConverter.h"

using android::ExynosCamera3;
using android::ExynosCamera3MetadataConverter;
using android::NO_ERROR;

namespace {

constexpr int kCameraCount = 1;
constexpr int kRearCameraId = 0;
constexpr uint32_t kPreviewWidth = 1920;
constexpr uint32_t kPreviewHeight = 1080;

pthread_mutex_t gLock = PTHREAD_MUTEX_INITIALIZER;
camera3_device_t *gDevice = nullptr;
camera_metadata_t *gStaticInfo = nullptr;
const camera_module_callbacks_t *gCallbacks = nullptr;
uint64_t gGeneration = 0;
uint64_t gOpenGeneration = 0;

ExynosCamera3 *engine(const camera3_device_t *dev)
{
    return dev == nullptr ? nullptr : static_cast<ExynosCamera3 *>(dev->priv);
}

bool parseRearId(const char *id)
{
    return id != nullptr && strcmp(id, "0") == 0;
}

int validateSinglePreviewConfiguration(
        const camera3_stream_configuration_t *config)
{
    if (config == nullptr || config->streams == nullptr || config->num_streams != 1) {
        ALOGE("M86_NATIVE3_GRAPH reject stream count=%u",
              config == nullptr ? 0 : config->num_streams);
        return -EINVAL;
    }

    const camera3_stream_t *stream = config->streams[0];
    if (stream == nullptr || stream->stream_type != CAMERA3_STREAM_OUTPUT) {
        ALOGE("M86_NATIVE3_GRAPH reject null/non-output stream");
        return -EINVAL;
    }
    if (stream->width != kPreviewWidth || stream->height != kPreviewHeight) {
        ALOGE("M86_NATIVE3_GRAPH reject size=%ux%u", stream->width, stream->height);
        return -EINVAL;
    }
    if (stream->format != HAL_PIXEL_FORMAT_IMPLEMENTATION_DEFINED &&
        stream->format != HAL_PIXEL_FORMAT_YCbCr_420_888) {
        ALOGE("M86_NATIVE3_GRAPH reject format=0x%x", stream->format);
        return -EINVAL;
    }

    ALOGI("M86_NATIVE3_GRAPH accept rear single stream %ux%u format=0x%x usage=0x%" PRIx64,
          stream->width, stream->height, stream->format,
          static_cast<uint64_t>(stream->usage));
    return 0;
}

int closeDevice(hw_device_t *device)
{
    if (device == nullptr) {
        return -EINVAL;
    }

    camera3_device_t *cameraDevice = reinterpret_cast<camera3_device_t *>(device);
    ExynosCamera3 *camera = engine(cameraDevice);
    const uint64_t generation = gOpenGeneration;
    int ret = 0;

    ALOGI("close camera=0 pid=%d generation=%" PRIu64, getpid(), generation);
    if (camera != nullptr) {
        const int releaseRet = camera->releaseDevice();
        if (releaseRet != NO_ERROR) {
            ALOGE("M86_NATIVE3_FLUSH release failed generation=%" PRIu64 " ret=%d",
                  generation, releaseRet);
            ret = -EINVAL;
        }
        delete camera;
        cameraDevice->priv = nullptr;
    }

    pthread_mutex_lock(&gLock);
    if (gDevice == cameraDevice) {
        gDevice = nullptr;
    }
    pthread_mutex_unlock(&gLock);

    free(cameraDevice);
    return ret;
}

int initialize(const camera3_device_t *dev,
               const camera3_callback_ops_t *callbacks)
{
    ExynosCamera3 *camera = engine(dev);
    if (camera == nullptr || callbacks == nullptr) {
        return -EINVAL;
    }
    ALOGI("initialize generation=%" PRIu64, gOpenGeneration);
    return camera->initilizeDevice(callbacks) == NO_ERROR ? 0 : -EINVAL;
}

int configureStreams(const camera3_device_t *dev,
                     camera3_stream_configuration_t *config)
{
    ExynosCamera3 *camera = engine(dev);
    if (camera == nullptr) {
        return -EINVAL;
    }
    const int validation = validateSinglePreviewConfiguration(config);
    if (validation != 0) {
        return validation;
    }
    const int ret = camera->configureStreams(config);
    ALOGI("M86_NATIVE3_GRAPH configure generation=%" PRIu64 " ret=%d",
          gOpenGeneration, ret);
    return ret == NO_ERROR ? 0 : -EINVAL;
}

int registerStreamBuffers(const camera3_device_t *dev,
                          const camera3_stream_buffer_set_t *buffers)
{
    ExynosCamera3 *camera = engine(dev);
    return camera != nullptr && camera->registerStreamBuffers(buffers) == NO_ERROR
            ? 0 : -EINVAL;
}

const camera_metadata_t *constructDefaultRequestSettings(
        const camera3_device_t *dev, int type)
{
    ExynosCamera3 *camera = engine(dev);
    camera_metadata_t *request = nullptr;
    if (camera == nullptr ||
        camera->construct_default_request_settings(&request, type) != NO_ERROR) {
        return nullptr;
    }
    return request;
}

int processCaptureRequest(const camera3_device_t *dev,
                          camera3_capture_request_t *request)
{
    ExynosCamera3 *camera = engine(dev);
    if (camera == nullptr || request == nullptr || request->num_output_buffers != 1 ||
        request->output_buffers == nullptr) {
        ALOGE("M86_NATIVE3_REQUEST reject generation=%" PRIu64, gOpenGeneration);
        return -EINVAL;
    }
    ALOGV("M86_NATIVE3_REQUEST generation=%" PRIu64 " frame=%u",
          gOpenGeneration, request->frame_number);
    const int ret = camera->processCaptureRequest(request);
    if (ret != NO_ERROR) {
        ALOGE("M86_NATIVE3_RESULT submit failed generation=%" PRIu64
              " frame=%u ret=%d", gOpenGeneration, request->frame_number, ret);
        return -EINVAL;
    }
    return 0;
}

void getMetadataVendorTagOps(const camera3_device_t *, vendor_tag_query_ops_t *ops)
{
    if (ops != nullptr) {
        memset(ops, 0, sizeof(*ops));
    }
}

void dumpDevice(const camera3_device_t *dev, int)
{
    ExynosCamera3 *camera = engine(dev);
    if (camera != nullptr) {
        camera->dump();
    }
}

int flushDevice(const camera3_device_t *dev)
{
    ExynosCamera3 *camera = engine(dev);
    if (camera == nullptr) {
        return -EINVAL;
    }
    ALOGI("M86_NATIVE3_FLUSH begin generation=%" PRIu64, gOpenGeneration);
    const int ret = camera->flush();
    ALOGI("M86_NATIVE3_FLUSH end generation=%" PRIu64 " ret=%d",
          gOpenGeneration, ret);
    return ret == NO_ERROR ? 0 : -EINVAL;
}

camera3_device_ops_t gDeviceOps = {
    .initialize = initialize,
    .configure_streams = configureStreams,
    .register_stream_buffers = registerStreamBuffers,
    .construct_default_request_settings = constructDefaultRequestSettings,
    .process_capture_request = processCaptureRequest,
    .get_metadata_vendor_tag_ops = getMetadataVendorTagOps,
    .dump = dumpDevice,
    .flush = flushDevice,
    .reserved = {nullptr},
};

int openDevice(const hw_module_t *module, const char *id, hw_device_t **device)
{
    if (module == nullptr || device == nullptr || !parseRearId(id)) {
        return -EINVAL;
    }

    pthread_mutex_lock(&gLock);
    if (gDevice != nullptr) {
        pthread_mutex_unlock(&gLock);
        return -EBUSY;
    }

    camera3_device_t *cameraDevice =
            static_cast<camera3_device_t *>(calloc(1, sizeof(*cameraDevice)));
    if (cameraDevice == nullptr) {
        pthread_mutex_unlock(&gLock);
        return -ENOMEM;
    }

    cameraDevice->common.tag = HARDWARE_DEVICE_TAG;
    cameraDevice->common.version = CAMERA_DEVICE_API_VERSION_3_2;
    cameraDevice->common.module = const_cast<hw_module_t *>(module);
    cameraDevice->common.close = closeDevice;
    cameraDevice->ops = &gDeviceOps;
    cameraDevice->priv = new (std::nothrow) ExynosCamera3(kRearCameraId, &gStaticInfo);
    if (cameraDevice->priv == nullptr) {
        free(cameraDevice);
        pthread_mutex_unlock(&gLock);
        return -ENOMEM;
    }

    gDevice = cameraDevice;
    gOpenGeneration = ++gGeneration;
    *device = &cameraDevice->common;
    pthread_mutex_unlock(&gLock);

    ALOGI("open camera=0 pid=%d generation=%" PRIu64, getpid(), gOpenGeneration);
    return 0;
}

int getNumberOfCameras()
{
    return kCameraCount;
}

int getCameraInfo(int cameraId, camera_info *info)
{
    if (cameraId != kRearCameraId || info == nullptr) {
        return -EINVAL;
    }
    if (gStaticInfo == nullptr &&
        ExynosCamera3MetadataConverter::constructStaticInfo(cameraId, &gStaticInfo) != NO_ERROR) {
        return -EINVAL;
    }
    memset(info, 0, sizeof(*info));
    info->facing = CAMERA_FACING_BACK;
    info->orientation = 90;
    info->device_version = CAMERA_DEVICE_API_VERSION_3_2;
    info->static_camera_characteristics = gStaticInfo;
    info->resource_cost = 100;
    return 0;
}

int setCallbacks(const camera_module_callbacks_t *callbacks)
{
    pthread_mutex_lock(&gLock);
    gCallbacks = callbacks;
    pthread_mutex_unlock(&gLock);
    return 0;
}

void getVendorTagOps(vendor_tag_ops_t *ops)
{
    if (ops != nullptr) {
        memset(ops, 0, sizeof(*ops));
    }
}

int openLegacy(const hw_module_t *, const char *, uint32_t, hw_device_t **)
{
    return -EOPNOTSUPP;
}

int setTorchMode(const char *cameraId, bool)
{
    return parseRearId(cameraId) ? -ENOSYS : -EINVAL;
}

int initModule()
{
    ALOGI("module init rear-only camera3.2");
    return 0;
}

hw_module_methods_t gModuleMethods = {
    .open = openDevice,
};

} // namespace

extern "C" camera_module_t HAL_MODULE_INFO_SYM = {
    .common = {
        .tag = HARDWARE_MODULE_TAG,
        .module_api_version = CAMERA_MODULE_API_VERSION_2_4,
        .hal_api_version = HARDWARE_HAL_API_VERSION,
        .id = CAMERA_HARDWARE_MODULE_ID,
        .name = "Meizu PRO 5 native Exynos Camera3 HAL",
        .author = "The LineageOS Project",
        .methods = &gModuleMethods,
        .dso = nullptr,
        .reserved = {0},
    },
    .get_number_of_cameras = getNumberOfCameras,
    .get_camera_info = getCameraInfo,
    .set_callbacks = setCallbacks,
    .get_vendor_tag_ops = getVendorTagOps,
    .open_legacy = openLegacy,
    .set_torch_mode = setTorchMode,
    .init = initModule,
    .reserved = {nullptr},
};
