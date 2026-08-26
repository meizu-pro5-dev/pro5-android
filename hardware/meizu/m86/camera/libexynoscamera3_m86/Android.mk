# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# Native Camera3 engine for the Meizu PRO 5.  The Camera3 request/result
# machinery comes from the published 34xx HAL3 tree, while the product-owned
# files in this directory provide the m86 sensor tables and Exynos7420
# topology.  Keep this module separate from the working HAL1-backed
# libexynoscamera_m86 during bring-up.

LOCAL_PATH := $(call my-dir)

SLSI_CAMERA := $(TOP)/hardware/samsung_slsi-linaro/exynos/libcamera

include $(CLEAR_VARS)

LOCAL_MODULE := libexynoscamera3_m86
LOCAL_MODULE_TAGS := optional
LOCAL_PRELINK_MODULE := false
LOCAL_MULTILIB := 32

LOCAL_SHARED_LIBRARIES := \
    libutils \
    libcutils \
    libbinder \
    liblog \
    libcamera_client \
    libcamera_metadata \
    libhardware \
    libui \
    libgui \
    libsync \
    libexynosutils \
    libexynosv4l2 \
    libexynosgscaler \
    libion \
    libcsc \
    libexpat \
    libc++ \
    libpower

LOCAL_WHOLE_STATIC_LIBRARIES := libhwjpeg_m86_static
LOCAL_STATIC_LIBRARIES := libjpeg

LOCAL_CFLAGS += \
    -DGAIA_FW_BETA \
    -DCAMERA_GED_FEATURE \
    -DUSE_CAMERA2_API_SUPPORT \
    -DUSE_CAMERA_ESD_RESET \
    -DM86_NATIVE_HAL3 \
    -DM86_NATIVE_HAL3_NO_VRA \
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
    $(TOP)/hardware/meizu/m86/camera/libhwjpeg_m86 \
    $(TOP)/hardware/meizu/m86/graphics/gralloc/a10-contract \
    $(SLSI_CAMERA)/common_v2 \
    $(SLSI_CAMERA)/common_v2/SensorInfos \
    $(SLSI_CAMERA)/common_v2/Pipes2 \
    $(SLSI_CAMERA)/common_v2/MCPipes \
    $(SLSI_CAMERA)/common_v2/Activities \
    $(SLSI_CAMERA)/common_v2/Buffers \
    $(SLSI_CAMERA)/common_v2/Ged \
    $(SLSI_CAMERA)/34xx \
    $(SLSI_CAMERA)/34xx/hal3 \
    $(SLSI_CAMERA)/74xx \
    $(SLSI_CAMERA)/74xx/JpegEncoderForCamera \
    $(TOP)/hardware/samsung_slsi-linaro/exynos/include \
    $(TOP)/hardware/samsung_slsi-linaro/exynos5/include \
    $(TOP)/hardware/samsung_slsi-linaro/graphics/base/libhwjpeg/include \
    $(TOP)/hardware/libhardware/include \
    $(TOP)/system/media/camera/include \
    $(TOP)/frameworks/native/include \
    $(TOP)/frameworks/native/headers/media_plugin \
    $(TOP)/frameworks/native/headers/media_plugin/media/openmax \
    $(TOP)/frameworks/native/libs/nativewindow/include \
    $(TOP)/frameworks/av/camera/include \
    $(TOP)/system/memory/libion/include \
    $(TOP)/system/memory/libion/kernel-headers \
    $(TOP)/external/expat/lib \
    $(TOP)/external/libcxx/include

LOCAL_SRC_FILES := \
    ExynosCamera3SensorInfo.cpp \
    ExynosCamera3FrameFactoryPreviewM86.cpp \
    ExynosCamera3FrameReprocessingFactoryM86.cpp \
    CameraParametersCompat.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/ExynosCameraFrame.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/ExynosCameraMemory.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/ExynosCameraFrameManager.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/ExynosCameraUtils.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/ExynosCameraNode.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/ExynosCameraNodeJpegHAL.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/ExynosCameraFrameSelector.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/SensorInfos/ExynosCameraSensorInfoBase.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/SensorInfos/ExynosCamera3SensorInfoBase.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/MCPipes/ExynosCameraMCPipe.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Pipes2/ExynosCameraPipe.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Pipes2/ExynosCameraPipeFlite.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Pipes2/ExynosCameraPipeVRA.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Pipes2/ExynosCameraPipeGSC.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Pipes2/ExynosCameraPipeJpeg.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Buffers/ExynosCameraBufferManager.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Activities/ExynosCameraActivityBase.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Activities/ExynosCameraActivityAutofocus.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Activities/ExynosCameraActivityFlash.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Activities/ExynosCameraActivitySpecialCapture.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Activities/ExynosCameraActivityUCTL.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/ExynosCameraRequestManager.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/ExynosCameraStreamManager.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/ExynosCameraMetadataConverter.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Ged/ExynosCameraActivityAutofocusVendor.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/common_v2/Ged/ExynosCameraFrameSelectorVendor.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/34xx/ExynosCameraActivityControl.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/34xx/ExynosCameraScalableSensor.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/34xx/ExynosCameraUtilsModule.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/34xx/hal3/ExynosCameraSizeControl.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/34xx/hal3/ExynosCamera3.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/34xx/hal3/ExynosCamera3Parameters.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/34xx/hal3/ExynosCamera3FrameFactory.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/34xx/hal3/ExynosCamera3FrameFactoryPreview.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/34xx/hal3/ExynosCamera3FrameReprocessingFactory.cpp \
    ../../../../samsung_slsi-linaro/exynos/libcamera/74xx/JpegEncoderForCamera/ExynosJpegEncoderForCamera.cpp

include $(TOP)/hardware/samsung_slsi-linaro/exynos/BoardConfigCFlags.mk
include $(BUILD_SHARED_LIBRARY)
