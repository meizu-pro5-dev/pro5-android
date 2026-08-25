# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)

LOCAL_MODULE := libm86camera3_routea
LOCAL_MODULE_TAGS := optional
LOCAL_PROPRIETARY_MODULE := true
LOCAL_MULTILIB := 32
LOCAL_SRC_FILES := M86Camera3RouteA.cpp

LOCAL_SHARED_LIBRARIES := \
    libcutils \
    libdl \
    liblog

LOCAL_CFLAGS += \
    -Wall \
    -Werror \
    -Wno-unused-parameter \
    -DMAIN_CAMERA_SENSOR_NAME=108 \
    -DFRONT_CAMERA_SENSOR_NAME=204 \
    -DBACK_ROTATION=90 \
    -DFRONT_ROTATION=270

include $(BUILD_SHARED_LIBRARY)
