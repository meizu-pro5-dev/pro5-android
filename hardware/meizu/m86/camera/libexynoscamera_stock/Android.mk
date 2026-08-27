# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# Prebuilt Flyme 8 stock libexynoscamera.so (m86 HAL1 engine, 32-bit).
# Exposed to the build only as a link-time dependency for the
# M86_STOCK_ENGINE=true camera.m86 variant. The module name matches the
# real SONAME so the prebuilt ELF check passes; LOCAL_UNINSTALLABLE_MODULE
# keeps the build from adding a second install rule for the same target
# file that device/meizu/m86/proprietary-files.txt already ships.

LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)

LOCAL_MODULE := libexynoscamera
LOCAL_MODULE_CLASS := SHARED_LIBRARIES
LOCAL_MODULE_SUFFIX := .so
LOCAL_MODULE_TAGS := optional
LOCAL_MULTILIB := 32
LOCAL_UNINSTALLABLE_MODULE := true
LOCAL_CHECK_ELF_FILES := false
LOCAL_SRC_FILES := libexynoscamera.so

include $(BUILD_PREBUILT)
