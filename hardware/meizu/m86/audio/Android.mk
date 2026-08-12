# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

LOCAL_PATH := $(call my-dir)

# The wrapper is deliberately a 32-bit system HAL.  AudioFlinger on this
# product is 32-bit, and the locked Flyme input is a 32-bit legacy module.
# Keep this module buildable before it becomes the selected producer; the
# product switch is a separate gate so a compile failure cannot replace the
# currently bootable HAL.
include $(CLEAR_VARS)

LOCAL_MODULE := audio.primary.m86
LOCAL_MODULE_RELATIVE_PATH := hw
LOCAL_MODULE_TAGS := optional
LOCAL_MULTILIB := 32
LOCAL_SRC_FILES := audio_primary_m86.cpp
LOCAL_CFLAGS := -Wall -Wextra -Wno-unused-parameter
LOCAL_C_INCLUDES := hardware/libhardware/include
LOCAL_HEADER_LIBRARIES := libhardware_headers
LOCAL_SHARED_LIBRARIES := libcutils libdl liblog

include $(BUILD_SHARED_LIBRARY)
