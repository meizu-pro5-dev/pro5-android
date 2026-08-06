# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

LOCAL_PATH := $(call my-dir)

ifneq ($(filter m86,$(TARGET_DEVICE)),)
include $(call all-subdir-makefiles,$(LOCAL_PATH))

# The PRO 5 bootloader reads a raw FDT from its dedicated dtb partition. Keep
# that image in target-files RADIO/ so releasetools can flash it without
# causing Android's boot-image reconstruction code to append it to boot.img.
M86_KERNEL_DTB := $(TARGET_OUT_INTERMEDIATES)/KERNEL_OBJ/arch/arm64/boot/dts/exynos7420-m86-codegen.dtb
M86_INSTALLED_DTB := $(PRODUCT_OUT)/dtb.img

$(M86_INSTALLED_DTB): $(PRODUCT_OUT)/kernel
	@echo "Target m86 DTB: $@"
	$(hide) test -s $(M86_KERNEL_DTB)
	$(hide) cp -f $(M86_KERNEL_DTB) $@

INSTALLED_RADIOIMAGE_TARGET += $(M86_INSTALLED_DTB)

# Android 10's Vulkan loader selects vulkan.$(ro.board.platform).so. Flyme
# 8.0.5.0A provides that name as a link to the combined 32/64-bit Mali GLES
# driver, and the LineageOS 17.1 universal7420 port uses the same arrangement.
# Keep the large, hash-locked blobs as PRODUCT_COPY_FILES entries and install
# only the links here so the proprietary payload is not duplicated.
M86_MALI_LIB32 := $(TARGET_OUT_VENDOR)/lib/egl/libGLES_mali.so
M86_MALI_LIB64 := $(TARGET_OUT_VENDOR)/lib64/egl/libGLES_mali.so
M86_VULKAN_HAL32 := $(TARGET_OUT_VENDOR)/lib/hw/vulkan.exynos5.so
M86_VULKAN_HAL64 := $(TARGET_OUT_VENDOR)/lib64/hw/vulkan.exynos5.so
M86_VULKAN_HAL_SYMLINKS := \
    $(M86_VULKAN_HAL32) \
    $(M86_VULKAN_HAL64)

ALL_DEFAULT_INSTALLED_MODULES += $(M86_VULKAN_HAL_SYMLINKS)

$(M86_VULKAN_HAL32): $(M86_MALI_LIB32)
	@echo "Symlink m86 Vulkan HAL: $@"
	$(hide) mkdir -p $(dir $@)
	$(hide) ln -sf ../egl/libGLES_mali.so $@

$(M86_VULKAN_HAL64): $(M86_MALI_LIB64)
	@echo "Symlink m86 Vulkan HAL: $@"
	$(hide) mkdir -p $(dir $@)
	$(hide) ln -sf ../egl/libGLES_mali.so $@
endif
