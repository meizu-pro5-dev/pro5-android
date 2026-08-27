# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

M86_GRALLOC_LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)

# Compile the lineage-19.1-old-r15 gralloc contract (A10/Nougat private
# handle layout: 160 bytes, 37 int/fd slots, internal_format at 0x90) that
# the Flyme r15p0 Mali EGL blob requires. m86 owns the device-specific fbdev
# implementation. Setting LOCAL_PATH to the source root avoids parent-directory
# paths and leaves the Samsung projects byte-clean.
LOCAL_PATH := .
LOCAL_MODULE := gralloc.m86
LOCAL_MODULE_RELATIVE_PATH := hw
LOCAL_MULTILIB := both
LOCAL_SHARED_LIBRARIES := \
    libcutils \
    libion \
    libion_exynos \
    liblog \
    libsync \
    libutils
LOCAL_C_INCLUDES := \
    hardware/meizu/m86/graphics/gralloc/a10-contract \
    hardware/samsung_slsi-linaro/exynos/gralloc \
    hardware/samsung_slsi-linaro/exynos/include \
    hardware/samsung_slsi-linaro/exynos5/include \
    system/memory/libion/include
LOCAL_SRC_FILES := \
    hardware/meizu/m86/graphics/gralloc/format_chooser_compat.cpp \
    hardware/meizu/m86/graphics/gralloc/a10-contract/gralloc.cpp \
    hardware/meizu/m86/graphics/gralloc/mapper_compat.cpp \
    hardware/meizu/m86/graphics/gralloc/framebuffer.cpp
LOCAL_CFLAGS := \
    -DLOG_TAG=\"gralloc.m86\" \
    -DMALI_AFBC_GRALLOC=1 \
    -DUSES_EXYNOS_COMMON_GRALLOC \
    -Wno-missing-field-initializers

ifeq ($(BOARD_USES_EXYNOS5_GRALLOC_RANGE_FLUSH),true)
LOCAL_CFLAGS += -DGRALLOC_RANGE_FLUSH
endif

ifeq ($(BOARD_USES_EXYNOS5_CRC_BUFFER_ALLOC),true)
LOCAL_CFLAGS += -DUSES_EXYNOS_CRC_BUFFER_ALLOC
endif

include $(BUILD_SHARED_LIBRARY)

LOCAL_PATH := $(M86_GRALLOC_LOCAL_PATH)
