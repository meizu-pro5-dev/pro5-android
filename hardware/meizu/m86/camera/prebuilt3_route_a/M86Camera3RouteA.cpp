/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#define LOG_TAG "M86Camera3RouteA"

#include <cutils/log.h>
#include <dlfcn.h>
#include <stdint.h>
#include <string.h>

#include <new>

namespace {

// Verified from createCamera3SensorInfo() in the checked 32-bit donor. Do not
// replace this with sizeof() from a nearby public tree: the donor has private
// state absent from the closest published header.
constexpr size_t kDonorSensorInfoSize = 1216;
constexpr uintptr_t kPatchedFactoryReturnOffset = 0x000bce40;

constexpr int kRearSensorId = 108;  // IMX230 reported by the M86 kernel
constexpr int kFrontSensorId = 204; // OV5670 reported by the M86 kernel

using CtorWithId = void (*)(void *, int);
using CtorWithoutId = void (*)(void *);

static void *createSensorInfo(int cameraId)
{
    void *handle = dlopen(
            "libexynoscamera3_routea.so", RTLD_NOW | RTLD_NOLOAD);
    if (handle == nullptr) {
        ALOGE("donor libexynoscamera3 is not loaded: %s", dlerror());
        return nullptr;
    }

    void *storage = ::operator new(kDonorSensorInfoSize, std::nothrow);
    if (storage == nullptr)
        return nullptr;

    if (cameraId == 0) {
        auto ctor = reinterpret_cast<CtorWithId>(dlsym(
                handle,
                "_ZN7android29ExynosCamera3SensorIMX240_2P2C1Ei"));
        if (ctor == nullptr) {
            ALOGE("rear donor constructor is missing: %s", dlerror());
            ::operator delete(storage);
            return nullptr;
        }

        // This donor profile uses the Exynos7420 16:9 path proven on M86
        // HAL1: 5328x3000 sensor and 1920x1080 BDS. Sensor selection and
        // setfile loading remain kernel-owned; the profile carries Camera3
        // metadata and topology for the actual IMX230.
        ctor(storage, 10);
        ALOGI("created camera 0 SensorInfo: IMX230 id=%d via IMX240 carrier",
              kRearSensorId);
        return storage;
    }

    if (cameraId == 1) {
        auto ctor = reinterpret_cast<CtorWithoutId>(dlsym(
                handle,
                "_ZN7android25ExynosCamera3SensorS5K4E6C1Ev"));
        if (ctor == nullptr) {
            ALOGE("front donor constructor is missing: %s", dlerror());
            ::operator delete(storage);
            return nullptr;
        }

        // The donor's exported OV5670 Camera3 base was folded to an empty
        // base constructor. S5K4E6 is its complete 5 MP front profile and has
        // the same 2592x1944 envelope required by the M86 OV5670 path.
        ctor(storage);
        ALOGI("created camera 1 SensorInfo: OV5670 id=%d via 5MP carrier",
              kFrontSensorId);
        return storage;
    }

    ALOGE("unsupported camera id %d", cameraId);
    ::operator delete(storage);
    return nullptr;
}

static bool isPatchedFactoryCall(void *returnAddress)
{
    Dl_info info = {};
    if (dladdr(returnAddress, &info) == 0 || info.dli_fbase == nullptr ||
            info.dli_fname == nullptr)
        return false;

    const uintptr_t returnOffset =
            reinterpret_cast<uintptr_t>(returnAddress) -
            reinterpret_cast<uintptr_t>(info.dli_fbase);
    return strstr(info.dli_fname, "libexynoscamera3.so") != nullptr &&
            (returnOffset & ~static_cast<uintptr_t>(1)) ==
                    kPatchedFactoryReturnOffset;
}

using SecNativeGetInstance = void *(*)();

static void *forwardSecNativeGetInstance()
{
    static void *handle = dlopen(
            "libsecnativefeature_routea.so", RTLD_NOW | RTLD_NOLOAD);
    static auto original = handle == nullptr ? nullptr
            : reinterpret_cast<SecNativeGetInstance>(dlsym(
                    handle, "_ZN16SecNativeFeature11getInstanceEv"));
    if (original == nullptr) {
        ALOGE("cannot forward SecNativeFeature::getInstance: %s", dlerror());
        return nullptr;
    }
    return original();
}

} // namespace

// The checked donor patch redirects only createCamera3SensorInfo() through
// the existing SecNativeFeature::getInstance PLT slot. All genuine calls to
// that symbol are forwarded to the original donor dependency.
extern "C" __attribute__((noinline, visibility("default")))
void *routeASecNativeGetInstance(int cameraId)
        __asm__("_ZN16SecNativeFeature11getInstanceEv");

extern "C" void *routeASecNativeGetInstance(int cameraId)
{
    void *returnAddress = __builtin_return_address(0);
    if (isPatchedFactoryCall(returnAddress))
        return createSensorInfo(cameraId);
    return forwardSecNativeGetInstance();
}
