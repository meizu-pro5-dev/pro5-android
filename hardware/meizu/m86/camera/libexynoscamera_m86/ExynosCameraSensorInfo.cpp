/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#define LOG_TAG "ExynosCameraM86SensorInfo"
#include <cutils/log.h>

#include "ExynosCameraSensorInfo.h"

namespace android {

// PRO 5's 7420 capture path only writes 4608 active YUYV pixels per line.
// Advertising the donor IMX230 table's 5312-pixel JPEG target leaves the
// remaining 704 pixels unwritten (green).  Keep the full sensor/Bayer geometry
// for ISP input and reprocessing allocation, but scale the final SCC/JPEG
// output to the verified 4:3 boundary.
int M86_PICTURE_SIZE_LUT_IMX230[][SIZE_OF_LUT] = {
    {SIZE_RATIO_4_3, 5344, 4016, 5344, 4016,
     5328, 3996, 4608, 3456, 4608, 3456},
    {SIZE_RATIO_16_9, 5328, 3000, 5328, 3000,
     5316, 2990, 4608, 2592, 4608, 2592},
};

int M86_PICTURE_LIST_IMX230[][SIZE_OF_RESOLUTION] = {
    {4608, 3456, SIZE_RATIO_4_3},
    {4608, 2592, SIZE_RATIO_16_9},
    {2656, 1992, SIZE_RATIO_4_3},
    {1920, 1080, SIZE_RATIO_16_9},
};

// Preview size LUT for the rear IMX230, matching the stock/Flyme
// PREVIEW_SIZE_LUT_IMX230 16:9 and 4:3 rows.  On m86 the live preview zoom is
// routed through the hardware GSC so these upstream 3AA/ISP dimensions remain
// stable while the camera is streaming.
int M86_PREVIEW_SIZE_LUT_IMX230[][SIZE_OF_LUT] = {
    {SIZE_RATIO_16_9, 5328, 3000, 5328, 3000,
     5316, 2990, 1920, 1080, 1920, 1080},
    {SIZE_RATIO_4_3, 5344, 4016, 5344, 4016,
     5328, 3996, 1440, 1080, 1440, 1080},
};

ExynosSensorIMX230::ExynosSensorIMX230() : ExynosSensorIMX230Base()
{
    // The 74xx HAL1 engine is constructed with the 3.2 compatibility version,
    // so getMaxNum*Areas() reads max3aRegions rather than the legacy fields.
    max3aRegions[AE] = 1;
    max3aRegions[AWB] = 0;
    max3aRegions[AF] = 1;
    // CAMERA_GED_FEATURE supplies the stock 31-step, 4x zoom table.  Keep the
    // full table; the external preview GSC avoids live 3AA geometry changes.
    pictureSizeLut = M86_PICTURE_SIZE_LUT_IMX230;
    pictureSizeLutMax = ARRAY_LENGTH(M86_PICTURE_SIZE_LUT_IMX230);
    previewSizeLut = M86_PREVIEW_SIZE_LUT_IMX230;
    previewSizeLutMax = ARRAY_LENGTH(M86_PREVIEW_SIZE_LUT_IMX230);
    rearPictureList = M86_PICTURE_LIST_IMX230;
    rearPictureListMax = ARRAY_LENGTH(M86_PICTURE_LIST_IMX230);
}

/*
 * PRO 5 OV5670 geometry derived from the Meizu kernel driver
 * (fimc-is-device-ov5670.c):
 *   full     2592x1944 @ 30 fps
 *   16:9     2592x1458 @ 30 fps
 * The generic SLSI table (2608x1960) is rejected by FLITE VIDIOC_S_FMT.
 */
/*
 * The 7420 ISP firmware rejects a 2592x1458 16:9 3AA/ISP input.  Its crop
 * alignment expands that request to sourceArea(2,244,2592,1460), which runs
 * past the 2592-pixel calibrated sensor width and asserts in ConfigureInput.
 * Keep the physical sensor/BNS geometry but constrain the processing crop to
 * the firmware's advertised 2560x1440 ceiling.
 */
int M86_PREVIEW_SIZE_LUT_OV5670[][SIZE_OF_LUT] = {
    {SIZE_RATIO_16_9, 2592, 1944, 2592, 1944,
     2560, 1440, 2560, 1440, 1920, 1080},
    {SIZE_RATIO_4_3, 2592, 1944, 2592, 1944,
     2576, 1932, 2576, 1932, 1440, 1080},
    {SIZE_RATIO_1_1, 2592, 1944, 2592, 1944,
     1944, 1944, 1944, 1944, 1072, 1072},
};

int M86_PICTURE_SIZE_LUT_OV5670[][SIZE_OF_LUT] = {
    {SIZE_RATIO_16_9, 2592, 1944, 2592, 1944,
     2560, 1440, 2560, 1440, 2560, 1440},
    {SIZE_RATIO_4_3, 2592, 1944, 2592, 1944,
     2576, 1932, 2576, 1932, 2576, 1932},
    {SIZE_RATIO_1_1, 2592, 1944, 2592, 1944,
     1944, 1944, 1944, 1944, 1920, 1920},
};

int M86_VIDEO_SIZE_LUT_OV5670[][SIZE_OF_LUT] = {
    {SIZE_RATIO_16_9, 2592, 1944, 2592, 1944,
     2560, 1440, 2560, 1440, 1920, 1080},
    {SIZE_RATIO_4_3, 2592, 1944, 2592, 1944,
     2576, 1932, 2576, 1932, 1440, 1080},
};

ExynosSensorOV5670::ExynosSensorOV5670() : ExynosSensorOV5670Base()
{
    max3aRegions[AE] = 1;
    max3aRegions[AWB] = 0;
    max3aRegions[AF] = 0;
    maxSensorW = 2592;
    maxSensorH = 1944;
    sensorMarginW = 0;
    sensorMarginH = 0;
    sensorMarginBase[WIDTH] = 0;
    sensorMarginBase[HEIGHT] = 0;

    previewSizeLut = M86_PREVIEW_SIZE_LUT_OV5670;
    previewSizeLutMax = ARRAY_LENGTH(M86_PREVIEW_SIZE_LUT_OV5670);
    pictureSizeLut = M86_PICTURE_SIZE_LUT_OV5670;
    pictureSizeLutMax = ARRAY_LENGTH(M86_PICTURE_SIZE_LUT_OV5670);
    videoSizeLut = M86_VIDEO_SIZE_LUT_OV5670;
    videoSizeLutMax = ARRAY_LENGTH(M86_VIDEO_SIZE_LUT_OV5670);
    dualPreviewSizeLut = M86_PREVIEW_SIZE_LUT_OV5670;
    dualVideoSizeLut = M86_VIDEO_SIZE_LUT_OV5670;
}

struct ExynosSensorInfoBase *createSensorInfo(int camId)
{
    struct ExynosSensorInfoBase *sensorInfo = nullptr;
    int sensorName = getSensorId(camId);

    if (sensorName < 0) {
        ALOGE("ERR(%s[%d]): invalid camId %d, sensor name is nothing",
              __FUNCTION__, __LINE__, camId);
        sensorName = SENSOR_NAME_NOTHING;
    }

    ALOGI("INFO(%s[%d]): camId(%d) sensorId(%d)",
          __FUNCTION__, __LINE__, camId, sensorName);

    switch (sensorName) {
    case SENSOR_NAME_IMX230:
        sensorInfo = new ExynosSensorIMX230();
        break;
    case SENSOR_NAME_OV5670:
        sensorInfo = new ExynosSensorOV5670();
        break;
    default:
        ALOGE("ERR(%s[%d]): unsupported m86 sensor %d",
              __FUNCTION__, __LINE__, sensorName);
        sensorInfo = new ExynosSensorInfoBase();
        break;
    }

    return sensorInfo;
}

struct ExynosSensorInfoBase *createExynosCamera1SensorInfo(int camId)
{
    return createSensorInfo(camId);
}

bool needGSCForCapture(int camId)
{
    return (camId == CAMERA_ID_BACK) ? USE_GSC_FOR_CAPTURE_BACK
                                     : USE_GSC_FOR_CAPTURE_FRONT;
}

}  // namespace android
