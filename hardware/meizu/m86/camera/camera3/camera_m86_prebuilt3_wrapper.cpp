/*
 * Copyright (C) 2017-2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#define LOG_TAG "M86Camera3RouteAWrapper"

#include <android/fdsan.h>
#include <cutils/log.h>
#include <hardware/camera3.h>
#include <hardware/hardware.h>
#include <utils/Mutex.h>

#include <errno.h>
#include <stdlib.h>
#include <string.h>

namespace {

struct WrapperCamera3Device {
    camera3_device_t base;
    camera3_device_t *vendor;
};

android::Mutex gLock;
camera_module_t *gVendorModule;

int ensureVendorModule()
{
    android_fdsan_set_error_level(ANDROID_FDSAN_ERROR_LEVEL_DISABLED);
    if (gVendorModule != nullptr)
        return 0;

    const hw_module_t *vendorModule = nullptr;
    int result = hw_get_module_by_class(
            CAMERA_HARDWARE_MODULE_ID, "vendor", &vendorModule);
    gVendorModule = reinterpret_cast<camera_module_t *>(
            const_cast<hw_module_t *>(vendorModule));
    if (result != 0)
        ALOGE("cannot load camera.vendor.exynos5: %d", result);
    return result;
}

WrapperCamera3Device *wrapper(const camera3_device_t *device)
{
    return reinterpret_cast<WrapperCamera3Device *>(
            const_cast<camera3_device_t *>(device));
}

int initialize(const camera3_device_t *device,
               const camera3_callback_ops_t *callbacks)
{
    return wrapper(device)->vendor->ops->initialize(
            wrapper(device)->vendor, callbacks);
}

int configureStreams(const camera3_device_t *device,
                     camera3_stream_configuration_t *streams)
{
    return wrapper(device)->vendor->ops->configure_streams(
            wrapper(device)->vendor, streams);
}

const camera_metadata_t *constructDefaultRequestSettings(
        const camera3_device_t *device, int type)
{
    return wrapper(device)->vendor->ops->construct_default_request_settings(
            wrapper(device)->vendor, type);
}

int processCaptureRequest(const camera3_device_t *device,
                          camera3_capture_request_t *request)
{
    return wrapper(device)->vendor->ops->process_capture_request(
            wrapper(device)->vendor, request);
}

void getMetadataVendorTagOps(const camera3_device_t *device,
                             vendor_tag_query_ops_t *ops)
{
    if (wrapper(device)->vendor->ops->get_metadata_vendor_tag_ops != nullptr)
        wrapper(device)->vendor->ops->get_metadata_vendor_tag_ops(
                wrapper(device)->vendor, ops);
}

void dump(const camera3_device_t *device, int fd)
{
    wrapper(device)->vendor->ops->dump(wrapper(device)->vendor, fd);
}

int flush(const camera3_device_t *device)
{
    if (wrapper(device)->vendor->ops->flush == nullptr)
        return 0;
    return wrapper(device)->vendor->ops->flush(wrapper(device)->vendor);
}

int closeDevice(hw_device_t *device)
{
    android::Mutex::Autolock lock(gLock);
    if (device == nullptr)
        return -EINVAL;

    auto wrapped = reinterpret_cast<WrapperCamera3Device *>(device);
    int result = wrapped->vendor->common.close(
            reinterpret_cast<hw_device_t *>(wrapped->vendor));
    free(const_cast<camera3_device_ops_t *>(wrapped->base.ops));
    free(wrapped);
    return result;
}

int openDevice(const hw_module_t *module, const char *name,
               hw_device_t **device)
{
    if (name == nullptr || device == nullptr)
        return -EINVAL;

    android::Mutex::Autolock lock(gLock);
    int result = ensureVendorModule();
    if (result != 0)
        return result;

    auto wrapped = static_cast<WrapperCamera3Device *>(
            calloc(1, sizeof(WrapperCamera3Device)));
    auto ops = static_cast<camera3_device_ops_t *>(
            calloc(1, sizeof(camera3_device_ops_t)));
    if (wrapped == nullptr || ops == nullptr) {
        free(ops);
        free(wrapped);
        return -ENOMEM;
    }

    result = gVendorModule->common.methods->open(
            &gVendorModule->common, name,
            reinterpret_cast<hw_device_t **>(&wrapped->vendor));
    if (result != 0) {
        ALOGE("donor camera %s open failed: %d", name, result);
        free(ops);
        free(wrapped);
        return result;
    }

    wrapped->base.common.tag = HARDWARE_DEVICE_TAG;
    wrapped->base.common.version = CAMERA_DEVICE_API_VERSION_3_4;
    wrapped->base.common.module = const_cast<hw_module_t *>(module);
    wrapped->base.common.close = closeDevice;
    wrapped->base.ops = ops;

    ops->initialize = initialize;
    ops->configure_streams = configureStreams;
    ops->register_stream_buffers = nullptr;
    ops->construct_default_request_settings = constructDefaultRequestSettings;
    ops->process_capture_request = processCaptureRequest;
    ops->get_metadata_vendor_tag_ops = getMetadataVendorTagOps;
    ops->dump = dump;
    ops->flush = flush;

    *device = &wrapped->base.common;
    ALOGI("opened donor Camera3 device %s through route A", name);
    return 0;
}

int getNumberOfCameras()
{
    return ensureVendorModule() == 0
            ? gVendorModule->get_number_of_cameras() : 0;
}

int getCameraInfo(int cameraId, camera_info *info)
{
    return ensureVendorModule() == 0
            ? gVendorModule->get_camera_info(cameraId, info) : -ENODEV;
}

int setCallbacks(const camera_module_callbacks_t *callbacks)
{
    return ensureVendorModule() == 0
            ? gVendorModule->set_callbacks(callbacks) : -ENODEV;
}

void getVendorTagOps(vendor_tag_ops_t *ops)
{
    if (ensureVendorModule() == 0 &&
            gVendorModule->get_vendor_tag_ops != nullptr)
        gVendorModule->get_vendor_tag_ops(ops);
}

int openLegacy(const hw_module_t *module, const char *id,
               uint32_t version, hw_device_t **device)
{
    if (ensureVendorModule() != 0 ||
            gVendorModule->open_legacy == nullptr)
        return -ENOSYS;
    return gVendorModule->open_legacy(
            &gVendorModule->common, id, version, device);
}

int setTorchMode(const char *cameraId, bool enabled)
{
    if (ensureVendorModule() != 0 ||
            gVendorModule->set_torch_mode == nullptr)
        return -ENOSYS;
    return gVendorModule->set_torch_mode(cameraId, enabled);
}

int init()
{
    if (ensureVendorModule() != 0)
        return -ENODEV;
    return gVendorModule->init != nullptr ? gVendorModule->init() : 0;
}

hw_module_methods_t moduleMethods = {
    .open = openDevice,
};

} // namespace

extern "C" camera_module_t HAL_MODULE_INFO_SYM = {
    .common = {
        .tag = HARDWARE_MODULE_TAG,
        .module_api_version = CAMERA_MODULE_API_VERSION_2_4,
        .hal_api_version = HARDWARE_HAL_API_VERSION,
        .id = CAMERA_HARDWARE_MODULE_ID,
        .name = "M86 donor Camera3 route A wrapper",
        .author = "The LineageOS Project",
        .methods = &moduleMethods,
        .dso = nullptr,
        .reserved = {0},
    },
    .get_number_of_cameras = getNumberOfCameras,
    .get_camera_info = getCameraInfo,
    .set_callbacks = setCallbacks,
    .get_vendor_tag_ops = getVendorTagOps,
    .open_legacy = openLegacy,
    .set_torch_mode = setTorchMode,
    .init = init,
    .reserved = {0},
};
