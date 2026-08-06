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
endif
