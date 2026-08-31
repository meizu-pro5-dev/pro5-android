# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# Build only the m86-owned native HAL3 stack.

M86_CAMERA_LOCAL_PATH := $(call my-dir)

include $(M86_CAMERA_LOCAL_PATH)/libhwjpeg_m86/Android.mk
include $(M86_CAMERA_LOCAL_PATH)/libexynoscamera3_m86/Android.mk
include $(M86_CAMERA_LOCAL_PATH)/camera3/Android.mk

LOCAL_PATH := $(M86_CAMERA_LOCAL_PATH)
