# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

LOCAL_PATH := $(call my-dir)

# Legacy gatekeeper ABI used by the Flyme gatekeeper.m86.so blob. The A10
# libgatekeeper uses pointer-parameter SizedBuffer constructors and matching
# request object layouts; the A12 system libgatekeeper switched to by-value
# SizedBuffer parameters and is therefore incompatible with the prebuilt blob.
# This module is installed under a private vendor subdirectory and selected
# only by the m86 gatekeeper service through LD_LIBRARY_PATH, so the system
# libgatekeeper.so used by software components remains untouched.
include $(CLEAR_VARS)

LOCAL_MODULE := libgatekeeper_m86
LOCAL_MODULE_RELATIVE_PATH := gatekeeper-legacy
LOCAL_MULTILIB := 64
LOCAL_PROPRIETARY_MODULE := true
LOCAL_SRC_FILES := \
    gatekeeper.cpp \
    gatekeeper_messages.cpp
LOCAL_C_INCLUDES := $(LOCAL_PATH)/include
LOCAL_HEADER_LIBRARIES := libhardware_headers
LOCAL_SHARED_LIBRARIES := liblog
LOCAL_CFLAGS := \
    -Wall \
    -Werror \
    -Wno-unused-parameter

LOCAL_POST_INSTALL_CMD := ln -sf libgatekeeper_m86.so $(TARGET_OUT_VENDOR)/lib64/gatekeeper-legacy/libgatekeeper.so

include $(BUILD_SHARED_LIBRARY)
