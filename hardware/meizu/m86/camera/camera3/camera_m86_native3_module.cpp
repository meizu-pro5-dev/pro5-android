/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#define LOG_TAG "M86_NATIVE3_INTERFACE"

#include <algorithm>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <new>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <vector>

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

constexpr int kCameraCount = 2;
constexpr int kRearCameraId = 0;
constexpr int kFrontCameraId = 1;

pthread_mutex_t gLock = PTHREAD_MUTEX_INITIALIZER;
camera3_device_t *gDevice = nullptr;
camera_metadata_t *gEngineStaticInfo[kCameraCount] = {nullptr, nullptr};
camera_metadata_t *gPublicStaticInfo[kCameraCount] = {nullptr, nullptr};
const camera_module_callbacks_t *gCallbacks = nullptr;
uint64_t gGeneration = 0;
uint64_t gOpenGeneration = 0;
bool gTorchEnabled = false;

bool isValidCameraId(int cameraId)
{
    return cameraId >= 0 && cameraId < kCameraCount;
}

int parseCameraId(const char *id)
{
    if (id == nullptr || id[0] == '\0' || id[1] != '\0') {
        return -1;
    }

    const int cameraId = id[0] - '0';
    return isValidCameraId(cameraId) ? cameraId : -1;
}

int writeSysfs(const char *path, const char *value)
{
    const int fd = open(path, O_WRONLY | O_CLOEXEC);
    if (fd < 0) {
        return -errno;
    }

    const size_t length = strlen(value);
    const ssize_t written = write(fd, value, length);
    const int savedErrno = errno;
    close(fd);
    if (written == static_cast<ssize_t>(length)) {
        return 0;
    }
    return written < 0 ? -savedErrno : -EIO;
}

void notifyTorchStatus(torch_mode_status_t status)
{
    pthread_mutex_lock(&gLock);
    const camera_module_callbacks_t *callbacks = gCallbacks;
    pthread_mutex_unlock(&gLock);
    if (callbacks != nullptr && callbacks->torch_mode_status_change != nullptr) {
        callbacks->torch_mode_status_change(callbacks, "0", status);
    }
}

int buildConservativeStaticInfo(int cameraId)
{
    if (!isValidCameraId(cameraId)) {
        return -EINVAL;
    }
    if (gPublicStaticInfo[cameraId] != nullptr) {
        return 0;
    }
    if (gEngineStaticInfo[cameraId] == nullptr &&
        ExynosCamera3MetadataConverter::constructStaticInfo(
                cameraId, &gEngineStaticInfo[cameraId]) != NO_ERROR) {
        return -EINVAL;
    }

    CameraMetadata metadata;
    metadata = gEngineStaticInfo[cameraId];

    const int64_t preview4By3MinFrameDuration =
            cameraId == kFrontCameraId ? 33333333LL : 41666667LL;

    std::vector<int32_t> streamConfigs = {
        HAL_PIXEL_FORMAT_IMPLEMENTATION_DEFINED, 1920, 1080,
        ANDROID_SCALER_AVAILABLE_STREAM_CONFIGURATIONS_OUTPUT,
        HAL_PIXEL_FORMAT_IMPLEMENTATION_DEFINED, 1440, 1080,
        ANDROID_SCALER_AVAILABLE_STREAM_CONFIGURATIONS_OUTPUT,
        HAL_PIXEL_FORMAT_IMPLEMENTATION_DEFINED, 1280, 720,
        ANDROID_SCALER_AVAILABLE_STREAM_CONFIGURATIONS_OUTPUT,
        HAL_PIXEL_FORMAT_YCbCr_420_888, 1920, 1080,
        ANDROID_SCALER_AVAILABLE_STREAM_CONFIGURATIONS_OUTPUT,
        HAL_PIXEL_FORMAT_YCbCr_420_888, 1440, 1080,
        ANDROID_SCALER_AVAILABLE_STREAM_CONFIGURATIONS_OUTPUT,
        HAL_PIXEL_FORMAT_YCbCr_420_888, 1280, 720,
        ANDROID_SCALER_AVAILABLE_STREAM_CONFIGURATIONS_OUTPUT,
    };
    std::vector<int64_t> minFrameDurations = {
        HAL_PIXEL_FORMAT_IMPLEMENTATION_DEFINED, 1920, 1080, 33333333LL,
        HAL_PIXEL_FORMAT_IMPLEMENTATION_DEFINED, 1440, 1080,
        preview4By3MinFrameDuration,
        HAL_PIXEL_FORMAT_IMPLEMENTATION_DEFINED, 1280, 720, 33333333LL,
        HAL_PIXEL_FORMAT_YCbCr_420_888, 1920, 1080, 33333333LL,
        HAL_PIXEL_FORMAT_YCbCr_420_888, 1440, 1080,
        preview4By3MinFrameDuration,
        HAL_PIXEL_FORMAT_YCbCr_420_888, 1280, 720, 33333333LL,
    };
    std::vector<int64_t> stallDurations = {
        HAL_PIXEL_FORMAT_IMPLEMENTATION_DEFINED, 1920, 1080, 0,
        HAL_PIXEL_FORMAT_IMPLEMENTATION_DEFINED, 1440, 1080, 0,
        HAL_PIXEL_FORMAT_IMPLEMENTATION_DEFINED, 1280, 720, 0,
        HAL_PIXEL_FORMAT_YCbCr_420_888, 1920, 1080, 0,
        HAL_PIXEL_FORMAT_YCbCr_420_888, 1440, 1080, 0,
        HAL_PIXEL_FORMAT_YCbCr_420_888, 1280, 720, 0,
    };
    const int32_t rearJpegSizes[][2] = {
        {5312, 3984}, {5312, 2988}, {4160, 3120},
        {2656, 1992}, {1920, 1080},
    };
    const int32_t frontJpegSizes[][2] = {
        {2592, 1944}, {2592, 1458}, {1920, 1080}, {640, 480},
    };
    const int32_t (*jpegSizes)[2] = cameraId == kFrontCameraId
            ? frontJpegSizes : rearJpegSizes;
    const size_t jpegSizeCount = cameraId == kFrontCameraId
            ? sizeof(frontJpegSizes) / sizeof(frontJpegSizes[0])
            : sizeof(rearJpegSizes) / sizeof(rearJpegSizes[0]);
    for (size_t i = 0; i < jpegSizeCount; ++i) {
        streamConfigs.insert(streamConfigs.end(), {
            HAL_PIXEL_FORMAT_BLOB, jpegSizes[i][0], jpegSizes[i][1],
            ANDROID_SCALER_AVAILABLE_STREAM_CONFIGURATIONS_OUTPUT,
        });
        minFrameDurations.insert(minFrameDurations.end(), {
            HAL_PIXEL_FORMAT_BLOB, jpegSizes[i][0], jpegSizes[i][1],
            100000000LL,
        });
        stallDurations.insert(stallDurations.end(), {
            HAL_PIXEL_FORMAT_BLOB, jpegSizes[i][0], jpegSizes[i][1],
            500000000LL,
        });
    }
    const uint8_t capabilities[] = {
        ANDROID_REQUEST_AVAILABLE_CAPABILITIES_BACKWARD_COMPATIBLE,
    };
    const int32_t maxOutputStreams[] = {0, 2, 1};
    const int32_t maxInputStreams = 0;
    const int32_t partialResultCount = 1;
    const uint8_t pipelineDepth = 4;
    const uint8_t hardwareLevel = ANDROID_INFO_SUPPORTED_HARDWARE_LEVEL_LEGACY;
    const uint8_t flashAvailable = cameraId == kRearCameraId
            ? ANDROID_FLASH_INFO_AVAILABLE_TRUE
            : ANDROID_FLASH_INFO_AVAILABLE_FALSE;
    const float maxDigitalZoom = cameraId == kRearCameraId ? 8.0f : 4.0f;
    const int32_t rearMaxRegions[] = {1, 0, 1};
    const int32_t frontMaxRegions[] = {0, 0, 0};
    const uint8_t antibandingModes[] = {
        ANDROID_CONTROL_AE_ANTIBANDING_MODE_OFF,
        ANDROID_CONTROL_AE_ANTIBANDING_MODE_50HZ,
        ANDROID_CONTROL_AE_ANTIBANDING_MODE_60HZ,
        ANDROID_CONTROL_AE_ANTIBANDING_MODE_AUTO,
    };
    const uint8_t rearAeModes[] = {
        ANDROID_CONTROL_AE_MODE_OFF,
        ANDROID_CONTROL_AE_MODE_ON,
        ANDROID_CONTROL_AE_MODE_ON_AUTO_FLASH,
        ANDROID_CONTROL_AE_MODE_ON_ALWAYS_FLASH,
    };
    const uint8_t frontAeModes[] = {
        ANDROID_CONTROL_AE_MODE_OFF,
        ANDROID_CONTROL_AE_MODE_ON,
    };
    const uint8_t rearAfModes[] = {
        ANDROID_CONTROL_AF_MODE_OFF,
        ANDROID_CONTROL_AF_MODE_AUTO,
        ANDROID_CONTROL_AF_MODE_MACRO,
        ANDROID_CONTROL_AF_MODE_CONTINUOUS_VIDEO,
        ANDROID_CONTROL_AF_MODE_CONTINUOUS_PICTURE,
    };
    const uint8_t frontAfModes[] = {ANDROID_CONTROL_AF_MODE_OFF};
    const uint8_t awbModes[] = {
        ANDROID_CONTROL_AWB_MODE_OFF,
        ANDROID_CONTROL_AWB_MODE_AUTO,
        ANDROID_CONTROL_AWB_MODE_INCANDESCENT,
        ANDROID_CONTROL_AWB_MODE_FLUORESCENT,
        ANDROID_CONTROL_AWB_MODE_DAYLIGHT,
        ANDROID_CONTROL_AWB_MODE_CLOUDY_DAYLIGHT,
    };
    const uint8_t controlModes[] = {
        ANDROID_CONTROL_MODE_OFF,
        ANDROID_CONTROL_MODE_AUTO,
        ANDROID_CONTROL_MODE_USE_SCENE_MODE,
    };
    const uint8_t effectModes[] = {
        ANDROID_CONTROL_EFFECT_MODE_OFF,
        ANDROID_CONTROL_EFFECT_MODE_MONO,
        ANDROID_CONTROL_EFFECT_MODE_NEGATIVE,
        ANDROID_CONTROL_EFFECT_MODE_SEPIA,
        ANDROID_CONTROL_EFFECT_MODE_POSTERIZE,
        ANDROID_CONTROL_EFFECT_MODE_AQUA,
    };
    const uint8_t sceneModes[] = {
        ANDROID_CONTROL_SCENE_MODE_DISABLED,
        ANDROID_CONTROL_SCENE_MODE_FACE_PRIORITY,
        ANDROID_CONTROL_SCENE_MODE_ACTION,
        ANDROID_CONTROL_SCENE_MODE_PORTRAIT,
        ANDROID_CONTROL_SCENE_MODE_LANDSCAPE,
        ANDROID_CONTROL_SCENE_MODE_NIGHT,
        ANDROID_CONTROL_SCENE_MODE_NIGHT_PORTRAIT,
        ANDROID_CONTROL_SCENE_MODE_THEATRE,
        ANDROID_CONTROL_SCENE_MODE_BEACH,
        ANDROID_CONTROL_SCENE_MODE_SNOW,
        ANDROID_CONTROL_SCENE_MODE_SUNSET,
        ANDROID_CONTROL_SCENE_MODE_STEADYPHOTO,
        ANDROID_CONTROL_SCENE_MODE_FIREWORKS,
        ANDROID_CONTROL_SCENE_MODE_SPORTS,
        ANDROID_CONTROL_SCENE_MODE_PARTY,
        ANDROID_CONTROL_SCENE_MODE_CANDLELIGHT,
    };
    std::vector<uint8_t> sceneModeOverrides;
    sceneModeOverrides.reserve(sizeof(sceneModes) * 3);
    for (size_t i = 0; i < sizeof(sceneModes); ++i) {
        sceneModeOverrides.push_back(ANDROID_CONTROL_AE_MODE_ON);
        sceneModeOverrides.push_back(ANDROID_CONTROL_AWB_MODE_AUTO);
        sceneModeOverrides.push_back(cameraId == kRearCameraId
                ? ANDROID_CONTROL_AF_MODE_AUTO
                : ANDROID_CONTROL_AF_MODE_OFF);
    }
    const uint8_t stabilizationModes[] = {
        ANDROID_CONTROL_VIDEO_STABILIZATION_MODE_OFF,
    };
    const uint8_t faceDetectModes[] = {
        ANDROID_STATISTICS_FACE_DETECT_MODE_OFF,
        ANDROID_STATISTICS_FACE_DETECT_MODE_SIMPLE,
    };
    const int32_t maxFaceCount = 16;
    const int32_t thumbnailSizes[] = {0, 0};
    const int32_t exposureCompensationRange[] = {-4, 4};
    const camera_metadata_rational_t exposureCompensationStep = {1, 2};
    const uint8_t aeLockAvailable = ANDROID_CONTROL_AE_LOCK_AVAILABLE_TRUE;
    const uint8_t awbLockAvailable = ANDROID_CONTROL_AWB_LOCK_AVAILABLE_TRUE;

    std::vector<int32_t> requestKeys = {
        ANDROID_CONTROL_AE_ANTIBANDING_MODE,
        ANDROID_CONTROL_AE_EXPOSURE_COMPENSATION,
        ANDROID_CONTROL_AE_LOCK,
        ANDROID_CONTROL_AE_MODE,
        ANDROID_CONTROL_AE_PRECAPTURE_TRIGGER,
        ANDROID_CONTROL_AE_TARGET_FPS_RANGE,
        ANDROID_CONTROL_AF_MODE,
        ANDROID_CONTROL_AF_TRIGGER,
        ANDROID_CONTROL_AWB_LOCK,
        ANDROID_CONTROL_AWB_MODE,
        ANDROID_CONTROL_CAPTURE_INTENT,
        ANDROID_CONTROL_EFFECT_MODE,
        ANDROID_CONTROL_MODE,
        ANDROID_CONTROL_SCENE_MODE,
        ANDROID_CONTROL_VIDEO_STABILIZATION_MODE,
        ANDROID_JPEG_ORIENTATION,
        ANDROID_JPEG_QUALITY,
        ANDROID_JPEG_THUMBNAIL_QUALITY,
        ANDROID_JPEG_THUMBNAIL_SIZE,
        ANDROID_SCALER_CROP_REGION,
        ANDROID_STATISTICS_FACE_DETECT_MODE,
    };
    std::vector<int32_t> resultKeys = {
        ANDROID_CONTROL_AE_ANTIBANDING_MODE,
        ANDROID_CONTROL_AE_EXPOSURE_COMPENSATION,
        ANDROID_CONTROL_AE_LOCK,
        ANDROID_CONTROL_AE_MODE,
        ANDROID_CONTROL_AE_PRECAPTURE_TRIGGER,
        ANDROID_CONTROL_AE_TARGET_FPS_RANGE,
        ANDROID_CONTROL_AE_STATE,
        ANDROID_CONTROL_AF_MODE,
        ANDROID_CONTROL_AF_STATE,
        ANDROID_CONTROL_AF_TRIGGER,
        ANDROID_CONTROL_AWB_LOCK,
        ANDROID_CONTROL_AWB_MODE,
        ANDROID_CONTROL_AWB_STATE,
        ANDROID_CONTROL_CAPTURE_INTENT,
        ANDROID_CONTROL_EFFECT_MODE,
        ANDROID_CONTROL_MODE,
        ANDROID_CONTROL_SCENE_MODE,
        ANDROID_CONTROL_VIDEO_STABILIZATION_MODE,
        ANDROID_LENS_FOCAL_LENGTH,
        ANDROID_JPEG_ORIENTATION,
        ANDROID_JPEG_QUALITY,
        ANDROID_JPEG_SIZE,
        ANDROID_JPEG_THUMBNAIL_QUALITY,
        ANDROID_JPEG_THUMBNAIL_SIZE,
        ANDROID_REQUEST_PIPELINE_DEPTH,
        ANDROID_SCALER_CROP_REGION,
        ANDROID_SENSOR_TIMESTAMP,
        ANDROID_STATISTICS_FACE_DETECT_MODE,
        ANDROID_STATISTICS_FACE_IDS,
        ANDROID_STATISTICS_FACE_RECTANGLES,
        ANDROID_STATISTICS_FACE_SCORES,
    };
    if (cameraId == kRearCameraId) {
        requestKeys.insert(requestKeys.end(), {
            ANDROID_CONTROL_AE_REGIONS,
            ANDROID_CONTROL_AF_REGIONS,
            ANDROID_FLASH_MODE,
        });
        resultKeys.insert(resultKeys.end(), {
            ANDROID_CONTROL_AE_REGIONS,
            ANDROID_CONTROL_AF_REGIONS,
            ANDROID_FLASH_MODE,
            ANDROID_FLASH_STATE,
        });
    }
    std::sort(requestKeys.begin(), requestKeys.end());
    std::sort(resultKeys.begin(), resultKeys.end());

    metadata.update(ANDROID_SCALER_AVAILABLE_STREAM_CONFIGURATIONS,
                    streamConfigs.data(), streamConfigs.size());
    metadata.update(ANDROID_SCALER_AVAILABLE_MIN_FRAME_DURATIONS,
                    minFrameDurations.data(), minFrameDurations.size());
    metadata.update(ANDROID_SCALER_AVAILABLE_STALL_DURATIONS,
                    stallDurations.data(), stallDurations.size());
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
    metadata.update(ANDROID_CONTROL_MAX_REGIONS,
                    cameraId == kRearCameraId ? rearMaxRegions : frontMaxRegions,
                    3);
    metadata.update(ANDROID_CONTROL_AE_AVAILABLE_ANTIBANDING_MODES,
                    antibandingModes, sizeof(antibandingModes));
    metadata.update(ANDROID_CONTROL_AE_COMPENSATION_RANGE,
                    exposureCompensationRange, 2);
    metadata.update(ANDROID_CONTROL_AE_COMPENSATION_STEP,
                    &exposureCompensationStep, 1);
    metadata.update(ANDROID_CONTROL_AE_LOCK_AVAILABLE, &aeLockAvailable, 1);
    metadata.update(ANDROID_CONTROL_AWB_LOCK_AVAILABLE, &awbLockAvailable, 1);
    if (cameraId == kFrontCameraId) {
        metadata.update(ANDROID_CONTROL_AE_AVAILABLE_MODES,
                        frontAeModes, sizeof(frontAeModes));
    } else {
        metadata.update(ANDROID_CONTROL_AE_AVAILABLE_MODES,
                        rearAeModes, sizeof(rearAeModes));
    }
    if (cameraId == kFrontCameraId) {
        metadata.update(ANDROID_CONTROL_AF_AVAILABLE_MODES,
                        frontAfModes, sizeof(frontAfModes));
    } else {
        metadata.update(ANDROID_CONTROL_AF_AVAILABLE_MODES,
                        rearAfModes, sizeof(rearAfModes));
    }
    metadata.update(ANDROID_CONTROL_AWB_AVAILABLE_MODES, awbModes, sizeof(awbModes));
    metadata.update(ANDROID_CONTROL_AVAILABLE_MODES, controlModes, sizeof(controlModes));
    metadata.update(ANDROID_CONTROL_AVAILABLE_EFFECTS, effectModes, sizeof(effectModes));
    metadata.update(ANDROID_CONTROL_AVAILABLE_SCENE_MODES, sceneModes, sizeof(sceneModes));
    metadata.update(ANDROID_CONTROL_SCENE_MODE_OVERRIDES,
                    sceneModeOverrides.data(), sceneModeOverrides.size());
    metadata.update(ANDROID_CONTROL_AVAILABLE_VIDEO_STABILIZATION_MODES,
                    stabilizationModes, sizeof(stabilizationModes));
    metadata.update(ANDROID_STATISTICS_INFO_AVAILABLE_FACE_DETECT_MODES,
                    faceDetectModes, sizeof(faceDetectModes));
    metadata.update(ANDROID_STATISTICS_INFO_MAX_FACE_COUNT, &maxFaceCount, 1);
    metadata.update(ANDROID_JPEG_AVAILABLE_THUMBNAIL_SIZES, thumbnailSizes, 2);
    metadata.update(ANDROID_REQUEST_AVAILABLE_REQUEST_KEYS,
                    requestKeys.data(), requestKeys.size());
    metadata.update(ANDROID_REQUEST_AVAILABLE_RESULT_KEYS,
                    resultKeys.data(), resultKeys.size());
    metadata.sort();
    gPublicStaticInfo[cameraId] = metadata.release();
    return gPublicStaticInfo[cameraId] == nullptr ? -ENOMEM : 0;
}

ExynosCamera3 *engine(const camera3_device_t *dev)
{
    return dev == nullptr ? nullptr : static_cast<ExynosCamera3 *>(dev->priv);
}

int closeDevice(hw_device_t *device)
{
    if (device == nullptr) {
        return -EINVAL;
    }

    camera3_device_t *cameraDevice = reinterpret_cast<camera3_device_t *>(device);
    ExynosCamera3 *camera = engine(cameraDevice);
    const int cameraId = camera == nullptr ? -1 : camera->getCameraId();
    const uint64_t generation = gOpenGeneration;
    int ret = 0;

    ALOGI("close camera=%d pid=%d generation=%" PRIu64,
          cameraId, getpid(), generation);
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
    if (cameraId == kRearCameraId) {
        notifyTorchStatus(TORCH_MODE_STATUS_AVAILABLE_OFF);
    }
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
    const int validation = ExynosCamera3StreamRouterM86::validateConfiguration(
            camera->getCameraId(), config);
    if (validation != 0) {
        return validation;
    }
    const int ret = camera->configureStreams(config);
    ALOGI("M86_NATIVE3_GRAPH configure generation=%" PRIu64 " ret=%d",
          gOpenGeneration, ret);
    return ret == NO_ERROR ? 0 : (ret < 0 ? ret : -EINVAL);
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
    if (camera == nullptr || ExynosCamera3StreamRouterM86::validateRequest(
            camera->getCameraId(), request) != 0) {
        ALOGE("M86_NATIVE3_REQUEST reject generation=%" PRIu64, gOpenGeneration);
        return -EINVAL;
    }
    ALOGV("M86_NATIVE3_REQUEST generation=%" PRIu64 " frame=%u",
          gOpenGeneration, request->frame_number);
    const int ret = camera->processCaptureRequest(request);
    if (ret != NO_ERROR) {
        ALOGE("M86_NATIVE3_RESULT submit failed generation=%" PRIu64
              " frame=%u ret=%d", gOpenGeneration, request->frame_number, ret);
        return ret < 0 ? ret : -EINVAL;
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
    const int cameraId = parseCameraId(id);
    if (module == nullptr || device == nullptr || cameraId < 0) {
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
            new (std::nothrow) ExynosCamera3(
                    cameraId, &gEngineStaticInfo[cameraId]);
    if (cameraDevice->priv == nullptr) {
        free(cameraDevice);
        pthread_mutex_unlock(&gLock);
        return -ENOMEM;
    }

    gDevice = cameraDevice;
    gOpenGeneration = ++gGeneration;
    *device = &cameraDevice->common;
    pthread_mutex_unlock(&gLock);

    ALOGI("open camera=%d pid=%d generation=%" PRIu64,
          cameraId, getpid(), gOpenGeneration);
    if (cameraId == kRearCameraId) {
        notifyTorchStatus(TORCH_MODE_STATUS_NOT_AVAILABLE);
    }
    return 0;
}

int getNumberOfCameras()
{
    return kCameraCount;
}

int getCameraInfo(int cameraId, camera_info *info)
{
    if (!isValidCameraId(cameraId) || info == nullptr) {
        return -EINVAL;
    }
    if (buildConservativeStaticInfo(cameraId) != 0) {
        return -EINVAL;
    }
    memset(info, 0, sizeof(*info));
    info->facing = cameraId == kRearCameraId
            ? CAMERA_FACING_BACK : CAMERA_FACING_FRONT;
    info->orientation = cameraId == kRearCameraId ? 90 : 270;
    info->device_version = CAMERA_DEVICE_API_VERSION_3_2;
    info->static_camera_characteristics = gPublicStaticInfo[cameraId];
    info->resource_cost = 100;
    return 0;
}

int setCallbacks(const camera_module_callbacks_t *callbacks)
{
    pthread_mutex_lock(&gLock);
    gCallbacks = callbacks;
    const torch_mode_status_t status = gDevice != nullptr
            ? TORCH_MODE_STATUS_NOT_AVAILABLE
            : (gTorchEnabled ? TORCH_MODE_STATUS_AVAILABLE_ON
                             : TORCH_MODE_STATUS_AVAILABLE_OFF);
    pthread_mutex_unlock(&gLock);
    if (callbacks != nullptr && callbacks->torch_mode_status_change != nullptr) {
        callbacks->torch_mode_status_change(callbacks, "0", status);
    }
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

int setTorchMode(const char *cameraId, bool enabled)
{
    const int id = parseCameraId(cameraId);
    if (id < 0) {
        return -EINVAL;
    }
    if (id != kRearCameraId) {
        return -ENOSYS;
    }

    pthread_mutex_lock(&gLock);
    if (gDevice != nullptr) {
        pthread_mutex_unlock(&gLock);
        return -EBUSY;
    }
    pthread_mutex_unlock(&gLock);

    int ret = 0;
    if (enabled) {
        ret = writeSysfs("/sys/class/leds/torch0/hwen", "enable\n");
        if (ret == 0) {
            usleep(2000);
            ret = writeSysfs("/sys/class/leds/torch0/brightness", "50000\n");
        }
        if (ret == 0) {
            ret = writeSysfs("/sys/class/leds/torch1/brightness", "50000\n");
        }
        if (ret == 0) {
            usleep(10000);
            ret = writeSysfs("/sys/class/leds/torch0/enable", "enable\n");
        }
        if (ret == 0) {
            ret = writeSysfs("/sys/class/leds/torch1/enable", "enable\n");
        }
        if (ret == 0) {
            ret = writeSysfs("/sys/class/leds/torch0/onoff", "on\n");
        }
        if (ret != 0) {
            writeSysfs("/sys/class/leds/torch0/onoff", "off\n");
            writeSysfs("/sys/class/leds/torch0/enable", "disable\n");
            writeSysfs("/sys/class/leds/torch1/enable", "disable\n");
            writeSysfs("/sys/class/leds/torch0/hwen", "disable\n");
        }
    } else {
        ret = writeSysfs("/sys/class/leds/torch0/onoff", "off\n");
        const int torch0Ret =
                writeSysfs("/sys/class/leds/torch0/enable", "disable\n");
        const int torch1Ret =
                writeSysfs("/sys/class/leds/torch1/enable", "disable\n");
        usleep(2000);
        const int hwenRet =
                writeSysfs("/sys/class/leds/torch0/hwen", "disable\n");
        if (ret == 0) ret = torch0Ret;
        if (ret == 0) ret = torch1Ret;
        if (ret == 0) ret = hwenRet;
    }

    if (ret != 0) {
        ALOGE("set torch enabled=%d failed: %d", enabled, ret);
        return ret;
    }

    pthread_mutex_lock(&gLock);
    gTorchEnabled = enabled;
    pthread_mutex_unlock(&gLock);
    notifyTorchStatus(enabled ? TORCH_MODE_STATUS_AVAILABLE_ON
                              : TORCH_MODE_STATUS_AVAILABLE_OFF);
    return 0;
}

int initModule()
{
    ALOGI("module init dual-camera camera3.2 rear=IMX230 front=OV5670");
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
