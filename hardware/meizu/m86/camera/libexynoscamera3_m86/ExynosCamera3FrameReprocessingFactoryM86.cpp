/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#define LOG_TAG "ExynosCamera3ReprocessM86"
#include <cutils/log.h>

#include "ExynosCamera3FrameReprocessingFactoryM86.h"

namespace android {

ExynosCamera3FrameReprocessingFactoryM86::
ExynosCamera3FrameReprocessingFactoryM86(
        int cameraId, ExynosCamera3Parameters *parameters)
    : ExynosCamera3FrameFactory(cameraId, parameters)
{
    m_flagReprocessing = true;
    strncpy(m_name, "M86ReprocessingFactory",
            EXYNOS_CAMERA_NAME_STR_SIZE - 1);
}

ExynosCamera3FrameReprocessingFactoryM86::
~ExynosCamera3FrameReprocessingFactoryM86()
{
    destroy();
    m_setCreate(false);
}

status_t ExynosCamera3FrameReprocessingFactoryM86::m_setupConfig(void)
{
    static_assert(ExynosCamera3HwCapsM86::dirtyBayerReprocessing,
                  "m86 reprocessing requires dirty Bayer");
    static_assert(!ExynosCamera3HwCapsM86::hasMcsc,
                  "m86 capture graph must not instantiate MCSC");
    static_assert(!ExynosCamera3HwCapsM86::hasHwfc,
                  "m86 capture graph must not instantiate HWFC");

    m_flagFlite3aaOTF = true;
    m_flag3aaIspOTF = false;
    m_flagIspTpuOTF = false;
    m_flagIspMcscOTF = false;
    m_flagTpuMcscOTF = false;
    m_flagMcscVraOTF = false;
    m_supportReprocessing = true;
    m_supportPureBayerReprocessing = false;
    m_supportSCC = false;
    m_supportMCSC = false;
    m_flagReprocessing = true;

    m_requestFLITE = 0;
    m_request3AC = 0;
    m_request3AP = 0;
    m_requestISP = 1;
    m_requestISPC = 1;
    m_requestISPP = 0;
    m_requestSCC = 0;
    m_requestDIS = 0;
    m_requestSCP = 0;
    m_requestVRA = 0;
    m_requestJPEG = 0;
    m_requestThumbnail = 0;

    const int pipeIndex = INDEX(PIPE_ISP_REPROCESSING);
    m_initDeviceInfo(pipeIndex);

    enum NODE_TYPE nodeType = getNodeType(PIPE_ISP_REPROCESSING);
    m_nodeInfo[pipeIndex].pipeId[nodeType] = PIPE_ISP_REPROCESSING;
    m_nodeInfo[pipeIndex].nodeNum[nodeType] = FIMC_IS_VIDEO_I1S_NUM;
    m_nodeInfo[pipeIndex].connectionMode[nodeType] = HW_CONNECTION_MODE_M2M;
    strncpy(m_nodeInfo[pipeIndex].nodeName[nodeType],
            "M86_REPROCESSING_I1S", EXYNOS_CAMERA_NAME_STR_SIZE - 1);
    m_sensorIds[pipeIndex][nodeType] = m_getSensorId(
            FIMC_IS_VIDEO_30P_NUM, false, true, true);

    nodeType = getNodeType(PIPE_ISPC_REPROCESSING);
    m_nodeInfo[pipeIndex].pipeId[nodeType] = PIPE_ISPC_REPROCESSING;
    m_nodeInfo[pipeIndex].nodeNum[nodeType] = FIMC_IS_VIDEO_I1C_NUM;
    m_nodeInfo[pipeIndex].connectionMode[nodeType] = HW_CONNECTION_MODE_OTF;
    strncpy(m_nodeInfo[pipeIndex].nodeName[nodeType],
            "M86_REPROCESSING_I1C", EXYNOS_CAMERA_NAME_STR_SIZE - 1);
    m_sensorIds[pipeIndex][nodeType] = m_getSensorId(
            FIMC_IS_VIDEO_I1S_NUM, true, false, true);

    m_nodeNums[INDEX(PIPE_GSC_REPROCESSING)][OUTPUT_NODE] =
            PICTURE_GSC_NODE_NUM;
    m_nodeNums[INDEX(PIPE_JPEG_REPROCESSING)][OUTPUT_NODE] = -1;

    ALOGI("M86_NATIVE3_CAPTURE camera=%d 30C->I1S(%d)->I1C(%d)->GSC->JPEG",
          m_cameraId, FIMC_IS_VIDEO_I1S_NUM, FIMC_IS_VIDEO_I1C_NUM);
    return NO_ERROR;
}

status_t ExynosCamera3FrameReprocessingFactoryM86::create(bool active)
{
    ALOGI("M86_NATIVE3_CAPTURE create camera=%d active=%d", m_cameraId, active);
    status_t ret = m_setupConfig();
    if (ret != NO_ERROR)
        return ret;

    m_pipes[INDEX(PIPE_ISP_REPROCESSING)] =
            (ExynosCameraPipe *)new ExynosCameraMCPipe(
                    m_cameraId, m_parameters, true,
                    &m_nodeInfo[INDEX(PIPE_ISP_REPROCESSING)]);
    m_pipes[INDEX(PIPE_ISP_REPROCESSING)]->setPipeId(PIPE_ISP_REPROCESSING);
    m_pipes[INDEX(PIPE_ISP_REPROCESSING)]->setPipeName(
            "PIPE_ISP_REPROCESSING_M86");

    m_pipes[INDEX(PIPE_GSC_REPROCESSING)] =
            (ExynosCameraPipe *)new ExynosCameraPipeGSC(
                    m_cameraId, m_parameters, true,
                    m_nodeNums[INDEX(PIPE_GSC_REPROCESSING)]);
    m_pipes[INDEX(PIPE_GSC_REPROCESSING)]->setPipeId(PIPE_GSC_REPROCESSING);
    m_pipes[INDEX(PIPE_GSC_REPROCESSING)]->setPipeName(
            "PIPE_GSC_REPROCESSING_M86");

    m_pipes[INDEX(PIPE_JPEG_REPROCESSING)] =
            (ExynosCameraPipe *)new ExynosCameraPipeJpeg(
                    m_cameraId, m_parameters, true,
                    m_nodeNums[INDEX(PIPE_JPEG_REPROCESSING)]);
    m_pipes[INDEX(PIPE_JPEG_REPROCESSING)]->setPipeId(PIPE_JPEG_REPROCESSING);
    m_pipes[INDEX(PIPE_JPEG_REPROCESSING)]->setPipeName(
            "PIPE_JPEG_REPROCESSING_M86");

    const uint32_t pipes[] = {
        PIPE_ISP_REPROCESSING,
        PIPE_GSC_REPROCESSING,
        PIPE_JPEG_REPROCESSING,
    };
    for (size_t i = 0; i < sizeof(pipes) / sizeof(pipes[0]); ++i) {
        ret = m_pipes[INDEX(pipes[i])]->create();
        if (ret != NO_ERROR) {
            ALOGE("M86_NATIVE3_CAPTURE create pipe=%u failed ret=%d",
                  pipes[i], ret);
            return INVALID_OPERATION;
        }
    }

    ret = m_pipes[INDEX(PIPE_ISP_REPROCESSING)]->setControl(
            V4L2_CID_IS_END_OF_STREAM, 1);
    if (ret != NO_ERROR) {
        ALOGE("M86_NATIVE3_CAPTURE ISP EOS failed ret=%d", ret);
        return INVALID_OPERATION;
    }

    m_setCreate(true);
    return NO_ERROR;
}

status_t ExynosCamera3FrameReprocessingFactoryM86::initPipes(void)
{
    camera_pipe_info_t pipeInfo[MAX_NODE];
    int32_t sensorIds[MAX_NODE];
    int32_t secondarySensorIds[MAX_NODE];
    memset(pipeInfo, 0, sizeof(pipeInfo));
    for (int i = 0; i < MAX_NODE; ++i) {
        sensorIds[i] = m_sensorIds[INDEX(PIPE_ISP_REPROCESSING)][i];
        secondarySensorIds[i] =
                m_secondarySensorIds[INDEX(PIPE_ISP_REPROCESSING)][i];
        status_t ret = m_pipes[INDEX(PIPE_ISP_REPROCESSING)]->setPipeId(
                static_cast<enum NODE_TYPE>(i),
                m_nodeInfo[INDEX(PIPE_ISP_REPROCESSING)].pipeId[i]);
        if (ret != NO_ERROR)
            return ret;
    }

    int hwSensorW = 0;
    int hwSensorH = 0;
    ExynosRect captureYuvSize = {0, };
    m_parameters->getHwSensorSize(&hwSensorW, &hwSensorH);
    status_t ret = m_parameters->getPictureBdsSize(&captureYuvSize);
    if (ret != NO_ERROR || captureYuvSize.w <= 0 || captureYuvSize.h <= 0) {
        ALOGE("M86_NATIVE3_CAPTURE invalid I1C size ret=%d size=%dx%d",
              ret, captureYuvSize.w, captureYuvSize.h);
        return BAD_VALUE;
    }

    const int pipeId = PIPE_ISP_REPROCESSING;
    enum NODE_TYPE leaderNodeType = getNodeType(PIPE_ISP_REPROCESSING);
    enum NODE_TYPE nodeType = leaderNodeType;
    ExynosRect tempRect = {0, };
    tempRect.fullW = hwSensorW;
    tempRect.fullH = hwSensorH;
    tempRect.colorFormat = ExynosCamera3HwCapsM86::previewBayerFormat;
    pipeInfo[nodeType].bytesPerPlane[0] =
            ExynosCamera3HwCapsM86::ispReprocessingBytesPerLine(hwSensorW);
    pipeInfo[nodeType].bufInfo.count =
            ExynosCamera3HwCapsM86::dirtyBayerBufferCount;
    SET_OUTPUT_DEVICE_BASIC_INFO(PERFRAME_INFO_DIRTY_REPROCESSING_ISP);

    nodeType = getNodeType(PIPE_ISPC_REPROCESSING);
    const int perFramePos = PERFRAME_REPROCESSING_SCC_POS;
    tempRect.fullW = captureYuvSize.w;
    tempRect.fullH = captureYuvSize.h;
    tempRect.colorFormat = m_parameters->getHwPictureFormat();
    /* fimc-is2 interprets YUYV bytesperline as a pixel stride and applies
     * the two bytes-per-pixel factor itself.  Leave it unset so queue_setup
     * derives exactly width * height * 2 for the I1C image plane. */
    pipeInfo[nodeType].bytesPerPlane[0] = 0;
    pipeInfo[nodeType].bufInfo.count =
            ExynosCamera3HwCapsM86::pictureBufferCount;
    SET_CAPTURE_DEVICE_BASIC_INFO();

    ret = m_pipes[INDEX(PIPE_ISP_REPROCESSING)]->setupPipe(
            pipeInfo, sensorIds, secondarySensorIds);
    if (ret != NO_ERROR) {
        ALOGE("M86_NATIVE3_CAPTURE setup I1S/I1C failed ret=%d", ret);
        return ret;
    }

    m_frameCount = 0;
    ALOGI("M86_NATIVE3_CAPTURE init camera=%d Bayer=%dx%d stride=%d count=%d "
          "YUV=%dx%d fmt=0x%x count=%d",
          m_cameraId, hwSensorW, hwSensorH,
          ExynosCamera3HwCapsM86::ispReprocessingBytesPerLine(hwSensorW),
          ExynosCamera3HwCapsM86::dirtyBayerBufferCount,
          captureYuvSize.w, captureYuvSize.h,
          m_parameters->getHwPictureFormat(),
          ExynosCamera3HwCapsM86::pictureBufferCount);
    return NO_ERROR;
}

status_t ExynosCamera3FrameReprocessingFactoryM86::preparePipes(void)
{
    return NO_ERROR;
}

status_t ExynosCamera3FrameReprocessingFactoryM86::startPipes(void)
{
    status_t ret = m_pipes[INDEX(PIPE_ISP_REPROCESSING)]->start();
    ALOGI("M86_NATIVE3_CAPTURE start I1S/I1C ret=%d", ret);
    return ret;
}

status_t ExynosCamera3FrameReprocessingFactoryM86::startInitialThreads(void)
{
    return NO_ERROR;
}

status_t ExynosCamera3FrameReprocessingFactoryM86::setStopFlag(void)
{
    if (m_pipes[INDEX(PIPE_ISP_REPROCESSING)] == nullptr)
        return NO_ERROR;
    return m_pipes[INDEX(PIPE_ISP_REPROCESSING)]->setStopFlag();
}

status_t ExynosCamera3FrameReprocessingFactoryM86::stopPipes(void)
{
    status_t ret = NO_ERROR;
    const uint32_t softwarePipes[] = {
        PIPE_GSC_REPROCESSING,
        PIPE_JPEG_REPROCESSING,
    };
    for (size_t i = 0; i < sizeof(softwarePipes) / sizeof(softwarePipes[0]); ++i) {
        ExynosCameraPipe *pipe = m_pipes[INDEX(softwarePipes[i])];
        if (pipe != nullptr && pipe->isThreadRunning()) {
            const status_t stopRet = pipe->stopThread();
            if (stopRet != NO_ERROR)
                ret = stopRet;
        }
    }

    ExynosCameraPipe *isp = m_pipes[INDEX(PIPE_ISP_REPROCESSING)];
    if (isp != nullptr && isp->isThreadRunning()) {
        const status_t stopRet = isp->stopThread();
        if (stopRet != NO_ERROR)
            ret = stopRet;
    }
    if (isp != nullptr && isp->flagStart()) {
        const status_t forceRet = isp->forceDone(V4L2_CID_IS_FORCE_DONE, 0x1000);
        if (forceRet != NO_ERROR)
            ALOGW("M86_NATIVE3_CAPTURE forceDone ret=%d", forceRet);
        const status_t stopRet = isp->stop();
        if (stopRet != NO_ERROR)
            ret = stopRet;
    }

    ALOGI("M86_NATIVE3_CAPTURE stop ret=%d", ret);
    return ret;
}

ExynosCameraFrame *
ExynosCamera3FrameReprocessingFactoryM86::createNewFrame(uint32_t frameCount)
{
    if (frameCount == 0)
        frameCount = m_frameCount;

    ExynosCameraFrame *frame = m_frameMgr->createFrame(
            m_parameters, frameCount, FRAME_TYPE_REPROCESSING);
    if (frame == nullptr)
        return nullptr;

    status_t ret = m_initFrameMetadata(frame);
    if (ret != NO_ERROR)
        ALOGE("M86_NATIVE3_CAPTURE metadata frame=%u ret=%d", frameCount, ret);

    ExynosCameraFrameEntity *isp = new ExynosCameraFrameEntity(
            PIPE_ISP_REPROCESSING, ENTITY_TYPE_INPUT_ONLY,
            ENTITY_BUFFER_FIXED);
    frame->addSiblingEntity(nullptr, isp);
    ExynosCameraFrameEntity *gsc = new ExynosCameraFrameEntity(
            PIPE_GSC_REPROCESSING, ENTITY_TYPE_INPUT_OUTPUT,
            ENTITY_BUFFER_FIXED);
    frame->addSiblingEntity(nullptr, gsc);
    ExynosCameraFrameEntity *jpeg = new ExynosCameraFrameEntity(
            PIPE_JPEG_REPROCESSING, ENTITY_TYPE_INPUT_OUTPUT,
            ENTITY_BUFFER_FIXED);
    frame->addSiblingEntity(nullptr, jpeg);

    ret = m_initPipelines(frame);
    if (ret != NO_ERROR)
        ALOGE("M86_NATIVE3_CAPTURE pipeline frame=%u ret=%d", frameCount, ret);
    frame->setNumRequestPipe(3);
    m_fillNodeGroupInfo(frame);
    ++m_frameCount;
    return frame;
}

status_t ExynosCamera3FrameReprocessingFactoryM86::m_fillNodeGroupInfo(
        ExynosCameraFrame *frame)
{
    if (frame == nullptr)
        return BAD_VALUE;

    camera2_node_group nodeGroup3aa;
    camera2_node_group nodeGroupIsp;
    memset(&nodeGroup3aa, 0, sizeof(nodeGroup3aa));
    memset(&nodeGroupIsp, 0, sizeof(nodeGroupIsp));
    nodeGroupIsp.leader.request = 1;
    nodeGroupIsp.capture[PERFRAME_REPROCESSING_SCC_POS].request = 1;
    nodeGroupIsp.capture[PERFRAME_REPROCESSING_SCC_POS].vid =
            FIMC_IS_VIDEO_I1C_NUM - FIMC_IS_VIDEO_BAS_NUM;

    ExynosRect previewBayerCrop = {0, };
    ExynosRect pictureBayerCrop = {0, };
    ExynosRect bnsSize = {0, };
    ExynosRect bdsSize = {0, };
    m_parameters->getPreviewBayerCropSize(&bnsSize, &previewBayerCrop);
    m_parameters->getPictureBayerCropSize(&bnsSize, &pictureBayerCrop);
    m_parameters->getPictureBdsSize(&bdsSize);

    /* I1C on Exynos7420 cannot scale.  The Flyme picture LUT records its
     * real YUYV output in BDS; the following GSC owns conversion to the
     * external JPEG request size.  Do not let a preview/picture ratio
     * mismatch fall back to the 34xx equation and widen this DMA plane. */
    pictureBayerCrop.x = 0;
    pictureBayerCrop.y = 0;
    pictureBayerCrop.w = bdsSize.w;
    pictureBayerCrop.h = bdsSize.h;

    /* The 34xx compatibility helper named updateNodeGroupInfo() is an
     * intentional no-op.  Use the same reprocessing calculator as the
     * working 74xx HAL1 so I1S/I1C receive real crop regions on the first
     * shot. */
    ExynosCameraNodeGroup::updateNodeGroupInfo(
            m_cameraId,
            &nodeGroup3aa,
            &nodeGroupIsp,
            previewBayerCrop,
            pictureBayerCrop,
            bdsSize,
            bdsSize.w,
            bdsSize.h,
            false,
            false);
    frame->storeNodeGroupInfo(&nodeGroupIsp,
                              PERFRAME_INFO_DIRTY_REPROCESSING_ISP,
                              m_parameters->getZoomLevel());

    ALOGV("M86_NATIVE3_CAPTURE crop camera=%d ISP=%dx%d I1C in=%d,%d %dx%d "
          "out=%dx%d",
          m_cameraId,
          nodeGroupIsp.leader.input.cropRegion[2],
          nodeGroupIsp.leader.input.cropRegion[3],
          nodeGroupIsp.capture[PERFRAME_REPROCESSING_SCC_POS]
                  .input.cropRegion[0],
          nodeGroupIsp.capture[PERFRAME_REPROCESSING_SCC_POS]
                  .input.cropRegion[1],
          nodeGroupIsp.capture[PERFRAME_REPROCESSING_SCC_POS]
                  .input.cropRegion[2],
          nodeGroupIsp.capture[PERFRAME_REPROCESSING_SCC_POS]
                  .input.cropRegion[3],
          nodeGroupIsp.capture[PERFRAME_REPROCESSING_SCC_POS]
                  .output.cropRegion[2],
          nodeGroupIsp.capture[PERFRAME_REPROCESSING_SCC_POS]
                  .output.cropRegion[3]);
    return NO_ERROR;
}

enum NODE_TYPE ExynosCamera3FrameReprocessingFactoryM86::getNodeType(
        uint32_t pipeId)
{
    switch (pipeId) {
    case PIPE_ISP_REPROCESSING:
        return OUTPUT_NODE;
    case PIPE_ISPC_REPROCESSING:
        return CAPTURE_NODE_1;
    default:
        ALOGE("M86_NATIVE3_CAPTURE unsupported node pipe=%u", pipeId);
        return INVALID_NODE;
    }
}

} // namespace android
