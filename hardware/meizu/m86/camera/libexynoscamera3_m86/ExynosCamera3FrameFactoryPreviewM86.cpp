/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#define LOG_TAG "ExynosCamera3FactoryM86"
#include <cutils/log.h>

#include "ExynosCamera3FrameFactoryPreviewM86.h"

namespace android {

namespace {

void setM86FixedNodeSize(camera2_node *node, int width, int height)
{
    node->input.cropRegion[0] = 0;
    node->input.cropRegion[1] = 0;
    node->input.cropRegion[2] = width;
    node->input.cropRegion[3] = height;
    node->output.cropRegion[0] = 0;
    node->output.cropRegion[1] = 0;
    node->output.cropRegion[2] = width;
    node->output.cropRegion[3] = height;
}

void forceM86PreviewBds(camera2_node_group *nodeGroup3aa,
                        camera2_node_group *nodeGroupIsp,
                        camera2_node_group *nodeGroupDis,
                        int width, int height)
{
    camera2_node *taaOutput =
            &nodeGroup3aa->capture[PERFRAME_BACK_3AP_POS];
    taaOutput->output.cropRegion[0] = 0;
    taaOutput->output.cropRegion[1] = 0;
    taaOutput->output.cropRegion[2] = width;
    taaOutput->output.cropRegion[3] = height;

    setM86FixedNodeSize(
            &nodeGroup3aa->capture[PERFRAME_BACK_ISPP_POS], width, height);
    setM86FixedNodeSize(
            &nodeGroup3aa->capture[PERFRAME_BACK_SCP_POS], width, height);

    setM86FixedNodeSize(&nodeGroupIsp->leader, width, height);
    setM86FixedNodeSize(
            &nodeGroupIsp->capture[PERFRAME_BACK_ISPP_POS], width, height);
    setM86FixedNodeSize(
            &nodeGroupIsp->capture[PERFRAME_BACK_SCP_POS], width, height);

    setM86FixedNodeSize(&nodeGroupDis->leader, width, height);
    setM86FixedNodeSize(
            &nodeGroupDis->capture[PERFRAME_BACK_SCP_POS], width, height);
}

} // namespace

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
    static_assert(CAMERA_BAYER_FORMAT ==
                          ExynosCamera3HwCapsM86::fliteBayerFormat,
                  "m86 FLITE must use the HAL1-proven packed BG12 format");
    static_assert(CAMERA_DUMP_BAYER_FORMAT ==
                          ExynosCamera3HwCapsM86::rawDumpBayerFormat,
                  "m86 raw dump must remain the unpacked BG16 format");

    ALOGI("M86_NATIVE3_GRAPH create camera=%d SS%d->30S->30P->I0S->DIS->SCP "
          "active=%d wire=RAW%d flite=0x%x preview=0x%x buffers=%d/%d/%d",
          m_cameraId, m_cameraId == CAMERA_ID_BACK ? 0 : 1,
          active, ExynosCamera3HwCapsM86::sensorWireBitDepth,
          ExynosCamera3HwCapsM86::fliteBayerFormat,
          ExynosCamera3HwCapsM86::previewYuvFormat,
          ExynosCamera3HwCapsM86::sensorBufferCount,
          ExynosCamera3HwCapsM86::aa3BufferCount,
          ExynosCamera3HwCapsM86::previewBufferCount);

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

    m_pipes[INDEX(PIPE_GSC)] = (ExynosCameraPipe *)new ExynosCameraPipeGSC(
            m_cameraId, reinterpret_cast<ExynosCameraParameters *>(m_parameters),
            true, m_nodeNums[INDEX(PIPE_GSC)]);
    m_pipes[INDEX(PIPE_GSC)]->setPipeId(PIPE_GSC);
    m_pipes[INDEX(PIPE_GSC)]->setPipeName("PIPE_GSC_M86_PREVIEW");

    m_pipes[INDEX(PIPE_GSC_VIDEO)] = (ExynosCameraPipe *)new ExynosCameraPipeGSC(
            m_cameraId, reinterpret_cast<ExynosCameraParameters *>(m_parameters),
            true, m_nodeNums[INDEX(PIPE_GSC_VIDEO)]);
    m_pipes[INDEX(PIPE_GSC_VIDEO)]->setPipeId(PIPE_GSC_VIDEO);
    m_pipes[INDEX(PIPE_GSC_VIDEO)]->setPipeName("PIPE_GSC_M86_VIDEO");

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
    ret = m_pipes[INDEX(PIPE_GSC)]->create();
    if (ret != NO_ERROR) {
        ALOGE("M86_NATIVE3_GRAPH preview GSC create failed ret=%d", ret);
        return INVALID_OPERATION;
    }
    ret = m_pipes[INDEX(PIPE_GSC_VIDEO)]->create();
    if (ret != NO_ERROR) {
        ALOGE("M86_NATIVE3_GRAPH video GSC create failed ret=%d", ret);
        return INVALID_OPERATION;
    }
    ret = m_pipes[INDEX(PIPE_3AA)]->setControl(V4L2_CID_IS_END_OF_STREAM, 1);
    if (ret != NO_ERROR) {
        ALOGE("M86_NATIVE3_GRAPH leader EOS failed ret=%d", ret);
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
    m_supportReprocessing =
            ExynosCamera3HwCapsM86::dirtyBayerReprocessing;
    m_supportPureBayerReprocessing = false;
    m_flagReprocessing = false;

    m_requestFLITE = 0;
    m_request3AC = ExynosCamera3HwCapsM86::dirtyBayerReprocessing ? 1 : 0;
    m_request3AP = 0;
    m_requestISP = 0;
    m_requestISPP = 0;
    m_requestISPC = 0;
    m_requestSCC = 0;
    m_requestDIS = 0;
    m_requestSCP = 1;
    m_requestVRA = 0;

    ALOGI("M86_NATIVE3_GRAPH requests 30S=leader 30C=%d 30P=OTF "
          "ISP=OTF DIS=OTF SCP=1",
          m_request3AC);
    return NO_ERROR;
}

status_t ExynosCamera3FrameFactoryPreviewM86::m_setDeviceInfo(void)
{
    m_supportReprocessing =
            ExynosCamera3HwCapsM86::dirtyBayerReprocessing;
    m_supportPureBayerReprocessing = false;
    status_t ret = ExynosCamera3FrameFactoryPreview::m_setDeviceInfo();
    if (ret == NO_ERROR) {
        ALOGI("M86_NATIVE3_GRAPH camera=%d owner=PIPE_3AA "
              "nodes=110,111,112,130,132,150,152 30C=dirty-bayer",
              m_cameraId);
    }
    return ret;
}

status_t ExynosCamera3FrameFactoryPreviewM86::m_initPipes(void)
{
    ALOGI("M86_NATIVE3_GRAPH init leader=%d scp-owner=%d",
          resolveLeaderPipe(PIPE_ISP), resolveLeaderPipe(PIPE_SCP));
    return ExynosCamera3FrameFactoryPreview::m_initPipes();
}

status_t ExynosCamera3FrameFactoryPreviewM86::m_fillNodeGroupInfo(
        ExynosCameraFrame *frame)
{
    status_t ret = ExynosCamera3FrameFactoryPreview::m_fillNodeGroupInfo(frame);
    if (ret != NO_ERROR || frame == nullptr) {
        return ret;
    }

    const uint32_t frameCount = frame->getFrameCount();
    if (m_cameraId == CAMERA_ID_BACK) {
        camera2_node_group nodeGroup3aa;
        camera2_node_group nodeGroupIsp;
        camera2_node_group nodeGroupDis;
        ExynosRect bayerSrc = {0, };
        ExynosRect ignoredDynamicCrop = {0, };
        ExynosRect fixedBayerCrop = {0, };
        ExynosRect fixedBds = {0, };
        int previewW = 0;
        int previewH = 0;
        int pictureW = 0;
        int pictureH = 0;

        m_parameters->getHwPreviewSize(&previewW, &previewH);
        m_parameters->getPictureSize(&pictureW, &pictureH);
        ret = m_parameters->getPreviewBayerCropSize(
                &bayerSrc, &ignoredDynamicCrop);
        if (ret != NO_ERROR) {
            ALOGE("M86_NATIVE3_ZOOM frame=%u cannot query Bayer source ret=%d",
                  frameCount, ret);
            return ret;
        }

        const bool preview4By3 =
                static_cast<int64_t>(previewW) * 3 ==
                static_cast<int64_t>(previewH) * 4;
        fixedBayerCrop.w = 5312;
        fixedBayerCrop.h = preview4By3 ? 3984 : 2988;
        fixedBayerCrop.w = fixedBayerCrop.w < bayerSrc.w
                ? fixedBayerCrop.w : ALIGN_DOWN(bayerSrc.w, CAMERA_BCROP_ALIGN);
        fixedBayerCrop.h = fixedBayerCrop.h < bayerSrc.h
                ? fixedBayerCrop.h : ALIGN_DOWN(bayerSrc.h, 2);
        fixedBayerCrop.x = ALIGN_DOWN((bayerSrc.w - fixedBayerCrop.w) >> 1, 2);
        fixedBayerCrop.y = ALIGN_DOWN((bayerSrc.h - fixedBayerCrop.h) >> 1, 2);
        fixedBds.w = previewW;
        fixedBds.h = previewH;

        frame->getNodeGroupInfo(&nodeGroup3aa, PERFRAME_INFO_3AA);
        frame->getNodeGroupInfo(&nodeGroupIsp, PERFRAME_INFO_ISP);
        frame->getNodeGroupInfo(&nodeGroupDis, PERFRAME_INFO_DIS);

        /* Keep the fixed, HAL1-proven M86 3AA graph. Camera3 cropRegion is
         * applied later by PIPE_GSC; the
         * inline SCP node must never be reconfigured while streaming. */
        ExynosCameraNodeGroup3AA::updateNodeGroupInfo(
                m_cameraId, &nodeGroup3aa, fixedBayerCrop, fixedBds,
                previewW, previewH, pictureW, pictureH);
        ExynosCameraNodeGroupISP::updateNodeGroupInfo(
                m_cameraId, &nodeGroupIsp, fixedBayerCrop, fixedBds,
                previewW, previewH, pictureW, pictureH,
                m_parameters->getHWVdisMode());
        ExynosCameraNodeGroupDIS::updateNodeGroupInfo(
                m_cameraId, &nodeGroupDis, fixedBayerCrop, fixedBds,
                previewW, previewH, pictureW, pictureH,
                m_parameters->getHWVdisMode());

        /* CAMERA_HAS_OWN_BDS is false in the donor configuration, but the
         * PRO 5 firmware requires the HAL1-proven 30P/ISP dimensions. */
        forceM86PreviewBds(&nodeGroup3aa, &nodeGroupIsp, &nodeGroupDis,
                           fixedBds.w, fixedBds.h);

        frame->storeNodeGroupInfo(&nodeGroup3aa, PERFRAME_INFO_3AA);
        frame->storeNodeGroupInfo(&nodeGroupIsp, PERFRAME_INFO_ISP);
        frame->storeNodeGroupInfo(&nodeGroupDis, PERFRAME_INFO_DIS);

    }

    if (frameCount <= 3 || (frameCount % 100) == 0) {
        camera2_node_group nodeGroup3aa;
        frame->getNodeGroupInfo(&nodeGroup3aa, PERFRAME_INFO_3AA);
        const camera2_node *leader = &nodeGroup3aa.leader;
        const camera2_node *bds =
                &nodeGroup3aa.capture[PERFRAME_BACK_3AP_POS];
        ALOGI("M86_NATIVE3_BDS frame=%u BCROP=(%d,%d %dx%d) "
              "30P=%dx%d ISP-input=%dx%d",
              frameCount,
              leader->input.cropRegion[0], leader->input.cropRegion[1],
              leader->input.cropRegion[2], leader->input.cropRegion[3],
              bds->output.cropRegion[2], bds->output.cropRegion[3],
              bds->output.cropRegion[2], bds->output.cropRegion[3]);
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
    ExynosCameraFrameEntity *gsc = new ExynosCameraFrameEntity(
            PIPE_GSC, ENTITY_TYPE_INPUT_OUTPUT, ENTITY_BUFFER_FIXED);
    frame->addSiblingEntity(nullptr, gsc);
    ExynosCameraFrameEntity *gscVideo = new ExynosCameraFrameEntity(
            PIPE_GSC_VIDEO, ENTITY_TYPE_INPUT_OUTPUT, ENTITY_BUFFER_FIXED);
    frame->addSiblingEntity(nullptr, gscVideo);

    ret = m_initPipelines(frame);
    if (ret != NO_ERROR) {
        ALOGE("M86_NATIVE3_GRAPH pipeline init failed frame=%u ret=%d",
              frameCount, ret);
    }
    frame->setNumRequestPipe(1);
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
    ALOGI("M86_NATIVE3_GRAPH start leader=PIPE_3AA");
    return ExynosCamera3FrameFactoryPreview::startPipes();
}

status_t ExynosCamera3FrameFactoryPreviewM86::startInitialThreads(void)
{
    status_t ret = startThread(PIPE_3AA);
    ALOGI("M86_NATIVE3_GRAPH start thread leader=PIPE_3AA ret=%d", ret);
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
    ALOGI("M86_NATIVE3_FLUSH set-stop leader ret=%d", ret);
    return ret;
}

status_t ExynosCamera3FrameFactoryPreviewM86::stopPipes(void)
{
    status_t ret = NO_ERROR;
    status_t firstError = NO_ERROR;
    ALOGI("M86_NATIVE3_FLUSH stop begin leader=PIPE_3AA");

    if (m_pipes[INDEX(PIPE_GSC)] != nullptr &&
        m_pipes[INDEX(PIPE_GSC)]->isThreadRunning()) {
        ret = stopThread(INDEX(PIPE_GSC));
        if (ret != NO_ERROR) {
            if (firstError == NO_ERROR)
                firstError = ret;
        }
    }
    if (m_pipes[INDEX(PIPE_GSC_VIDEO)] != nullptr &&
        m_pipes[INDEX(PIPE_GSC_VIDEO)]->isThreadRunning()) {
        ret = stopThread(INDEX(PIPE_GSC_VIDEO));
        if (ret != NO_ERROR) {
            if (firstError == NO_ERROR)
                firstError = ret;
        }
    }
    if (m_pipes[INDEX(PIPE_3AA)] != nullptr &&
        m_pipes[INDEX(PIPE_3AA)]->isThreadRunning()) {
        ret = m_pipes[INDEX(PIPE_3AA)]->stopThread();
        if (ret != NO_ERROR) {
            if (firstError == NO_ERROR)
                firstError = ret;
        }
    }
    if (m_pipes[INDEX(PIPE_FLITE)] != nullptr) {
        ret = m_pipes[INDEX(PIPE_FLITE)]->sensorStream(false);
        if (ret != NO_ERROR) {
            ALOGW("M86_PIPELINE FLITE sensor disable ret=%d; continue cleanup",
                  ret);
            if (firstError == NO_ERROR)
                firstError = ret;
        }
        ret = m_pipes[INDEX(PIPE_FLITE)]->stop();
        if (ret != NO_ERROR) {
            ALOGE("M86_PIPELINE FLITE stop ret=%d; software cleanup completed",
                  ret);
            if (firstError == NO_ERROR)
                firstError = ret;
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
            ALOGE("M86_PIPELINE 3AA stop ret=%d; continue cleanup", ret);
            if (firstError == NO_ERROR)
                firstError = ret;
        }
    }
    if (m_pipes[INDEX(PIPE_GSC)] != nullptr) {
        const status_t waitRet = stopThreadAndWait(INDEX(PIPE_GSC));
        if (waitRet != NO_ERROR) {
            ALOGW("M86_NATIVE3_FLUSH GSC drain ret=%d", waitRet);
        }
    }
    if (m_pipes[INDEX(PIPE_GSC_VIDEO)] != nullptr) {
        const status_t waitRet = stopThreadAndWait(INDEX(PIPE_GSC_VIDEO));
        if (waitRet != NO_ERROR) {
            ALOGW("M86_NATIVE3_FLUSH video GSC drain ret=%d", waitRet);
        }
    }
    ALOGI("M86_NATIVE3_FLUSH stop complete ret=%d", firstError);
    return firstError;
}

int ExynosCamera3FrameFactoryPreviewM86::resolveLeaderPipe(int pipeId) const
{
    switch (pipeId) {
    case PIPE_3AA:
    case PIPE_3AC:
    case PIPE_3AP:
    case PIPE_ISP:
    case PIPE_ISPP:
    case PIPE_DIS:
    case PIPE_SCP:
        return PIPE_3AA;
    default:
        return pipeId;
    }
}

} // namespace android
