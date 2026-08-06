# Meizu PRO 5 (`m86`)

This directory is the clean LineageOS 17.1 device definition. It intentionally
starts with only the verified boot geometry, partition map, basic ramdisk, and
input configuration required for kernel/recovery bring-up.

The historical CyanogenMod 14.1 tree is preserved at
`legacy/device-meizu-m86-cm14`. The Android 10 Exynos platform reference is
`device/samsung/universal7420-common`; local patches extend its target routing
for m86 without importing Samsung-specific boot image geometry.

`BoardConfig.mk` inherits the common file only to obtain Exynos 7420 build,
graphics, media, and old-kernel integration flags. It immediately restores
`BOARD_VENDOR := meizu` and clears Galaxy audio/camera/fingerprint/radio/NFC,
Bluetooth, shim, filesystem-label, SELinux, and seccomp selections. The common
product makefile is never inherited. A cleared subsystem must be reintroduced
with an m86-owned package, exact Flyme 8 ABI evidence, and a build result.

This directory also owns `proprietary-files.txt` and the extraction scripts.
They must stay outside `vendor/meizu/m86`, because LineageOS `setup_vendor`
cleans that generated output directory before recreating its makefiles and
ignored `proprietary/` payload.

Do not add a hardware feature merely because a Flyme blob exists. Each HAL or
shim must have a build result and runtime evidence before it enters
`PRODUCT_PACKAGES` or the device VINTF manifest.
