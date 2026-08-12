/*
 * Copyright (C) 2016 The Android Open Source Project
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#define LOG_TAG "android.hardware.bluetooth@1.0-service.m86"

#include <android/hardware/bluetooth/1.0/IBluetoothHci.h>
#include <hidl/LegacySupport.h>

using android::hardware::bluetooth::V1_0::IBluetoothHci;
using android::hardware::defaultPassthroughServiceImplementation;

int main() {
    return defaultPassthroughServiceImplementation<IBluetoothHci>(5);
}
