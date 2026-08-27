# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# m86-owned build glue for the open-source SLSI Exynos7420 HAL1 camera engine.
# The source files themselves stay in the pinned
# hardware/samsung_slsi-linaro/exynos checkout; this module only restores the
# build glue that upstream did not publish and selects the PRO 5 sensors.

LOCAL_PATH := $(call my-dir)

SLSI_CAMERA := $(TOP)/hardware/samsung_slsi-linaro/exynos/libcamera

include $(CLEAR_VARS)

LOCAL_MODULE := libexynoscamera_m86
LOCAL_MODULE_TAGS := optional
LOCAL_PRELINK_MODULE := false
LOCAL_MULTILIB := 32

LOCAL_SHARED_LIBRARIES := \
    libutils \
    libcutils \
    libbinder \
    liblog \
    libcamera_client \
    libhardware \
    libui \
    libexynosutils \
    libexynosv4l2 \
    libexynosgscaler \
    libion \
    libcsc \
    libexpat \
    libc++ \
    libpower \
    libgui

LOCAL_WHOLE_STATIC_LIBRARIES := libhwjpeg_m86_static
LOCAL_STATIC_LIBRARIES := libjpeg

LOCAL_CFLAGS += \
    -DGAIA_FW_BETA \
    -DCAMERA_GED_FEATURE \
    -DMAIN_CAMERA_SINGLE_ISP_TPU_OTF=0 \
    -DUSE_CAMERA_ESD_RESET \
    -DMAIN_CAMERA_SENSOR_NAME=108 \
    -DFRONT_CAMERA_SENSOR_NAME=204 \
    -DBACK_ROTATION=90 \
    -DFRONT_ROTATION=270 \
    -Wno-unused-variable \
    -Wno-unused-private-field \
    -Wno-unused-parameter \
    -Wno-unused-function \
    -Wno-overloaded-virtual \
    -Wno-tautological-compare \
    -Wno-implicit-fallthrough \
    -Wno-unused-label \
    -Wno-format

LOCAL_C_INCLUDES += \
    $(LOCAL_PATH) \
    $(TOP)/hardware/meizu/m86/graphics/gralloc/a10-contract \
    $(SLSI_CAMERA)/74xx \
    $(SLSI_CAMERA)/34xx/hal1 \
    $(SLSI_CAMERA)/74xx/JpegEncoderForCamera \
    $(SLSI_CAMERA)/common_v2 \
    $(SLSI_CAMERA)/common_v2/SensorInfos \
    $(SLSI_CAMERA)/common_v2/Pipes2 \
    $(SLSI_CAMERA)/common_v2/MCPipes \
    $(SLSI_CAMERA)/common_v2/Activities \
    $(SLSI_CAMERA)/common_v2/Buffers \
    $(SLSI_CAMERA)/common_v2/Ged \
    $(TOP)/hardware/samsung_slsi-linaro/exynos/include \
    $(TOP)/hardware/samsung_slsi-linaro/exynos5/include \
    $(TOP)/system/media/camera/include \
    $(TOP)/frameworks/native/include \
    $(TOP)/frameworks/native/headers/media_plugin \
    $(TOP)/frameworks/native/headers/media_plugin/media/openmax \
    $(TOP)/external/expat/lib \
    $(TOP)/external/libcxx/include

LOCAL_SRC_FILES := \
    ExynosCameraSensorInfo.cpp \
    CameraParametersCompat.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/ExynosCameraFrame.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/ExynosCameraMemory.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/ExynosCameraFrameManager.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/ExynosCameraUtils.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/ExynosCameraNode.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/ExynosCameraNodeJpegHAL.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/ExynosCameraFrameSelector.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/ExynosCamera1MetadataConverter.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/SensorInfos/ExynosCameraSensorInfoBase.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/MCPipes/ExynosCameraMCPipe.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Pipes2/ExynosCameraPipe.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Pipes2/ExynosCameraPipeFlite.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Pipes2/ExynosCameraPipeVRA.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Pipes2/ExynosCameraPipeGSC.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Pipes2/ExynosCameraPipeJpeg.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Pipes2/ExynosCameraPipe3AA.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Pipes2/ExynosCameraPipe3AA_ISP.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Pipes2/ExynosCameraPipe3AC.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Pipes2/ExynosCameraPipeISP.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Pipes2/ExynosCameraPipeISPC.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Pipes2/ExynosCameraPipeSCC.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Pipes2/ExynosCameraPipeSCP.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Buffers/ExynosCameraBufferManager.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Activities/ExynosCameraActivityBase.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Activities/ExynosCameraActivityAutofocus.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Activities/ExynosCameraActivityFlash.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Activities/ExynosCameraActivitySpecialCapture.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Activities/ExynosCameraActivityUCTL.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Ged/ExynosCameraActivityAutofocusVendor.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Ged/ExynosCameraFrameSelectorVendor.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/74xx/ExynosCameraUtilsModule.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/34xx/hal1/ExynosCameraSizeControl.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/74xx/ExynosCameraActivityControl.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/74xx/ExynosCameraScalableSensor.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/74xx/ExynosCamera.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/74xx/ExynosCameraParameters.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/74xx/ExynosCameraFrameFactory.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/74xx/ExynosCameraFrameFactoryPreview.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/74xx/ExynosCameraFrameFactory3aaIspM2M.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/74xx/ExynosCameraFrameFactory3aaIspM2MTpu.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/74xx/ExynosCameraFrameFactory3aaIspOtf.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/74xx/ExynosCameraFrameFactory3aaIspOtfTpu.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/74xx/ExynosCameraFrameFactory3aaIspTpu.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/74xx/ExynosCameraFrameReprocessingFactory.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/74xx/ExynosCameraFrameFactoryVision.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/74xx/ExynosCameraFrameFactoryFront.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/74xx/JpegEncoderForCamera/ExynosJpegEncoderForCamera.cpp

include $(TOP)/hardware/samsung_slsi-linaro/exynos/BoardConfigCFlags.mk
include $(BUILD_SHARED_LIBRARY)
