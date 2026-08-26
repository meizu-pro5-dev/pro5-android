# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# m86-owned Camera3 module. The product variable selects either the verified
# legacy-engine wrapper or the native common_v2/libcamera3 engine.

LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)

LOCAL_MODULE := camera.m86
LOCAL_MODULE_RELATIVE_PATH := hw
LOCAL_MODULE_TAGS := optional
LOCAL_MULTILIB := 32

ifeq ($(M86_USE_PREBUILT_EXYNOS_HAL3),true)
LOCAL_SRC_FILES := camera_m86_prebuilt3_wrapper.cpp
LOCAL_PROPRIETARY_MODULE := true
else ifeq ($(M86_USE_NATIVE_EXYNOS_HAL3),true)
LOCAL_SRC_FILES := \
    camera_m86_native3_module.cpp \
    ExynosCamera3StreamRouterM86.cpp
LOCAL_C_INCLUDES += \
    $(LOCAL_PATH)/../libexynoscamera3_m86 \
    $(TOP)/hardware/samsung_slsi-linaro/exynos/libcamera/34xx/hal3 \
    $(TOP)/hardware/samsung_slsi-linaro/exynos/libcamera/common_v2 \
    $(TOP)/hardware/samsung_slsi-linaro/exynos/libcamera/common_v2/SensorInfos
LOCAL_CFLAGS += \
    -DM86_NATIVE_HAL3 \
    -DM86_NATIVE_HAL3_NO_VRA
else
LOCAL_SRC_FILES := camera_m86_module.cpp
endif

LOCAL_SHARED_LIBRARIES := \
    liblog \
    libcutils \
    libutils \
    libhardware \
    libcamera_metadata \
    libcamera_client \
    libgui \
    libui \
    libsync

ifeq ($(M86_USE_PREBUILT_EXYNOS_HAL3),true)
LOCAL_SHARED_LIBRARIES += libm86camera3_bridge libbinder libdl
else ifeq ($(M86_USE_NATIVE_EXYNOS_HAL3),true)
LOCAL_SHARED_LIBRARIES += libexynoscamera3_m86 libbinder
else ifeq ($(M86_STOCK_ENGINE),true)
# Plan-3 experiment: link the HAL3 shell against the Flyme stock
# libexynoscamera.so (recorded as DT_NEEDED libexynoscamera.so) instead of
# the source-built engine. The device image already ships the stock engine.
LOCAL_SHARED_LIBRARIES += libexynoscamera
LOCAL_CFLAGS += -DM86_STOCK_ENGINE
else
LOCAL_SHARED_LIBRARIES += libexynoscamera_m86
endif

LOCAL_C_INCLUDES += \
    $(LOCAL_PATH)/../libexynoscamera_m86 \
    $(TOP)/hardware/meizu/m86/graphics/gralloc/a10-contract \
    $(TOP)/hardware/samsung_slsi-linaro/exynos/libcamera/74xx \
    $(TOP)/hardware/samsung_slsi-linaro/exynos/libcamera/74xx/JpegEncoderForCamera \
    $(TOP)/hardware/samsung_slsi-linaro/exynos/libcamera/34xx/hal1 \
    $(TOP)/hardware/samsung_slsi-linaro/exynos/libcamera/common_v2 \
    $(TOP)/hardware/samsung_slsi-linaro/exynos/libcamera/common_v2/SensorInfos \
    $(TOP)/hardware/samsung_slsi-linaro/exynos/libcamera/common_v2/Buffers \
    $(TOP)/hardware/samsung_slsi-linaro/exynos/libcamera/common_v2/Pipes2 \
    $(TOP)/hardware/samsung_slsi-linaro/exynos/libcamera/common_v2/MCPipes \
    $(TOP)/hardware/samsung_slsi-linaro/exynos/libcamera/common_v2/Activities \
    $(TOP)/hardware/samsung_slsi-linaro/exynos/libcamera/common_v2/Ged \
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
    $(TOP)/system/memory/libion/kernel-headers

LOCAL_CFLAGS += \
    -Wall \
    -Werror \
    -Wno-overloaded-virtual \
    -Wno-unused-parameter \
    -DCAMERA_GED_FEATURE \
    -DMAIN_CAMERA_SENSOR_NAME=108 \
    -DFRONT_CAMERA_SENSOR_NAME=204 \
    -DBACK_ROTATION=90 \
    -DFRONT_ROTATION=270

include $(BUILD_SHARED_LIBRARY)
