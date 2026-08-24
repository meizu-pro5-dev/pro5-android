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

#include <camera/CameraMetadata.h>
#include <hardware/camera.h>
#include <hardware/camera3.h>
#include <log/log.h>
#include <system/camera_metadata.h>

#include "ExynosCamera3.h"
#include "ExynosCameraMetadataConverter.h"
#include "ExynosCamera3StreamRouterM86.h"

using android::ExynosCamera3;
using android::ExynosCamera3MetadataConverter;
using android::ExynosCamera3StreamRouterM86;
using android::CameraMetadata;
using android::NO_ERROR;

namespace {

constexpr int kCameraCount = 1;
constexpr int kRearCameraId = 0;

pthread_mutex_t gLock = PTHREAD_MUTEX_INITIALIZER;
camera3_device_t *gDevice = nullptr;
camera_metadata_t *gEngineStaticInfo = nullptr;
camera_metadata_t *gPublicStaticInfo = nullptr;
const camera_module_callbacks_t *gCallbacks = nullptr;
uint64_t gGeneration = 0;
uint64_t gOpenGeneration = 0;

int buildConservativeStaticInfo()
{
    if (gPublicStaticInfo != nullptr) {
        return 0;
    }
    if (gEngineStaticInfo == nullptr &&
        ExynosCamera3MetadataConverter::constructStaticInfo(
                kRearCameraId, &gEngineStaticInfo) != NO_ERROR) {
        return -EINVAL;
    }

    CameraMetadata metadata;
    metadata = gEngineStaticInfo;

    const int32_t streamConfigs[] = {
        HAL_PIXEL_FORMAT_IMPLEMENTATION_DEFINED, 1920, 1080,
        ANDROID_SCALER_AVAILABLE_STREAM_CONFIGURATIONS_OUTPUT,
        HAL_PIXEL_FORMAT_YCbCr_420_888, 1920, 1080,
        ANDROID_SCALER_AVAILABLE_STREAM_CONFIGURATIONS_OUTPUT,
    };
    const int64_t minFrameDurations[] = {
        HAL_PIXEL_FORMAT_IMPLEMENTATION_DEFINED, 1920, 1080, 33333333LL,
        HAL_PIXEL_FORMAT_YCbCr_420_888, 1920, 1080, 33333333LL,
    };
    const int64_t stallDurations[] = {
        HAL_PIXEL_FORMAT_IMPLEMENTATION_DEFINED, 1920, 1080, 0,
        HAL_PIXEL_FORMAT_YCbCr_420_888, 1920, 1080, 0,
    };
    const uint8_t capabilities[] = {
        ANDROID_REQUEST_AVAILABLE_CAPABILITIES_BACKWARD_COMPATIBLE,
    };
    const int32_t maxOutputStreams[] = {0, 1, 0};
    const int32_t maxInputStreams = 0;
    const int32_t partialResultCount = 1;
    const uint8_t pipelineDepth = 4;
    const uint8_t hardwareLevel = ANDROID_INFO_SUPPORTED_HARDWARE_LEVEL_LEGACY;
    const uint8_t flashAvailable = ANDROID_FLASH_INFO_AVAILABLE_FALSE;
    const float maxDigitalZoom = 1.0f;
    const int32_t maxRegions[] = {0, 0, 0};
    const uint8_t aeModes[] = {ANDROID_CONTROL_AE_MODE_ON};
    const uint8_t afModes[] = {ANDROID_CONTROL_AF_MODE_OFF};
    const uint8_t awbModes[] = {ANDROID_CONTROL_AWB_MODE_AUTO};
    const uint8_t controlModes[] = {ANDROID_CONTROL_MODE_AUTO};
    const uint8_t effectModes[] = {ANDROID_CONTROL_EFFECT_MODE_OFF};
    const uint8_t sceneModes[] = {ANDROID_CONTROL_SCENE_MODE_DISABLED};
    const uint8_t stabilizationModes[] = {
        ANDROID_CONTROL_VIDEO_STABILIZATION_MODE_OFF,
    };
    const uint8_t faceDetectModes[] = {ANDROID_STATISTICS_FACE_DETECT_MODE_OFF};
    const int32_t maxFaceCount = 0;
    const int32_t thumbnailSizes[] = {0, 0};

    const int32_t requestKeys[] = {
        ANDROID_CONTROL_AE_MODE,
        ANDROID_CONTROL_AE_TARGET_FPS_RANGE,
        ANDROID_CONTROL_AF_MODE,
        ANDROID_CONTROL_AWB_MODE,
        ANDROID_CONTROL_CAPTURE_INTENT,
        ANDROID_CONTROL_EFFECT_MODE,
        ANDROID_CONTROL_MODE,
        ANDROID_CONTROL_SCENE_MODE,
        ANDROID_CONTROL_VIDEO_STABILIZATION_MODE,
        ANDROID_SCALER_CROP_REGION,
        ANDROID_STATISTICS_FACE_DETECT_MODE,
    };
    const int32_t resultKeys[] = {
        ANDROID_CONTROL_AE_MODE,
        ANDROID_CONTROL_AE_STATE,
        ANDROID_CONTROL_AF_MODE,
        ANDROID_CONTROL_AF_STATE,
        ANDROID_CONTROL_AWB_MODE,
        ANDROID_CONTROL_AWB_STATE,
        ANDROID_CONTROL_MODE,
        ANDROID_LENS_FOCAL_LENGTH,
        ANDROID_REQUEST_PIPELINE_DEPTH,
        ANDROID_SCALER_CROP_REGION,
        ANDROID_SENSOR_TIMESTAMP,
        ANDROID_STATISTICS_FACE_DETECT_MODE,
    };

    metadata.update(ANDROID_SCALER_AVAILABLE_STREAM_CONFIGURATIONS,
                    streamConfigs, sizeof(streamConfigs) / sizeof(streamConfigs[0]));
    metadata.update(ANDROID_SCALER_AVAILABLE_MIN_FRAME_DURATIONS,
                    minFrameDurations,
                    sizeof(minFrameDurations) / sizeof(minFrameDurations[0]));
    metadata.update(ANDROID_SCALER_AVAILABLE_STALL_DURATIONS,
                    stallDurations, sizeof(stallDurations) / sizeof(stallDurations[0]));
    metadata.update(ANDROID_REQUEST_AVAILABLE_CAPABILITIES,
                    capabilities, sizeof(capabilities));
    metadata.update(ANDROID_REQUEST_MAX_NUM_OUTPUT_STREAMS,
                    maxOutputStreams,
                    sizeof(maxOutputStreams) / sizeof(maxOutputStreams[0]));
    metadata.update(ANDROID_REQUEST_MAX_NUM_INPUT_STREAMS, &maxInputStreams, 1);
    metadata.update(ANDROID_REQUEST_PARTIAL_RESULT_COUNT, &partialResultCount, 1);
    metadata.update(ANDROID_REQUEST_PIPELINE_MAX_DEPTH, &pipelineDepth, 1);
    metadata.update(ANDROID_INFO_SUPPORTED_HARDWARE_LEVEL, &hardwareLevel, 1);
    metadata.update(ANDROID_FLASH_INFO_AVAILABLE, &flashAvailable, 1);
    metadata.update(ANDROID_SCALER_AVAILABLE_MAX_DIGITAL_ZOOM, &maxDigitalZoom, 1);
    metadata.update(ANDROID_CONTROL_MAX_REGIONS, maxRegions, 3);
    metadata.update(ANDROID_CONTROL_AE_AVAILABLE_MODES, aeModes, sizeof(aeModes));
    metadata.update(ANDROID_CONTROL_AF_AVAILABLE_MODES, afModes, sizeof(afModes));
    metadata.update(ANDROID_CONTROL_AWB_AVAILABLE_MODES, awbModes, sizeof(awbModes));
    metadata.update(ANDROID_CONTROL_AVAILABLE_MODES, controlModes, sizeof(controlModes));
    metadata.update(ANDROID_CONTROL_AVAILABLE_EFFECTS, effectModes, sizeof(effectModes));
    metadata.update(ANDROID_CONTROL_AVAILABLE_SCENE_MODES, sceneModes, sizeof(sceneModes));
    metadata.update(ANDROID_CONTROL_AVAILABLE_VIDEO_STABILIZATION_MODES,
                    stabilizationModes, sizeof(stabilizationModes));
    metadata.update(ANDROID_STATISTICS_INFO_AVAILABLE_FACE_DETECT_MODES,
                    faceDetectModes, sizeof(faceDetectModes));
    metadata.update(ANDROID_STATISTICS_INFO_MAX_FACE_COUNT, &maxFaceCount, 1);
    metadata.update(ANDROID_JPEG_AVAILABLE_THUMBNAIL_SIZES, thumbnailSizes, 2);
    metadata.update(ANDROID_REQUEST_AVAILABLE_REQUEST_KEYS,
                    requestKeys, sizeof(requestKeys) / sizeof(requestKeys[0]));
    metadata.update(ANDROID_REQUEST_AVAILABLE_RESULT_KEYS,
                    resultKeys, sizeof(resultKeys) / sizeof(resultKeys[0]));
    metadata.sort();
    gPublicStaticInfo = metadata.release();
    return gPublicStaticInfo == nullptr ? -ENOMEM : 0;
}

ExynosCamera3 *engine(const camera3_device_t *dev)
{
    return dev == nullptr ? nullptr : static_cast<ExynosCamera3 *>(dev->priv);
}

bool parseRearId(const char *id)
{
    return id != nullptr && strcmp(id, "0") == 0;
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
    const int validation = ExynosCamera3StreamRouterM86::validateConfiguration(config);
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
    if (camera == nullptr || ExynosCamera3StreamRouterM86::validateRequest(request) != 0) {
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
    cameraDevice->priv =
            new (std::nothrow) ExynosCamera3(kRearCameraId, &gEngineStaticInfo);
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
    if (buildConservativeStaticInfo() != 0) {
        return -EINVAL;
    }
    memset(info, 0, sizeof(*info));
    info->facing = CAMERA_FACING_BACK;
    info->orientation = 90;
    info->device_version = CAMERA_DEVICE_API_VERSION_3_2;
    info->static_camera_characteristics = gPublicStaticInfo;
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
