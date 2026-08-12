# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

M86_HARDWARE_CALLER_LOCAL_PATH := $(LOCAL_PATH)
LOCAL_PATH := $(call my-dir)

ifneq ($(filter m86,$(TARGET_DEVICE)),)
include $(call all-subdir-makefiles,$(LOCAL_PATH))
endif

LOCAL_PATH := $(M86_HARDWARE_CALLER_LOCAL_PATH)
