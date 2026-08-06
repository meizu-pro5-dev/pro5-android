# Copyright (C) 2016 faust93 <monumentum@gmail.com>
# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := libm86fprint
LOCAL_VENDOR_MODULE := true
LOCAL_MULTILIB := 64
LOCAL_SRC_FILES := \
    libfprint/core.c \
    libfprint/data.c \
    libfprint/img.c \
    libfprint/imgdev.c \
    libfprint/fpc1150.c \
    libfprint/nbis/bozorth3/bozorth3.c \
    libfprint/nbis/bozorth3/bz_alloc.c \
    libfprint/nbis/bozorth3/bz_drvrs.c \
    libfprint/nbis/bozorth3/bz_gbls.c \
    libfprint/nbis/bozorth3/bz_io.c \
    libfprint/nbis/bozorth3/bz_sort.c \
    libfprint/nbis/mindtct/binar.c \
    libfprint/nbis/mindtct/contour.c \
    libfprint/nbis/mindtct/dft.c \
    libfprint/nbis/mindtct/globals.c \
    libfprint/nbis/mindtct/init.c \
    libfprint/nbis/mindtct/log.c \
    libfprint/nbis/mindtct/maps.c \
    libfprint/nbis/mindtct/minutia.c \
    libfprint/nbis/mindtct/quality.c \
    libfprint/nbis/mindtct/ridges.c \
    libfprint/nbis/mindtct/sort.c \
    libfprint/nbis/mindtct/block.c \
    libfprint/nbis/mindtct/detect.c \
    libfprint/nbis/mindtct/free.c \
    libfprint/nbis/mindtct/imgutil.c \
    libfprint/nbis/mindtct/line.c \
    libfprint/nbis/mindtct/loop.c \
    libfprint/nbis/mindtct/matchpat.c \
    libfprint/nbis/mindtct/morph.c \
    libfprint/nbis/mindtct/remove.c \
    libfprint/nbis/mindtct/shape.c \
    libfprint/nbis/mindtct/util.c
LOCAL_C_INCLUDES := \
    $(LOCAL_PATH)/libfprint \
    $(LOCAL_PATH)/libfprint/nbis/include \
    external/glib \
    external/glib/glib
LOCAL_EXPORT_C_INCLUDE_DIRS := $(LOCAL_PATH)/libfprint
LOCAL_CFLAGS := \
    -DANDROID_STUB \
    -fno-strict-aliasing \
    -Wno-missing-field-initializers \
    -Wno-pointer-sign \
    -Wno-sign-compare \
    -Wno-unused-parameter
include $(BUILD_STATIC_LIBRARY)

include $(CLEAR_VARS)
LOCAL_MODULE := fingerprint.m86
LOCAL_MODULE_RELATIVE_PATH := hw
LOCAL_VENDOR_MODULE := true
LOCAL_MULTILIB := 64
LOCAL_SRC_FILES := FingerprintHAL.c
LOCAL_STATIC_LIBRARIES := libm86fprint
LOCAL_SHARED_LIBRARIES := \
    libglib \
    liblog \
    libm
LOCAL_C_INCLUDES := \
    $(LOCAL_PATH)/libfprint \
    external/glib \
    external/glib/glib
LOCAL_CFLAGS := \
    -std=gnu11 \
    -Wall \
    -Wextra \
    -Werror
include $(BUILD_SHARED_LIBRARY)
