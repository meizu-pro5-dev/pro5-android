/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#define LOG_TAG "ExynosCamera3SensorInfoM86"
#include <cutils/log.h>

#include "ExynosCamera3SensorInfo.h"
#include "ExynosCameraAvailabilityTable.h"

namespace android {

bool needGSCForCapture(int camId)
{
    return camId == CAMERA_ID_BACK ? USE_GSC_FOR_CAPTURE_BACK
                                    : USE_GSC_FOR_CAPTURE_FRONT;
}

static int m86RearPreviewLut[][SIZE_OF_LUT] = {
    {SIZE_RATIO_16_9, 5328, 3000, 5328, 3000,
     5316, 2990, 1920, 1080, 1920, 1080},
    {SIZE_RATIO_4_3, 5344, 4016, 5344, 4016,
     5328, 3996, 1440, 1080, 1440, 1080},
};

static int m86RearPictureLut[][SIZE_OF_LUT] = {
    {SIZE_RATIO_4_3, 5344, 4016, 5344, 4016,
     5328, 3996, 4608, 3456, 4608, 3456},
    {SIZE_RATIO_16_9, 5328, 3000, 5328, 3000,
     5316, 2990, 4608, 2592, 4608, 2592},
};

static int m86FrontPreviewLut[][SIZE_OF_LUT] = {
    {SIZE_RATIO_16_9, 2592, 1944, 2592, 1944,
     2560, 1440, 2560, 1440, 1920, 1080},
    {SIZE_RATIO_4_3, 2592, 1944, 2592, 1944,
     2576, 1932, 2576, 1932, 1440, 1080},
};

static int m86RearPreviewList[][SIZE_OF_RESOLUTION] = {
    {1920, 1080, SIZE_RATIO_16_9},
    {1440, 1080, SIZE_RATIO_4_3},
};

static int m86RearPictureList[][SIZE_OF_RESOLUTION] = {
    {4608, 3456, SIZE_RATIO_4_3},
    {4608, 2592, SIZE_RATIO_16_9},
};

static int m86FrontPreviewList[][SIZE_OF_RESOLUTION] = {
    {1920, 1080, SIZE_RATIO_16_9},
    {1440, 1080, SIZE_RATIO_4_3},
};

static int m86FrontPictureList[][SIZE_OF_RESOLUTION] = {
    {2560, 1440, SIZE_RATIO_16_9},
};

static int m86VideoList[][SIZE_OF_RESOLUTION] = {
    {1920, 1080, SIZE_RATIO_16_9},
    {1280, 720, SIZE_RATIO_16_9},
};

static int m86ThumbnailList[][SIZE_OF_RESOLUTION] = {
    {0, 0, SIZE_RATIO_1_1},
};

static int m86FpsList[][2] = {
    {15000, 30000},
    {30000, 30000},
};

static uint8_t m86Capabilities[] = {
    ANDROID_REQUEST_AVAILABLE_CAPABILITIES_BACKWARD_COMPATIBLE,
};

static uint8_t m86FaceDetectModes[] = {
    ANDROID_STATISTICS_FACE_DETECT_MODE_OFF,
};

static void initM86StaticMetadata(ExynosSensorInfoBase *info, bool front)
{
    info->minFps = 15;
    info->maxFps = 30;
    info->supportedHwLevel = ANDROID_INFO_SUPPORTED_HARDWARE_LEVEL_LEGACY;
    info->lensFacing = front ? ANDROID_LENS_FACING_FRONT
                             : ANDROID_LENS_FACING_BACK;
    info->orientation = front ? FRONT_ROTATION : BACK_ROTATION;

    info->capabilities = m86Capabilities;
    info->capabilitiesLength = ARRAY_LENGTH(m86Capabilities);
    info->requestKeys = AVAILABLE_REQUEST_KEYS_LEGACY;
    info->requestKeysLength = ARRAY_LENGTH(AVAILABLE_REQUEST_KEYS_LEGACY);
    info->resultKeys = AVAILABLE_RESULT_KEYS_LEGACY;
    info->resultKeysLength = ARRAY_LENGTH(AVAILABLE_RESULT_KEYS_LEGACY);
    info->characteristicsKeys = AVAILABLE_CHARACTERISTICS_KEYS_LEGACY;
    info->characteristicsKeysLength = ARRAY_LENGTH(AVAILABLE_CHARACTERISTICS_KEYS_LEGACY);

    info->colorAberrationModes = AVAILABLE_COLOR_CORRECTION_ABERRATION_MODES;
    info->colorAberrationModesLength = ARRAY_LENGTH(AVAILABLE_COLOR_CORRECTION_ABERRATION_MODES);
    info->antiBandingModes = AVAILABLE_ANTIBANDING_MODES;
    info->antiBandingModesLength = ARRAY_LENGTH(AVAILABLE_ANTIBANDING_MODES);
    info->aeModes = front ? AVAILABLE_AE_MODES_FRONT : AVAILABLE_AE_MODES_BACK;
    info->aeModesLength = front ? ARRAY_LENGTH(AVAILABLE_AE_MODES_FRONT)
                                : ARRAY_LENGTH(AVAILABLE_AE_MODES_BACK);
    info->afModes = front ? AVAILABLE_AF_MODES_FRONT : AVAILABLE_AF_MODES_BACK;
    info->afModesLength = front ? ARRAY_LENGTH(AVAILABLE_AF_MODES_FRONT)
                                : ARRAY_LENGTH(AVAILABLE_AF_MODES_BACK);
    info->effectModes = AVAILABLE_EFFECT_MODES;
    info->effectModesLength = ARRAY_LENGTH(AVAILABLE_EFFECT_MODES);
    info->sceneModes = AVAILABLE_SCENE_MODES;
    info->sceneModesLength = ARRAY_LENGTH(AVAILABLE_SCENE_MODES);
    info->videoStabilizationModes = AVAILABLE_VIDEO_STABILIZATION_MODES;
    info->videoStabilizationModesLength = ARRAY_LENGTH(AVAILABLE_VIDEO_STABILIZATION_MODES);
    info->awbModes = AVAILABLE_AWB_MODES;
    info->awbModesLength = ARRAY_LENGTH(AVAILABLE_AWB_MODES);
    info->controlModes = AVAILABLE_CONTROL_MODES;
    info->controlModesLength = ARRAY_LENGTH(AVAILABLE_CONTROL_MODES);
    info->sceneModeOverrides = SCENE_MODE_OVERRIDES;
    info->sceneModeOverridesLength = ARRAY_LENGTH(SCENE_MODE_OVERRIDES);
    info->max3aRegions[AE] = 1;
    info->max3aRegions[AWB] = 0;
    info->max3aRegions[AF] = front ? 0 : 1;

    info->edgeModes = AVAILABLE_EDGE_MODES;
    info->edgeModesLength = ARRAY_LENGTH(AVAILABLE_EDGE_MODES);
    info->hotPixelModes = AVAILABLE_HOT_PIXEL_MODES;
    info->hotPixelModesLength = ARRAY_LENGTH(AVAILABLE_HOT_PIXEL_MODES);
    info->noiseReductionModes = AVAILABLE_NOISE_REDUCTION_MODES;
    info->noiseReductionModesLength = ARRAY_LENGTH(AVAILABLE_NOISE_REDUCTION_MODES);
    info->opticalStabilization = AVAILABLE_OPTICAL_STABILIZATION;
    info->opticalStabilizationLength = ARRAY_LENGTH(AVAILABLE_OPTICAL_STABILIZATION);
    info->faceDetectModes = m86FaceDetectModes;
    info->faceDetectModesLength = ARRAY_LENGTH(m86FaceDetectModes);
    info->maxNumDetectedFaces = 0;
    info->testPatternModes = AVAILABLE_TEST_PATTERN_MODES;
    info->testPatternModesLength = ARRAY_LENGTH(AVAILABLE_TEST_PATTERN_MODES);
    info->hotPixelMapModes = AVAILABLE_HOT_PIXEL_MAP_MODES;
    info->hotPixelMapModesLength = ARRAY_LENGTH(AVAILABLE_HOT_PIXEL_MAP_MODES);
    info->toneMapModes = AVAILABLE_TONE_MAP_MODES;
    info->toneMapModesLength = ARRAY_LENGTH(AVAILABLE_TONE_MAP_MODES);
    info->leds = AVAILABLE_LEDS;
    info->ledsLength = ARRAY_LENGTH(AVAILABLE_LEDS);

    info->maxNumOutputStreams[RAW] = 0;
    info->maxNumOutputStreams[PROCESSED] = 1;
    info->maxNumOutputStreams[PROCESSED_STALL] = 0;
    info->maxNumInputStreams = 0;
    info->maxPipelineDepth = 4;
    info->partialResultCount = 1;
    info->zoomSupport = false;
    info->smoothZoomSupport = false;
    info->maxZoomLevel = 0;
    info->maxZoomRatio = 1000;
    info->croppingType = ANDROID_SCALER_CROPPING_TYPE_CENTER_ONLY;
    info->stallDurations = NULL;
    info->stallDurationsLength = 0;
    info->videoStabilizationSupport = false;
}

ExynosCamera3SensorIMX230M86::ExynosCamera3SensorIMX230M86()
    : ExynosCamera3SensorInfoBase()
{
    maxPreviewW = 1920;
    maxPreviewH = 1080;
    maxPictureW = 4608;
    maxPictureH = 3456;
    maxVideoW = 1920;
    maxVideoH = 1080;
    maxSensorW = 5344;
    maxSensorH = 4016;
    sensorMarginW = 16;
    sensorMarginH = 10;
    fNumberNum = 22;
    fNumberDen = 10;
    focalLengthNum = 473;
    focalLengthDen = 100;
    aperture = 2.2f;
    fNumber = 2.2f;
    focalLength = 4.73f;
    minimumFocusDistance = 10.0f;
    flashAvailable = ANDROID_FLASH_INFO_AVAILABLE_TRUE;

    previewSizeLut = m86RearPreviewLut;
    previewSizeLutMax = ARRAY_LENGTH(m86RearPreviewLut);
    pictureSizeLut = m86RearPictureLut;
    pictureSizeLutMax = ARRAY_LENGTH(m86RearPictureLut);
    videoSizeLut = m86RearPreviewLut;
    videoSizeLutMax = ARRAY_LENGTH(m86RearPreviewLut);
    sizeTableSupport = true;

    rearPreviewList = m86RearPreviewList;
    rearPreviewListMax = ARRAY_LENGTH(m86RearPreviewList);
    rearPictureList = m86RearPictureList;
    rearPictureListMax = ARRAY_LENGTH(m86RearPictureList);
    rearVideoList = m86VideoList;
    rearVideoListMax = ARRAY_LENGTH(m86VideoList);
    rearFPSList = m86FpsList;
    rearFPSListMax = ARRAY_LENGTH(m86FpsList);
    thumbnailList = m86ThumbnailList;
    thumbnailListMax = ARRAY_LENGTH(m86ThumbnailList);

    initM86StaticMetadata(this, false);
}

ExynosCamera3SensorOV5670M86::ExynosCamera3SensorOV5670M86()
    : ExynosCamera3SensorOV5670Base()
{
    maxPreviewW = 1920;
    maxPreviewH = 1080;
    maxPictureW = 2560;
    maxPictureH = 1440;
    maxVideoW = 1920;
    maxVideoH = 1080;
    maxSensorW = 2592;
    maxSensorH = 1944;
    sensorMarginW = 0;
    sensorMarginH = 0;
    sensorMarginBase[LEFT_BASE] = 0;
    sensorMarginBase[TOP_BASE] = 0;
    sensorMarginBase[WIDTH_BASE] = 0;
    sensorMarginBase[HEIGHT_BASE] = 0;

    previewSizeLut = m86FrontPreviewLut;
    previewSizeLutMax = ARRAY_LENGTH(m86FrontPreviewLut);
    pictureSizeLut = m86FrontPreviewLut;
    pictureSizeLutMax = ARRAY_LENGTH(m86FrontPreviewLut);
    videoSizeLut = m86FrontPreviewLut;
    videoSizeLutMax = ARRAY_LENGTH(m86FrontPreviewLut);
    sizeTableSupport = true;

    frontPreviewList = m86FrontPreviewList;
    frontPreviewListMax = ARRAY_LENGTH(m86FrontPreviewList);
    frontPictureList = m86FrontPictureList;
    frontPictureListMax = ARRAY_LENGTH(m86FrontPictureList);
    frontVideoList = m86VideoList;
    frontVideoListMax = ARRAY_LENGTH(m86VideoList);
    frontFPSList = m86FpsList;
    frontFPSListMax = ARRAY_LENGTH(m86FpsList);
    thumbnailList = m86ThumbnailList;
    thumbnailListMax = ARRAY_LENGTH(m86ThumbnailList);

    initM86StaticMetadata(this, true);
}

struct ExynosSensorInfoBase *createExynosCamera3SensorInfo(int cameraId)
{
    const int sensorId = getSensorId(cameraId);

    ALOGI("cameraId(%d) sensorId(%d)", cameraId, sensorId);
    switch (sensorId) {
    case SENSOR_NAME_IMX230:
        return new ExynosCamera3SensorIMX230M86();
    case SENSOR_NAME_OV5670:
        return new ExynosCamera3SensorOV5670M86();
    default:
        ALOGE("unsupported m86 Camera3 sensor(%d)", sensorId);
        return NULL;
    }
}

} // namespace android
