# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

ifneq ($(filter m86,$(TARGET_DEVICE)),)

LOCAL_PATH := $(call my-dir)

include $(call all-makefiles-under,$(LOCAL_PATH))

endif
