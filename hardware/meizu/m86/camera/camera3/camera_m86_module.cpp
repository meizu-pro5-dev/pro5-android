/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 *
 * m86-owned source HAL3 module.
 *
 * Report the two PRO 5 cameras as camera.device@3.4 and translate the basic
 * camera3 preview path onto the source-built ExynosCamera engine.
 */

#define LOG_TAG "camera.m86"
#include <log/log.h>

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <new>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include <camera/CameraMetadata.h>
#include <camera/CameraParameters.h>
#include <media/hardware/HardwareAPI.h>
#include <hardware/camera.h>
#include <hardware/camera3.h>
#include <hardware/gralloc.h>
#include <hardware/hardware.h>
#include <sync/sync.h>
#include <system/camera.h>
#include <system/camera_metadata.h>
#include <system/graphics.h>
#include <ui/GraphicBufferAllocator.h>

#include "ExynosCamera.h"
#include "gralloc_priv.h"

using android::CameraMetadata;
using android::CameraParameters;
using android::ExynosCamera;
using android::OK;

#define M86_CAMERA_COUNT 2
#define M86_MAX_PENDING_PREVIEW_REQUESTS 16
#define M86_MAX_PENDING_JPEG_REQUESTS 8
#define M86_MAX_REQUEST_OUTPUT_BUFFERS 3

typedef struct m86_pending_output_buffer {
    camera3_stream_t *stream;
    buffer_handle_t *buffer;
} m86_pending_output_buffer_t;

typedef struct m86_pending_preview_request {
    uint32_t frame_number;
    int64_t timestamp_ns;
    uint32_t num_output_buffers;
    int preview_output_index;
    int video_output_index;
    int jpeg_output_index;
    m86_pending_output_buffer_t output_buffers[M86_MAX_REQUEST_OUTPUT_BUFFERS];
} m86_pending_preview_request_t;

typedef struct m86_pending_stream_request {
    uint32_t frame_number;
    int64_t timestamp_ns;
    m86_pending_output_buffer_t output;
} m86_pending_stream_request_t;

typedef struct m86_pending_jpeg_request {
    bool shutter_and_metadata_sent;
    uint32_t frame_number;
    int64_t timestamp_ns;
    m86_pending_output_buffer_t output;
    int jpeg_quality;
    int jpeg_orientation;
    int thumbnail_quality;
    int thumbnail_width;
    int thumbnail_height;
    bool has_gps;
    double gps_coordinates[3];
    int64_t gps_timestamp;
    char gps_processing_method[64];
} m86_pending_jpeg_request_t;

typedef struct m86_camera3_device {
    camera3_device_t base;
    int camera_id;
    const camera3_callback_ops_t *callback_ops;
    ExynosCamera *engine;

    camera3_stream_t *configured_preview_stream;
    camera3_stream_t *configured_video_stream;
    camera3_stream_t *configured_jpeg_stream;
    pthread_mutex_t pending_lock;
    pthread_cond_t pending_cond;
    m86_pending_stream_request_t pending[M86_MAX_PENDING_PREVIEW_REQUESTS];
    uint32_t pending_head;
    uint32_t pending_count;
    m86_pending_stream_request_t video_pending[M86_MAX_PENDING_PREVIEW_REQUESTS];
    uint32_t video_pending_head;
    uint32_t video_pending_count;
    m86_pending_jpeg_request_t pending_jpeg[M86_MAX_PENDING_JPEG_REQUESTS];
    uint32_t pending_jpeg_head;
    uint32_t pending_jpeg_count;
    bool jpeg_capture_active;
    bool flushing;
    bool preview_started;
    bool recording_started;
    pthread_t preview_start_thread;
    bool preview_start_thread_joinable;
    bool stop_preview_start_thread;
    bool buffer_layout_logged;
    struct m86_preview_window *window;

    uint8_t ae_mode;
    uint8_t ae_state;
    uint8_t af_mode;
    uint8_t af_state;
    uint8_t awb_mode;
    uint8_t awb_state;
    uint8_t flash_mode;
    uint8_t flash_state;
    int32_t exposure_compensation;
    int32_t crop_region[4];
} m86_camera3_device_t;

#define M86_PREVIEW_WINDOW_MAX_BUFFERS 16
#define M86_PREVIEW_WINDOW_MIN_BUFFERS 12

typedef struct m86_preview_window_buffer {
    buffer_handle_t handle;
    int stride;
    bool busy;
} m86_preview_window_buffer_t;

typedef struct m86_preview_window {
    // Stock Flyme libexynoscamera's startPreview() returns early without a
    // real HAL1 preview window, so expose the legacy preview_stream_ops_t
    // contract and copy the frames it enqueues into the camera3 stream.
    // ops must stay the first member: the engine receives a pointer to it.
    preview_stream_ops_t ops;
    pthread_mutex_t lock;
    m86_camera3_device_t *dev;
    int buffer_count;
    int width;
    int height;
    int format;
    int usage;
    int allocated_count;
    int allocated_width;
    int allocated_height;
    int allocated_format;
    uint64_t allocated_usage;
    int64_t last_timestamp;
    m86_preview_window_buffer_t buffers[M86_PREVIEW_WINDOW_MAX_BUFFERS];
} m86_preview_window_t;

static void m86_preview_window_deliver(m86_preview_window_t *window,
                                       buffer_handle_t handle,
                                       int64_t timestamp_ns);
static void m86_start_next_jpeg_capture(m86_camera3_device_t *m86_dev);
static const gralloc_module_t *m86_get_gralloc_module(void);
static void m86_preview_window_init(m86_preview_window_t *window,
                                    m86_camera3_device_t *dev);
static void m86_preview_window_deinit(m86_preview_window_t *window);

static const char *g_camera_names[M86_CAMERA_COUNT] = {"rear-imx230", "front-ov5670"};
static const camera_module_callbacks_t *g_module_callbacks;
static pthread_mutex_t g_module_lock = PTHREAD_MUTEX_INITIALIZER;
static bool g_rear_camera_open;
static bool g_torch_enabled;

static void m86_notify_torch_status(torch_mode_status_t status)
{
    pthread_mutex_lock(&g_module_lock);
    const camera_module_callbacks_t *callbacks = g_module_callbacks;
    pthread_mutex_unlock(&g_module_lock);
    if (callbacks != nullptr && callbacks->torch_mode_status_change != nullptr) {
        callbacks->torch_mode_status_change(callbacks, "0", status);
    }
}

static int m86_write_sysfs(const char *path, const char *value)
{
    int fd = open(path, O_WRONLY | O_CLOEXEC);
    if (fd < 0) {
        return -errno;
    }
    const size_t length = strlen(value);
    const ssize_t written = write(fd, value, length);
    const int saved_errno = errno;
    close(fd);
    if (written == static_cast<ssize_t>(length)) {
        return 0;
    }
    return written < 0 ? -saved_errno : -EIO;
}

static int m86_get_number_of_cameras(void)
{
    return M86_CAMERA_COUNT;
}

static void m86_fill_static_metadata(int camera_id, CameraMetadata *meta)
{
    const bool is_front = (camera_id == 1);
    const uint8_t facing = is_front ? ANDROID_LENS_FACING_FRONT : ANDROID_LENS_FACING_BACK;
    const uint8_t flash_available = is_front ? ANDROID_FLASH_INFO_AVAILABLE_FALSE
                                             : ANDROID_FLASH_INFO_AVAILABLE_TRUE;
    const float focal_length = is_front ? 3.50f : 4.73f;
    const float aperture = 2.2f;
    const int32_t pixel_array[2] = {is_front ? 2592 : 5344, is_front ? 1944 : 4016};
    const int32_t active_array[4] = {0, 0, is_front ? 2592 : 5344, is_front ? 1944 : 4016};
    const int32_t sensor_orientation = is_front ? 270 : 90;
    const int32_t ae_fps_range[2] = {15, 30};
    const int32_t ae_comp_range[2] = {-4, 4};
    const camera_metadata_rational_t ae_comp_step = {1, 2};
    // camera3 order is AE, AWB, AF.  Both sensors expose one HAL1 metering
    // area; only the rear IMX230 exposes touch-focus areas.
    const int32_t max_regions[3] = {1, 0, is_front ? 0 : 1};
    /* The m86 engine keeps 3AA/ISP geometry fixed and performs live preview
     * zoom in the hardware GSC, so the full IMX230 4x table is usable. */
    const float max_digital_zoom = is_front ? 2.0f : 4.0f;
    const uint8_t hw_level = static_cast<uint8_t>(ANDROID_INFO_SUPPORTED_HARDWARE_LEVEL_LEGACY);
    const int32_t preview_size[2] = {1920, 1080};
    // The sensor array includes alignment margins.  ExynosCamera only accepts
    // sizes from its public picture list, not the raw max sensor dimensions.
    // Keep the minimal front-camera JPEG stream at the same 16:9 ratio as
    // preview.  With dirty-bayer reprocessing, a 4:3 picture plus a 16:9
    // preview makes the legacy engine bypass the OV5670 LUT and calculate an
    // invalid 2592x1460 3AA crop.
    const int32_t picture_size[2] = {is_front ? 2560 : 4608, is_front ? 1440 : 3456};

    // format, width, height, input/output flag
    const int32_t stream_configs[8] = {
        HAL_PIXEL_FORMAT_IMPLEMENTATION_DEFINED, preview_size[0], preview_size[1],
        ANDROID_SCALER_AVAILABLE_STREAM_CONFIGURATIONS_OUTPUT,
        HAL_PIXEL_FORMAT_BLOB, picture_size[0], picture_size[1],
        ANDROID_SCALER_AVAILABLE_STREAM_CONFIGURATIONS_OUTPUT};
    const int64_t min_frame_durations[8] = {
        HAL_PIXEL_FORMAT_IMPLEMENTATION_DEFINED, preview_size[0], preview_size[1], 33333333LL,
        HAL_PIXEL_FORMAT_BLOB, picture_size[0], picture_size[1], 100000000LL};
    const int64_t stall_durations[8] = {
        HAL_PIXEL_FORMAT_IMPLEMENTATION_DEFINED, preview_size[0], preview_size[1], 0,
        HAL_PIXEL_FORMAT_BLOB, picture_size[0], picture_size[1], 100000000LL};

    const uint8_t caps[1] = {ANDROID_REQUEST_AVAILABLE_CAPABILITIES_BACKWARD_COMPATIBLE};
    const uint8_t rear_ae_modes[] = {
        ANDROID_CONTROL_AE_MODE_ON,
        ANDROID_CONTROL_AE_MODE_ON_AUTO_FLASH,
        ANDROID_CONTROL_AE_MODE_ON_ALWAYS_FLASH,
    };
    const uint8_t front_ae_modes[] = {ANDROID_CONTROL_AE_MODE_ON};
    const uint8_t rear_af_modes[] = {
        ANDROID_CONTROL_AF_MODE_AUTO,
        ANDROID_CONTROL_AF_MODE_CONTINUOUS_PICTURE,
        ANDROID_CONTROL_AF_MODE_CONTINUOUS_VIDEO,
    };
    const uint8_t front_af_modes[] = {ANDROID_CONTROL_AF_MODE_OFF};
    const uint8_t awb_modes[1] = {ANDROID_CONTROL_AWB_MODE_AUTO};
    const uint8_t control_modes[1] = {ANDROID_CONTROL_MODE_AUTO};
    const uint8_t scene_modes[1] = {ANDROID_CONTROL_SCENE_MODE_DISABLED};
    const uint8_t effect_modes[1] = {ANDROID_CONTROL_EFFECT_MODE_OFF};
    const uint8_t video_stabilization_modes[1] = {
        ANDROID_CONTROL_VIDEO_STABILIZATION_MODE_OFF};
    const uint8_t ae_antibanding_modes[] = {
        ANDROID_CONTROL_AE_ANTIBANDING_MODE_OFF,
        ANDROID_CONTROL_AE_ANTIBANDING_MODE_50HZ,
        ANDROID_CONTROL_AE_ANTIBANDING_MODE_60HZ,
        ANDROID_CONTROL_AE_ANTIBANDING_MODE_AUTO,
    };
    const uint8_t ae_lock_available = ANDROID_CONTROL_AE_LOCK_AVAILABLE_FALSE;
    const uint8_t awb_lock_available = ANDROID_CONTROL_AWB_LOCK_AVAILABLE_FALSE;
    const uint8_t face_detect_modes[1] = {ANDROID_STATISTICS_FACE_DETECT_MODE_OFF};
    const int32_t max_face_count = 0;
    // camera3 order is RAW, processed, processed-stalling (JPEG).
    const int32_t max_num_output_streams[3] = {0, 2, 1};
    const int32_t max_num_input_streams = 0;
    const int32_t partial_result_count = 1;
    const uint8_t pipeline_max_depth = 4;
    const int32_t available_thumbnail_sizes[6] = {0, 0, 320, 240, 160, 120};
    const float sensor_physical_size[2] = {is_front ? 2.88f : 5.99f,
                                           is_front ? 2.16f : 4.50f};
    const uint8_t timestamp_source = ANDROID_SENSOR_INFO_TIMESTAMP_SOURCE_UNKNOWN;
    const uint8_t cropping_type = ANDROID_SCALER_CROPPING_TYPE_CENTER_ONLY;
    const int32_t sync_max_latency = ANDROID_SYNC_MAX_LATENCY_UNKNOWN;
    const float minimum_focus_distance = is_front ? 0.0f : 10.0f;
    const float hyperfocal_distance = is_front ? 0.0f : 0.2f;
    const uint8_t focus_calibration =
        ANDROID_LENS_INFO_FOCUS_DISTANCE_CALIBRATION_UNCALIBRATED;
    const uint8_t optical_stabilization_modes[1] = {
        ANDROID_LENS_OPTICAL_STABILIZATION_MODE_OFF};
    const int32_t jpeg_max_size = picture_size[0] * picture_size[1] * 2;

    const int32_t request_keys[] = {
        ANDROID_CONTROL_AE_ANTIBANDING_MODE,
        ANDROID_CONTROL_AE_EXPOSURE_COMPENSATION,
        ANDROID_CONTROL_AE_LOCK,
        ANDROID_CONTROL_AE_MODE,
        ANDROID_CONTROL_AE_PRECAPTURE_TRIGGER,
        ANDROID_CONTROL_AE_REGIONS,
        ANDROID_CONTROL_AE_TARGET_FPS_RANGE,
        ANDROID_CONTROL_AF_MODE,
        ANDROID_CONTROL_AF_REGIONS,
        ANDROID_CONTROL_AF_TRIGGER,
        ANDROID_CONTROL_AWB_LOCK,
        ANDROID_CONTROL_AWB_MODE,
        ANDROID_CONTROL_CAPTURE_INTENT,
        ANDROID_CONTROL_EFFECT_MODE,
        ANDROID_CONTROL_MODE,
        ANDROID_CONTROL_SCENE_MODE,
        ANDROID_CONTROL_VIDEO_STABILIZATION_MODE,
        ANDROID_FLASH_MODE,
        ANDROID_JPEG_GPS_COORDINATES,
        ANDROID_JPEG_GPS_PROCESSING_METHOD,
        ANDROID_JPEG_GPS_TIMESTAMP,
        ANDROID_JPEG_ORIENTATION,
        ANDROID_JPEG_QUALITY,
        ANDROID_JPEG_THUMBNAIL_QUALITY,
        ANDROID_JPEG_THUMBNAIL_SIZE,
        ANDROID_LENS_FOCAL_LENGTH,
        ANDROID_LENS_OPTICAL_STABILIZATION_MODE,
        ANDROID_SCALER_CROP_REGION,
        ANDROID_STATISTICS_FACE_DETECT_MODE,
    };
    const int32_t result_keys[] = {
        ANDROID_CONTROL_AE_MODE,
        ANDROID_CONTROL_AE_STATE,
        ANDROID_CONTROL_AE_EXPOSURE_COMPENSATION,
        ANDROID_CONTROL_AF_MODE,
        ANDROID_CONTROL_AF_STATE,
        ANDROID_CONTROL_AWB_MODE,
        ANDROID_CONTROL_AWB_STATE,
        ANDROID_CONTROL_MODE,
        ANDROID_FLASH_MODE,
        ANDROID_FLASH_STATE,
        ANDROID_LENS_FOCAL_LENGTH,
        ANDROID_REQUEST_PIPELINE_DEPTH,
        ANDROID_SCALER_CROP_REGION,
        ANDROID_SENSOR_TIMESTAMP,
        ANDROID_STATISTICS_FACE_DETECT_MODE,
    };
    const int32_t characteristic_keys[] = {
        ANDROID_CONTROL_AE_AVAILABLE_ANTIBANDING_MODES,
        ANDROID_CONTROL_AE_AVAILABLE_MODES,
        ANDROID_CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES,
        ANDROID_CONTROL_AE_COMPENSATION_RANGE,
        ANDROID_CONTROL_AE_COMPENSATION_STEP,
        ANDROID_CONTROL_AE_LOCK_AVAILABLE,
        ANDROID_CONTROL_AF_AVAILABLE_MODES,
        ANDROID_CONTROL_AVAILABLE_EFFECTS,
        ANDROID_CONTROL_AVAILABLE_MODES,
        ANDROID_CONTROL_AVAILABLE_SCENE_MODES,
        ANDROID_CONTROL_AVAILABLE_VIDEO_STABILIZATION_MODES,
        ANDROID_CONTROL_AWB_AVAILABLE_MODES,
        ANDROID_CONTROL_AWB_LOCK_AVAILABLE,
        ANDROID_CONTROL_MAX_REGIONS,
        ANDROID_FLASH_INFO_AVAILABLE,
        ANDROID_INFO_SUPPORTED_HARDWARE_LEVEL,
        ANDROID_JPEG_AVAILABLE_THUMBNAIL_SIZES,
        ANDROID_JPEG_MAX_SIZE,
        ANDROID_LENS_FACING,
        ANDROID_LENS_INFO_AVAILABLE_APERTURES,
        ANDROID_LENS_INFO_AVAILABLE_FOCAL_LENGTHS,
        ANDROID_LENS_INFO_AVAILABLE_OPTICAL_STABILIZATION,
        ANDROID_LENS_INFO_FOCUS_DISTANCE_CALIBRATION,
        ANDROID_LENS_INFO_HYPERFOCAL_DISTANCE,
        ANDROID_LENS_INFO_MINIMUM_FOCUS_DISTANCE,
        ANDROID_REQUEST_AVAILABLE_CAPABILITIES,
        ANDROID_REQUEST_AVAILABLE_CHARACTERISTICS_KEYS,
        ANDROID_REQUEST_AVAILABLE_REQUEST_KEYS,
        ANDROID_REQUEST_AVAILABLE_RESULT_KEYS,
        ANDROID_REQUEST_MAX_NUM_INPUT_STREAMS,
        ANDROID_REQUEST_MAX_NUM_OUTPUT_STREAMS,
        ANDROID_REQUEST_PARTIAL_RESULT_COUNT,
        ANDROID_REQUEST_PIPELINE_MAX_DEPTH,
        ANDROID_SCALER_AVAILABLE_MAX_DIGITAL_ZOOM,
        ANDROID_SCALER_AVAILABLE_MIN_FRAME_DURATIONS,
        ANDROID_SCALER_AVAILABLE_STALL_DURATIONS,
        ANDROID_SCALER_AVAILABLE_STREAM_CONFIGURATIONS,
        ANDROID_SCALER_CROPPING_TYPE,
        ANDROID_SENSOR_INFO_ACTIVE_ARRAY_SIZE,
        ANDROID_SENSOR_INFO_PHYSICAL_SIZE,
        ANDROID_SENSOR_INFO_PIXEL_ARRAY_SIZE,
        ANDROID_SENSOR_INFO_TIMESTAMP_SOURCE,
        ANDROID_SENSOR_ORIENTATION,
        ANDROID_STATISTICS_INFO_AVAILABLE_FACE_DETECT_MODES,
        ANDROID_STATISTICS_INFO_MAX_FACE_COUNT,
        ANDROID_SYNC_MAX_LATENCY,
    };

    meta->update(ANDROID_LENS_FACING, &facing, 1);
    meta->update(ANDROID_LENS_INFO_AVAILABLE_FOCAL_LENGTHS, &focal_length, 1);
    meta->update(ANDROID_LENS_INFO_AVAILABLE_APERTURES, &aperture, 1);
    meta->update(ANDROID_SENSOR_INFO_PIXEL_ARRAY_SIZE, pixel_array, 2);
    meta->update(ANDROID_SENSOR_INFO_ACTIVE_ARRAY_SIZE, active_array, 4);
    meta->update(ANDROID_SENSOR_ORIENTATION, &sensor_orientation, 1);
    meta->update(ANDROID_CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES, ae_fps_range, 2);
    meta->update(ANDROID_CONTROL_AE_COMPENSATION_RANGE, ae_comp_range, 2);
    meta->update(ANDROID_CONTROL_AE_COMPENSATION_STEP, &ae_comp_step, 1);
    meta->update(ANDROID_CONTROL_MAX_REGIONS, max_regions, 3);
    meta->update(ANDROID_SCALER_AVAILABLE_MAX_DIGITAL_ZOOM, &max_digital_zoom, 1);
    meta->update(ANDROID_INFO_SUPPORTED_HARDWARE_LEVEL, &hw_level, 1);
    meta->update(ANDROID_SCALER_AVAILABLE_STREAM_CONFIGURATIONS, stream_configs, 8);
    meta->update(ANDROID_SCALER_AVAILABLE_MIN_FRAME_DURATIONS, min_frame_durations, 8);
    meta->update(ANDROID_SCALER_AVAILABLE_STALL_DURATIONS, stall_durations, 8);
    meta->update(ANDROID_REQUEST_AVAILABLE_CAPABILITIES, caps, 1);
    meta->update(ANDROID_REQUEST_MAX_NUM_OUTPUT_STREAMS, max_num_output_streams, 3);
    meta->update(ANDROID_REQUEST_PARTIAL_RESULT_COUNT, &partial_result_count, 1);
    meta->update(ANDROID_REQUEST_PIPELINE_MAX_DEPTH, &pipeline_max_depth, 1);
    meta->update(ANDROID_CONTROL_AE_AVAILABLE_MODES,
                 is_front ? front_ae_modes : rear_ae_modes,
                 is_front ? sizeof(front_ae_modes) : sizeof(rear_ae_modes));
    meta->update(ANDROID_CONTROL_AF_AVAILABLE_MODES,
                 is_front ? front_af_modes : rear_af_modes,
                 is_front ? sizeof(front_af_modes) : sizeof(rear_af_modes));
    meta->update(ANDROID_CONTROL_AWB_AVAILABLE_MODES, awb_modes, 1);
    meta->update(ANDROID_CONTROL_AVAILABLE_MODES, control_modes, 1);
    meta->update(ANDROID_CONTROL_AVAILABLE_SCENE_MODES, scene_modes, 1);
    meta->update(ANDROID_CONTROL_AVAILABLE_EFFECTS, effect_modes, 1);
    meta->update(ANDROID_CONTROL_AVAILABLE_VIDEO_STABILIZATION_MODES,
                 video_stabilization_modes, 1);
    meta->update(ANDROID_CONTROL_AE_AVAILABLE_ANTIBANDING_MODES, ae_antibanding_modes,
                 sizeof(ae_antibanding_modes));
    meta->update(ANDROID_CONTROL_AE_LOCK_AVAILABLE, &ae_lock_available, 1);
    meta->update(ANDROID_CONTROL_AWB_LOCK_AVAILABLE, &awb_lock_available, 1);
    meta->update(ANDROID_JPEG_AVAILABLE_THUMBNAIL_SIZES, available_thumbnail_sizes, 6);
    meta->update(ANDROID_JPEG_MAX_SIZE, &jpeg_max_size, 1);
    meta->update(ANDROID_SENSOR_INFO_PHYSICAL_SIZE, sensor_physical_size, 2);
    meta->update(ANDROID_SENSOR_INFO_TIMESTAMP_SOURCE, &timestamp_source, 1);
    meta->update(ANDROID_SCALER_CROPPING_TYPE, &cropping_type, 1);
    meta->update(ANDROID_SYNC_MAX_LATENCY, &sync_max_latency, 1);
    meta->update(ANDROID_LENS_INFO_MINIMUM_FOCUS_DISTANCE, &minimum_focus_distance, 1);
    meta->update(ANDROID_LENS_INFO_HYPERFOCAL_DISTANCE, &hyperfocal_distance, 1);
    meta->update(ANDROID_LENS_INFO_FOCUS_DISTANCE_CALIBRATION, &focus_calibration, 1);
    meta->update(ANDROID_LENS_INFO_AVAILABLE_OPTICAL_STABILIZATION,
                 optical_stabilization_modes, 1);
    meta->update(ANDROID_FLASH_INFO_AVAILABLE, &flash_available, 1);
    meta->update(ANDROID_STATISTICS_INFO_AVAILABLE_FACE_DETECT_MODES, face_detect_modes, 1);
    meta->update(ANDROID_STATISTICS_INFO_MAX_FACE_COUNT, &max_face_count, 1);
    meta->update(ANDROID_REQUEST_MAX_NUM_INPUT_STREAMS, &max_num_input_streams, 1);
    meta->update(ANDROID_REQUEST_AVAILABLE_REQUEST_KEYS, request_keys,
                 sizeof(request_keys) / sizeof(request_keys[0]));
    meta->update(ANDROID_REQUEST_AVAILABLE_RESULT_KEYS, result_keys,
                 sizeof(result_keys) / sizeof(result_keys[0]));
    meta->update(ANDROID_REQUEST_AVAILABLE_CHARACTERISTICS_KEYS, characteristic_keys,
                 sizeof(characteristic_keys) / sizeof(characteristic_keys[0]));
}

static int m86_get_camera_info(int camera_id, struct camera_info *info)
{
    if (info == nullptr || camera_id < 0 || camera_id >= M86_CAMERA_COUNT) {
        return -EINVAL;
    }

    memset(info, 0, sizeof(*info));

    CameraMetadata *meta = new CameraMetadata();
    if (meta == nullptr) {
        return -ENOMEM;
    }

    m86_fill_static_metadata(camera_id, meta);
    meta->sort();

    info->facing = (camera_id == 1) ? CAMERA_FACING_FRONT : CAMERA_FACING_BACK;
    info->orientation = (camera_id == 1) ? 270 : 90;
    info->device_version = CAMERA_DEVICE_API_VERSION_3_4;
    info->static_camera_characteristics = meta->release();
    info->resource_cost = 51;
    info->conflicting_devices = nullptr;
    info->conflicting_devices_length = 0;

    delete meta;
    return 0;
}

static int m86_set_callbacks(const camera_module_callbacks_t *callbacks)
{
    pthread_mutex_lock(&g_module_lock);
    g_module_callbacks = callbacks;
    const torch_mode_status_t status = g_rear_camera_open
            ? TORCH_MODE_STATUS_NOT_AVAILABLE
            : (g_torch_enabled ? TORCH_MODE_STATUS_AVAILABLE_ON
                               : TORCH_MODE_STATUS_AVAILABLE_OFF);
    pthread_mutex_unlock(&g_module_lock);
    if (callbacks != nullptr && callbacks->torch_mode_status_change != nullptr) {
        callbacks->torch_mode_status_change(callbacks, "0", status);
    }
    return 0;
}

static void m86_get_vendor_tag_ops(vendor_tag_ops_t * /* ops */)
{
}

static int m86_open_legacy(const struct hw_module_t * /* module */, const char * /* id */,
                           uint32_t /* halVersion */, struct hw_device_t ** /* device */)
{
    return -EOPNOTSUPP;
}

static int m86_set_torch_mode(const char *camera_id, bool enabled)
{
    if (camera_id == nullptr) {
        return -EINVAL;
    }
    if (strcmp(camera_id, "1") == 0) {
        return -ENOSYS;
    }
    if (strcmp(camera_id, "0") != 0) {
        return -EINVAL;
    }

    pthread_mutex_lock(&g_module_lock);
    if (g_rear_camera_open) {
        pthread_mutex_unlock(&g_module_lock);
        return -EBUSY;
    }
    pthread_mutex_unlock(&g_module_lock);

    int err;
    if (enabled) {
        /*
         * The LM3644 driver leaves HWEN low after probe.  Register writes made
         * through brightness/enable while HWEN is low are accepted by sysfs,
         * but fail asynchronously on I2C, so CameraService would otherwise be
         * told that the torch is on while the LED remains dark.
         */
        err = m86_write_sysfs("/sys/class/leds/torch0/hwen", "enable\n");
        if (err == 0) {
            usleep(2000);
            err = m86_write_sysfs("/sys/class/leds/torch0/brightness", "50000\n");
        }
        if (err == 0) {
            err = m86_write_sysfs("/sys/class/leds/torch1/brightness", "50000\n");
        }
        if (err == 0) {
            /* brightness_set runs on the driver's workqueue. */
            usleep(10000);
            err = m86_write_sysfs("/sys/class/leds/torch0/enable", "enable\n");
        }
        if (err == 0) {
            err = m86_write_sysfs("/sys/class/leds/torch1/enable", "enable\n");
        }
        if (err == 0) {
            err = m86_write_sysfs("/sys/class/leds/torch0/onoff", "on\n");
        }
        if (err != 0) {
            m86_write_sysfs("/sys/class/leds/torch0/onoff", "off\n");
            m86_write_sysfs("/sys/class/leds/torch0/enable", "disable\n");
            m86_write_sysfs("/sys/class/leds/torch1/enable", "disable\n");
            m86_write_sysfs("/sys/class/leds/torch0/hwen", "disable\n");
            ALOGE("%s: failed to enable torch: %d", __FUNCTION__, err);
            return err;
        }
    } else {
        err = m86_write_sysfs("/sys/class/leds/torch0/onoff", "off\n");
        const int disable_err =
                m86_write_sysfs("/sys/class/leds/torch0/enable", "disable\n");
        const int disable_second_err =
                m86_write_sysfs("/sys/class/leds/torch1/enable", "disable\n");
        usleep(2000);
        const int hwen_err =
                m86_write_sysfs("/sys/class/leds/torch0/hwen", "disable\n");
        if (err == 0) {
            err = disable_err;
        }
        if (err == 0) {
            err = disable_second_err;
        }
        if (err == 0) {
            err = hwen_err;
        }
        if (err != 0) {
            ALOGE("%s: failed to disable torch: %d", __FUNCTION__, err);
            return err;
        }
    }

    pthread_mutex_lock(&g_module_lock);
    g_torch_enabled = enabled;
    pthread_mutex_unlock(&g_module_lock);
    m86_notify_torch_status(enabled ? TORCH_MODE_STATUS_AVAILABLE_ON
                                    : TORCH_MODE_STATUS_AVAILABLE_OFF);
    return 0;
}

static int m86_init(void)
{
    return 0;
}

static int m86_device_flush(const struct camera3_device *device);

static int m86_device_close(hw_device_t *device)
{
    if (device == nullptr) {
        return -EINVAL;
    }

    m86_camera3_device_t *m86_dev = reinterpret_cast<m86_camera3_device_t *>(device);
    const bool rear_camera = m86_dev->camera_id == 0;
    if (m86_dev->engine != nullptr) {
        m86_device_flush(&m86_dev->base);
        // ~ExynosCamera() calls release(); calling it here first would tear
        // down the FIMC-IS pipes twice and hang fimc_is_ischain_3aa_close.
        delete m86_dev->engine;
    }
    if (m86_dev->window != nullptr) {
        m86_preview_window_deinit(m86_dev->window);
        delete m86_dev->window;
    }
    pthread_cond_destroy(&m86_dev->pending_cond);
    pthread_mutex_destroy(&m86_dev->pending_lock);
    delete const_cast<camera3_device_ops_t *>(m86_dev->base.ops);
    delete m86_dev;
    if (rear_camera) {
        pthread_mutex_lock(&g_module_lock);
        g_rear_camera_open = false;
        pthread_mutex_unlock(&g_module_lock);
        m86_notify_torch_status(TORCH_MODE_STATUS_AVAILABLE_OFF);
    }
    return 0;
}

struct m86_camera_memory : public camera_memory_t {
    m86_camera_memory(int fd, size_t buffer_size, unsigned int num_buffers)
    {
        memset(this, 0, sizeof(*this));
        backing_fd = fd;
        this->buffer_size = buffer_size;
        this->num_buffers = num_buffers;
        this->size = buffer_size * num_buffers;
        if (fd < 0) {
            mapped = malloc(this->size ? this->size : 1);
            this->data = mapped;
        } else if (this->size > 0) {
            mapped = mmap(nullptr, this->size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
            if (mapped == MAP_FAILED) {
                mapped = nullptr;
            }
            this->data = mapped;
        }
        this->release = m86_camera_memory_release;
    }

    static void m86_camera_memory_release(camera_memory_t *mem)
    {
        m86_camera_memory *self = static_cast<m86_camera_memory *>(mem);
        if (self == nullptr) {
            return;
        }
        if (self->mapped != nullptr) {
            if (self->backing_fd < 0) {
                free(self->mapped);
            } else {
                munmap(self->mapped, self->size);
            }
        }
        delete self;
    }

    void *mapped;
    int backing_fd;
    size_t buffer_size;
    unsigned int num_buffers;
};

static camera_memory_t *m86_request_memory(int fd, size_t buf_size, unsigned int num_bufs,
                                           void * /* user */)
{
    if (num_bufs == 0 || (buf_size != 0 && num_bufs > SIZE_MAX / buf_size)) {
        return nullptr;
    }
    m86_camera_memory *mem = new (std::nothrow) m86_camera_memory(fd, buf_size, num_bufs);
    return (mem == nullptr || mem->data == nullptr) ? nullptr : mem;
}

static int64_t m86_now_ns(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return static_cast<int64_t>(ts.tv_sec) * 1000000000LL + ts.tv_nsec;
}

static bool m86_enqueue_stream_request(m86_camera3_device_t *m86_dev,
                                       const m86_pending_stream_request_t *request,
                                       bool video)
{
    bool queued = false;

    pthread_mutex_lock(&m86_dev->pending_lock);
    uint32_t *head = video ? &m86_dev->video_pending_head : &m86_dev->pending_head;
    uint32_t *count = video ? &m86_dev->video_pending_count : &m86_dev->pending_count;
    m86_pending_stream_request_t *queue = video ? m86_dev->video_pending : m86_dev->pending;
    if (*count < M86_MAX_PENDING_PREVIEW_REQUESTS) {
        const uint32_t tail = (*head + *count) %
                M86_MAX_PENDING_PREVIEW_REQUESTS;
        queue[tail] = *request;
        (*count)++;
        pthread_cond_signal(&m86_dev->pending_cond);
        queued = true;
    }
    pthread_mutex_unlock(&m86_dev->pending_lock);

    return queued;
}

static bool m86_dequeue_stream_request(m86_camera3_device_t *m86_dev,
                                       m86_pending_stream_request_t *request,
                                       bool video)
{
    bool dequeued = false;

    pthread_mutex_lock(&m86_dev->pending_lock);
    uint32_t *head = video ? &m86_dev->video_pending_head : &m86_dev->pending_head;
    uint32_t *count = video ? &m86_dev->video_pending_count : &m86_dev->pending_count;
    m86_pending_stream_request_t *queue = video ? m86_dev->video_pending : m86_dev->pending;
    if (*count > 0) {
        *request = queue[*head];
        memset(&queue[*head], 0, sizeof(queue[*head]));
        *head = (*head + 1) % M86_MAX_PENDING_PREVIEW_REQUESTS;
        (*count)--;
        dequeued = true;
    }
    pthread_mutex_unlock(&m86_dev->pending_lock);

    return dequeued;
}

static bool m86_reserve_jpeg_request(m86_camera3_device_t *m86_dev,
                                     const m86_pending_jpeg_request_t *request)
{
    bool reserved = false;

    pthread_mutex_lock(&m86_dev->pending_lock);
    if (!m86_dev->flushing &&
        m86_dev->pending_jpeg_count < M86_MAX_PENDING_JPEG_REQUESTS) {
        const uint32_t tail =
                (m86_dev->pending_jpeg_head + m86_dev->pending_jpeg_count) %
                M86_MAX_PENDING_JPEG_REQUESTS;
        m86_dev->pending_jpeg[tail] = *request;
        m86_dev->pending_jpeg_count++;
        reserved = true;
    }
    pthread_mutex_unlock(&m86_dev->pending_lock);

    return reserved;
}

static bool m86_take_jpeg_request(m86_camera3_device_t *m86_dev,
                                  m86_pending_jpeg_request_t *request)
{
    bool found = false;

    pthread_mutex_lock(&m86_dev->pending_lock);
    if (m86_dev->pending_jpeg_count > 0) {
        *request = m86_dev->pending_jpeg[m86_dev->pending_jpeg_head];
        memset(&m86_dev->pending_jpeg[m86_dev->pending_jpeg_head], 0,
               sizeof(m86_dev->pending_jpeg[m86_dev->pending_jpeg_head]));
        m86_dev->pending_jpeg_head =
                (m86_dev->pending_jpeg_head + 1) % M86_MAX_PENDING_JPEG_REQUESTS;
        m86_dev->pending_jpeg_count--;
        m86_dev->jpeg_capture_active = false;
        found = true;
    }
    pthread_mutex_unlock(&m86_dev->pending_lock);

    return found;
}

static bool m86_begin_next_jpeg_request(m86_camera3_device_t *m86_dev,
                                        m86_pending_jpeg_request_t *request)
{
    bool found = false;
    pthread_mutex_lock(&m86_dev->pending_lock);
    if (!m86_dev->flushing && !m86_dev->jpeg_capture_active &&
        m86_dev->pending_jpeg_count > 0) {
        *request = m86_dev->pending_jpeg[m86_dev->pending_jpeg_head];
        m86_dev->jpeg_capture_active = true;
        found = true;
    }
    pthread_mutex_unlock(&m86_dev->pending_lock);
    return found;
}

static void m86_send_request_error(m86_camera3_device_t *m86_dev,
                                   const m86_pending_preview_request_t *pending)
{
    if (m86_dev == nullptr || m86_dev->callback_ops == nullptr || pending == nullptr) {
        return;
    }

    camera3_notify_msg_t notify;
    memset(&notify, 0, sizeof(notify));
    notify.type = CAMERA3_MSG_ERROR;
    notify.message.error.frame_number = pending->frame_number;
    notify.message.error.error_stream = nullptr;
    notify.message.error.error_code = CAMERA3_MSG_ERROR_REQUEST;
    m86_dev->callback_ops->notify(m86_dev->callback_ops, &notify);

    camera3_stream_buffer_t output_buffers[M86_MAX_REQUEST_OUTPUT_BUFFERS];
    memset(output_buffers, 0, sizeof(output_buffers));
    for (uint32_t i = 0; i < pending->num_output_buffers; i++) {
        output_buffers[i].stream = pending->output_buffers[i].stream;
        output_buffers[i].buffer = pending->output_buffers[i].buffer;
        output_buffers[i].status = CAMERA3_BUFFER_STATUS_ERROR;
        output_buffers[i].acquire_fence = -1;
        output_buffers[i].release_fence = -1;
    }

    camera3_capture_result_t result;
    memset(&result, 0, sizeof(result));
    result.frame_number = pending->frame_number;
    result.num_output_buffers = pending->num_output_buffers;
    result.output_buffers = output_buffers;
    m86_dev->callback_ops->process_capture_result(m86_dev->callback_ops, &result);
}

static camera_metadata_t *m86_build_result_metadata(m86_camera3_device_t *m86_dev,
                                                    int64_t timestamp_ns)
{
    CameraMetadata metadata;
    const uint8_t control_mode = ANDROID_CONTROL_MODE_AUTO;
    const uint8_t pipeline_depth = M86_PREVIEW_WINDOW_MIN_BUFFERS;
    const uint8_t face_detect_mode = ANDROID_STATISTICS_FACE_DETECT_MODE_OFF;
    const float focal_length = m86_dev->camera_id == 1 ? 3.50f : 4.73f;

    pthread_mutex_lock(&m86_dev->pending_lock);
    const uint8_t ae_mode = m86_dev->ae_mode;
    const uint8_t ae_state = m86_dev->ae_state;
    const uint8_t af_mode = m86_dev->af_mode;
    const uint8_t af_state = m86_dev->af_state;
    const uint8_t awb_mode = m86_dev->awb_mode;
    const uint8_t awb_state = m86_dev->awb_state;
    const uint8_t flash_mode = m86_dev->flash_mode;
    const uint8_t flash_state = m86_dev->flash_state;
    const int32_t exposure_compensation = m86_dev->exposure_compensation;
    int32_t crop_region[4];
    memcpy(crop_region, m86_dev->crop_region, sizeof(crop_region));
    if (m86_dev->ae_state == ANDROID_CONTROL_AE_STATE_PRECAPTURE) {
        m86_dev->ae_state = ANDROID_CONTROL_AE_STATE_CONVERGED;
    }
    pthread_mutex_unlock(&m86_dev->pending_lock);

    metadata.update(ANDROID_CONTROL_MODE, &control_mode, 1);
    metadata.update(ANDROID_CONTROL_AE_MODE, &ae_mode, 1);
    metadata.update(ANDROID_CONTROL_AE_STATE, &ae_state, 1);
    metadata.update(ANDROID_CONTROL_AE_EXPOSURE_COMPENSATION, &exposure_compensation, 1);
    metadata.update(ANDROID_CONTROL_AF_MODE, &af_mode, 1);
    metadata.update(ANDROID_CONTROL_AF_STATE, &af_state, 1);
    metadata.update(ANDROID_CONTROL_AWB_MODE, &awb_mode, 1);
    metadata.update(ANDROID_CONTROL_AWB_STATE, &awb_state, 1);
    metadata.update(ANDROID_FLASH_MODE, &flash_mode, 1);
    metadata.update(ANDROID_FLASH_STATE, &flash_state, 1);
    metadata.update(ANDROID_LENS_FOCAL_LENGTH, &focal_length, 1);
    metadata.update(ANDROID_REQUEST_PIPELINE_DEPTH, &pipeline_depth, 1);
    metadata.update(ANDROID_SCALER_CROP_REGION, crop_region, 4);
    metadata.update(ANDROID_SENSOR_TIMESTAMP, &timestamp_ns, 1);
    metadata.update(ANDROID_STATISTICS_FACE_DETECT_MODE, &face_detect_mode, 1);
    metadata.sort();
    return metadata.release();
}

static void m86_send_stream_result(m86_camera3_device_t *m86_dev,
                                   const m86_pending_stream_request_t *pending,
                                   bool success)
{
    if (m86_dev == nullptr || m86_dev->callback_ops == nullptr || pending == nullptr) {
        return;
    }

    if (!success) {
        camera3_notify_msg_t notify;
        memset(&notify, 0, sizeof(notify));
        notify.type = CAMERA3_MSG_ERROR;
        notify.message.error.frame_number = pending->frame_number;
        notify.message.error.error_stream = pending->output.stream;
        notify.message.error.error_code = CAMERA3_MSG_ERROR_BUFFER;
        m86_dev->callback_ops->notify(m86_dev->callback_ops, &notify);
    }

    camera3_stream_buffer_t output;
    memset(&output, 0, sizeof(output));
    output.stream = pending->output.stream;
    output.buffer = pending->output.buffer;
    output.status = success ? CAMERA3_BUFFER_STATUS_OK : CAMERA3_BUFFER_STATUS_ERROR;
    output.acquire_fence = -1;
    output.release_fence = -1;

    camera3_capture_result_t result;
    memset(&result, 0, sizeof(result));
    result.frame_number = pending->frame_number;
    result.result = nullptr;
    result.num_output_buffers = 1;
    result.output_buffers = &output;
    result.input_buffer = nullptr;
    result.partial_result = 0;
    m86_dev->callback_ops->process_capture_result(m86_dev->callback_ops, &result);
}

static void m86_send_request_shutter_and_metadata(
        m86_camera3_device_t *m86_dev,
        const m86_pending_preview_request_t *pending)
{
    if (m86_dev == nullptr || m86_dev->callback_ops == nullptr || pending == nullptr) {
        return;
    }

    // The legacy engine can spend hundreds of milliseconds encoding a still
    // image while newer preview requests continue to complete.  Camera3,
    // however, requires shutter notifications to be strictly frame ordered.
    // Publish shutter and the single metadata partial synchronously, in request
    // order, then return the stream buffers asynchronously from the callbacks.
    camera3_notify_msg_t notify;
    memset(&notify, 0, sizeof(notify));
    notify.type = CAMERA3_MSG_SHUTTER;
    notify.message.shutter.frame_number = pending->frame_number;
    notify.message.shutter.timestamp = pending->timestamp_ns;
    m86_dev->callback_ops->notify(m86_dev->callback_ops, &notify);

    camera_metadata_t *metadata =
            m86_build_result_metadata(m86_dev, pending->timestamp_ns);
    camera3_capture_result_t result;
    memset(&result, 0, sizeof(result));
    result.frame_number = pending->frame_number;
    result.result = metadata;
    result.partial_result = 1;
    m86_dev->callback_ops->process_capture_result(m86_dev->callback_ops, &result);
    free_camera_metadata(metadata);
}

static void m86_send_jpeg_error(m86_camera3_device_t *m86_dev,
                                const m86_pending_jpeg_request_t *pending)
{
    if (m86_dev == nullptr || m86_dev->callback_ops == nullptr || pending == nullptr) {
        return;
    }

    camera3_notify_msg_t notify;
    memset(&notify, 0, sizeof(notify));
    notify.type = CAMERA3_MSG_ERROR;
    notify.message.error.frame_number = pending->frame_number;
    notify.message.error.error_stream = pending->output.stream;
    notify.message.error.error_code = CAMERA3_MSG_ERROR_BUFFER;
    m86_dev->callback_ops->notify(m86_dev->callback_ops, &notify);

    camera3_stream_buffer_t output;
    memset(&output, 0, sizeof(output));
    output.stream = pending->output.stream;
    output.buffer = pending->output.buffer;
    output.status = CAMERA3_BUFFER_STATUS_ERROR;
    output.acquire_fence = -1;
    output.release_fence = -1;

    camera3_capture_result_t result;
    memset(&result, 0, sizeof(result));
    result.frame_number = pending->frame_number;
    result.num_output_buffers = 1;
    result.output_buffers = &output;
    m86_dev->callback_ops->process_capture_result(m86_dev->callback_ops, &result);
    pthread_mutex_lock(&m86_dev->pending_lock);
    if (m86_dev->camera_id == 0 && m86_dev->flash_mode != ANDROID_FLASH_MODE_TORCH) {
        m86_dev->flash_state = ANDROID_FLASH_STATE_READY;
    }
    pthread_mutex_unlock(&m86_dev->pending_lock);
}

static bool m86_send_jpeg_result(m86_camera3_device_t *m86_dev,
                                 const camera_memory_t *data,
                                 unsigned int index)
{
    if (m86_dev == nullptr || data == nullptr || data->data == nullptr) {
        return false;
    }

    m86_pending_jpeg_request_t pending;
    if (!m86_take_jpeg_request(m86_dev, &pending)) {
        ALOGW("%s: compressed image without a pending BLOB request", __FUNCTION__);
        return false;
    }

    const m86_camera_memory *memory = static_cast<const m86_camera_memory *>(data);
    if (index >= memory->num_buffers || pending.output.buffer == nullptr) {
        ALOGE("%s: invalid JPEG callback index=%u count=%u buffer=%p", __FUNCTION__,
              index, memory->num_buffers, pending.output.buffer);
        m86_send_jpeg_error(m86_dev, &pending);
        return false;
    }

    const buffer_handle_t handle = *pending.output.buffer;
    private_handle_t *hnd = private_handle_t::dynamicCast(handle);
    const gralloc_module_t *gralloc = m86_get_gralloc_module();
    if (hnd == nullptr || gralloc == nullptr || gralloc->lock == nullptr ||
        gralloc->unlock == nullptr) {
        ALOGE("%s: cannot map JPEG BLOB handle", __FUNCTION__);
        m86_send_jpeg_error(m86_dev, &pending);
        return false;
    }

    const size_t jpeg_size = memory->buffer_size;
    const size_t capacity = hnd->size > 0
            ? static_cast<size_t>(hnd->size)
            : static_cast<size_t>(hnd->width) * hnd->height;
    if (capacity < sizeof(camera3_jpeg_blob_t) ||
        jpeg_size > capacity - sizeof(camera3_jpeg_blob_t)) {
        ALOGE("%s: JPEG does not fit BLOB buffer size=%zu capacity=%zu", __FUNCTION__,
              jpeg_size, capacity);
        m86_send_jpeg_error(m86_dev, &pending);
        return false;
    }

    void *planes[3] = {nullptr, nullptr, nullptr};
    int err = gralloc->lock(gralloc, handle, GRALLOC_USAGE_SW_WRITE_OFTEN,
                            0, 0, hnd->width, hnd->height, planes);
    if (err != 0 || planes[0] == nullptr) {
        ALOGE("%s: JPEG BLOB gralloc lock failed: %d", __FUNCTION__, err);
        m86_send_jpeg_error(m86_dev, &pending);
        return false;
    }

    uint8_t *destination = static_cast<uint8_t *>(planes[0]);
    const uint8_t *source = static_cast<const uint8_t *>(data->data) +
                            static_cast<size_t>(index) * memory->buffer_size;
    memcpy(destination, source, jpeg_size);
    camera3_jpeg_blob_t blob;
    blob.jpeg_blob_id = CAMERA3_JPEG_BLOB_ID;
    blob.jpeg_size = static_cast<uint32_t>(jpeg_size);
    memcpy(destination + capacity - sizeof(blob), &blob, sizeof(blob));
    err = gralloc->unlock(gralloc, handle);
    if (err != 0) {
        ALOGE("%s: JPEG BLOB gralloc unlock failed: %d", __FUNCTION__, err);
        m86_send_jpeg_error(m86_dev, &pending);
        return false;
    }

    camera3_stream_buffer_t output;
    memset(&output, 0, sizeof(output));
    output.stream = pending.output.stream;
    output.buffer = pending.output.buffer;
    output.status = CAMERA3_BUFFER_STATUS_OK;
    output.acquire_fence = -1;
    output.release_fence = -1;

    camera3_capture_result_t result;
    memset(&result, 0, sizeof(result));
    result.frame_number = pending.frame_number;
    result.result = nullptr;
    result.num_output_buffers = 1;
    result.output_buffers = &output;
    result.partial_result = 0;
    m86_dev->callback_ops->process_capture_result(m86_dev->callback_ops, &result);

    pthread_mutex_lock(&m86_dev->pending_lock);
    if (m86_dev->camera_id == 0 && m86_dev->flash_mode != ANDROID_FLASH_MODE_TORCH) {
        m86_dev->flash_state = ANDROID_FLASH_STATE_READY;
    }
    pthread_mutex_unlock(&m86_dev->pending_lock);

    ALOGI("%s: completed JPEG frame %u size=%zu capacity=%zu", __FUNCTION__,
          pending.frame_number, jpeg_size, capacity);
    return true;
}

static void m86_notify_cb(int32_t msg_type, int32_t ext1, int32_t /* ext2 */, void *user)
{
    m86_camera3_device_t *m86_dev = static_cast<m86_camera3_device_t *>(user);
    if (m86_dev == nullptr || m86_dev->callback_ops == nullptr) {
        return;
    }
    if (msg_type == CAMERA_MSG_FOCUS || msg_type == CAMERA_MSG_FOCUS_MOVE) {
        pthread_mutex_lock(&m86_dev->pending_lock);
        if (msg_type == CAMERA_MSG_FOCUS) {
            m86_dev->af_state = ext1 ? ANDROID_CONTROL_AF_STATE_FOCUSED_LOCKED
                                     : ANDROID_CONTROL_AF_STATE_NOT_FOCUSED_LOCKED;
        } else if (m86_dev->af_mode == ANDROID_CONTROL_AF_MODE_CONTINUOUS_PICTURE ||
                   m86_dev->af_mode == ANDROID_CONTROL_AF_MODE_CONTINUOUS_VIDEO) {
            m86_dev->af_state = ext1 ? ANDROID_CONTROL_AF_STATE_PASSIVE_SCAN
                                     : ANDROID_CONTROL_AF_STATE_PASSIVE_FOCUSED;
        }
        pthread_mutex_unlock(&m86_dev->pending_lock);
        return;
    }
    if (msg_type == CAMERA_MSG_ERROR) {
        m86_pending_jpeg_request_t jpeg;
        if (m86_take_jpeg_request(m86_dev, &jpeg)) {
            m86_send_jpeg_error(m86_dev, &jpeg);
            m86_start_next_jpeg_capture(m86_dev);
            return;
        }
        m86_pending_stream_request_t pending;
        if (m86_dequeue_stream_request(m86_dev, &pending, false)) {
            m86_send_stream_result(m86_dev, &pending, false);
        }
        if (m86_dequeue_stream_request(m86_dev, &pending, true)) {
            m86_send_stream_result(m86_dev, &pending, false);
        }
    }
}

static const gralloc_module_t *m86_get_gralloc_module(void)
{
    static const gralloc_module_t *module = nullptr;
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_lock(&lock);
    if (module == nullptr) {
        const hw_module_t *hw = nullptr;
        if (hw_get_module(GRALLOC_HARDWARE_MODULE_ID, &hw) == 0 && hw != nullptr) {
            module = reinterpret_cast<const gralloc_module_t *>(hw);
        }
    }
    pthread_mutex_unlock(&lock);
    return module;
}

static bool m86_copy_preview_to_stream(
        m86_camera3_device_t *m86_dev,
        const m86_pending_stream_request_t *pending,
        const uint8_t *src_y, const uint8_t *src_chroma,
        int src_y_stride, int src_chroma_stride,
        bool src_is_nv21, int64_t timestamp_ns)
{
    if (m86_dev == nullptr || pending == nullptr || src_y == nullptr ||
        src_chroma == nullptr) {
        return false;
    }

    if (pending->output.stream == nullptr || pending->output.buffer == nullptr) {
        ALOGE("%s: invalid stream output", __FUNCTION__);
        m86_send_stream_result(m86_dev, pending, false);
        return false;
    }

    const m86_pending_output_buffer_t *preview_output = &pending->output;
    camera3_stream_t *stream = preview_output->stream;
    const int width = static_cast<int>(stream->width);
    const int height = static_cast<int>(stream->height);

    const buffer_handle_t handle = *preview_output->buffer;
    private_handle_t *hnd = private_handle_t::dynamicCast(handle);
    if (hnd == nullptr) {
        ALOGE("%s: invalid m86 gralloc handle", __FUNCTION__);
        m86_send_stream_result(m86_dev, pending, false);
        return false;
    }

    const gralloc_module_t *gralloc = m86_get_gralloc_module();
    if (gralloc == nullptr || gralloc->lock == nullptr || gralloc->unlock == nullptr) {
        ALOGE("%s: cannot load legacy gralloc module", __FUNCTION__);
        m86_send_stream_result(m86_dev, pending, false);
        return false;
    }

    if (src_y_stride < width || src_chroma_stride < width ||
        hnd->width < width || hnd->height < height) {
        ALOGE("%s: incompatible source/destination size src_stride=%d/%d dst=%dx%d stream=%dx%d",
              __FUNCTION__, src_y_stride, src_chroma_stride, hnd->width, hnd->height,
              width, height);
        m86_send_stream_result(m86_dev, pending, false);
        return false;
    }

    // The m86 gralloc 0.2 lock implementation writes up to three plane
    // addresses through vaddr.  Gralloc2Mapper supplies only one pointer and
    // consequently corrupts its own stack for the normal NV21M preview
    // allocation.  Call the native module contract with all three slots.
    void *planes[3] = {nullptr, nullptr, nullptr};
    int err = gralloc->lock(gralloc, handle, GRALLOC_USAGE_SW_WRITE_OFTEN,
                            0, 0, hnd->width, hnd->height, planes);
    if (err != 0 || planes[0] == nullptr) {
        ALOGE("%s: legacy gralloc lock failed: %d", __FUNCTION__, err);
        m86_send_stream_result(m86_dev, pending, false);
        return false;
    }

    uint8_t *dst_y = static_cast<uint8_t *>(planes[0]);
    uint8_t *dst_chroma = nullptr;
    const int y_stride = hnd->stride > 0 ? hnd->stride : width;
    const int y_vstride = hnd->vstride > 0 ? hnd->vstride : height;
    int chroma_stride = y_stride;
    bool destination_is_nv21 = false;

    switch (hnd->format) {
        case HAL_PIXEL_FORMAT_YCrCb_420_SP:
            dst_chroma = dst_y + static_cast<size_t>(y_stride) * height;
            destination_is_nv21 = true;
            break;
        case HAL_PIXEL_FORMAT_EXYNOS_YCrCb_420_SP_M:
        case HAL_PIXEL_FORMAT_EXYNOS_YCrCb_420_SP_M_FULL:
            dst_chroma = static_cast<uint8_t *>(planes[1]);
            destination_is_nv21 = true;
            break;
        case HAL_PIXEL_FORMAT_EXYNOS_YCbCr_420_SP_M:
        case HAL_PIXEL_FORMAT_EXYNOS_YCbCr_420_SP_M_PRIV:
            dst_chroma = static_cast<uint8_t *>(planes[1]);
            destination_is_nv21 = false;
            break;
        case HAL_PIXEL_FORMAT_EXYNOS_YCbCr_420_SPN:
            dst_chroma = dst_y + static_cast<size_t>(y_stride) * y_vstride + 256;
            destination_is_nv21 = false;
            break;
        default:
            ALOGE("%s: unsupported gralloc format 0x%x", __FUNCTION__, hnd->format);
            gralloc->unlock(gralloc, handle);
            m86_send_stream_result(m86_dev, pending, false);
            return false;
    }

    if (dst_chroma == nullptr || y_stride < width || chroma_stride < width) {
        ALOGE("%s: invalid destination layout format=0x%x stride=%d planes=%p/%p/%p",
              __FUNCTION__, hnd->format, y_stride, planes[0], planes[1], planes[2]);
        gralloc->unlock(gralloc, handle);
        m86_send_stream_result(m86_dev, pending, false);
        return false;
    }

    if (!m86_dev->buffer_layout_logged) {
        ALOGI("%s: gralloc format=0x%x framework=0x%x size=%dx%d stride=%d/%d "
              "fds=%d/%d/%d",
              __FUNCTION__, hnd->format, hnd->frameworkFormat, hnd->width, hnd->height,
              y_stride, y_vstride, hnd->fd, hnd->fd1, hnd->fd2);
        m86_dev->buffer_layout_logged = true;
    }

    for (int y = 0; y < height; y++) {
        memcpy(dst_y + static_cast<size_t>(y) * y_stride,
               src_y + static_cast<size_t>(y) * src_y_stride, static_cast<size_t>(width));
    }

    const int chroma_height = (height + 1) / 2;
    for (int y = 0; y < chroma_height; y++) {
        uint8_t *dst_row = dst_chroma + static_cast<size_t>(y) * chroma_stride;
        const uint8_t *src_row = src_chroma + static_cast<size_t>(y) * src_chroma_stride;
        if (destination_is_nv21 == src_is_nv21) {
            memcpy(dst_row, src_row, static_cast<size_t>(width));
        } else {
            for (int x = 0; x + 1 < width; x += 2) {
                dst_row[x] = src_row[x + 1];
                dst_row[x + 1] = src_row[x];
            }
        }
    }

    err = gralloc->unlock(gralloc, handle);
    if (err != 0) {
        ALOGE("%s: legacy gralloc unlock failed: %d", __FUNCTION__, err);
        m86_send_stream_result(m86_dev, pending, false);
        return false;
    }

    m86_send_stream_result(m86_dev, pending, true);
    return true;
}

static void m86_data_cb(int32_t msg_type, const camera_memory_t *data, unsigned int index,
                        camera_frame_metadata_t * /* metadata */, void *user)
{
    m86_camera3_device_t *m86_dev = static_cast<m86_camera3_device_t *>(user);
    if (m86_dev == nullptr || data == nullptr || data->data == nullptr) {
        return;
    }

    if (msg_type == CAMERA_MSG_COMPRESSED_IMAGE) {
        m86_send_jpeg_result(m86_dev, data, index);
        m86_start_next_jpeg_capture(m86_dev);
        return;
    }
    if (msg_type != CAMERA_MSG_PREVIEW_FRAME) {
        return;
    }

    m86_pending_stream_request_t pending;
    if (!m86_dequeue_stream_request(m86_dev, &pending, false)) {
        return;
    }

    const m86_camera_memory *memory = static_cast<const m86_camera_memory *>(data);
    if (index >= memory->num_buffers) {
        ALOGE("%s: invalid preview buffer index %u/%u", __FUNCTION__, index,
              memory->num_buffers);
        m86_send_stream_result(m86_dev, &pending, false);
        return;
    }

    const int width = static_cast<int>(m86_dev->configured_preview_stream->width);
    const int height = static_cast<int>(m86_dev->configured_preview_stream->height);
    const size_t source_size = static_cast<size_t>(width) * height * 3 / 2;
    if (memory->buffer_size < source_size) {
        ALOGE("%s: incompatible source size %zu for %dx%d", __FUNCTION__,
              memory->buffer_size, width, height);
        m86_send_stream_result(m86_dev, &pending, false);
        return;
    }

    const uint8_t *src = static_cast<const uint8_t *>(data->data) +
                         static_cast<size_t>(index) * memory->buffer_size;
    m86_copy_preview_to_stream(m86_dev, &pending, src,
                               src + static_cast<size_t>(width) * height,
                               width, width, true, m86_now_ns());
}

static void m86_data_timestamp_cb(int64_t timestamp_ns, int32_t msg_type,
                                  const camera_memory_t *data, unsigned int index,
                                  void *user)
{
    m86_camera3_device_t *m86_dev = static_cast<m86_camera3_device_t *>(user);
    if (m86_dev == nullptr || m86_dev->engine == nullptr || data == nullptr ||
        data->data == nullptr || msg_type != CAMERA_MSG_VIDEO_FRAME) {
        return;
    }

    const m86_camera_memory *memory = static_cast<const m86_camera_memory *>(data);
    if (index >= memory->num_buffers ||
        memory->buffer_size < sizeof(VideoNativeHandleMetadata)) {
        ALOGE("%s: invalid recording metadata index=%u count=%u size=%zu", __FUNCTION__,
              index, memory->num_buffers, memory->buffer_size);
        return;
    }

    VideoNativeHandleMetadata *metadata =
            reinterpret_cast<VideoNativeHandleMetadata *>(
                    static_cast<uint8_t *>(data->data) +
                    static_cast<size_t>(index) * memory->buffer_size);
    native_handle_t *source_handle = metadata->pHandle;
    if (metadata->eType != kMetadataBufferTypeNativeHandleSource ||
        source_handle == nullptr || source_handle->numFds < 2 ||
        source_handle->numInts < 1) {
        ALOGE("%s: malformed recording native handle", __FUNCTION__);
        return;
    }

    // ExynosCamera deletes the callback's temporary native_handle immediately
    // after this function returns. releaseRecordingFrame() also owns and
    // deletes the handle it receives, so let the engine delete its original
    // handle and release a clone.  The metadata pointer itself must remain the
    // original callback-heap entry: ExynosCamera uses its address to return
    // that slot to m_recordingCallbackHeapAvailable.
    native_handle_t *release_handle = native_handle_clone(source_handle);
    if (release_handle == nullptr) {
        ALOGE("%s: could not clone recording native handle", __FUNCTION__);
        return;
    }
    metadata->pHandle = release_handle;

    m86_pending_stream_request_t pending;
    if (!m86_dequeue_stream_request(m86_dev, &pending, true)) {
        m86_dev->engine->releaseRecordingFrame(metadata);
        return;
    }

    const int width = static_cast<int>(pending.output.stream->width);
    const int height = static_cast<int>(pending.output.stream->height);
    const int source_stride = (width + 15) & ~15;
    const int source_vstride = (height + 15) & ~15;
    const size_t y_size = static_cast<size_t>(source_stride) * source_vstride;
    const size_t chroma_size = static_cast<size_t>(source_stride) *
                               (((height + 1) / 2 + 15) & ~15);

    struct stat y_stat;
    struct stat chroma_stat;
    const bool sizes_valid = fstat(source_handle->data[0], &y_stat) == 0 &&
                             fstat(source_handle->data[1], &chroma_stat) == 0 &&
                             (y_stat.st_size == 0 ||
                              static_cast<size_t>(y_stat.st_size) >= y_size) &&
                             (chroma_stat.st_size == 0 ||
                              static_cast<size_t>(chroma_stat.st_size) >= chroma_size);
    uint8_t *src_y = static_cast<uint8_t *>(MAP_FAILED);
    uint8_t *src_chroma = static_cast<uint8_t *>(MAP_FAILED);
    if (sizes_valid) {
        src_y = static_cast<uint8_t *>(mmap(nullptr, y_size, PROT_READ, MAP_SHARED,
                                            source_handle->data[0], 0));
        src_chroma = static_cast<uint8_t *>(mmap(nullptr, chroma_size, PROT_READ,
                                                 MAP_SHARED, source_handle->data[1], 0));
    }

    if (src_y == static_cast<uint8_t *>(MAP_FAILED) ||
        src_chroma == static_cast<uint8_t *>(MAP_FAILED)) {
        ALOGE("%s: could not map recording planes fds=%d/%d", __FUNCTION__,
              source_handle->data[0], source_handle->data[1]);
        if (src_y != static_cast<uint8_t *>(MAP_FAILED)) {
            munmap(src_y, y_size);
        }
        if (src_chroma != static_cast<uint8_t *>(MAP_FAILED)) {
            munmap(src_chroma, chroma_size);
        }
        m86_send_stream_result(m86_dev, &pending, false);
    } else {
        // The 74xx recording callback explicitly exports NV21M (Y + CrCb).
        m86_copy_preview_to_stream(m86_dev, &pending, src_y, src_chroma,
                                   source_stride, source_stride, true, timestamp_ns);
        munmap(src_chroma, chroma_size);
        munmap(src_y, y_size);
    }

    m86_dev->engine->releaseRecordingFrame(metadata);
}

static void m86_preview_window_free_buffers_locked(m86_preview_window_t *window)
{
    android::GraphicBufferAllocator &allocator = android::GraphicBufferAllocator::get();
    for (int i = 0; i < M86_PREVIEW_WINDOW_MAX_BUFFERS; i++) {
        if (window->buffers[i].handle != nullptr) {
            allocator.free(window->buffers[i].handle);
        }
        window->buffers[i].handle = nullptr;
        window->buffers[i].stride = 0;
        window->buffers[i].busy = false;
    }
    window->allocated_count = 0;
    window->allocated_width = 0;
    window->allocated_height = 0;
    window->allocated_format = 0;
    window->allocated_usage = 0;
}

static int m86_preview_window_alloc_buffers_locked(m86_preview_window_t *window)
{
    int count = window->buffer_count;
    if (count < M86_PREVIEW_WINDOW_MIN_BUFFERS) {
        // The engine's SCP buffer manager dequeues num_preview_buffers (12 on
        // m86) through this window before canceling them again.  Fewer window
        // buffers make that allocation fail midway with "dequeue_buffer
        // failed" and leave m_allocatedBufCount at zero.
        count = M86_PREVIEW_WINDOW_MIN_BUFFERS;
    } else if (count > M86_PREVIEW_WINDOW_MAX_BUFFERS) {
        count = M86_PREVIEW_WINDOW_MAX_BUFFERS;
    }

    const int format = window->format != 0 ? window->format : HAL_PIXEL_FORMAT_YCrCb_420_SP;
    const uint64_t usage = static_cast<uint64_t>(window->usage) |
                           GRALLOC_USAGE_HW_CAMERA_WRITE | GRALLOC_USAGE_SW_READ_OFTEN;
    if (window->allocated_count == count &&
        window->allocated_width == window->width &&
        window->allocated_height == window->height &&
        window->allocated_format == format &&
        window->allocated_usage == usage &&
        window->buffers[0].handle != nullptr) {
        return 0;
    }

    m86_preview_window_free_buffers_locked(window);
    android::GraphicBufferAllocator &allocator = android::GraphicBufferAllocator::get();

    for (int i = 0; i < count; i++) {
        buffer_handle_t handle = nullptr;
        uint32_t stride = 0;
        status_t err = allocator.allocate(static_cast<uint32_t>(window->width),
                                          static_cast<uint32_t>(window->height),
                                          static_cast<android::PixelFormat>(format), 1, usage,
                                          &handle, &stride, "m86-preview-window");
        if (err != OK || handle == nullptr) {
            ALOGE("%s: gralloc alloc failed %dx%d fmt=0x%x usage=0x%" PRIx64 " err=%d",
                  __FUNCTION__, window->width, window->height, format, usage, err);
            m86_preview_window_free_buffers_locked(window);
            return -ENOMEM;
        }
        window->buffers[i].handle = handle;
        window->buffers[i].stride = static_cast<int>(stride);
        window->buffers[i].busy = false;
    }
    window->allocated_count = count;
    window->allocated_width = window->width;
    window->allocated_height = window->height;
    window->allocated_format = format;
    window->allocated_usage = usage;
    ALOGI("%s: allocated %d preview-window buffers %dx%d fmt=0x%x usage=0x%" PRIx64,
          __FUNCTION__, count, window->width, window->height, format, usage);
    return 0;
}

static int m86_preview_window_dequeue_buffer(struct preview_stream_ops *w,
                                             buffer_handle_t **buffer, int *stride)
{
    m86_preview_window_t *window = reinterpret_cast<m86_preview_window_t *>(w);
    if (window == nullptr || buffer == nullptr || stride == nullptr) {
        return -EINVAL;
    }

    pthread_mutex_lock(&window->lock);
    if (window->buffers[0].handle == nullptr) {
        const int err = m86_preview_window_alloc_buffers_locked(window);
        if (err != 0) {
            pthread_mutex_unlock(&window->lock);
            return err;
        }
    }

    for (int i = 0; i < M86_PREVIEW_WINDOW_MAX_BUFFERS; i++) {
        if (window->buffers[i].handle != nullptr && !window->buffers[i].busy) {
            window->buffers[i].busy = true;
            *buffer = &window->buffers[i].handle;
            *stride = window->buffers[i].stride;
            pthread_mutex_unlock(&window->lock);
            return 0;
        }
    }
    pthread_mutex_unlock(&window->lock);
    return -ENOMEM;
}

static int m86_preview_window_find_index_locked(const m86_preview_window_t *window,
                                                const buffer_handle_t handle)
{
    for (int i = 0; i < M86_PREVIEW_WINDOW_MAX_BUFFERS; i++) {
        if (window->buffers[i].handle == handle) {
            return i;
        }
    }
    return -1;
}

static int m86_preview_window_enqueue_buffer(struct preview_stream_ops *w,
                                             buffer_handle_t *buffer)
{
    m86_preview_window_t *window = reinterpret_cast<m86_preview_window_t *>(w);
    if (window == nullptr || buffer == nullptr || *buffer == nullptr) {
        return -EINVAL;
    }

    int64_t timestamp = m86_now_ns();
    pthread_mutex_lock(&window->lock);
    const int index = m86_preview_window_find_index_locked(window, *buffer);
    if (index >= 0) {
        timestamp = window->last_timestamp > 0 ? window->last_timestamp : timestamp;
    }
    pthread_mutex_unlock(&window->lock);

    if (index < 0) {
        return -EINVAL;
    }

    m86_preview_window_deliver(window, *buffer, timestamp);

    pthread_mutex_lock(&window->lock);
    if (index < M86_PREVIEW_WINDOW_MAX_BUFFERS) {
        window->buffers[index].busy = false;
    }
    pthread_mutex_unlock(&window->lock);
    return 0;
}

static int m86_preview_window_cancel_buffer(struct preview_stream_ops *w,
                                            buffer_handle_t *buffer)
{
    m86_preview_window_t *window = reinterpret_cast<m86_preview_window_t *>(w);
    if (window == nullptr || buffer == nullptr || *buffer == nullptr) {
        return -EINVAL;
    }
    pthread_mutex_lock(&window->lock);
    const int index = m86_preview_window_find_index_locked(window, *buffer);
    if (index >= 0) {
        window->buffers[index].busy = false;
    }
    pthread_mutex_unlock(&window->lock);
    return index >= 0 ? 0 : -EINVAL;
}

static int m86_preview_window_set_buffer_count(struct preview_stream_ops *w, int count)
{
    m86_preview_window_t *window = reinterpret_cast<m86_preview_window_t *>(w);
    if (window == nullptr) {
        return -EINVAL;
    }
    pthread_mutex_lock(&window->lock);
    int err = 0;
    if (count <= 0) {
        err = -EINVAL;
    } else {
        window->buffer_count = count;
    }
    if (err == 0 && window->width > 0 && window->height > 0) {
        err = m86_preview_window_alloc_buffers_locked(window);
    }
    pthread_mutex_unlock(&window->lock);
    return err;
}

static int m86_preview_window_set_buffers_geometry(struct preview_stream_ops *w,
                                                   int width, int height, int format)
{
    m86_preview_window_t *window = reinterpret_cast<m86_preview_window_t *>(w);
    if (window == nullptr) {
        return -EINVAL;
    }
    pthread_mutex_lock(&window->lock);
    int err = 0;
    if (width <= 0 || height <= 0) {
        err = -EINVAL;
    } else {
        window->width = width;
        window->height = height;
        window->format = format;
    }
    if (err == 0 && window->buffer_count > 0) {
        err = m86_preview_window_alloc_buffers_locked(window);
    }
    pthread_mutex_unlock(&window->lock);
    return err;
}

static int m86_preview_window_set_crop(struct preview_stream_ops *w,
                                       int /* left */, int /* top */,
                                       int /* right */, int /* bottom */)
{
    return w != nullptr ? 0 : -EINVAL;
}

static int m86_preview_window_set_usage(struct preview_stream_ops *w, int usage)
{
    m86_preview_window_t *window = reinterpret_cast<m86_preview_window_t *>(w);
    if (window == nullptr) {
        return -EINVAL;
    }
    pthread_mutex_lock(&window->lock);
    window->usage = usage;
    int err = 0;
    if (window->buffer_count > 0 && window->width > 0 && window->height > 0) {
        err = m86_preview_window_alloc_buffers_locked(window);
    }
    pthread_mutex_unlock(&window->lock);
    return err;
}

static int m86_preview_window_set_swap_interval(struct preview_stream_ops *w,
                                                int /* interval */)
{
    return w != nullptr ? 0 : -EINVAL;
}

static int m86_preview_window_get_min_undequeued_buffer_count(
        const struct preview_stream_ops *w, int *count)
{
    if (w == nullptr || count == nullptr) {
        return -EINVAL;
    }
    *count = 2;
    return 0;
}

static int m86_preview_window_lock_buffer(struct preview_stream_ops *w,
                                          buffer_handle_t * /* buffer */)
{
    return w != nullptr ? 0 : -EINVAL;
}

static int m86_preview_window_set_timestamp(struct preview_stream_ops *w, int64_t timestamp)
{
    m86_preview_window_t *window = reinterpret_cast<m86_preview_window_t *>(w);
    if (window == nullptr) {
        return -EINVAL;
    }
    pthread_mutex_lock(&window->lock);
    window->last_timestamp = timestamp;
    pthread_mutex_unlock(&window->lock);
    return 0;
}

static void m86_preview_window_deliver(m86_preview_window_t *window,
                                       buffer_handle_t handle,
                                       int64_t timestamp_ns)
{
    if (window == nullptr || window->dev == nullptr || handle == nullptr) {
        return;
    }
    m86_camera3_device_t *m86_dev = window->dev;

    m86_pending_stream_request_t pending;
    if (!m86_dequeue_stream_request(m86_dev, &pending, false)) {
        return;
    }

    const gralloc_module_t *gralloc = m86_get_gralloc_module();
    private_handle_t *hnd = private_handle_t::dynamicCast(handle);
    if (gralloc == nullptr || gralloc->lock == nullptr || gralloc->unlock == nullptr ||
        hnd == nullptr) {
        ALOGE("%s: cannot map preview-window buffer gralloc=%p handle=%p", __FUNCTION__,
              gralloc, handle);
        m86_send_stream_result(m86_dev, &pending, false);
        return;
    }

    void *planes[3] = {nullptr, nullptr, nullptr};
    int err = gralloc->lock(gralloc, handle, GRALLOC_USAGE_SW_READ_OFTEN,
                            0, 0, hnd->width, hnd->height, planes);
    if (err != 0 || planes[0] == nullptr) {
        ALOGE("%s: preview-window gralloc lock failed: %d", __FUNCTION__, err);
        m86_send_stream_result(m86_dev, &pending, false);
        return;
    }

    const uint8_t *src_y = static_cast<const uint8_t *>(planes[0]);
    const uint8_t *src_chroma = nullptr;
    const int y_stride = hnd->stride > 0 ? hnd->stride : hnd->width;
    const int y_vstride = hnd->vstride > 0 ? hnd->vstride : hnd->height;
    bool src_is_nv21 = true;

    switch (hnd->format) {
        case HAL_PIXEL_FORMAT_YCrCb_420_SP:
            src_chroma = src_y + static_cast<size_t>(y_stride) * y_vstride;
            break;
        case HAL_PIXEL_FORMAT_EXYNOS_YCrCb_420_SP_M:
        case HAL_PIXEL_FORMAT_EXYNOS_YCrCb_420_SP_M_FULL:
            src_chroma = static_cast<const uint8_t *>(planes[1]);
            break;
        case HAL_PIXEL_FORMAT_EXYNOS_YCbCr_420_SP_M:
        case HAL_PIXEL_FORMAT_EXYNOS_YCbCr_420_SP_M_PRIV:
            src_chroma = static_cast<const uint8_t *>(planes[1]);
            src_is_nv21 = false;
            break;
        case HAL_PIXEL_FORMAT_EXYNOS_YCbCr_420_SPN:
            src_chroma = src_y + static_cast<size_t>(y_stride) * y_vstride + 256;
            src_is_nv21 = false;
            break;
        default:
            src_chroma = src_y + static_cast<size_t>(y_stride) * y_vstride;
            break;
    }

    if (src_chroma != nullptr) {
        m86_copy_preview_to_stream(m86_dev, &pending, src_y, src_chroma,
                                   y_stride, y_stride, src_is_nv21, timestamp_ns);
    } else {
        m86_send_stream_result(m86_dev, &pending, false);
    }

    gralloc->unlock(gralloc, handle);
}

static void m86_preview_window_init(m86_preview_window_t *window, m86_camera3_device_t *dev)
{
    memset(window, 0, sizeof(*window));
    window->ops.dequeue_buffer = m86_preview_window_dequeue_buffer;
    window->ops.enqueue_buffer = m86_preview_window_enqueue_buffer;
    window->ops.cancel_buffer = m86_preview_window_cancel_buffer;
    window->ops.set_buffer_count = m86_preview_window_set_buffer_count;
    window->ops.set_buffers_geometry = m86_preview_window_set_buffers_geometry;
    window->ops.set_crop = m86_preview_window_set_crop;
    window->ops.set_usage = m86_preview_window_set_usage;
    window->ops.set_swap_interval = m86_preview_window_set_swap_interval;
    window->ops.get_min_undequeued_buffer_count =
            m86_preview_window_get_min_undequeued_buffer_count;
    window->ops.lock_buffer = m86_preview_window_lock_buffer;
    window->ops.set_timestamp = m86_preview_window_set_timestamp;
    pthread_mutex_init(&window->lock, nullptr);
    window->dev = dev;
    window->buffer_count = 4;
    window->format = HAL_PIXEL_FORMAT_YCrCb_420_SP;
    window->usage = GRALLOC_USAGE_HW_CAMERA_WRITE | GRALLOC_USAGE_SW_READ_OFTEN;
}

static void m86_preview_window_deinit(m86_preview_window_t *window)
{
    if (window == nullptr) {
        return;
    }
    pthread_mutex_lock(&window->lock);
    m86_preview_window_free_buffers_locked(window);
    pthread_mutex_unlock(&window->lock);
    pthread_mutex_destroy(&window->lock);
}

static void m86_start_recording_if_needed(m86_camera3_device_t *m86_dev)
{
    if (m86_dev->preview_started && m86_dev->configured_video_stream != nullptr &&
        !m86_dev->recording_started) {
        m86_dev->engine->storeMetaDataInBuffers(true);
        const status_t err = m86_dev->engine->startRecording();
        if (err != OK) {
            ALOGE("%s: startRecording failed: %d", __FUNCTION__, err);
            m86_pending_stream_request_t failed;
            while (m86_dequeue_stream_request(m86_dev, &failed, true)) {
                m86_send_stream_result(m86_dev, &failed, false);
            }
        } else {
            m86_dev->recording_started = true;
            ALOGI("%s: recording started", __FUNCTION__);
        }
    }
}

static void *m86_preview_start_worker(void *user)
{
    m86_camera3_device_t *m86_dev = static_cast<m86_camera3_device_t *>(user);
    pthread_mutex_lock(&m86_dev->pending_lock);
    while (m86_dev->pending_count == 0 && m86_dev->video_pending_count == 0 &&
           !m86_dev->stop_preview_start_thread) {
        pthread_cond_wait(&m86_dev->pending_cond, &m86_dev->pending_lock);
    }

    const bool stop = m86_dev->stop_preview_start_thread;
    pthread_mutex_unlock(&m86_dev->pending_lock);
    if (stop) {
        return nullptr;
    }

    pthread_mutex_lock(&m86_dev->window->lock);
    m86_preview_window_free_buffers_locked(m86_dev->window);
    pthread_mutex_unlock(&m86_dev->window->lock);

    status_t err = m86_dev->engine->setPreviewWindow(&m86_dev->window->ops);
    if (err == OK) {
        m86_dev->engine->disableMsgType(CAMERA_MSG_PREVIEW_FRAME);
        err = m86_dev->engine->startPreview();
    }
    if (err != OK) {
        ALOGE("%s: startPreview(buffered) failed: %d", __FUNCTION__, err);
        m86_pending_stream_request_t failed;
        while (m86_dequeue_stream_request(m86_dev, &failed, false)) {
            m86_send_stream_result(m86_dev, &failed, false);
        }
        while (m86_dequeue_stream_request(m86_dev, &failed, true)) {
            m86_send_stream_result(m86_dev, &failed, false);
        }
        m86_pending_jpeg_request_t jpeg;
        while (m86_take_jpeg_request(m86_dev, &jpeg)) {
            m86_send_jpeg_error(m86_dev, &jpeg);
        }
        return nullptr;
    }

    m86_dev->preview_started = true;
    ALOGI("%s: preview started using legacy buffered path", __FUNCTION__);
    m86_start_recording_if_needed(m86_dev);
    m86_start_next_jpeg_capture(m86_dev);
    return nullptr;
}

static int m86_device_initialize(const struct camera3_device *device,
                                 const camera3_callback_ops_t *callback_ops)
{
    m86_camera3_device_t *m86_dev =
            reinterpret_cast<m86_camera3_device_t *>(const_cast<camera3_device *>(device));
    m86_dev->callback_ops = callback_ops;
    return 0;
}

static int m86_device_configure_streams(const struct camera3_device *device,
                                        camera3_stream_configuration_t *stream_list)
{
    m86_camera3_device_t *m86_dev =
            reinterpret_cast<m86_camera3_device_t *>(const_cast<camera3_device *>(device));

    if (stream_list == nullptr || stream_list->num_streams == 0) {
        return -EINVAL;
    }
    if (m86_dev->preview_start_thread_joinable || m86_dev->preview_started ||
        m86_dev->recording_started) {
        m86_device_flush(device);
    }

    camera3_stream_t *preview = nullptr;
    camera3_stream_t *video = nullptr;
    camera3_stream_t *jpeg = nullptr;
    for (uint32_t i = 0; i < stream_list->num_streams; i++) {
        camera3_stream_t *stream = stream_list->streams[i];
        if (stream == nullptr) {
            return -EINVAL;
        }
        if (stream->stream_type != CAMERA3_STREAM_OUTPUT) {
            return -EINVAL;
        }
        if (stream->format == HAL_PIXEL_FORMAT_IMPLEMENTATION_DEFINED ||
            stream->format == HAL_PIXEL_FORMAT_YCbCr_420_888) {
            stream->usage |= GRALLOC_USAGE_SW_WRITE_OFTEN |
                             GRALLOC_USAGE_HW_CAMERA_WRITE;
            if ((stream->usage & GRALLOC_USAGE_HW_VIDEO_ENCODER) != 0) {
                if (video != nullptr) {
                    ALOGE("%s: more than one video stream", __FUNCTION__);
                    return -EINVAL;
                }
                video = stream;
                stream->max_buffers = 8;
            } else {
                if (preview != nullptr) {
                    ALOGE("%s: more than one preview stream", __FUNCTION__);
                    return -EINVAL;
                }
                preview = stream;
                stream->max_buffers = 4;
            }
        } else if (stream->format == HAL_PIXEL_FORMAT_BLOB) {
            jpeg = stream;
            stream->max_buffers = 1;
        } else {
            ALOGE("%s: unsupported output format 0x%x", __FUNCTION__, stream->format);
            return -EINVAL;
        }
    }

    if (preview == nullptr) {
        ALOGE("%s: no preview stream in configuration", __FUNCTION__);
        return -EINVAL;
    }

    m86_dev->configured_preview_stream = preview;
    m86_dev->configured_video_stream = video;
    m86_dev->configured_jpeg_stream = jpeg;

    if (m86_dev->engine == nullptr) {
        return -ENODEV;
    }

    CameraParameters params = m86_dev->engine->getParameters();
    params.setPreviewSize(static_cast<int>(preview->width), static_cast<int>(preview->height));
    params.setPreviewFormat(CameraParameters::PIXEL_FORMAT_YUV420SP);
    if (video != nullptr) {
        params.setVideoSize(static_cast<int>(video->width), static_cast<int>(video->height));
        /*
         * The published 7420 video LUT does not describe PRO5's IMX230 path:
         * enabling recording-hint switches 3AA to a route that never returns
         * an SCP frame and eventually overflows firmware.  Keep the verified
         * preview route and feed its frames through the independent recording
         * CSC buffers instead.  startRecording() still supplies timestamped
         * HAL1 video callbacks and applies the recording AF/flash hints.
         */
        params.set(CameraParameters::KEY_RECORDING_HINT, CameraParameters::FALSE);
    } else {
        params.set(CameraParameters::KEY_RECORDING_HINT, CameraParameters::FALSE);
    }
    if (m86_dev->camera_id == 1 &&
        preview->width * 9 == preview->height * 16) {
        params.setPictureSize(2560, 1440);
        params.setPictureFormat(CameraParameters::PIXEL_FORMAT_JPEG);
    } else if (jpeg != nullptr) {
        params.setPictureSize(static_cast<int>(jpeg->width), static_cast<int>(jpeg->height));
        params.setPictureFormat(CameraParameters::PIXEL_FORMAT_JPEG);
    }
    status_t err = m86_dev->engine->setParameters(params);
    if (err != OK) {
        ALOGE("%s: setParameters failed: %d", __FUNCTION__, err);
        return err;
    }

    if (m86_dev->window == nullptr) {
        ALOGE("%s: preview window shim missing", __FUNCTION__);
        return -ENODEV;
    }

    m86_dev->engine->setCallbacks(m86_notify_cb, m86_data_cb, m86_data_timestamp_cb,
                                  m86_request_memory, m86_dev);
    m86_dev->engine->disableMsgType(CAMERA_MSG_PREVIEW_FRAME);
    m86_dev->engine->enableMsgType(CAMERA_MSG_COMPRESSED_IMAGE);
    m86_dev->engine->enableMsgType(CAMERA_MSG_FOCUS);
    m86_dev->engine->enableMsgType(CAMERA_MSG_FOCUS_MOVE);
    if (video != nullptr) {
        m86_dev->engine->enableMsgType(CAMERA_MSG_VIDEO_FRAME);
    } else {
        m86_dev->engine->disableMsgType(CAMERA_MSG_VIDEO_FRAME);
    }
    pthread_mutex_lock(&m86_dev->pending_lock);
    m86_dev->stop_preview_start_thread = false;
    pthread_mutex_unlock(&m86_dev->pending_lock);
    const int thread_err = pthread_create(&m86_dev->preview_start_thread, nullptr,
                                          m86_preview_start_worker, m86_dev);
    if (thread_err != 0) {
        ALOGE("%s: could not create preview start worker: %d", __FUNCTION__, thread_err);
        return -thread_err;
    }
    m86_dev->preview_start_thread_joinable = true;
    ALOGI("%s: configured preview %ux%u video=%s jpeg=%s", __FUNCTION__, preview->width,
          preview->height, video != nullptr ? "yes" : "no",
          jpeg != nullptr ? "yes" : "no");
    return 0;
}

static const camera_metadata_t *m86_device_construct_default_request_settings(
        const struct camera3_device *device, int type)
{
    m86_camera3_device_t *m86_dev =
            reinterpret_cast<m86_camera3_device_t *>(const_cast<camera3_device *>(device));

    if (type < CAMERA3_TEMPLATE_PREVIEW || type > CAMERA3_TEMPLATE_MANUAL) {
        return nullptr;
    }

    CameraMetadata *request = new CameraMetadata();
    if (request == nullptr) {
        return nullptr;
    }

    const uint8_t control_mode = ANDROID_CONTROL_MODE_AUTO;
    const uint8_t af_mode = static_cast<uint8_t>(
        (m86_dev->camera_id == 1) ? ANDROID_CONTROL_AF_MODE_OFF
        : (type == CAMERA3_TEMPLATE_VIDEO_RECORD ||
           type == CAMERA3_TEMPLATE_VIDEO_SNAPSHOT)
                ? ANDROID_CONTROL_AF_MODE_CONTINUOUS_VIDEO
                : ANDROID_CONTROL_AF_MODE_CONTINUOUS_PICTURE);
    const uint8_t ae_mode = ANDROID_CONTROL_AE_MODE_ON;
    const uint8_t awb_mode = ANDROID_CONTROL_AWB_MODE_AUTO;
    const uint8_t ae_antibanding_mode = ANDROID_CONTROL_AE_ANTIBANDING_MODE_AUTO;
    const uint8_t ae_precapture_trigger = ANDROID_CONTROL_AE_PRECAPTURE_TRIGGER_IDLE;
    const uint8_t af_trigger = ANDROID_CONTROL_AF_TRIGGER_IDLE;
    const uint8_t ae_lock = ANDROID_CONTROL_AE_LOCK_OFF;
    const uint8_t awb_lock = ANDROID_CONTROL_AWB_LOCK_OFF;
    const uint8_t capture_intent = static_cast<uint8_t>(type);
    const uint8_t effect_mode = ANDROID_CONTROL_EFFECT_MODE_OFF;
    const uint8_t scene_mode = ANDROID_CONTROL_SCENE_MODE_DISABLED;
    const uint8_t video_stabilization_mode = ANDROID_CONTROL_VIDEO_STABILIZATION_MODE_OFF;
    const uint8_t flash_mode = ANDROID_FLASH_MODE_OFF;
    const uint8_t face_detect_mode = ANDROID_STATISTICS_FACE_DETECT_MODE_OFF;
    const uint8_t optical_stabilization_mode = ANDROID_LENS_OPTICAL_STABILIZATION_MODE_OFF;
    const uint8_t jpeg_quality = 90;
    const uint8_t jpeg_thumbnail_quality = 90;
    const int32_t ae_exposure_compensation = 0;
    const int32_t ae_target_fps_range[2] = {15, 30};
    const int32_t jpeg_orientation = 0;
    const int32_t jpeg_thumbnail_size[2] = {320, 240};
    const int32_t crop_region[4] = {0, 0,
                                    (m86_dev->camera_id == 1) ? 2592 : 5344,
                                    (m86_dev->camera_id == 1) ? 1944 : 4016};
    const float focal_length = (m86_dev->camera_id == 1) ? 3.50f : 4.73f;

    request->update(ANDROID_CONTROL_MODE, &control_mode, 1);
    request->update(ANDROID_CONTROL_AF_MODE, &af_mode, 1);
    request->update(ANDROID_CONTROL_AF_TRIGGER, &af_trigger, 1);
    request->update(ANDROID_CONTROL_AE_MODE, &ae_mode, 1);
    request->update(ANDROID_CONTROL_AE_ANTIBANDING_MODE, &ae_antibanding_mode, 1);
    request->update(ANDROID_CONTROL_AE_EXPOSURE_COMPENSATION, &ae_exposure_compensation, 1);
    request->update(ANDROID_CONTROL_AE_LOCK, &ae_lock, 1);
    request->update(ANDROID_CONTROL_AE_PRECAPTURE_TRIGGER, &ae_precapture_trigger, 1);
    request->update(ANDROID_CONTROL_AE_TARGET_FPS_RANGE, ae_target_fps_range, 2);
    request->update(ANDROID_CONTROL_AWB_MODE, &awb_mode, 1);
    request->update(ANDROID_CONTROL_AWB_LOCK, &awb_lock, 1);
    request->update(ANDROID_CONTROL_CAPTURE_INTENT, &capture_intent, 1);
    request->update(ANDROID_CONTROL_EFFECT_MODE, &effect_mode, 1);
    request->update(ANDROID_CONTROL_SCENE_MODE, &scene_mode, 1);
    request->update(ANDROID_CONTROL_VIDEO_STABILIZATION_MODE, &video_stabilization_mode, 1);
    request->update(ANDROID_FLASH_MODE, &flash_mode, 1);
    request->update(ANDROID_JPEG_ORIENTATION, &jpeg_orientation, 1);
    request->update(ANDROID_JPEG_QUALITY, &jpeg_quality, 1);
    request->update(ANDROID_JPEG_THUMBNAIL_QUALITY, &jpeg_thumbnail_quality, 1);
    request->update(ANDROID_JPEG_THUMBNAIL_SIZE, jpeg_thumbnail_size, 2);
    request->update(ANDROID_LENS_OPTICAL_STABILIZATION_MODE,
                    &optical_stabilization_mode, 1);
    request->update(ANDROID_SCALER_CROP_REGION, crop_region, 4);
    request->update(ANDROID_STATISTICS_FACE_DETECT_MODE, &face_detect_mode, 1);
    request->update(ANDROID_LENS_FOCAL_LENGTH, &focal_length, 1);
    request->sort();

    camera_metadata_t *released = request->release();
    delete request;
    return released;
}

static int32_t m86_clamp_i32(int32_t value, int32_t minimum, int32_t maximum)
{
    if (value < minimum) {
        return minimum;
    }
    if (value > maximum) {
        return maximum;
    }
    return value;
}

static void m86_format_metering_region(const camera_metadata_ro_entry_t &entry,
                                       int32_t active_width, int32_t active_height,
                                       char *area, size_t area_size)
{
    if (entry.count < 5 || active_width <= 0 || active_height <= 0 ||
        entry.data.i32[4] <= 0 || entry.data.i32[2] <= entry.data.i32[0] ||
        entry.data.i32[3] <= entry.data.i32[1]) {
        snprintf(area, area_size, "(0,0,0,0,0)");
        return;
    }
    const int32_t left = m86_clamp_i32(
            entry.data.i32[0] * 2000 / active_width - 1000, -1000, 1000);
    const int32_t top = m86_clamp_i32(
            entry.data.i32[1] * 2000 / active_height - 1000, -1000, 1000);
    const int32_t right = m86_clamp_i32(
            entry.data.i32[2] * 2000 / active_width - 1000, -1000, 1000);
    const int32_t bottom = m86_clamp_i32(
            entry.data.i32[3] * 2000 / active_height - 1000, -1000, 1000);
    const int32_t weight = m86_clamp_i32(entry.data.i32[4], 1, 1000);
    snprintf(area, area_size, "(%d,%d,%d,%d,%d)", left, top, right, bottom, weight);
}

static bool m86_set_parameter_if_changed(CameraParameters *params, const char *key,
                                         const char *value)
{
    const char *current = params->get(key);
    if (current != nullptr && value != nullptr && strcmp(current, value) == 0) {
        return false;
    }
    params->set(key, value);
    return true;
}

static bool m86_set_parameter_if_changed(CameraParameters *params, const char *key,
                                         int value)
{
    char desired[24];
    snprintf(desired, sizeof(desired), "%d", value);
    return m86_set_parameter_if_changed(params, key, desired);
}

static int m86_find_zoom_index(const char *ratios, int max_zoom, int desired_ratio,
                               int *actual_ratio)
{
    int best_index = -1;
    int best_ratio = 100;
    int best_difference = 0x7fffffff;
    const char *cursor = ratios;

    for (int index = 0; cursor != nullptr && *cursor != '\0' && index <= max_zoom;
         index++) {
        char *end = nullptr;
        const long parsed = strtol(cursor, &end, 10);
        if (end == cursor) {
            break;
        }
        if (parsed >= 100 && parsed <= 800) {
            const int ratio = static_cast<int>(parsed);
            const int difference = ratio > desired_ratio ? ratio - desired_ratio
                                                         : desired_ratio - ratio;
            if (difference < best_difference) {
                best_difference = difference;
                best_index = index;
                best_ratio = ratio;
            }
        }
        cursor = *end == ',' ? end + 1 : end;
    }

    if (best_index < 0) {
        best_index = max_zoom > 0
                ? m86_clamp_i32((desired_ratio - 100) * max_zoom / 300, 0, max_zoom)
                : 0;
        best_ratio = max_zoom > 0 ? 100 + best_index * 300 / max_zoom : 100;
    }
    if (actual_ratio != nullptr) {
        *actual_ratio = best_ratio;
    }
    return best_index;
}

static void m86_apply_request_controls(m86_camera3_device_t *m86_dev,
                                       const camera_metadata_t *settings)
{
    if (m86_dev == nullptr || m86_dev->engine == nullptr || settings == nullptr) {
        return;
    }

    CameraParameters params = m86_dev->engine->getParameters();
    camera_metadata_ro_entry_t entry;
    bool parameters_changed = false;
    bool start_af = false;
    bool cancel_af = false;
    const int32_t active_width = m86_dev->camera_id == 1 ? 2592 : 5344;
    const int32_t active_height = m86_dev->camera_id == 1 ? 1944 : 4016;

    if (find_camera_metadata_ro_entry(settings, ANDROID_CONTROL_AF_MODE, &entry) == 0 &&
        entry.count > 0) {
        uint8_t af_mode = entry.data.u8[0];
        const char *legacy_mode = CameraParameters::FOCUS_MODE_FIXED;
        if (m86_dev->camera_id == 0) {
            switch (af_mode) {
                case ANDROID_CONTROL_AF_MODE_AUTO:
                    legacy_mode = CameraParameters::FOCUS_MODE_AUTO;
                    break;
                case ANDROID_CONTROL_AF_MODE_CONTINUOUS_VIDEO:
                    legacy_mode = CameraParameters::FOCUS_MODE_CONTINUOUS_VIDEO;
                    break;
                case ANDROID_CONTROL_AF_MODE_CONTINUOUS_PICTURE:
                    legacy_mode = CameraParameters::FOCUS_MODE_CONTINUOUS_PICTURE;
                    break;
                default:
                    af_mode = ANDROID_CONTROL_AF_MODE_AUTO;
                    legacy_mode = CameraParameters::FOCUS_MODE_AUTO;
                    break;
            }
        } else {
            af_mode = ANDROID_CONTROL_AF_MODE_OFF;
        }
        pthread_mutex_lock(&m86_dev->pending_lock);
        const bool mode_changed = m86_dev->af_mode != af_mode;
        if (mode_changed) {
            m86_dev->af_mode = af_mode;
            m86_dev->af_state = m86_dev->camera_id == 1
                    ? ANDROID_CONTROL_AF_STATE_INACTIVE
                    : (af_mode == ANDROID_CONTROL_AF_MODE_AUTO
                               ? ANDROID_CONTROL_AF_STATE_INACTIVE
                               : ANDROID_CONTROL_AF_STATE_PASSIVE_SCAN);
        }
        pthread_mutex_unlock(&m86_dev->pending_lock);
        parameters_changed |= m86_set_parameter_if_changed(
                &params, CameraParameters::KEY_FOCUS_MODE, legacy_mode);
    }

    if (m86_dev->camera_id == 0 &&
        find_camera_metadata_ro_entry(settings, ANDROID_CONTROL_AF_REGIONS, &entry) == 0) {
        char area[96];
        m86_format_metering_region(entry, active_width, active_height, area, sizeof(area));
        parameters_changed |= m86_set_parameter_if_changed(
                &params, CameraParameters::KEY_FOCUS_AREAS, area);
    }
    if (find_camera_metadata_ro_entry(settings, ANDROID_CONTROL_AE_REGIONS, &entry) == 0) {
        char area[96];
        m86_format_metering_region(entry, active_width, active_height, area, sizeof(area));
        parameters_changed |= m86_set_parameter_if_changed(
                &params, CameraParameters::KEY_METERING_AREAS, area);
    }

    if (find_camera_metadata_ro_entry(settings,
                                      ANDROID_CONTROL_AE_EXPOSURE_COMPENSATION,
                                      &entry) == 0 && entry.count > 0) {
        const int32_t compensation = m86_clamp_i32(entry.data.i32[0], -4, 4);
        parameters_changed |= m86_set_parameter_if_changed(
                &params, CameraParameters::KEY_EXPOSURE_COMPENSATION, compensation);
        pthread_mutex_lock(&m86_dev->pending_lock);
        m86_dev->exposure_compensation = compensation;
        pthread_mutex_unlock(&m86_dev->pending_lock);
    }

    if (find_camera_metadata_ro_entry(settings, ANDROID_CONTROL_AE_ANTIBANDING_MODE,
                                      &entry) == 0 && entry.count > 0) {
        const char *mode = CameraParameters::ANTIBANDING_AUTO;
        switch (entry.data.u8[0]) {
            case ANDROID_CONTROL_AE_ANTIBANDING_MODE_OFF:
                mode = CameraParameters::ANTIBANDING_OFF;
                break;
            case ANDROID_CONTROL_AE_ANTIBANDING_MODE_50HZ:
                mode = CameraParameters::ANTIBANDING_50HZ;
                break;
            case ANDROID_CONTROL_AE_ANTIBANDING_MODE_60HZ:
                mode = CameraParameters::ANTIBANDING_60HZ;
                break;
            default:
                break;
        }
        parameters_changed |= m86_set_parameter_if_changed(
                &params, CameraParameters::KEY_ANTIBANDING, mode);
    }

    uint8_t ae_mode = ANDROID_CONTROL_AE_MODE_ON;
    uint8_t flash_mode = ANDROID_FLASH_MODE_OFF;
    if (find_camera_metadata_ro_entry(settings, ANDROID_CONTROL_AE_MODE, &entry) == 0 &&
        entry.count > 0) {
        ae_mode = entry.data.u8[0];
    }
    if (find_camera_metadata_ro_entry(settings, ANDROID_FLASH_MODE, &entry) == 0 &&
        entry.count > 0) {
        flash_mode = entry.data.u8[0];
    }
    const char *legacy_flash = CameraParameters::FLASH_MODE_OFF;
    uint8_t flash_state = m86_dev->camera_id == 1 ? ANDROID_FLASH_STATE_UNAVAILABLE
                                                  : ANDROID_FLASH_STATE_READY;
    if (m86_dev->camera_id == 0) {
        if (flash_mode == ANDROID_FLASH_MODE_TORCH) {
            legacy_flash = CameraParameters::FLASH_MODE_TORCH;
            flash_state = ANDROID_FLASH_STATE_FIRED;
        } else if (flash_mode == ANDROID_FLASH_MODE_SINGLE ||
                   ae_mode == ANDROID_CONTROL_AE_MODE_ON_ALWAYS_FLASH) {
            legacy_flash = CameraParameters::FLASH_MODE_ON;
        } else if (ae_mode == ANDROID_CONTROL_AE_MODE_ON_AUTO_FLASH) {
            legacy_flash = CameraParameters::FLASH_MODE_AUTO;
        }
    } else {
        ae_mode = ANDROID_CONTROL_AE_MODE_ON;
        flash_mode = ANDROID_FLASH_MODE_OFF;
    }
    parameters_changed |= m86_set_parameter_if_changed(
            &params, CameraParameters::KEY_FLASH_MODE, legacy_flash);
    pthread_mutex_lock(&m86_dev->pending_lock);
    m86_dev->ae_mode = ae_mode;
    m86_dev->flash_mode = flash_mode;
    m86_dev->flash_state = flash_state;
    pthread_mutex_unlock(&m86_dev->pending_lock);

    if (find_camera_metadata_ro_entry(settings, ANDROID_CONTROL_AE_PRECAPTURE_TRIGGER,
                                      &entry) == 0 && entry.count > 0) {
        pthread_mutex_lock(&m86_dev->pending_lock);
        if (entry.data.u8[0] == ANDROID_CONTROL_AE_PRECAPTURE_TRIGGER_START) {
            m86_dev->ae_state = ANDROID_CONTROL_AE_STATE_PRECAPTURE;
        } else if (entry.data.u8[0] == ANDROID_CONTROL_AE_PRECAPTURE_TRIGGER_CANCEL) {
            m86_dev->ae_state = ANDROID_CONTROL_AE_STATE_CONVERGED;
        }
        pthread_mutex_unlock(&m86_dev->pending_lock);
    }

    if (find_camera_metadata_ro_entry(settings, ANDROID_SCALER_CROP_REGION, &entry) == 0 &&
        entry.count >= 4) {
        const int32_t requested_width = m86_clamp_i32(
                entry.data.i32[2], active_width / 4, active_width);
        const int32_t requested_height = m86_clamp_i32(
                entry.data.i32[3], active_height / 4, active_height);
        const int width_ratio = active_width * 100 / requested_width;
        const int height_ratio = active_height * 100 / requested_height;
        const int desired_ratio = m86_clamp_i32(
                width_ratio > height_ratio ? width_ratio : height_ratio, 100, 400);
        const int max_zoom = params.getInt(CameraParameters::KEY_MAX_ZOOM);
        int actual_ratio = 100;
        const int zoom = m86_find_zoom_index(
                params.get(CameraParameters::KEY_ZOOM_RATIOS), max_zoom,
                desired_ratio, &actual_ratio);
        const bool zoom_changed = m86_set_parameter_if_changed(
                &params, CameraParameters::KEY_ZOOM, zoom);
        parameters_changed |= zoom_changed;
        const int32_t crop_width = active_width * 100 / actual_ratio;
        const int32_t crop_height = active_height * 100 / actual_ratio;
        pthread_mutex_lock(&m86_dev->pending_lock);
        // Exynos7420 exposes center-only cropping.  Report the crop that the
        // selected HAL1 zoom ratio actually applies, not an unsupported
        // off-center rectangle from the request.
        m86_dev->crop_region[0] = (active_width - crop_width) / 2;
        m86_dev->crop_region[1] = (active_height - crop_height) / 2;
        m86_dev->crop_region[2] = crop_width;
        m86_dev->crop_region[3] = crop_height;
        pthread_mutex_unlock(&m86_dev->pending_lock);
        if (zoom_changed) {
            ALOGI("%s: zoom changed req=(%dx%d) desired=%d actual=%d index=%d",
                  __FUNCTION__, requested_width, requested_height,
                  desired_ratio, actual_ratio, zoom);
        }
    }

    bool controls_applied = true;
    if (parameters_changed) {
        const status_t err = m86_dev->engine->setParameters(params);
        if (err != OK) {
            ALOGW("%s: legacy control update failed: %d", __FUNCTION__, err);
            controls_applied = false;
        }
    }

    if (m86_dev->camera_id == 0 &&
        find_camera_metadata_ro_entry(settings, ANDROID_CONTROL_AF_TRIGGER, &entry) == 0 &&
        entry.count > 0) {
        start_af = entry.data.u8[0] == ANDROID_CONTROL_AF_TRIGGER_START;
        cancel_af = entry.data.u8[0] == ANDROID_CONTROL_AF_TRIGGER_CANCEL;
    }
    if (!controls_applied) {
        return;
    }
    if (cancel_af) {
        m86_dev->engine->cancelAutoFocus();
        pthread_mutex_lock(&m86_dev->pending_lock);
        m86_dev->af_state = m86_dev->af_mode == ANDROID_CONTROL_AF_MODE_AUTO
                ? ANDROID_CONTROL_AF_STATE_INACTIVE
                : ANDROID_CONTROL_AF_STATE_PASSIVE_SCAN;
        pthread_mutex_unlock(&m86_dev->pending_lock);
    } else if (start_af) {
        pthread_mutex_lock(&m86_dev->pending_lock);
        m86_dev->af_state = ANDROID_CONTROL_AF_STATE_ACTIVE_SCAN;
        pthread_mutex_unlock(&m86_dev->pending_lock);
        const status_t err = m86_dev->engine->autoFocus();
        if (err != OK) {
            pthread_mutex_lock(&m86_dev->pending_lock);
            m86_dev->af_state = ANDROID_CONTROL_AF_STATE_NOT_FOCUSED_LOCKED;
            pthread_mutex_unlock(&m86_dev->pending_lock);
        }
    }
}

static void m86_read_jpeg_request_settings(m86_pending_jpeg_request_t *jpeg,
                                           const camera_metadata_t *settings)
{
    if (jpeg == nullptr) {
        return;
    }

    jpeg->jpeg_quality = 90;
    jpeg->thumbnail_quality = 90;
    jpeg->thumbnail_width = 320;
    jpeg->thumbnail_height = 240;
    if (settings == nullptr) {
        return;
    }

    camera_metadata_ro_entry_t entry;
    if (find_camera_metadata_ro_entry(settings, ANDROID_JPEG_QUALITY, &entry) == 0 &&
        entry.count > 0) {
        jpeg->jpeg_quality = static_cast<int>(entry.data.u8[0]);
    }
    if (find_camera_metadata_ro_entry(settings, ANDROID_JPEG_ORIENTATION, &entry) == 0 &&
        entry.count > 0) {
        jpeg->jpeg_orientation = entry.data.i32[0];
    }
    if (find_camera_metadata_ro_entry(settings, ANDROID_JPEG_THUMBNAIL_QUALITY, &entry) == 0 &&
        entry.count > 0) {
        jpeg->thumbnail_quality = static_cast<int>(entry.data.u8[0]);
    }
    if (find_camera_metadata_ro_entry(settings, ANDROID_JPEG_THUMBNAIL_SIZE, &entry) == 0 &&
        entry.count >= 2) {
        jpeg->thumbnail_width = entry.data.i32[0];
        jpeg->thumbnail_height = entry.data.i32[1];
    }
    if (find_camera_metadata_ro_entry(settings, ANDROID_JPEG_GPS_COORDINATES, &entry) == 0 &&
        entry.count >= 3) {
        jpeg->has_gps = true;
        memcpy(jpeg->gps_coordinates, entry.data.d, sizeof(jpeg->gps_coordinates));
    }
    if (find_camera_metadata_ro_entry(settings, ANDROID_JPEG_GPS_TIMESTAMP, &entry) == 0 &&
        entry.count > 0) {
        jpeg->gps_timestamp = entry.data.i64[0];
    }
    if (find_camera_metadata_ro_entry(settings, ANDROID_JPEG_GPS_PROCESSING_METHOD,
                                      &entry) == 0 && entry.count > 0) {
        const size_t length = entry.count < sizeof(jpeg->gps_processing_method) - 1
                ? entry.count : sizeof(jpeg->gps_processing_method) - 1;
        memcpy(jpeg->gps_processing_method, entry.data.u8, length);
        jpeg->gps_processing_method[length] = '\0';
    }
}

static bool m86_apply_jpeg_request_settings(
        m86_camera3_device_t *m86_dev, const m86_pending_jpeg_request_t *jpeg)
{
    if (m86_dev == nullptr || m86_dev->engine == nullptr || jpeg == nullptr) {
        return false;
    }

    CameraParameters params = m86_dev->engine->getParameters();
    params.set(CameraParameters::KEY_JPEG_QUALITY, jpeg->jpeg_quality);
    params.set(CameraParameters::KEY_ROTATION, jpeg->jpeg_orientation);
    params.set(CameraParameters::KEY_JPEG_THUMBNAIL_QUALITY, jpeg->thumbnail_quality);
    params.set(CameraParameters::KEY_JPEG_THUMBNAIL_WIDTH, jpeg->thumbnail_width);
    params.set(CameraParameters::KEY_JPEG_THUMBNAIL_HEIGHT, jpeg->thumbnail_height);

    params.remove(CameraParameters::KEY_GPS_LATITUDE);
    params.remove(CameraParameters::KEY_GPS_LONGITUDE);
    params.remove(CameraParameters::KEY_GPS_ALTITUDE);
    params.remove(CameraParameters::KEY_GPS_TIMESTAMP);
    params.remove(CameraParameters::KEY_GPS_PROCESSING_METHOD);
    if (jpeg->has_gps) {
        char value[48];
        snprintf(value, sizeof(value), "%.8f", jpeg->gps_coordinates[0]);
        params.set(CameraParameters::KEY_GPS_LATITUDE, value);
        snprintf(value, sizeof(value), "%.8f", jpeg->gps_coordinates[1]);
        params.set(CameraParameters::KEY_GPS_LONGITUDE, value);
        snprintf(value, sizeof(value), "%.3f", jpeg->gps_coordinates[2]);
        params.set(CameraParameters::KEY_GPS_ALTITUDE, value);
        snprintf(value, sizeof(value), "%" PRId64, jpeg->gps_timestamp);
        params.set(CameraParameters::KEY_GPS_TIMESTAMP, value);
        if (jpeg->gps_processing_method[0] != '\0') {
            params.set(CameraParameters::KEY_GPS_PROCESSING_METHOD,
                       jpeg->gps_processing_method);
        }
    }

    status_t err = m86_dev->engine->setParameters(params);
    if (err != OK) {
        ALOGW("%s: setParameters for JPEG request failed: %d", __FUNCTION__, err);
        return false;
    }
    return true;
}

static void m86_start_next_jpeg_capture(m86_camera3_device_t *m86_dev)
{
    if (m86_dev == nullptr || m86_dev->engine == nullptr ||
        !m86_dev->preview_started) {
        return;
    }

    m86_pending_jpeg_request_t jpeg;
    while (m86_begin_next_jpeg_request(m86_dev, &jpeg)) {
        pthread_mutex_lock(&m86_dev->pending_lock);
        if (m86_dev->camera_id == 0 &&
            (m86_dev->flash_mode == ANDROID_FLASH_MODE_SINGLE ||
             m86_dev->ae_mode == ANDROID_CONTROL_AE_MODE_ON_ALWAYS_FLASH)) {
            m86_dev->flash_state = ANDROID_FLASH_STATE_FIRED;
        }
        pthread_mutex_unlock(&m86_dev->pending_lock);
        status_t err = m86_apply_jpeg_request_settings(m86_dev, &jpeg)
                ? m86_dev->engine->takePicture() : -EINVAL;
        if (err == OK) {
            ALOGI("%s: JPEG capture started for frame %u", __FUNCTION__,
                  jpeg.frame_number);
            return;
        }

        ALOGE("%s: takePicture failed for frame %u: %d", __FUNCTION__,
              jpeg.frame_number, err);
        m86_pending_jpeg_request_t failed;
        if (!m86_take_jpeg_request(m86_dev, &failed)) {
            return;
        }
        m86_send_jpeg_error(m86_dev, &failed);
    }
}

static int m86_device_process_capture_request(const struct camera3_device *device,
                                              camera3_capture_request_t *request)
{
    m86_camera3_device_t *m86_dev =
            reinterpret_cast<m86_camera3_device_t *>(const_cast<camera3_device *>(device));

    if (request == nullptr || m86_dev->callback_ops == nullptr || m86_dev->engine == nullptr) {
        return -EINVAL;
    }

    m86_pending_preview_request_t pending;
    memset(&pending, 0, sizeof(pending));
    pending.frame_number = request->frame_number;
    pending.timestamp_ns = m86_now_ns();
    pending.preview_output_index = -1;
    pending.video_output_index = -1;
    pending.jpeg_output_index = -1;

    if (request->input_buffer != nullptr || request->num_output_buffers == 0 ||
        request->num_output_buffers > M86_MAX_REQUEST_OUTPUT_BUFFERS) {
        return -EINVAL;
    }

    pending.num_output_buffers = request->num_output_buffers;
    bool fence_failed = false;

    for (uint32_t i = 0; i < request->num_output_buffers; i++) {
        const camera3_stream_buffer_t *buffer = &request->output_buffers[i];
        if (buffer == nullptr || buffer->stream == nullptr || buffer->buffer == nullptr) {
            return -EINVAL;
        }
        pending.output_buffers[i].stream = buffer->stream;
        pending.output_buffers[i].buffer = const_cast<buffer_handle_t *>(buffer->buffer);

        if (buffer->acquire_fence >= 0) {
            const int fence = buffer->acquire_fence;
            const int wait_err = sync_wait(fence, 1000);
            close(fence);
            if (wait_err < 0) {
                ALOGE("%s: acquire fence wait failed for frame %u output %u: %d",
                      __FUNCTION__, request->frame_number, i, errno);
                fence_failed = true;
            }
        }

        if (buffer->stream == m86_dev->configured_preview_stream) {
            if (pending.preview_output_index >= 0) {
                return -EINVAL;
            }
            pending.preview_output_index = static_cast<int>(i);
        } else if (buffer->stream == m86_dev->configured_video_stream) {
            if (pending.video_output_index >= 0) {
                return -EINVAL;
            }
            pending.video_output_index = static_cast<int>(i);
        } else if (buffer->stream == m86_dev->configured_jpeg_stream) {
            if (pending.jpeg_output_index >= 0) {
                return -EINVAL;
            }
            pending.jpeg_output_index = static_cast<int>(i);
        }
    }

    if (fence_failed ||
        (pending.preview_output_index < 0 && pending.video_output_index < 0 &&
         pending.jpeg_output_index < 0)) {
        ALOGW("%s: completing unsupported/error request %u with %u outputs",
              __FUNCTION__, request->frame_number, request->num_output_buffers);
        m86_send_request_error(m86_dev, &pending);
        return 0;
    }

    m86_apply_request_controls(m86_dev, request->settings);

    if (pending.jpeg_output_index >= 0) {
        m86_pending_jpeg_request_t jpeg;
        memset(&jpeg, 0, sizeof(jpeg));
        jpeg.frame_number = request->frame_number;
        jpeg.timestamp_ns = pending.timestamp_ns;
        jpeg.shutter_and_metadata_sent = true;
        jpeg.output = pending.output_buffers[pending.jpeg_output_index];
        m86_read_jpeg_request_settings(&jpeg, request->settings);
        if (!m86_reserve_jpeg_request(m86_dev, &jpeg)) {
            ALOGE("%s: JPEG request queue full at frame %u", __FUNCTION__,
                  request->frame_number);
            m86_send_request_error(m86_dev, &pending);
            return 0;
        }
    }

    m86_send_request_shutter_and_metadata(m86_dev, &pending);

    if (pending.preview_output_index >= 0) {
        m86_pending_stream_request_t stream_request;
        memset(&stream_request, 0, sizeof(stream_request));
        stream_request.frame_number = pending.frame_number;
        stream_request.timestamp_ns = pending.timestamp_ns;
        stream_request.output = pending.output_buffers[pending.preview_output_index];
        if (!m86_enqueue_stream_request(m86_dev, &stream_request, false)) {
            ALOGE("%s: preview request queue full at frame %u", __FUNCTION__,
                  request->frame_number);
            m86_send_stream_result(m86_dev, &stream_request, false);
        }
    }
    if (pending.video_output_index >= 0) {
        m86_pending_stream_request_t stream_request;
        memset(&stream_request, 0, sizeof(stream_request));
        stream_request.frame_number = pending.frame_number;
        stream_request.timestamp_ns = pending.timestamp_ns;
        stream_request.output = pending.output_buffers[pending.video_output_index];
        if (!m86_enqueue_stream_request(m86_dev, &stream_request, true)) {
            ALOGE("%s: video request queue full at frame %u", __FUNCTION__,
                  request->frame_number);
            m86_send_stream_result(m86_dev, &stream_request, false);
        }
    }

    if (pending.jpeg_output_index >= 0 && m86_dev->preview_started) {
        m86_start_next_jpeg_capture(m86_dev);
    }

    return 0;
}

static int m86_device_flush(const struct camera3_device *device)
{
    m86_camera3_device_t *m86_dev =
            reinterpret_cast<m86_camera3_device_t *>(const_cast<camera3_device *>(device));
    pthread_mutex_lock(&m86_dev->pending_lock);
    m86_dev->stop_preview_start_thread = true;
    pthread_cond_broadcast(&m86_dev->pending_cond);
    pthread_mutex_unlock(&m86_dev->pending_lock);
    if (m86_dev->preview_start_thread_joinable) {
        pthread_join(m86_dev->preview_start_thread, nullptr);
        m86_dev->preview_start_thread_joinable = false;
    }

    pthread_mutex_lock(&m86_dev->pending_lock);
    m86_dev->flushing = true;
    const bool cancel_jpeg = m86_dev->jpeg_capture_active;
    pthread_mutex_unlock(&m86_dev->pending_lock);

    if (m86_dev->engine != nullptr && cancel_jpeg) {
        m86_dev->engine->cancelPicture();
    }
    if (m86_dev->engine != nullptr && m86_dev->recording_started) {
        m86_dev->engine->stopRecording();
        m86_dev->recording_started = false;
    }
    if (m86_dev->engine != nullptr && m86_dev->preview_started) {
        m86_dev->engine->stopPreview();
        m86_dev->preview_started = false;
    }

    m86_pending_stream_request_t pending;
    while (m86_dequeue_stream_request(m86_dev, &pending, false)) {
        m86_send_stream_result(m86_dev, &pending, false);
    }
    while (m86_dequeue_stream_request(m86_dev, &pending, true)) {
        m86_send_stream_result(m86_dev, &pending, false);
    }
    m86_pending_jpeg_request_t jpeg;
    while (m86_take_jpeg_request(m86_dev, &jpeg)) {
        m86_send_jpeg_error(m86_dev, &jpeg);
    }
    pthread_mutex_lock(&m86_dev->pending_lock);
    m86_dev->flushing = false;
    pthread_mutex_unlock(&m86_dev->pending_lock);
    return 0;
}

static void m86_device_dump(const struct camera3_device * /* device */, int fd)
{
    dprintf(fd, "m86 source HAL3 (stable legacy buffered preview)\n");
}

static int m86_device_open(const hw_module_t *module, const char *name, hw_device_t **device)
{
    if (module == nullptr || name == nullptr || device == nullptr) {
        return -EINVAL;
    }

    int camera_id = atoi(name);
    if (camera_id < 0 || camera_id >= M86_CAMERA_COUNT) {
        ALOGE("%s: invalid camera id %s", __FUNCTION__, name);
        return -EINVAL;
    }

    m86_camera3_device_t *m86_dev = new (std::nothrow) m86_camera3_device_t();
    if (m86_dev == nullptr) {
        return -ENOMEM;
    }

    memset(m86_dev, 0, sizeof(*m86_dev));
    if (pthread_mutex_init(&m86_dev->pending_lock, nullptr) != 0) {
        delete m86_dev;
        return -ENOMEM;
    }
    if (pthread_cond_init(&m86_dev->pending_cond, nullptr) != 0) {
        pthread_mutex_destroy(&m86_dev->pending_lock);
        delete m86_dev;
        return -ENOMEM;
    }
    m86_dev->camera_id = camera_id;
    m86_dev->ae_mode = ANDROID_CONTROL_AE_MODE_ON;
    m86_dev->ae_state = ANDROID_CONTROL_AE_STATE_CONVERGED;
    m86_dev->af_mode = camera_id == 1 ? ANDROID_CONTROL_AF_MODE_OFF
                                      : ANDROID_CONTROL_AF_MODE_CONTINUOUS_PICTURE;
    m86_dev->af_state = camera_id == 1 ? ANDROID_CONTROL_AF_STATE_INACTIVE
                                       : ANDROID_CONTROL_AF_STATE_PASSIVE_SCAN;
    m86_dev->awb_mode = ANDROID_CONTROL_AWB_MODE_AUTO;
    m86_dev->awb_state = ANDROID_CONTROL_AWB_STATE_CONVERGED;
    m86_dev->flash_mode = ANDROID_FLASH_MODE_OFF;
    m86_dev->flash_state = camera_id == 1 ? ANDROID_FLASH_STATE_UNAVAILABLE
                                          : ANDROID_FLASH_STATE_READY;
    m86_dev->crop_region[0] = 0;
    m86_dev->crop_region[1] = 0;
    m86_dev->crop_region[2] = camera_id == 1 ? 2592 : 5344;
    m86_dev->crop_region[3] = camera_id == 1 ? 1944 : 4016;
    m86_dev->engine = new (std::nothrow) ExynosCamera(camera_id, nullptr);
    if (m86_dev->engine == nullptr) {
        pthread_cond_destroy(&m86_dev->pending_cond);
        pthread_mutex_destroy(&m86_dev->pending_lock);
        delete m86_dev;
        return -ENOMEM;
    }
    m86_dev->window = new (std::nothrow) m86_preview_window_t();
    if (m86_dev->window == nullptr) {
        delete m86_dev->engine;
        pthread_cond_destroy(&m86_dev->pending_cond);
        pthread_mutex_destroy(&m86_dev->pending_lock);
        delete m86_dev;
        return -ENOMEM;
    }
    m86_preview_window_init(m86_dev->window, m86_dev);
    m86_dev->base.common.tag = HARDWARE_DEVICE_TAG;
    m86_dev->base.common.version = CAMERA_DEVICE_API_VERSION_3_4;
    m86_dev->base.common.module = const_cast<hw_module_t *>(module);
    m86_dev->base.common.close = m86_device_close;
    m86_dev->base.ops = new (std::nothrow) camera3_device_ops_t();
    if (m86_dev->base.ops == nullptr) {
        delete m86_dev->engine;
        if (m86_dev->window != nullptr) {
            m86_preview_window_deinit(m86_dev->window);
            delete m86_dev->window;
        }
        pthread_cond_destroy(&m86_dev->pending_cond);
        pthread_mutex_destroy(&m86_dev->pending_lock);
        delete m86_dev;
        return -ENOMEM;
    }

    memset(const_cast<camera3_device_ops_t *>(m86_dev->base.ops), 0, sizeof(camera3_device_ops_t));
    camera3_device_ops_t *ops = const_cast<camera3_device_ops_t *>(m86_dev->base.ops);
    ops->initialize = m86_device_initialize;
    ops->configure_streams = m86_device_configure_streams;
    ops->construct_default_request_settings = m86_device_construct_default_request_settings;
    ops->process_capture_request = m86_device_process_capture_request;
    ops->flush = m86_device_flush;
    ops->dump = m86_device_dump;

    *device = &m86_dev->base.common;
    if (camera_id == 0) {
        pthread_mutex_lock(&g_module_lock);
        g_rear_camera_open = true;
        g_torch_enabled = false;
        pthread_mutex_unlock(&g_module_lock);
        m86_notify_torch_status(TORCH_MODE_STATUS_NOT_AVAILABLE);
    }
    ALOGI("%s: opened camera %d (%s)", __FUNCTION__, camera_id, g_camera_names[camera_id]);
    return 0;
}

static struct hw_module_methods_t m86_module_methods = {
    .open = m86_device_open,
};

camera_module_t HAL_MODULE_INFO_SYM = {
    .common = {
        .tag = HARDWARE_MODULE_TAG,
        .module_api_version = CAMERA_MODULE_API_VERSION_2_4,
        .hal_api_version = HARDWARE_HAL_API_VERSION,
        .id = CAMERA_HARDWARE_MODULE_ID,
        .name = "Meizu PRO 5 source HAL3",
        .author = "The LineageOS Project",
        .methods = &m86_module_methods,
        .dso = nullptr,
        .reserved = {0},
    },
    .get_number_of_cameras = m86_get_number_of_cameras,
    .get_camera_info = m86_get_camera_info,
    .set_callbacks = m86_set_callbacks,
    .get_vendor_tag_ops = m86_get_vendor_tag_ops,
    .open_legacy = m86_open_legacy,
    .set_torch_mode = m86_set_torch_mode,
    .init = m86_init,
    .reserved = {0},
};
