# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# Build an m86-owned JPEG backend for the Exynos 7420 m2m1shot ABI.  The
# generic SLSI implementation expects a newer V4L2 node (/dev/video12), while
# both the m86 kernel and Flyme expose /dev/m2m1shot_jpeg.

LOCAL_PATH := $(call my-dir)

SLSI_HWJPEG := $(TOP)/hardware/samsung_slsi-linaro/graphics/base/libhwjpeg

include $(CLEAR_VARS)

LOCAL_MODULE := libhwjpeg_m86_static
LOCAL_MODULE_TAGS := optional
LOCAL_MULTILIB := 32

LOCAL_CFLAGS += -DLOG_TAG=\"exynos-libhwjpeg-m86\"

LOCAL_HEADER_LIBRARIES := \
    libcutils_headers \
    libsystem_headers \
    libhardware_headers \
    libexynos_headers

LOCAL_C_INCLUDES := $(SLSI_HWJPEG)/include
LOCAL_C_INCLUDES += $(LOCAL_PATH)
LOCAL_EXPORT_C_INCLUDE_DIRS := $(LOCAL_PATH)

LOCAL_SRC_FILES := \
    ExynosJpegEncoderM2M.cpp

include $(TOP)/hardware/samsung_slsi-linaro/graphics/base/BoardConfigCFlags.mk
include $(BUILD_STATIC_LIBRARY)
