/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#define LOG_TAG "ExynosCamera3FactoryM86"
#include <cutils/log.h>

#include "ExynosCamera3FrameFactoryPreviewM86.h"

namespace android {

ExynosCamera3FrameFactoryPreviewM86::ExynosCamera3FrameFactoryPreviewM86(
    int cameraId, ExynosCamera3Parameters *parameters)
    : ExynosCamera3FrameFactoryPreview(cameraId, parameters)
{
}

status_t ExynosCamera3FrameFactoryPreviewM86::create(bool active)
{
    static_assert(!ExynosCamera3HwCapsM86::hasMcsc,
                  "m86 must not instantiate MCSC");
    static_assert(!ExynosCamera3HwCapsM86::hasVra,
                  "m86 must not instantiate VRA");
    static_assert(!ExynosCamera3HwCapsM86::hasHwfc,
                  "m86 must not instantiate HWFC");
    static_assert(ExynosCamera3HwCapsM86::previewOutputPipe == PIPE_SCP,
                  "m86 preview output must be SCP");

    ALOGI("M86_NATIVE3_GRAPH create SS0->30S->30P->I0S->DIS->SCP active=%d",
          active);

    status_t ret = m_setupConfig();
    if (ret != NO_ERROR) {
        return ret;
    }

    m_pipes[INDEX(PIPE_FLITE)] = (ExynosCameraPipe *)new ExynosCameraPipeFlite(
            m_cameraId, reinterpret_cast<ExynosCameraParameters *>(m_parameters),
            false, m_nodeNums[INDEX(PIPE_FLITE)]);
    m_pipes[INDEX(PIPE_FLITE)]->setPipeId(PIPE_FLITE);
    m_pipes[INDEX(PIPE_FLITE)]->setPipeName("PIPE_FLITE_M86");

    m_pipes[INDEX(PIPE_3AA)] = (ExynosCameraPipe *)new ExynosCameraMCPipe(
            m_cameraId, reinterpret_cast<ExynosCameraParameters *>(m_parameters),
            false, &m_nodeInfo[INDEX(PIPE_3AA)]);
    m_pipes[INDEX(PIPE_3AA)]->setPipeId(PIPE_3AA);
    m_pipes[INDEX(PIPE_3AA)]->setPipeName("PIPE_3AA_M86_LEADER");

    m_pipes[INDEX(PIPE_DIS)] = (ExynosCameraPipe *)new ExynosCameraMCPipe(
            m_cameraId, reinterpret_cast<ExynosCameraParameters *>(m_parameters),
            false, &m_nodeInfo[INDEX(PIPE_DIS)]);
    m_pipes[INDEX(PIPE_DIS)]->setPipeId(PIPE_DIS);
    m_pipes[INDEX(PIPE_DIS)]->setPipeName("PIPE_DIS_M86_LEADER");

    m_pipes[INDEX(PIPE_GSC)] = (ExynosCameraPipe *)new ExynosCameraPipeGSC(
            m_cameraId, reinterpret_cast<ExynosCameraParameters *>(m_parameters),
            true, m_nodeNums[INDEX(PIPE_GSC)]);
    m_pipes[INDEX(PIPE_GSC)]->setPipeId(PIPE_GSC);
    m_pipes[INDEX(PIPE_GSC)]->setPipeName("PIPE_GSC_M86_PREVIEW");

    ret = m_pipes[INDEX(PIPE_FLITE)]->create(m_sensorIds[INDEX(PIPE_FLITE)]);
    if (ret != NO_ERROR) {
        ALOGE("M86_NATIVE3_GRAPH FLITE create failed ret=%d", ret);
        return INVALID_OPERATION;
    }
    ret = m_pipes[INDEX(PIPE_3AA)]->create();
    if (ret != NO_ERROR) {
        ALOGE("M86_NATIVE3_GRAPH 3AA leader create failed ret=%d", ret);
        return INVALID_OPERATION;
    }
    ret = m_pipes[INDEX(PIPE_DIS)]->create();
    if (ret != NO_ERROR) {
        ALOGE("M86_NATIVE3_GRAPH DIS leader create failed ret=%d", ret);
        return INVALID_OPERATION;
    }
    ret = m_pipes[INDEX(PIPE_GSC)]->create();
    if (ret != NO_ERROR) {
        ALOGE("M86_NATIVE3_GRAPH preview GSC create failed ret=%d", ret);
        return INVALID_OPERATION;
    }
    m_setCreate(true);
    return NO_ERROR;
}

status_t ExynosCamera3FrameFactoryPreviewM86::m_setupConfig(void)
{
    status_t ret = ExynosCamera3FrameFactoryPreview::m_setupConfig();
    if (ret != NO_ERROR) {
        return ret;
    }

    m_flagFlite3aaOTF = true;
    m_flag3aaIspOTF = true;
    m_flagIspTpuOTF = true;
    m_flagIspMcscOTF = false;
    m_flagTpuMcscOTF = false;
    m_flagMcscVraOTF = false;
    m_supportMCSC = false;
    m_supportSCC = false;
    m_supportReprocessing = false;
    m_supportPureBayerReprocessing = false;
    m_flagReprocessing = false;

    m_requestFLITE = 0;
    m_request3AC = 0;
    m_request3AP = 0;
    m_requestISP = 0;
    m_requestISPP = 1;
    m_requestISPC = 0;
    m_requestSCC = 0;
    m_requestDIS = 1;
    m_requestSCP = 1;
    m_requestVRA = 0;

    ALOGI("M86_NATIVE3_GRAPH requests 30S=leader 30C=off 30P=OTF ISP=OTF I0P=M2M DIS=leader SCP=1");
    return NO_ERROR;
}

status_t ExynosCamera3FrameFactoryPreviewM86::m_setDeviceInfo(void)
{
    int t3aaNums[MAX_NODE] = {-1, };
    int ispNums[MAX_NODE] = {-1, };
    int pipeId;
    enum NODE_TYPE nodeType;

    t3aaNums[OUTPUT_NODE] = FIMC_IS_VIDEO_30S_NUM;
    t3aaNums[CAPTURE_NODE_2] = FIMC_IS_VIDEO_30P_NUM;
    ispNums[OUTPUT_NODE] = FIMC_IS_VIDEO_I0S_NUM;
    ispNums[CAPTURE_NODE_2] = FIMC_IS_VIDEO_I0P_NUM;

    m_initDeviceInfo(INDEX(PIPE_3AA));
    m_initDeviceInfo(INDEX(PIPE_DIS));

    pipeId = INDEX(PIPE_3AA);
    nodeType = getNodeType(PIPE_3AA);
    m_nodeInfo[pipeId].nodeNum[nodeType] = t3aaNums[OUTPUT_NODE];
    strncpy(m_nodeInfo[pipeId].nodeName[nodeType], "3AA_OUTPUT", EXYNOS_CAMERA_NAME_STR_SIZE - 1);
    m_sensorIds[pipeId][nodeType] = m_getSensorId(
            m_nodeNums[INDEX(PIPE_FLITE)][getNodeType(PIPE_FLITE)], true, true, false);
    m_nodeInfo[pipeId].pipeId[nodeType] = PIPE_3AA;

    /* 30C deliberately remains unopened during preview-only bring-up. */
    nodeType = getNodeType(PIPE_3AP);
    m_nodeInfo[pipeId].secondaryNodeNum[nodeType] = t3aaNums[CAPTURE_NODE_2];
    strncpy(m_nodeInfo[pipeId].secondaryNodeName[nodeType], "3AA_PREVIEW", EXYNOS_CAMERA_NAME_STR_SIZE - 1);
    m_secondarySensorIds[pipeId][nodeType] = m_getSensorId(t3aaNums[OUTPUT_NODE], true, false, false);
    m_nodeInfo[pipeId].pipeId[nodeType] = PIPE_3AP;

    nodeType = getNodeType(PIPE_ISP);
    m_nodeInfo[pipeId].secondaryNodeNum[nodeType] = ispNums[OUTPUT_NODE];
    strncpy(m_nodeInfo[pipeId].secondaryNodeName[nodeType], "ISP_OUTPUT", EXYNOS_CAMERA_NAME_STR_SIZE - 1);
    m_secondarySensorIds[pipeId][nodeType] = m_getSensorId(t3aaNums[CAPTURE_NODE_2], true, false, false);
    m_nodeInfo[pipeId].pipeId[nodeType] = PIPE_ISP;

    nodeType = getNodeType(PIPE_ISPP);
    m_nodeInfo[pipeId].nodeNum[nodeType] = ispNums[CAPTURE_NODE_2];
    strncpy(m_nodeInfo[pipeId].nodeName[nodeType], "ISP_PREVIEW", EXYNOS_CAMERA_NAME_STR_SIZE - 1);
    m_sensorIds[pipeId][nodeType] = m_getSensorId(ispNums[OUTPUT_NODE], false, false, false);
    m_nodeInfo[pipeId].pipeId[nodeType] = PIPE_ISPP;

    for (int i = 0; i < MAX_NODE; i++)
        m_nodeNums[pipeId][i] = m_nodeInfo[pipeId].nodeNum[i];
    if (m_checkNodeSetting(pipeId) != NO_ERROR)
        return INVALID_OPERATION;

    pipeId = INDEX(PIPE_DIS);
    nodeType = getNodeType(PIPE_DIS);
    m_nodeInfo[pipeId].nodeNum[nodeType] = FIMC_IS_VIDEO_TPU_NUM;
    strncpy(m_nodeInfo[pipeId].nodeName[nodeType], "DIS_OUTPUT", EXYNOS_CAMERA_NAME_STR_SIZE - 1);
    m_sensorIds[pipeId][nodeType] = m_getSensorId(ispNums[CAPTURE_NODE_2], false, false, false);
    m_nodeInfo[pipeId].pipeId[nodeType] = PIPE_DIS;

    nodeType = getNodeType(PIPE_SCP);
    m_nodeInfo[pipeId].nodeNum[nodeType] = FIMC_IS_VIDEO_SCP_NUM;
    strncpy(m_nodeInfo[pipeId].nodeName[nodeType], "SCP_PREVIEW", EXYNOS_CAMERA_NAME_STR_SIZE - 1);
    m_sensorIds[pipeId][nodeType] = m_getSensorId(FIMC_IS_VIDEO_TPU_NUM, true, false, false);
    m_nodeInfo[pipeId].pipeId[nodeType] = PIPE_SCP;

    for (int i = 0; i < MAX_NODE; i++)
        m_nodeNums[pipeId][i] = m_nodeInfo[pipeId].nodeNum[i];
    if (m_checkNodeSetting(pipeId) != NO_ERROR)
        return INVALID_OPERATION;

    ALOGI("M86_NATIVE3_GRAPH PIPE_3AA=110/112/130/132 PIPE_DIS=150/152 30C=off");
    return NO_ERROR;
}

status_t ExynosCamera3FrameFactoryPreviewM86::m_initPipes(void)
{
    status_t ret;
    camera_pipe_info_t pipeInfo[MAX_NODE];
    int32_t sensorIds[MAX_NODE];
    int32_t secondarySensorIds[MAX_NODE];
    ExynosRect rect = {0, };
    ExynosRect bds = {0, };
    int hwPreviewW = 0, hwPreviewH = 0;
    struct ExynosConfigInfo *config = m_parameters->getConfig();
    const int bayerFormat = CAMERA_BAYER_FORMAT;
    const int previewFormat = m_parameters->getHwPreviewFormat();
    const int hwVdisFormat = m_parameters->getHWVdisFormat();

    m_parameters->getPreviewBdsSize(&bds);
    m_parameters->getHwPreviewSize(&hwPreviewW, &hwPreviewH);

    memset(pipeInfo, 0, sizeof(pipeInfo));
    for (int i = 0; i < MAX_NODE; i++) {
        ret = m_pipes[INDEX(PIPE_3AA)]->setPipeId(
                (enum NODE_TYPE)i, m_nodeInfo[INDEX(PIPE_3AA)].pipeId[i]);
        if (ret != NO_ERROR)
            return ret;
        sensorIds[i] = m_sensorIds[INDEX(PIPE_3AA)][i];
        secondarySensorIds[i] = m_secondarySensorIds[INDEX(PIPE_3AA)][i];
    }

    const enum NODE_TYPE t3as = getNodeType(PIPE_3AA);
    rect.fullW = 32;
    rect.fullH = 64;
    rect.colorFormat = bayerFormat;
    pipeInfo[t3as].rectInfo = rect;
    pipeInfo[t3as].bufInfo.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
    pipeInfo[t3as].bufInfo.memory = V4L2_CAMERA_MEMORY_TYPE;
    pipeInfo[t3as].bufInfo.count = config->current->bufInfo.num_3aa_buffers;
    pipeInfo[t3as].perFrameNodeGroupInfo.perframeSupportNodeNum = CAPTURE_NODE_MAX;
    pipeInfo[t3as].perFrameNodeGroupInfo.perFrameLeaderInfo.perframeInfoIndex = PERFRAME_INFO_3AA;
    pipeInfo[t3as].perFrameNodeGroupInfo.perFrameLeaderInfo.perFrameNodeType = PERFRAME_NODE_TYPE_LEADER;
    pipeInfo[t3as].perFrameNodeGroupInfo.perFrameLeaderInfo.perFrameVideoID =
            FIMC_IS_VIDEO_30S_NUM - FIMC_IS_VIDEO_BAS_NUM;

    const enum NODE_TYPE t3ap = getNodeType(PIPE_3AP);
    int perFramePos = (m_cameraId == CAMERA_ID_BACK) ? PERFRAME_BACK_3AP_POS : PERFRAME_FRONT_3AP_POS;
    pipeInfo[t3as].perFrameNodeGroupInfo.perFrameCaptureInfo[perFramePos].perFrameNodeType = PERFRAME_NODE_TYPE_CAPTURE;
    pipeInfo[t3as].perFrameNodeGroupInfo.perFrameCaptureInfo[perFramePos].perFrameVideoID =
            FIMC_IS_VIDEO_30P_NUM - FIMC_IS_VIDEO_BAS_NUM;
    pipeInfo[t3ap].perFrameNodeGroupInfo.perFrameLeaderInfo.perFrameNodeType = PERFRAME_NODE_TYPE_NONE;

    const enum NODE_TYPE isps = getNodeType(PIPE_ISP);
    pipeInfo[isps].perFrameNodeGroupInfo.perFrameLeaderInfo.perframeInfoIndex = PERFRAME_INFO_ISP;
    pipeInfo[isps].perFrameNodeGroupInfo.perFrameLeaderInfo.perFrameNodeType = PERFRAME_NODE_TYPE_LEADER;
    pipeInfo[isps].perFrameNodeGroupInfo.perFrameLeaderInfo.perFrameVideoID =
            FIMC_IS_VIDEO_I0S_NUM - FIMC_IS_VIDEO_BAS_NUM;

    const enum NODE_TYPE ispp = getNodeType(PIPE_ISPP);
    perFramePos = (m_cameraId == CAMERA_ID_BACK) ? PERFRAME_BACK_ISPP_POS : PERFRAME_FRONT_ISPP_POS;
    pipeInfo[t3as].perFrameNodeGroupInfo.perFrameCaptureInfo[perFramePos].perFrameNodeType = PERFRAME_NODE_TYPE_CAPTURE;
    pipeInfo[t3as].perFrameNodeGroupInfo.perFrameCaptureInfo[perFramePos].perFrameVideoID =
            FIMC_IS_VIDEO_I0P_NUM - FIMC_IS_VIDEO_BAS_NUM;
    rect.fullW = bds.w;
    rect.fullH = bds.h;
    rect.colorFormat = hwVdisFormat;
    pipeInfo[ispp].rectInfo = rect;
    pipeInfo[ispp].bufInfo.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
    pipeInfo[ispp].bufInfo.memory = V4L2_CAMERA_MEMORY_TYPE;
    pipeInfo[ispp].bufInfo.count = config->current->bufInfo.num_hwdis_buffers;
    pipeInfo[ispp].perFrameNodeGroupInfo.perFrameLeaderInfo.perFrameNodeType = PERFRAME_NODE_TYPE_NONE;

    ret = m_pipes[INDEX(PIPE_3AA)]->setupPipe(pipeInfo, sensorIds, secondarySensorIds);
    if (ret != NO_ERROR)
        return INVALID_OPERATION;

    memset(pipeInfo, 0, sizeof(pipeInfo));
    for (int i = 0; i < MAX_NODE; i++) {
        ret = m_pipes[INDEX(PIPE_DIS)]->setPipeId(
                (enum NODE_TYPE)i, m_nodeInfo[INDEX(PIPE_DIS)].pipeId[i]);
        if (ret != NO_ERROR)
            return ret;
        sensorIds[i] = m_sensorIds[INDEX(PIPE_DIS)][i];
        secondarySensorIds[i] = m_secondarySensorIds[INDEX(PIPE_DIS)][i];
    }

    const enum NODE_TYPE dis = getNodeType(PIPE_DIS);
    rect.fullW = bds.w;
    rect.fullH = bds.h;
    rect.colorFormat = hwVdisFormat;
    pipeInfo[dis].rectInfo = rect;
    pipeInfo[dis].bytesPerPlane[0] = ROUND_UP(bds.w, 16);
    pipeInfo[dis].bufInfo.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
    pipeInfo[dis].bufInfo.memory = V4L2_CAMERA_MEMORY_TYPE;
    pipeInfo[dis].bufInfo.count = config->current->bufInfo.num_hwdis_buffers;
    pipeInfo[dis].perFrameNodeGroupInfo.perframeSupportNodeNum = CAPTURE_NODE_MAX;
    pipeInfo[dis].perFrameNodeGroupInfo.perFrameLeaderInfo.perframeInfoIndex = PERFRAME_INFO_DIS;
    pipeInfo[dis].perFrameNodeGroupInfo.perFrameLeaderInfo.perFrameNodeType = PERFRAME_NODE_TYPE_LEADER;
    pipeInfo[dis].perFrameNodeGroupInfo.perFrameLeaderInfo.perFrameVideoID =
            FIMC_IS_VIDEO_TPU_NUM - FIMC_IS_VIDEO_BAS_NUM;

    const enum NODE_TYPE scp = getNodeType(PIPE_SCP);
    rect.fullW = hwPreviewW;
    rect.fullH = hwPreviewH;
    rect.colorFormat = previewFormat;
    pipeInfo[scp].rectInfo = rect;
    pipeInfo[scp].bufInfo.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
    pipeInfo[scp].bufInfo.memory = V4L2_CAMERA_MEMORY_TYPE;
    pipeInfo[scp].bufInfo.count = config->current->bufInfo.num_preview_buffers;
    perFramePos = (m_cameraId == CAMERA_ID_BACK) ? PERFRAME_BACK_SCP_POS : PERFRAME_FRONT_SCP_POS;
    pipeInfo[dis].perFrameNodeGroupInfo.perFrameCaptureInfo[perFramePos].perFrameNodeType = PERFRAME_NODE_TYPE_CAPTURE;
    pipeInfo[dis].perFrameNodeGroupInfo.perFrameCaptureInfo[perFramePos].perFrameVideoID =
            FIMC_IS_VIDEO_SCP_NUM - FIMC_IS_VIDEO_BAS_NUM;
    pipeInfo[scp].perFrameNodeGroupInfo.perFrameLeaderInfo.perFrameNodeType = PERFRAME_NODE_TYPE_NONE;

    ret = m_pipes[INDEX(PIPE_DIS)]->setupPipe(pipeInfo, sensorIds, secondarySensorIds);
    if (ret != NO_ERROR)
        return INVALID_OPERATION;

    ALOGI("M86_NATIVE3_GRAPH init 3AA->I0P(M2M %dx%d)->DIS->SCP(%dx%d)",
          bds.w, bds.h, hwPreviewW, hwPreviewH);
    return NO_ERROR;
}

status_t ExynosCamera3FrameFactoryPreviewM86::m_fillNodeGroupInfo(
        ExynosCameraFrame *frame)
{
    status_t ret = ExynosCamera3FrameFactoryPreview::m_fillNodeGroupInfo(frame);
    if (ret != NO_ERROR || frame == nullptr) {
        return ret;
    }

    const uint32_t frameCount = frame->getFrameCount();
    if (frameCount <= 3 || (frameCount % 100) == 0) {
        ExynosRect bayerSrc = {0, };
        ExynosRect bayerCrop = {0, };
        ExynosRect bds = {0, };
        status_t cropRet = m_parameters->getPreviewBayerCropSize(
                &bayerSrc, &bayerCrop);
        status_t bdsRet = m_parameters->getPreviewBdsSize(&bds);
        if (cropRet == NO_ERROR && bdsRet == NO_ERROR) {
            const int outputW = bayerCrop.w < bds.w ? bayerCrop.w : bds.w;
            const int outputH = bayerCrop.h < bds.h ? bayerCrop.h : bds.h;
            ALOGI("M86_NATIVE3_BDS frame=%u BCROP=%dx%d BDS=%dx%d 30P=%dx%d ISP-input=%dx%d",
                  frameCount, bayerCrop.w, bayerCrop.h, bds.w, bds.h,
                  outputW, outputH, outputW, outputH);
        } else {
            ALOGE("M86_NATIVE3_BDS frame=%u size query failed crop=%d bds=%d",
                  frameCount, cropRet, bdsRet);
        }
    }

    return NO_ERROR;
}

ExynosCameraFrame *ExynosCamera3FrameFactoryPreviewM86::createNewFrame(
        uint32_t frameCount)
{
    if (frameCount == 0) {
        frameCount = m_frameCount;
    }

    ExynosCameraFrame *frame = m_frameMgr->createFrame(
            m_parameters, frameCount, FRAME_TYPE_PREVIEW);
    if (frame == nullptr) {
        return nullptr;
    }
    status_t ret = m_initFrameMetadata(frame);
    if (ret != NO_ERROR) {
        ALOGE("M86_NATIVE3_GRAPH frame metadata failed frame=%u ret=%d",
              frameCount, ret);
    }

    ExynosCameraFrameEntity *leader = new ExynosCameraFrameEntity(
            PIPE_3AA, ENTITY_TYPE_INPUT_ONLY, ENTITY_BUFFER_FIXED);
    frame->addSiblingEntity(nullptr, leader);
    ExynosCameraFrameEntity *dis = new ExynosCameraFrameEntity(
            PIPE_DIS, ENTITY_TYPE_INPUT_ONLY, ENTITY_BUFFER_DELIVERY);
    frame->addChildEntity(leader, dis, INDEX(PIPE_ISPP));
    ExynosCameraFrameEntity *gsc = new ExynosCameraFrameEntity(
            PIPE_GSC, ENTITY_TYPE_INPUT_OUTPUT, ENTITY_BUFFER_FIXED);
    frame->addSiblingEntity(nullptr, gsc);

    ret = m_initPipelines(frame);
    if (ret != NO_ERROR) {
        ALOGE("M86_NATIVE3_GRAPH pipeline init failed frame=%u ret=%d",
              frameCount, ret);
    }
    frame->setNumRequestPipe(2);
    m_fillNodeGroupInfo(frame);
    ++m_frameCount;

    ALOGV("M86_NATIVE3_GRAPH frame=%u leader=%d 30C=%d SCP=%d",
          frame->getFrameCount(), PIPE_3AA,
          frame->getRequest(PIPE_3AC), frame->getRequest(PIPE_SCP));
    return frame;
}

ExynosCameraFrame *ExynosCamera3FrameFactoryPreviewM86::createNewFrame(void)
{
    return createNewFrame(0);
}

status_t ExynosCamera3FrameFactoryPreviewM86::initPipes(void)
{
    return ExynosCamera3FrameFactoryPreview::initPipes();
}

status_t ExynosCamera3FrameFactoryPreviewM86::preparePipes(void)
{
    return ExynosCamera3FrameFactoryPreview::preparePipes();
}

status_t ExynosCamera3FrameFactoryPreviewM86::startPipes(void)
{
    status_t ret = m_pipes[INDEX(PIPE_DIS)]->start();
    if (ret != NO_ERROR)
        return INVALID_OPERATION;
    ret = m_pipes[INDEX(PIPE_3AA)]->start();
    if (ret != NO_ERROR)
        return INVALID_OPERATION;
    ret = m_pipes[INDEX(PIPE_FLITE)]->start();
    if (ret != NO_ERROR)
        return INVALID_OPERATION;
    ret = m_pipes[INDEX(PIPE_3AA)]->prepare();
    if (ret != NO_ERROR)
        return INVALID_OPERATION;
    ret = m_pipes[INDEX(PIPE_FLITE)]->sensorStream(true);
    ALOGI("M86_NATIVE3_GRAPH start DIS then 3AA ret=%d", ret);
    return ret;
}

status_t ExynosCamera3FrameFactoryPreviewM86::startInitialThreads(void)
{
    status_t ret = startThread(PIPE_3AA);
    if (ret == NO_ERROR)
        ret = startThread(PIPE_DIS);
    ALOGI("M86_NATIVE3_GRAPH start threads 3AA/DIS ret=%d", ret);
    return ret;
}

status_t ExynosCamera3FrameFactoryPreviewM86::setStopFlag(void)
{
    status_t ret = NO_ERROR;
    if (m_pipes[INDEX(PIPE_FLITE)] != nullptr) {
        ret = m_pipes[INDEX(PIPE_FLITE)]->setStopFlag();
    }
    if (m_pipes[INDEX(PIPE_3AA)] != nullptr &&
        m_pipes[INDEX(PIPE_3AA)]->flagStart()) {
        ret |= m_pipes[INDEX(PIPE_3AA)]->setStopFlag();
    }
    if (m_pipes[INDEX(PIPE_DIS)] != nullptr &&
        m_pipes[INDEX(PIPE_DIS)]->flagStart()) {
        ret |= m_pipes[INDEX(PIPE_DIS)]->setStopFlag();
    }
    ALOGI("M86_NATIVE3_FLUSH set-stop leader ret=%d", ret);
    return ret;
}

status_t ExynosCamera3FrameFactoryPreviewM86::stopPipes(void)
{
    status_t ret = NO_ERROR;
    ALOGI("M86_NATIVE3_FLUSH stop begin leader=PIPE_3AA");

    if (m_pipes[INDEX(PIPE_DIS)] != nullptr &&
        m_pipes[INDEX(PIPE_DIS)]->isThreadRunning()) {
        ret = m_pipes[INDEX(PIPE_DIS)]->stopThread();
        if (ret != NO_ERROR)
            return INVALID_OPERATION;
    }

    if (m_pipes[INDEX(PIPE_GSC)] != nullptr &&
        m_pipes[INDEX(PIPE_GSC)]->isThreadRunning()) {
        ret = stopThread(INDEX(PIPE_GSC));
        if (ret != NO_ERROR) {
            return INVALID_OPERATION;
        }
    }
    if (m_pipes[INDEX(PIPE_3AA)] != nullptr &&
        m_pipes[INDEX(PIPE_3AA)]->isThreadRunning()) {
        ret = m_pipes[INDEX(PIPE_3AA)]->stopThread();
        if (ret != NO_ERROR) {
            return INVALID_OPERATION;
        }
    }
    if (m_pipes[INDEX(PIPE_FLITE)] != nullptr) {
        ret = m_pipes[INDEX(PIPE_FLITE)]->sensorStream(false);
        if (ret != NO_ERROR) {
            return INVALID_OPERATION;
        }
        ret = m_pipes[INDEX(PIPE_FLITE)]->stop();
        if (ret != NO_ERROR) {
            return INVALID_OPERATION;
        }
    }
    if (m_pipes[INDEX(PIPE_3AA)] != nullptr &&
        m_pipes[INDEX(PIPE_3AA)]->flagStart()) {
        const status_t forceRet =
                m_pipes[INDEX(PIPE_3AA)]->forceDone(V4L2_CID_IS_FORCE_DONE, 0x1000);
        if (forceRet != NO_ERROR) {
            ALOGW("M86_NATIVE3_FLUSH leader forceDone ret=%d", forceRet);
        }
        ret = m_pipes[INDEX(PIPE_3AA)]->stop();
        if (ret != NO_ERROR) {
            return INVALID_OPERATION;
        }
    }
    if (m_pipes[INDEX(PIPE_DIS)] != nullptr &&
        m_pipes[INDEX(PIPE_DIS)]->flagStart()) {
        const status_t forceRet =
                m_pipes[INDEX(PIPE_DIS)]->forceDone(V4L2_CID_IS_FORCE_DONE, 0x1000);
        if (forceRet != NO_ERROR)
            ALOGW("M86_NATIVE3_FLUSH DIS forceDone ret=%d", forceRet);
        ret = m_pipes[INDEX(PIPE_DIS)]->stop();
        if (ret != NO_ERROR)
            return INVALID_OPERATION;
    }
    if (m_pipes[INDEX(PIPE_GSC)] != nullptr) {
        const status_t waitRet = stopThreadAndWait(INDEX(PIPE_GSC));
        if (waitRet != NO_ERROR) {
            ALOGW("M86_NATIVE3_FLUSH GSC drain ret=%d", waitRet);
        }
    }
    ALOGI("M86_NATIVE3_FLUSH stop complete ret=%d", ret);
    return ret;
}

int ExynosCamera3FrameFactoryPreviewM86::resolveLeaderPipe(int pipeId) const
{
    switch (pipeId) {
    case PIPE_3AA:
    case PIPE_3AC:
    case PIPE_3AP:
    case PIPE_ISP:
    case PIPE_ISPP:
        return PIPE_3AA;
    case PIPE_DIS:
    case PIPE_SCP:
        return PIPE_DIS;
    default:
        return pipeId;
    }
}

enum NODE_TYPE ExynosCamera3FrameFactoryPreviewM86::getNodeType(uint32_t pipeId)
{
    switch (pipeId) {
    case PIPE_FLITE: return CAPTURE_NODE_1;
    case PIPE_3AA: return OUTPUT_NODE;
    case PIPE_3AC: return CAPTURE_NODE_1;
    case PIPE_3AP: return OTF_NODE_1;
    case PIPE_ISP: return OTF_NODE_2;
    case PIPE_ISPP: return CAPTURE_NODE_4;
    case PIPE_DIS: return OUTPUT_NODE;
    case PIPE_ISPC:
    case PIPE_SCC:
    case PIPE_JPEG: return CAPTURE_NODE_5;
    case PIPE_SCP: return CAPTURE_NODE_6;
    default:
        android_printAssert(nullptr, LOG_TAG,
                "Unexpected M86 pipe id %u", pipeId);
        return INVALID_NODE;
    }
}

} // namespace android
