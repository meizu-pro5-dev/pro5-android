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
     5312, 2988, 1920, 1080, 1920, 1080},
    {SIZE_RATIO_4_3, 5344, 4016, 5344, 4016,
     5312, 3984, 1440, 1080, 1440, 1080},
};

static int m86RearPictureLut[][SIZE_OF_LUT] = {
    {SIZE_RATIO_16_9, 5328, 3000, 5328, 3000,
     5312, 2988, 5312, 2988, 5312, 2988},
    {SIZE_RATIO_4_3, 5344, 4016, 5344, 4016,
     5312, 3984, 5312, 3984, 5312, 3984},
};

static int m86FrontPreviewLut[][SIZE_OF_LUT] = {
    {SIZE_RATIO_16_9, 2592, 1944, 2592, 1944,
     2560, 1440, 2560, 1440, 1920, 1080},
    {SIZE_RATIO_4_3, 2592, 1944, 2592, 1944,
     2576, 1934, 2576, 1934, 1440, 1080},
};

static int m86FrontPictureLut[][SIZE_OF_LUT] = {
    {SIZE_RATIO_16_9, 2592, 1944, 2592, 1944,
     2560, 1440, 2560, 1440, 2560, 1440},
    {SIZE_RATIO_4_3, 2592, 1944, 2592, 1944,
     2576, 1934, 2576, 1934, 2576, 1934},
};

static int m86RearPreviewList[][SIZE_OF_RESOLUTION] = {
    {1920, 1080, SIZE_RATIO_16_9},
    {1440, 1080, SIZE_RATIO_4_3},
    {1280, 720, SIZE_RATIO_16_9},
};

static int m86RearPictureList[][SIZE_OF_RESOLUTION] = {
    {5312, 3984, SIZE_RATIO_4_3},
    {5312, 2988, SIZE_RATIO_16_9},
    {4160, 3120, SIZE_RATIO_4_3},
    {2656, 1992, SIZE_RATIO_4_3},
    {1920, 1080, SIZE_RATIO_16_9},
};

static int m86FrontPreviewList[][SIZE_OF_RESOLUTION] = {
    {1920, 1080, SIZE_RATIO_16_9},
    {1440, 1080, SIZE_RATIO_4_3},
    {1280, 720, SIZE_RATIO_16_9},
};

static int m86FrontPictureList[][SIZE_OF_RESOLUTION] = {
    {2592, 1944, SIZE_RATIO_4_3},
    {2592, 1458, SIZE_RATIO_16_9},
    {1920, 1080, SIZE_RATIO_16_9},
    {640, 480, SIZE_RATIO_4_3},
};

static int m86VideoList[][SIZE_OF_RESOLUTION] = {
    {1920, 1080, SIZE_RATIO_16_9},
    {1280, 720, SIZE_RATIO_16_9},
};

static int m86ThumbnailList[][SIZE_OF_RESOLUTION] = {
    {0, 0, SIZE_RATIO_1_1},
};

static int m86FpsList[][2] = {
    {15000, 24000},
    {24000, 24000},
    {15000, 30000},
    {30000, 30000},
};

static uint8_t m86Capabilities[] = {
    ANDROID_REQUEST_AVAILABLE_CAPABILITIES_BACKWARD_COMPATIBLE,
};

static uint8_t m86FaceDetectModes[] = {
    ANDROID_STATISTICS_FACE_DETECT_MODE_OFF,
    ANDROID_STATISTICS_FACE_DETECT_MODE_SIMPLE,
};

static uint8_t m86AntibandingModes[] = {
    ANDROID_CONTROL_AE_ANTIBANDING_MODE_OFF,
    ANDROID_CONTROL_AE_ANTIBANDING_MODE_50HZ,
    ANDROID_CONTROL_AE_ANTIBANDING_MODE_60HZ,
    ANDROID_CONTROL_AE_ANTIBANDING_MODE_AUTO,
};

static uint8_t m86SceneModes[] = {
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

#define M86_SCENE_OVERRIDE(afMode) \
    ANDROID_CONTROL_AE_MODE_ON, ANDROID_CONTROL_AWB_MODE_AUTO, afMode

static uint8_t m86RearSceneModeOverrides[] = {
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_AUTO),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_AUTO),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_AUTO),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_AUTO),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_AUTO),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_AUTO),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_AUTO),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_AUTO),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_AUTO),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_AUTO),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_AUTO),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_AUTO),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_AUTO),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_AUTO),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_AUTO),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_AUTO),
};

static uint8_t m86FrontSceneModeOverrides[] = {
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_OFF),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_OFF),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_OFF),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_OFF),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_OFF),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_OFF),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_OFF),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_OFF),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_OFF),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_OFF),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_OFF),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_OFF),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_OFF),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_OFF),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_OFF),
    M86_SCENE_OVERRIDE(ANDROID_CONTROL_AF_MODE_OFF),
};

#undef M86_SCENE_OVERRIDE

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
    info->antiBandingModes = m86AntibandingModes;
    info->antiBandingModesLength = ARRAY_LENGTH(m86AntibandingModes);
    info->aeModes = front ? AVAILABLE_AE_MODES_FRONT : AVAILABLE_AE_MODES_BACK;
    info->aeModesLength = front ? ARRAY_LENGTH(AVAILABLE_AE_MODES_FRONT)
                                : ARRAY_LENGTH(AVAILABLE_AE_MODES_BACK);
    info->afModes = front ? AVAILABLE_AF_MODES_FRONT : AVAILABLE_AF_MODES_BACK;
    info->afModesLength = front ? ARRAY_LENGTH(AVAILABLE_AF_MODES_FRONT)
                                : ARRAY_LENGTH(AVAILABLE_AF_MODES_BACK);
    info->effectModes = AVAILABLE_EFFECT_MODES;
    info->effectModesLength = ARRAY_LENGTH(AVAILABLE_EFFECT_MODES);
    info->sceneModes = m86SceneModes;
    info->sceneModesLength = ARRAY_LENGTH(m86SceneModes);
    info->videoStabilizationModes = AVAILABLE_VIDEO_STABILIZATION_MODES;
    info->videoStabilizationModesLength = ARRAY_LENGTH(AVAILABLE_VIDEO_STABILIZATION_MODES);
    info->awbModes = AVAILABLE_AWB_MODES;
    info->awbModesLength = ARRAY_LENGTH(AVAILABLE_AWB_MODES);
    info->controlModes = AVAILABLE_CONTROL_MODES;
    info->controlModesLength = ARRAY_LENGTH(AVAILABLE_CONTROL_MODES);
    info->sceneModeOverrides = front ? m86FrontSceneModeOverrides
                                     : m86RearSceneModeOverrides;
    info->sceneModeOverridesLength = front
            ? ARRAY_LENGTH(m86FrontSceneModeOverrides)
            : ARRAY_LENGTH(m86RearSceneModeOverrides);
    info->exposureCompensationRange[MIN] = -4;
    info->exposureCompensationRange[MAX] = 4;
    info->exposureCompensationStep = 0.5f;
    info->aeLockAvailable = ANDROID_CONTROL_AE_LOCK_AVAILABLE_TRUE;
    info->awbLockAvailable = ANDROID_CONTROL_AWB_LOCK_AVAILABLE_TRUE;
    info->max3aRegions[AE] = front ? 0 : 1;
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
    info->maxNumDetectedFaces = NUM_OF_DETECTED_FACES;
    info->testPatternModes = AVAILABLE_TEST_PATTERN_MODES;
    info->testPatternModesLength = ARRAY_LENGTH(AVAILABLE_TEST_PATTERN_MODES);
    info->hotPixelMapModes = AVAILABLE_HOT_PIXEL_MAP_MODES;
    info->hotPixelMapModesLength = ARRAY_LENGTH(AVAILABLE_HOT_PIXEL_MAP_MODES);
    info->toneMapModes = AVAILABLE_TONE_MAP_MODES;
    info->toneMapModesLength = ARRAY_LENGTH(AVAILABLE_TONE_MAP_MODES);
    info->leds = AVAILABLE_LEDS;
    info->ledsLength = ARRAY_LENGTH(AVAILABLE_LEDS);

    info->maxNumOutputStreams[RAW] = 0;
    info->maxNumOutputStreams[PROCESSED] = 2;
    info->maxNumOutputStreams[PROCESSED_STALL] = 1;
    info->maxNumInputStreams = 0;
    info->maxPipelineDepth = 4;
    info->partialResultCount = 1;
    info->zoomSupport = true;
    info->smoothZoomSupport = false;
    info->maxZoomLevel = front ? MAX_ZOOM_LEVEL_FRONT : MAX_ZOOM_LEVEL;
    info->maxZoomRatio = front ? MAX_ZOOM_RATIO_FRONT : MAX_ZOOM_RATIO;
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
    /* Flyme keeps the aligned sensor envelope here and advertises the
     * active 5312-wide outputs through rearPictureList. */
    maxPictureW = 5344;
    maxPictureH = 4016;
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
    maxPictureW = 2592;
    maxPictureH = 1944;
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
    minimumFocusDistance = 0.0f;
    focusDistanceCalibration =
            ANDROID_LENS_INFO_FOCUS_DISTANCE_CALIBRATION_UNCALIBRATED;
    flashAvailable = ANDROID_FLASH_INFO_AVAILABLE_FALSE;

    previewSizeLut = m86FrontPreviewLut;
    previewSizeLutMax = ARRAY_LENGTH(m86FrontPreviewLut);
    pictureSizeLut = m86FrontPictureLut;
    pictureSizeLutMax = ARRAY_LENGTH(m86FrontPictureLut);
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
