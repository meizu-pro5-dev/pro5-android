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

    ALOGI("M86_NATIVE3_GRAPH create SS0->30S->I0S->DIS->SCP active=%d", active);

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
    m_supportReprocessing = true; // Preview 30C is retained for later dirty Bayer JPEG.
    m_supportPureBayerReprocessing = false;
    m_flagReprocessing = false;

    m_requestFLITE = 0;
    m_request3AC = 1;
    m_request3AP = 0;
    m_requestISP = 0;
    m_requestISPP = 0;
    m_requestISPC = 0;
    m_requestSCC = 0;
    m_requestDIS = 0;
    m_requestSCP = 1;
    m_requestVRA = 0;

    ALOGI("M86_NATIVE3_GRAPH requests 30S=leader 30C=1 30P=0 ISP=0 DIS=0 SCP=1");
    return NO_ERROR;
}

status_t ExynosCamera3FrameFactoryPreviewM86::m_setDeviceInfo(void)
{
    // Force the preview MCPipe to expose 30C even though the stage-1 public
    // API does not expose a reprocessing/JPEG stream.
    m_supportReprocessing = true;
    m_supportPureBayerReprocessing = false;
    status_t ret = ExynosCamera3FrameFactoryPreview::m_setDeviceInfo();
    if (ret == NO_ERROR) {
        ALOGI("M86_NATIVE3_GRAPH owner=PIPE_3AA nodes=110,111,112,130,132,150,152");
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
    return ExynosCamera3FrameFactoryPreview::m_fillNodeGroupInfo(frame);
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
    ALOGI("M86_NATIVE3_FLUSH stop begin leader=PIPE_3AA");

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
    case PIPE_DIS:
    case PIPE_SCP:
        return PIPE_3AA;
    default:
        return pipeId;
    }
}

} // namespace android
