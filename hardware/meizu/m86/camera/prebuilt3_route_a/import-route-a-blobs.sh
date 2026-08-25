#!/bin/bash
# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <universal7420-common proprietary/vendor> <m86 proprietary/vendor>" >&2
    exit 2
fi

donor_root=$1
output_root=$2
donor_lib="$donor_root/lib"
output_lib="$output_root/lib"

expected_camera3=fc9d6b32c5756f38a8e13252b42d989fa3139e6599e5f86094335e9027b20b61
expected_module=b9eedebf16b5db2d778a062813ef26376f3af72318d37e51163ed38043332014

test "$(sha256sum "$donor_lib/libexynoscamera3.so" | cut -d' ' -f1)" = \
    "$expected_camera3"
test "$(sha256sum "$donor_lib/hw/camera.vendor.exynos5.so" | cut -d' ' -f1)" = \
    "$expected_module"

install -d "$output_lib/hw"
install -m 0644 "$donor_lib/libexynoscamera.so" \
    "$output_lib/libexynoscamera.so"
install -m 0644 "$donor_lib/libexynoscamera3.so" \
    "$output_lib/libexynoscamera3.so"
install -m 0644 "$donor_lib/libhwjpeg.so" \
    "$output_lib/libhwjpeg.so"
install -m 0644 "$donor_lib/libsecnativefeature.so" \
    "$output_lib/libsecnativefeature.so"
install -m 0644 "$donor_lib/libsensorlistener.so" \
    "$output_lib/libsensorlistener.so"
install -m 0644 "$donor_lib/libuniplugin.so" \
    "$output_lib/libuniplugin.so"
install -m 0644 "$donor_lib/hw/camera.vendor.exynos5.so" \
    "$output_lib/hw/camera.vendor.exynos5.so"

# The donor factory starts at virtual address 0x000bce38 and file offset
# 0x000b8e38. Redirect it through the existing
# SecNativeFeature::getInstance() PLT entry at 0x0004815c:
#
#   push {r4, lr}; mov r4, r0; blx 0x4815c; pop {r4, pc}
#
# The bridge distinguishes this return site from genuine SecNativeFeature
# calls and receives cameraId in r0. Keep this tied to the checked input hash.
factory_patch='\x10\xb5\x04\x46\x8b\xf7\x8e\xe9\x10\xbd'
printf '%b' "$factory_patch" | dd \
    of="$output_lib/libexynoscamera3.so" \
    bs=1 seek=$((0x000b8e38)) conv=notrunc status=none

for engine in \
    "$output_lib/libexynoscamera.so" \
    "$output_lib/libexynoscamera3.so"; do
    # Make the bridge a direct dependency of either donor engine. Besides
    # carrying the guarded factory hook, it exports the Samsung
    # CameraParameters ABI constants removed from the platform library.
    patchelf --add-needed libm86camera3_bridge.so "$engine"

    # Reuse the existing m86 platform ABI shim for legacy framework symbols
    # such as android::Fence::~Fence(). The stock LD_SHIM rule is path-scoped
    # to /system/lib/libexynoscamera.so and therefore cannot make this shim
    # visible to the privately renamed Route A engines.
    patchelf --add-needed libm86camera_shim.so "$engine"
done

# Put the bridge first in the donor module's dependency scope so its guarded
# SecNativeFeature symbol wins only for this camera process.
patchelf --add-needed libm86camera3_bridge.so \
    "$output_lib/hw/camera.vendor.exynos5.so"

sha256sum \
    "$output_lib/hw/camera.vendor.exynos5.so" \
    "$output_lib/libexynoscamera.so" \
    "$output_lib/libexynoscamera3.so" \
    "$output_lib/libhwjpeg.so" \
    "$output_lib/libsecnativefeature.so" \
    "$output_lib/libsensorlistener.so" \
    "$output_lib/libuniplugin.so"
