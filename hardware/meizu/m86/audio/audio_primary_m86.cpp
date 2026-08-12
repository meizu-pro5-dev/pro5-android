/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 *
 * The Flyme PRO 5 primary HAL predates the Android 10 audio ABI.  Its
 * device, output, and input objects contain private fields where newer
 * Android callbacks live.  This wrapper owns the public Android objects and
 * forwards only the legacy prefix to the locked Flyme implementation.
 */

#include <hardware/audio.h>
#include <hardware/hardware.h>

#include <cutils/log.h>
#include <cutils/properties.h>

#include <dlfcn.h>
#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

namespace {

constexpr char kFlymeModulePath[] =
        "/system/lib/hw/audio.primary.m86.flyme.so";
constexpr char kHifiEnabledProperty[] = "persist.vendor.m86.hifi.enabled";
constexpr char kHifiGainProperty[] = "persist.vendor.m86.hifi.gain";

struct FlymeDevice;
struct FlymeStreamOut;
struct FlymeStreamIn;

/* The fields through legacy_dump are the measured 32-bit Flyme layout. */
struct FlymeDevice {
    hw_device_t common;
    uint32_t (*get_supported_devices)(const FlymeDevice*);
    int (*init_check)(const FlymeDevice*);
    int (*set_voice_volume)(FlymeDevice*, float);
    int (*set_master_volume)(FlymeDevice*, float);
    int (*get_master_volume)(FlymeDevice*, float*);
    int (*set_mode)(FlymeDevice*, audio_mode_t);
    int (*set_mic_mute)(FlymeDevice*, bool);
    int (*get_mic_mute)(const FlymeDevice*, bool*);
    void* vendor_reserved0;
    void* vendor_reserved1;
    int (*set_headphone_volume)(FlymeDevice*, float);
    int (*set_parameters)(FlymeDevice*, const char*);
    char* (*get_parameters)(const FlymeDevice*, const char*);
    size_t (*get_input_buffer_size)(const FlymeDevice*, const audio_config*);
    int (*open_output_stream)(FlymeDevice*, audio_io_handle_t, audio_devices_t,
                              audio_output_flags_t, audio_config*,
                              FlymeStreamOut**, const char*);
    void (*close_output_stream)(FlymeDevice*, FlymeStreamOut*);
    int (*open_input_stream)(FlymeDevice*, audio_io_handle_t, audio_devices_t,
                             audio_config*, FlymeStreamIn**, audio_input_flags_t,
                             const char*, audio_source_t);
    void (*close_input_stream)(FlymeDevice*, FlymeStreamIn*);
    int (*legacy_dump)(const FlymeDevice*, int);
};

static_assert(offsetof(FlymeDevice, vendor_reserved0) == 96,
              "Flyme device ABI changed before private slots");
static_assert(offsetof(FlymeDevice, set_headphone_volume) == 104,
              "Flyme headphone callback offset changed");
static_assert(offsetof(FlymeDevice, set_parameters) == 108,
              "Flyme set_parameters offset changed");
static_assert(offsetof(FlymeDevice, get_input_buffer_size) == 116,
              "Flyme input-buffer callback offset changed");
static_assert(offsetof(FlymeDevice, legacy_dump) == 136,
              "Flyme legacy dump offset changed");

struct FlymeStreamOut {
    audio_stream_t common;
    uint32_t (*get_latency)(const audio_stream_out_t*);
    int (*set_volume)(audio_stream_out_t*, float, float);
    ssize_t (*write)(audio_stream_out_t*, const void*, size_t);
    int (*get_render_position)(const audio_stream_out_t*, uint32_t*);
    int (*get_next_write_timestamp)(const audio_stream_out_t*, int64_t*);
    int (*set_callback)(audio_stream_out_t*, stream_callback_t, void*);
    int (*pause)(audio_stream_out_t*);
    int (*resume)(audio_stream_out_t*);
    int (*drain)(audio_stream_out_t*, audio_drain_type_t);
    int (*flush)(audio_stream_out_t*);
    int (*get_presentation_position)(const audio_stream_out_t*, uint64_t*,
                                     struct timespec*);
    void* private_reserved[4];
    uint32_t pcm_config_channels;
};

static_assert(offsetof(FlymeStreamOut, private_reserved) == 100,
              "Flyme output private ABI prefix changed");
static_assert(offsetof(FlymeStreamOut, pcm_config_channels) == 116,
              "Flyme output pcm_config offset changed");

struct FlymeStreamIn {
    audio_stream_t common;
    int (*set_gain)(audio_stream_in_t*, float);
    ssize_t (*read)(audio_stream_in_t*, void*, size_t);
    uint32_t (*get_input_frames_lost)(audio_stream_in_t*);
    uint8_t private_state[108];
};

static_assert(offsetof(FlymeStreamIn, private_state) == 68,
              "Flyme input private ABI prefix changed");

struct M86StreamOut;

struct M86Device {
    audio_hw_device_t public_device;
    FlymeDevice* flyme_device;
    void* flyme_handle;
    M86StreamOut* active_output;
    audio_devices_t active_output_devices;
    bool hifi_enabled;
    int hifi_gain;
};

struct M86StreamOut {
    audio_stream_out_t public_stream;
    FlymeStreamOut* flyme_stream;
    M86Device* owner;
};

struct M86StreamIn {
    audio_stream_in_t public_stream;
    FlymeStreamIn* flyme_stream;
    M86Device* owner;
};

static M86Device* m86_device(audio_hw_device_t* device) {
    return reinterpret_cast<M86Device*>(device);
}

static const M86Device* m86_device(const audio_hw_device_t* device) {
    return reinterpret_cast<const M86Device*>(device);
}

static M86StreamOut* m86_output(audio_stream_out_t* stream) {
    return reinterpret_cast<M86StreamOut*>(stream);
}

static const M86StreamOut* m86_output(const audio_stream_out_t* stream) {
    return reinterpret_cast<const M86StreamOut*>(stream);
}

static M86StreamIn* m86_input(audio_stream_in_t* stream) {
    return reinterpret_cast<M86StreamIn*>(stream);
}

static const M86StreamIn* m86_input(const audio_stream_in_t* stream) {
    return reinterpret_cast<const M86StreamIn*>(stream);
}

static int m86_apply_hifi_state(M86Device* wrapper);
static int m86_apply_hifi_gain(M86Device* wrapper);
static int m86_apply_hifi_policy(M86Device* wrapper);
static int m86_apply_headphone_volume(M86Device* wrapper);

static bool m86_is_wired_output(audio_devices_t devices) {
    return (devices & (AUDIO_DEVICE_OUT_WIRED_HEADSET
            | AUDIO_DEVICE_OUT_WIRED_HEADPHONE)) != 0;
}

static bool m86_find_parameter(const char* kv_pairs, const char* key,
                               char* value, size_t value_size) {
    if (kv_pairs == nullptr || key == nullptr || value == nullptr || value_size == 0) {
        return false;
    }
    const size_t key_size = strlen(key);
    const char* cursor = kv_pairs;
    while (*cursor != '\0') {
        while (*cursor == ';' || *cursor == ',' || *cursor == ' ') {
            ++cursor;
        }
        if (strncmp(cursor, key, key_size) == 0 && cursor[key_size] == '=') {
            const char* start = cursor + key_size + 1;
            const char* end = strpbrk(start, ";,");
            const size_t length = end == nullptr
                    ? strlen(start) : static_cast<size_t>(end - start);
            const size_t copied = length < value_size - 1 ? length : value_size - 1;
            memcpy(value, start, copied);
            value[copied] = '\0';
            return true;
        }
        const char* next = strpbrk(cursor, ";,");
        if (next == nullptr) {
            break;
        }
        cursor = next + 1;
    }
    return false;
}

#define M86_OUT_COMMON(name, return_type, args, call_args, fallback)          \
    static return_type out_##name args {                                     \
        M86StreamOut* out = m86_output(                                       \
                reinterpret_cast<audio_stream_out_t*>(stream));              \
        if (out->flyme_stream == nullptr ||                                   \
            out->flyme_stream->common.name == nullptr) {                     \
            return fallback;                                                  \
        }                                                                      \
        return out->flyme_stream->common.name call_args;                      \
    }

static uint32_t out_get_sample_rate(const audio_stream_t* stream) {
    const M86StreamOut* out = m86_output(
            reinterpret_cast<const audio_stream_out_t*>(stream));
    return out->flyme_stream != nullptr &&
                           out->flyme_stream->common.get_sample_rate != nullptr
            ? out->flyme_stream->common.get_sample_rate(
                      &out->flyme_stream->common)
            : 0;
}

static int out_set_sample_rate(audio_stream_t* stream, uint32_t rate) {
    M86StreamOut* out = m86_output(reinterpret_cast<audio_stream_out_t*>(stream));
    return out->flyme_stream != nullptr &&
                           out->flyme_stream->common.set_sample_rate != nullptr
            ? out->flyme_stream->common.set_sample_rate(
                      &out->flyme_stream->common, rate)
            : -ENOSYS;
}

static size_t out_get_buffer_size(const audio_stream_t* stream) {
    const M86StreamOut* out = m86_output(
            reinterpret_cast<const audio_stream_out_t*>(stream));
    return out->flyme_stream != nullptr &&
                           out->flyme_stream->common.get_buffer_size != nullptr
            ? out->flyme_stream->common.get_buffer_size(
                      &out->flyme_stream->common)
            : 0;
}

static audio_channel_mask_t out_get_channels(const audio_stream_t* stream) {
    const M86StreamOut* out = m86_output(
            reinterpret_cast<const audio_stream_out_t*>(stream));
    return out->flyme_stream != nullptr &&
                           out->flyme_stream->common.get_channels != nullptr
            ? out->flyme_stream->common.get_channels(&out->flyme_stream->common)
            : AUDIO_CHANNEL_NONE;
}

static audio_format_t out_get_format(const audio_stream_t* stream) {
    const M86StreamOut* out = m86_output(
            reinterpret_cast<const audio_stream_out_t*>(stream));
    return out->flyme_stream != nullptr &&
                           out->flyme_stream->common.get_format != nullptr
            ? out->flyme_stream->common.get_format(&out->flyme_stream->common)
            : AUDIO_FORMAT_INVALID;
}

static int out_set_format(audio_stream_t* stream, audio_format_t format) {
    M86StreamOut* out = m86_output(reinterpret_cast<audio_stream_out_t*>(stream));
    return out->flyme_stream != nullptr &&
                           out->flyme_stream->common.set_format != nullptr
            ? out->flyme_stream->common.set_format(&out->flyme_stream->common,
                                                   format)
            : -ENOSYS;
}

static int out_standby(audio_stream_t* stream) {
    M86StreamOut* out = m86_output(reinterpret_cast<audio_stream_out_t*>(stream));
    return out->flyme_stream != nullptr && out->flyme_stream->common.standby != nullptr
            ? out->flyme_stream->common.standby(&out->flyme_stream->common)
            : -ENOSYS;
}

static int out_dump(const audio_stream_t* stream, int fd) {
    const M86StreamOut* out = m86_output(
            reinterpret_cast<const audio_stream_out_t*>(stream));
    return out->flyme_stream != nullptr && out->flyme_stream->common.dump != nullptr
            ? out->flyme_stream->common.dump(&out->flyme_stream->common, fd)
            : -ENOSYS;
}

static audio_devices_t out_get_device(const audio_stream_t* stream) {
    const M86StreamOut* out = m86_output(
            reinterpret_cast<const audio_stream_out_t*>(stream));
    return out->flyme_stream != nullptr &&
                           out->flyme_stream->common.get_device != nullptr
            ? out->flyme_stream->common.get_device(&out->flyme_stream->common)
            : AUDIO_DEVICE_NONE;
}

static int out_set_device(audio_stream_t* stream, audio_devices_t device) {
    M86StreamOut* out = m86_output(reinterpret_cast<audio_stream_out_t*>(stream));
    if (out->flyme_stream == nullptr ||
        out->flyme_stream->common.set_device == nullptr) {
        return -ENOSYS;
    }
    const int result = out->flyme_stream->common.set_device(
            &out->flyme_stream->common, device);
    if (result == 0 && out->owner != nullptr) {
        out->owner->active_output_devices = device;
        (void)m86_apply_headphone_volume(out->owner);
        (void)m86_apply_hifi_state(out->owner);
        (void)m86_apply_hifi_gain(out->owner);
    }
    return result;
}

static int out_set_parameters(audio_stream_t* stream, const char* kv_pairs) {
    M86StreamOut* out = m86_output(reinterpret_cast<audio_stream_out_t*>(stream));
    if (out->flyme_stream == nullptr ||
        out->flyme_stream->common.set_parameters == nullptr) {
        return -ENOSYS;
    }

    char routing[32];
    bool has_routing = false;
    audio_devices_t requested_devices = AUDIO_DEVICE_NONE;
    if (m86_find_parameter(kv_pairs, "routing", routing, sizeof(routing))) {
        char* end = nullptr;
        const unsigned long requested = strtoul(routing, &end, 0);
        has_routing = end != routing && *end == '\0';
        requested_devices = static_cast<audio_devices_t>(requested);
    }

    const int result = out->flyme_stream->common.set_parameters(
            &out->flyme_stream->common, kv_pairs);
    if (result == 0 && has_routing && out->owner != nullptr) {
        out->owner->active_output_devices = requested_devices;
        (void)m86_apply_headphone_volume(out->owner);
        (void)m86_apply_hifi_policy(out->owner);
    }
    return result;
}

static char* out_get_parameters(const audio_stream_t* stream, const char* keys) {
    const M86StreamOut* out = m86_output(
            reinterpret_cast<const audio_stream_out_t*>(stream));
    return out->flyme_stream != nullptr &&
                           out->flyme_stream->common.get_parameters != nullptr
            ? out->flyme_stream->common.get_parameters(
                      &out->flyme_stream->common, keys)
            : nullptr;
}

static int out_add_effect(const audio_stream_t* stream, effect_handle_t effect) {
    const M86StreamOut* out = m86_output(
            reinterpret_cast<const audio_stream_out_t*>(stream));
    return out->flyme_stream != nullptr &&
                           out->flyme_stream->common.add_audio_effect != nullptr
            ? out->flyme_stream->common.add_audio_effect(
                      &out->flyme_stream->common, effect)
            : -ENOSYS;
}

static int out_remove_effect(const audio_stream_t* stream,
                             effect_handle_t effect) {
    const M86StreamOut* out = m86_output(
            reinterpret_cast<const audio_stream_out_t*>(stream));
    return out->flyme_stream != nullptr &&
                           out->flyme_stream->common.remove_audio_effect != nullptr
            ? out->flyme_stream->common.remove_audio_effect(
                      &out->flyme_stream->common, effect)
            : -ENOSYS;
}

static uint32_t out_latency(const audio_stream_out_t* stream) {
    const M86StreamOut* out = m86_output(stream);
    return out->flyme_stream != nullptr && out->flyme_stream->get_latency != nullptr
            ? out->flyme_stream->get_latency(
                      reinterpret_cast<const audio_stream_out_t*>(
                              out->flyme_stream))
            : 0;
}

static int out_set_volume(audio_stream_out_t* stream, float left, float right) {
    M86StreamOut* out = m86_output(stream);
    if (out->flyme_stream == nullptr || out->flyme_stream->set_volume == nullptr) {
        return -ENOSYS;
    }

    /*
     * The Flyme HAL has a second, absolute headphone scalar.  Keep it at
     * unity immediately before every framework stream-volume update so the
     * framework curve is the only user-volume attenuation.  This call is
     * deliberately wrapper-owned and idempotent; left/right are forwarded
     * unchanged to the vendor stream below.  The framework stream volume is
     * the only user-volume attenuation.
     */
    if (out->owner != nullptr) {
        const int headphone_result = m86_apply_headphone_volume(out->owner);
        if (headphone_result != 0) {
            ALOGW("Unable to normalize Flyme headphone volume before stream volume: %d",
                  headphone_result);
        }
    }
    return out->flyme_stream->set_volume(
            reinterpret_cast<audio_stream_out_t*>(out->flyme_stream), left, right);
}

static ssize_t out_write(audio_stream_out_t* stream, const void* buffer,
                         size_t bytes) {
    M86StreamOut* out = m86_output(stream);
    return out->flyme_stream != nullptr && out->flyme_stream->write != nullptr
            ? out->flyme_stream->write(
                      reinterpret_cast<audio_stream_out_t*>(out->flyme_stream),
                      buffer, bytes)
            : -ENOSYS;
}

static int out_get_render_position(const audio_stream_out_t* stream,
                                   uint32_t* frames) {
    const M86StreamOut* out = m86_output(stream);
    return out->flyme_stream != nullptr &&
                           out->flyme_stream->get_render_position != nullptr
            ? out->flyme_stream->get_render_position(
                      reinterpret_cast<const audio_stream_out_t*>(
                              out->flyme_stream),
                      frames)
            : -ENOSYS;
}

static int out_get_next_write_timestamp(const audio_stream_out_t* stream,
                                        int64_t* timestamp) {
    const M86StreamOut* out = m86_output(stream);
    return out->flyme_stream != nullptr &&
                           out->flyme_stream->get_next_write_timestamp != nullptr
            ? out->flyme_stream->get_next_write_timestamp(
                      reinterpret_cast<const audio_stream_out_t*>(
                              out->flyme_stream),
                      timestamp)
            : -ENOSYS;
}

static int out_set_callback(audio_stream_out_t* stream, stream_callback_t callback,
                            void* cookie) {
    M86StreamOut* out = m86_output(stream);
    return out->flyme_stream != nullptr && out->flyme_stream->set_callback != nullptr
            ? out->flyme_stream->set_callback(
                      reinterpret_cast<audio_stream_out_t*>(out->flyme_stream),
                      callback, cookie)
            : -ENOSYS;
}

static int out_pause(audio_stream_out_t* stream) {
    M86StreamOut* out = m86_output(stream);
    return out->flyme_stream != nullptr && out->flyme_stream->pause != nullptr
            ? out->flyme_stream->pause(
                      reinterpret_cast<audio_stream_out_t*>(out->flyme_stream))
            : -ENOSYS;
}

static int out_resume(audio_stream_out_t* stream) {
    M86StreamOut* out = m86_output(stream);
    return out->flyme_stream != nullptr && out->flyme_stream->resume != nullptr
            ? out->flyme_stream->resume(
                      reinterpret_cast<audio_stream_out_t*>(out->flyme_stream))
            : -ENOSYS;
}

static int out_drain(audio_stream_out_t* stream, audio_drain_type_t type) {
    M86StreamOut* out = m86_output(stream);
    return out->flyme_stream != nullptr && out->flyme_stream->drain != nullptr
            ? out->flyme_stream->drain(
                      reinterpret_cast<audio_stream_out_t*>(out->flyme_stream), type)
            : -ENOSYS;
}

static int out_flush(audio_stream_out_t* stream) {
    M86StreamOut* out = m86_output(stream);
    return out->flyme_stream != nullptr && out->flyme_stream->flush != nullptr
            ? out->flyme_stream->flush(
                      reinterpret_cast<audio_stream_out_t*>(out->flyme_stream))
            : -ENOSYS;
}

static void init_output(M86StreamOut* out) {
    memset(&out->public_stream, 0, sizeof(out->public_stream));
    audio_stream_t& common = out->public_stream.common;
    common.get_sample_rate = out_get_sample_rate;
    common.set_sample_rate = out_set_sample_rate;
    common.get_buffer_size = out_get_buffer_size;
    common.get_channels = out_get_channels;
    common.get_format = out_get_format;
    common.set_format = out_set_format;
    common.standby = out_standby;
    common.dump = out_dump;
    common.get_device = out_get_device;
    common.set_device = out_set_device;
    common.set_parameters = out_set_parameters;
    common.get_parameters = out_get_parameters;
    common.add_audio_effect = out_add_effect;
    common.remove_audio_effect = out_remove_effect;
    out->public_stream.get_latency = out_latency;
    out->public_stream.set_volume = out_set_volume;
    out->public_stream.write = out_write;
    out->public_stream.get_render_position = out_get_render_position;
    out->public_stream.get_next_write_timestamp = out_get_next_write_timestamp;
    out->public_stream.set_callback = out_set_callback;
    out->public_stream.pause = out_pause;
    out->public_stream.resume = out_resume;
    out->public_stream.drain = out_drain;
    out->public_stream.flush = out_flush;
}

static uint32_t in_get_sample_rate(const audio_stream_t* stream) {
    const M86StreamIn* in = m86_input(
            reinterpret_cast<const audio_stream_in_t*>(stream));
    return in->flyme_stream != nullptr &&
                           in->flyme_stream->common.get_sample_rate != nullptr
            ? in->flyme_stream->common.get_sample_rate(&in->flyme_stream->common)
            : 0;
}

static int in_set_sample_rate(audio_stream_t* stream, uint32_t rate) {
    M86StreamIn* in = m86_input(reinterpret_cast<audio_stream_in_t*>(stream));
    return in->flyme_stream != nullptr &&
                           in->flyme_stream->common.set_sample_rate != nullptr
            ? in->flyme_stream->common.set_sample_rate(
                      &in->flyme_stream->common, rate)
            : -ENOSYS;
}

static size_t in_get_buffer_size(const audio_stream_t* stream) {
    const M86StreamIn* in = m86_input(
            reinterpret_cast<const audio_stream_in_t*>(stream));
    return in->flyme_stream != nullptr &&
                           in->flyme_stream->common.get_buffer_size != nullptr
            ? in->flyme_stream->common.get_buffer_size(&in->flyme_stream->common)
            : 0;
}

static audio_channel_mask_t in_get_channels(const audio_stream_t* stream) {
    const M86StreamIn* in = m86_input(
            reinterpret_cast<const audio_stream_in_t*>(stream));
    return in->flyme_stream != nullptr &&
                           in->flyme_stream->common.get_channels != nullptr
            ? in->flyme_stream->common.get_channels(&in->flyme_stream->common)
            : AUDIO_CHANNEL_NONE;
}

static audio_format_t in_get_format(const audio_stream_t* stream) {
    const M86StreamIn* in = m86_input(
            reinterpret_cast<const audio_stream_in_t*>(stream));
    return in->flyme_stream != nullptr &&
                           in->flyme_stream->common.get_format != nullptr
            ? in->flyme_stream->common.get_format(&in->flyme_stream->common)
            : AUDIO_FORMAT_INVALID;
}

static int in_set_format(audio_stream_t* stream, audio_format_t format) {
    M86StreamIn* in = m86_input(reinterpret_cast<audio_stream_in_t*>(stream));
    return in->flyme_stream != nullptr &&
                           in->flyme_stream->common.set_format != nullptr
            ? in->flyme_stream->common.set_format(&in->flyme_stream->common,
                                                  format)
            : -ENOSYS;
}

static int in_standby(audio_stream_t* stream) {
    M86StreamIn* in = m86_input(reinterpret_cast<audio_stream_in_t*>(stream));
    return in->flyme_stream != nullptr && in->flyme_stream->common.standby != nullptr
            ? in->flyme_stream->common.standby(&in->flyme_stream->common)
            : -ENOSYS;
}

static int in_dump(const audio_stream_t* stream, int fd) {
    const M86StreamIn* in = m86_input(
            reinterpret_cast<const audio_stream_in_t*>(stream));
    return in->flyme_stream != nullptr && in->flyme_stream->common.dump != nullptr
            ? in->flyme_stream->common.dump(&in->flyme_stream->common, fd)
            : -ENOSYS;
}

static audio_devices_t in_get_device(const audio_stream_t* stream) {
    const M86StreamIn* in = m86_input(
            reinterpret_cast<const audio_stream_in_t*>(stream));
    return in->flyme_stream != nullptr &&
                           in->flyme_stream->common.get_device != nullptr
            ? in->flyme_stream->common.get_device(&in->flyme_stream->common)
            : AUDIO_DEVICE_NONE;
}

static int in_set_device(audio_stream_t* stream, audio_devices_t device) {
    M86StreamIn* in = m86_input(reinterpret_cast<audio_stream_in_t*>(stream));
    return in->flyme_stream != nullptr &&
                           in->flyme_stream->common.set_device != nullptr
            ? in->flyme_stream->common.set_device(&in->flyme_stream->common,
                                                  device)
            : -ENOSYS;
}

static int in_set_parameters(audio_stream_t* stream, const char* kv_pairs) {
    M86StreamIn* in = m86_input(reinterpret_cast<audio_stream_in_t*>(stream));
    return in->flyme_stream != nullptr &&
                           in->flyme_stream->common.set_parameters != nullptr
            ? in->flyme_stream->common.set_parameters(&in->flyme_stream->common,
                                                       kv_pairs)
            : -ENOSYS;
}

static char* in_get_parameters(const audio_stream_t* stream, const char* keys) {
    const M86StreamIn* in = m86_input(
            reinterpret_cast<const audio_stream_in_t*>(stream));
    return in->flyme_stream != nullptr &&
                           in->flyme_stream->common.get_parameters != nullptr
            ? in->flyme_stream->common.get_parameters(&in->flyme_stream->common,
                                                       keys)
            : nullptr;
}

static int in_add_effect(const audio_stream_t* stream, effect_handle_t effect) {
    const M86StreamIn* in = m86_input(
            reinterpret_cast<const audio_stream_in_t*>(stream));
    return in->flyme_stream != nullptr &&
                           in->flyme_stream->common.add_audio_effect != nullptr
            ? in->flyme_stream->common.add_audio_effect(&in->flyme_stream->common,
                                                        effect)
            : -ENOSYS;
}

static int in_remove_effect(const audio_stream_t* stream, effect_handle_t effect) {
    const M86StreamIn* in = m86_input(
            reinterpret_cast<const audio_stream_in_t*>(stream));
    return in->flyme_stream != nullptr &&
                           in->flyme_stream->common.remove_audio_effect != nullptr
            ? in->flyme_stream->common.remove_audio_effect(
                      &in->flyme_stream->common, effect)
            : -ENOSYS;
}

static int in_set_gain(audio_stream_in_t* stream, float gain) {
    M86StreamIn* in = m86_input(stream);
    return in->flyme_stream != nullptr && in->flyme_stream->set_gain != nullptr
            ? in->flyme_stream->set_gain(
                      reinterpret_cast<audio_stream_in_t*>(in->flyme_stream), gain)
            : -ENOSYS;
}

static ssize_t in_read(audio_stream_in_t* stream, void* buffer, size_t bytes) {
    M86StreamIn* in = m86_input(stream);
    return in->flyme_stream != nullptr && in->flyme_stream->read != nullptr
            ? in->flyme_stream->read(
                      reinterpret_cast<audio_stream_in_t*>(in->flyme_stream),
                      buffer, bytes)
            : -ENOSYS;
}

static uint32_t in_frames_lost(audio_stream_in_t* stream) {
    M86StreamIn* in = m86_input(stream);
    return in->flyme_stream != nullptr &&
                           in->flyme_stream->get_input_frames_lost != nullptr
            ? in->flyme_stream->get_input_frames_lost(
                      reinterpret_cast<audio_stream_in_t*>(in->flyme_stream))
            : 0;
}

static void init_input(M86StreamIn* in) {
    memset(&in->public_stream, 0, sizeof(in->public_stream));
    audio_stream_t& common = in->public_stream.common;
    common.get_sample_rate = in_get_sample_rate;
    common.set_sample_rate = in_set_sample_rate;
    common.get_buffer_size = in_get_buffer_size;
    common.get_channels = in_get_channels;
    common.get_format = in_get_format;
    common.set_format = in_set_format;
    common.standby = in_standby;
    common.dump = in_dump;
    common.get_device = in_get_device;
    common.set_device = in_set_device;
    common.set_parameters = in_set_parameters;
    common.get_parameters = in_get_parameters;
    common.add_audio_effect = in_add_effect;
    common.remove_audio_effect = in_remove_effect;
    in->public_stream.set_gain = in_set_gain;
    in->public_stream.read = in_read;
    in->public_stream.get_input_frames_lost = in_frames_lost;
}

static int m86_device_close(hw_device_t* device) {
    M86Device* wrapper = reinterpret_cast<M86Device*>(device);
    int result = 0;
    if (wrapper->flyme_device != nullptr &&
        wrapper->flyme_device->common.close != nullptr) {
        result = wrapper->flyme_device->common.close(
                &wrapper->flyme_device->common);
    }
    if (wrapper->flyme_handle != nullptr) {
        dlclose(wrapper->flyme_handle);
    }
    free(wrapper);
    return result;
}

static uint32_t m86_get_supported_devices(const audio_hw_device_t* device) {
    const M86Device* wrapper = m86_device(device);
    return wrapper->flyme_device != nullptr &&
                           wrapper->flyme_device->get_supported_devices != nullptr
            ? wrapper->flyme_device->get_supported_devices(wrapper->flyme_device)
            : 0;
}

static int m86_init_check(const audio_hw_device_t* device) {
    const M86Device* wrapper = m86_device(device);
    return wrapper->flyme_device != nullptr &&
                           wrapper->flyme_device->init_check != nullptr
            ? wrapper->flyme_device->init_check(wrapper->flyme_device)
            : -ENOSYS;
}

static int m86_set_voice_volume(audio_hw_device_t* device, float volume) {
    M86Device* wrapper = m86_device(device);
    return wrapper->flyme_device != nullptr &&
                           wrapper->flyme_device->set_voice_volume != nullptr
            ? wrapper->flyme_device->set_voice_volume(wrapper->flyme_device, volume)
            : -ENOSYS;
}

static int m86_set_master_volume(audio_hw_device_t* device, float volume) {
    M86Device* wrapper = m86_device(device);
    return wrapper->flyme_device != nullptr &&
                           wrapper->flyme_device->set_master_volume != nullptr
            ? wrapper->flyme_device->set_master_volume(wrapper->flyme_device, volume)
            : -ENOSYS;
}

static int m86_get_master_volume(audio_hw_device_t* device, float* volume) {
    M86Device* wrapper = m86_device(device);
    return wrapper->flyme_device != nullptr &&
                           wrapper->flyme_device->get_master_volume != nullptr
            ? wrapper->flyme_device->get_master_volume(wrapper->flyme_device, volume)
            : -ENOSYS;
}

static int m86_set_mode(audio_hw_device_t* device, audio_mode_t mode) {
    M86Device* wrapper = m86_device(device);
    return wrapper->flyme_device != nullptr && wrapper->flyme_device->set_mode != nullptr
            ? wrapper->flyme_device->set_mode(wrapper->flyme_device, mode)
            : -ENOSYS;
}

static int m86_set_mic_mute(audio_hw_device_t* device, bool state) {
    M86Device* wrapper = m86_device(device);
    return wrapper->flyme_device != nullptr &&
                           wrapper->flyme_device->set_mic_mute != nullptr
            ? wrapper->flyme_device->set_mic_mute(wrapper->flyme_device, state)
            : -ENOSYS;
}

static int m86_get_mic_mute(const audio_hw_device_t* device, bool* state) {
    const M86Device* wrapper = m86_device(device);
    return wrapper->flyme_device != nullptr &&
                           wrapper->flyme_device->get_mic_mute != nullptr
            ? wrapper->flyme_device->get_mic_mute(wrapper->flyme_device, state)
            : -ENOSYS;
}

static int m86_set_headphone_volume(audio_hw_device_t* device, float volume) {
    M86Device* wrapper = m86_device(device);
    return wrapper->flyme_device != nullptr &&
                           wrapper->flyme_device->set_headphone_volume != nullptr
            ? wrapper->flyme_device->set_headphone_volume(wrapper->flyme_device,
                                                           volume)
            : -ENOSYS;
}

static int m86_apply_headphone_volume(M86Device* wrapper) {
    if (wrapper == nullptr || wrapper->flyme_device == nullptr ||
        wrapper->flyme_device->set_headphone_volume == nullptr) {
        return -ENOSYS;
    }
    // The legacy HAL's working path requires this callback after each output
    // open/route transition; leaving it at the vendor default is the known
    // low-headphone-volume failure mode.
    return wrapper->flyme_device->set_headphone_volume(wrapper->flyme_device,
                                                        1.0f);
}

static int m86_apply_output_device(M86Device* wrapper,
                                   audio_devices_t output_devices) {
    if (wrapper == nullptr || wrapper->active_output == nullptr ||
        wrapper->active_output->flyme_stream == nullptr) {
        return -ENODEV;
    }
    if (wrapper->active_output->flyme_stream->common.set_parameters == nullptr) {
        return -ENOSYS;
    }

    /*
     * The working direct-HAL path advertises AUDIO_DEVICE_API_VERSION_2_0.
     * AudioFlinger consequently uses its legacy routing fallback and calls
     * the output stream's set_parameters("routing=N").  Do exactly that here
     * for the defensive create_audio_patch bridge; never call the Flyme
     * device-level set_parameters for routing, because that callback does not
     * select the media DAPM route on this HAL.
     */
    char routing[32];
    snprintf(routing, sizeof(routing), "routing=%u",
             static_cast<unsigned int>(output_devices));
    return wrapper->active_output->flyme_stream->common.set_parameters(
            &wrapper->active_output->flyme_stream->common, routing);
}

static int m86_apply_hifi_state(M86Device* wrapper) {
    if (wrapper == nullptr || wrapper->active_output == nullptr ||
        wrapper->active_output->flyme_stream == nullptr ||
        wrapper->active_output->flyme_stream->common.set_parameters == nullptr) {
        // The state is retained in the wrapper and will be applied when the
        // primary output is opened. This is normal during audioserver start.
        return 0;
    }

    const bool active = wrapper->hifi_enabled
            && m86_is_wired_output(wrapper->active_output_devices);
    char state[32];
    snprintf(state, sizeof(state), "hifi_state=%s", active ? "on" : "off");
    const int state_result = wrapper->active_output->flyme_stream->common.set_parameters(
            &wrapper->active_output->flyme_stream->common, state);
    if (state_result != 0) {
        ALOGW("HiFi state apply failed: active=%d devices=0x%x result=%d",
              active ? 1 : 0,
              static_cast<unsigned int>(wrapper->active_output_devices), state_result);
        return state_result;
    }
    ALOGI("HiFi state applied: active=%d devices=0x%x gain=%d",
          active ? 1 : 0,
          static_cast<unsigned int>(wrapper->active_output_devices),
          wrapper->hifi_gain);
    return 0;
}

static int m86_apply_hifi_gain(M86Device* wrapper) {
    if (wrapper == nullptr || wrapper->flyme_device == nullptr ||
        wrapper->flyme_device->set_parameters == nullptr) {
        return -ENOSYS;
    }
    char gain[32];
    snprintf(gain, sizeof(gain), "hifi_gain=%d", wrapper->hifi_gain);
    return wrapper->flyme_device->set_parameters(wrapper->flyme_device, gain);
}

static int m86_apply_hifi_policy(M86Device* wrapper) {
    const int gain_result = m86_apply_hifi_gain(wrapper);
    const int state_result = m86_apply_hifi_state(wrapper);
    return state_result != 0 ? state_result : gain_result;
}

static void m86_load_hifi_properties(M86Device* wrapper) {
    char value[PROPERTY_VALUE_MAX];
    property_get(kHifiEnabledProperty, value, "1");
    wrapper->hifi_enabled = strcmp(value, "0") != 0;

    property_get(kHifiGainProperty, value, "0");
    char* end = nullptr;
    const long requested = strtol(value, &end, 10);
    wrapper->hifi_gain = (end == value || *end != '\0')
            ? 0
            : static_cast<int>(requested < 0 ? 0 : requested > 3 ? 3 : requested);
}

static void m86_store_hifi_properties(const M86Device* wrapper) {
    if (wrapper == nullptr) {
        return;
    }
    const int enabled_result = property_set(kHifiEnabledProperty,
                                             wrapper->hifi_enabled ? "1" : "0");
    char gain[16];
    snprintf(gain, sizeof(gain), "%d", wrapper->hifi_gain);
    const int gain_result = property_set(kHifiGainProperty, gain);
    if (enabled_result != 0 || gain_result != 0) {
        ALOGW("Unable to persist HiFi policy: enabled=%d gain=%d",
              enabled_result, gain_result);
    }
}

static int m86_set_parameters(audio_hw_device_t* device, const char* kv_pairs) {
    M86Device* wrapper = m86_device(device);
    if (kv_pairs != nullptr &&
        strcmp(kv_pairs, "vendor.meizu.set_headphone_volume=1") == 0) {
        return m86_set_headphone_volume(device, 1.0f);
    }

    char value[32];
    const bool has_hifi_state = m86_find_parameter(kv_pairs, "hifi_state", value,
                                                   sizeof(value));
    const bool has_hifi_gain = m86_find_parameter(kv_pairs, "hifi_gain", value,
                                                  sizeof(value));
    if (has_hifi_state || has_hifi_gain) {
        int result = 0;
        if (has_hifi_state) {
            char state[32];
            if (!m86_find_parameter(kv_pairs, "hifi_state", state, sizeof(state))) {
                return -EINVAL;
            }
            wrapper->hifi_enabled = strcmp(state, "on") == 0 || strcmp(state, "1") == 0;
        }
        if (has_hifi_gain) {
            char gain[32];
            if (!m86_find_parameter(kv_pairs, "hifi_gain", gain, sizeof(gain))) {
                return -EINVAL;
            }
            char* end = nullptr;
            const long requested = strtol(gain, &end, 10);
            if (end == gain || *end != '\0') {
                return -EINVAL;
            }
            wrapper->hifi_gain = static_cast<int>(requested < 0 ? 0
                    : requested > 3 ? 3 : requested);
        }
        m86_store_hifi_properties(wrapper);
        result = m86_apply_hifi_policy(wrapper);
        return result;
    }
    return wrapper->flyme_device != nullptr &&
                           wrapper->flyme_device->set_parameters != nullptr
            ? wrapper->flyme_device->set_parameters(wrapper->flyme_device, kv_pairs)
            : -ENOSYS;
}

static char* m86_get_parameters(const audio_hw_device_t* device, const char* keys) {
    const M86Device* wrapper = m86_device(device);
    return wrapper->flyme_device != nullptr &&
                           wrapper->flyme_device->get_parameters != nullptr
            ? wrapper->flyme_device->get_parameters(wrapper->flyme_device, keys)
            : nullptr;
}

static size_t m86_get_input_buffer_size(const audio_hw_device_t* device,
                                        const audio_config* config) {
    const M86Device* wrapper = m86_device(device);
    return wrapper->flyme_device != nullptr &&
                           wrapper->flyme_device->get_input_buffer_size != nullptr
            ? wrapper->flyme_device->get_input_buffer_size(wrapper->flyme_device,
                                                           config)
            : 0;
}

static int m86_open_output(audio_hw_device_t* device, audio_io_handle_t handle,
                           audio_devices_t devices, audio_output_flags_t flags,
                           audio_config* config, audio_stream_out_t** stream,
                           const char* address) {
    M86Device* wrapper = m86_device(device);
    if (wrapper->flyme_device == nullptr ||
        wrapper->flyme_device->open_output_stream == nullptr || stream == nullptr) {
        return -ENOSYS;
    }
    FlymeStreamOut* flyme_stream = nullptr;
    int result = wrapper->flyme_device->open_output_stream(
            wrapper->flyme_device, handle, devices, flags, config, &flyme_stream,
            address);
    if (result != 0) {
        return result;
    }
    M86StreamOut* output = static_cast<M86StreamOut*>(calloc(1, sizeof(*output)));
    if (output == nullptr) {
        wrapper->flyme_device->close_output_stream(wrapper->flyme_device,
                                                   flyme_stream);
        return -ENOMEM;
    }
    output->flyme_stream = flyme_stream;
    output->owner = wrapper;
    init_output(output);
    wrapper->active_output = output;
    wrapper->active_output_devices = devices;
    *stream = &output->public_stream;
    // M86Parts may have delivered the persistent HiFi policy before the
    // primary stream existed. Apply it after the raw stream is available;
    // this also covers audioserver restarts without a framework special case.
    (void)m86_apply_headphone_volume(wrapper);
    (void)m86_apply_hifi_policy(wrapper);
    return 0;
}

static void m86_close_output(audio_hw_device_t* device,
                             audio_stream_out_t* stream) {
    M86Device* wrapper = m86_device(device);
    if (stream == nullptr) {
        return;
    }
    M86StreamOut* output = m86_output(stream);
    if (wrapper->active_output == output) {
        wrapper->active_output = nullptr;
        wrapper->active_output_devices = AUDIO_DEVICE_NONE;
    }
    if (wrapper->flyme_device != nullptr &&
        wrapper->flyme_device->close_output_stream != nullptr) {
        wrapper->flyme_device->close_output_stream(wrapper->flyme_device,
                                                   output->flyme_stream);
    }
    free(output);
}

static int m86_open_input(audio_hw_device_t* device, audio_io_handle_t handle,
                          audio_devices_t devices, audio_config* config,
                          audio_stream_in_t** stream, audio_input_flags_t flags,
                          const char* address, audio_source_t source) {
    M86Device* wrapper = m86_device(device);
    if (wrapper->flyme_device == nullptr ||
        wrapper->flyme_device->open_input_stream == nullptr || stream == nullptr) {
        return -ENOSYS;
    }
    FlymeStreamIn* flyme_stream = nullptr;
    int result = wrapper->flyme_device->open_input_stream(
            wrapper->flyme_device, handle, devices, config, &flyme_stream, flags,
            address, source);
    if (result != 0) {
        return result;
    }
    M86StreamIn* input = static_cast<M86StreamIn*>(calloc(1, sizeof(*input)));
    if (input == nullptr) {
        wrapper->flyme_device->close_input_stream(wrapper->flyme_device,
                                                  flyme_stream);
        return -ENOMEM;
    }
    input->flyme_stream = flyme_stream;
    input->owner = wrapper;
    init_input(input);
    *stream = &input->public_stream;
    return 0;
}

static void m86_close_input(audio_hw_device_t* device, audio_stream_in_t* stream) {
    M86Device* wrapper = m86_device(device);
    if (stream == nullptr) {
        return;
    }
    M86StreamIn* input = m86_input(stream);
    if (wrapper->flyme_device != nullptr &&
        wrapper->flyme_device->close_input_stream != nullptr) {
        wrapper->flyme_device->close_input_stream(wrapper->flyme_device,
                                                  input->flyme_stream);
    }
    free(input);
}

static int m86_dump(const audio_hw_device_t* device, int fd) {
    const M86Device* wrapper = m86_device(device);
    return wrapper->flyme_device != nullptr &&
                           wrapper->flyme_device->legacy_dump != nullptr
            ? wrapper->flyme_device->legacy_dump(wrapper->flyme_device, fd)
            : -ENOSYS;
}

/*
 * The stock Flyme device stops at its legacy dump callback.  Android 10's
 * audio_hw_device continues with optional microphone, mute, routing and port
 * callbacks.  Leaving those public wrapper slots NULL is not safe: the
 * passthrough audio@5 Device implementation calls create_audio_patch while
 * opening the primary output, and a NULL slot becomes a jump to address 0.
 * The old HAL has no modern patch object, so translate the device sink into
 * its legacy stream/device routing callbacks instead of exposing a NULL
 * function pointer or silently returning ENOSYS.  Without this translation
 * Android 10 opens the stream with AUDIO_DEVICE_NONE and the codec path stays
 * in DAPM Off while the PCM writer reports EBUSY.
 */
static int m86_get_microphones(
        const audio_hw_device_t* /*device*/,
        audio_microphone_characteristic_t* /*microphones*/,
        size_t* /*count*/) {
    return -ENOSYS;
}

static int m86_set_master_mute(audio_hw_device_t* /*device*/, bool /*mute*/) {
    return -ENOSYS;
}

static int m86_get_master_mute(audio_hw_device_t* /*device*/, bool* /*mute*/) {
    return -ENOSYS;
}

static int m86_create_audio_patch(
        audio_hw_device_t* device, unsigned int /*num_sources*/,
        const audio_port_config* /*sources*/, unsigned int num_sinks,
        const audio_port_config* sinks, audio_patch_handle_t* handle) {
    M86Device* wrapper = m86_device(device);
    if (wrapper->flyme_device == nullptr || sinks == nullptr || num_sinks == 0) {
        return -EINVAL;
    }

    audio_devices_t output_devices = AUDIO_DEVICE_NONE;
    bool has_output_sink = false;
    for (unsigned int i = 0; i < num_sinks; ++i) {
        if (sinks[i].type == AUDIO_PORT_TYPE_DEVICE) {
            has_output_sink = true;
            output_devices |= sinks[i].ext.device.type;
        }
    }
    if (!has_output_sink) {
        if (handle != nullptr) {
            *handle = 1;
        }
        return 0;
    }
    if (output_devices == AUDIO_DEVICE_NONE) {
        output_devices = AUDIO_DEVICE_OUT_SPEAKER;
    }

    int result = m86_apply_output_device(wrapper, output_devices);
    if (result == 0) {
        wrapper->active_output_devices = output_devices;
        (void)m86_apply_headphone_volume(wrapper);
        (void)m86_apply_hifi_policy(wrapper);
    }
    ALOGI("create_audio_patch: output_devices=0x%x result=%d",
          static_cast<unsigned int>(output_devices), result);
    if (result == 0 && handle != nullptr) {
        *handle = 1;
    }
    return result;
}

static int m86_release_audio_patch(audio_hw_device_t* /*device*/,
                                   audio_patch_handle_t /*handle*/) {
    /* The legacy HAL has no patch object; stream close/standby owns teardown. */
    return 0;
}

static int m86_get_audio_port(audio_hw_device_t* /*device*/,
                              audio_port* /*port*/) {
    return -ENOSYS;
}

static int m86_set_audio_port_config(
        audio_hw_device_t* /*device*/, const audio_port_config* /*config*/) {
    return -ENOSYS;
}

static hw_module_t* flyme_module(void* handle) {
    return reinterpret_cast<hw_module_t*>(dlsym(handle, HAL_MODULE_INFO_SYM_AS_STR));
}

static int m86_module_open(const hw_module_t* module, const char* id,
                           hw_device_t** device) {
    if (id == nullptr || device == nullptr ||
        strcmp(id, AUDIO_HARDWARE_INTERFACE) != 0) {
        return -EINVAL;
    }
    *device = nullptr;
    void* handle = dlopen(kFlymeModulePath, RTLD_NOW | RTLD_LOCAL);
    if (handle == nullptr) {
        ALOGE("Unable to load Flyme audio HAL %s: %s", kFlymeModulePath,
              dlerror());
        return -ENOENT;
    }
    hw_module_t* raw_module = flyme_module(handle);
    if (raw_module == nullptr || raw_module->methods == nullptr ||
        raw_module->methods->open == nullptr) {
        ALOGE("Flyme audio HAL has no valid module methods");
        dlclose(handle);
        return -ENODEV;
    }
    hw_device_t* raw_device = nullptr;
    int result = raw_module->methods->open(raw_module, id, &raw_device);
    if (result != 0 || raw_device == nullptr) {
        ALOGE("Flyme audio HAL open failed: %d", result);
        dlclose(handle);
        return result != 0 ? result : -ENODEV;
    }
    M86Device* wrapper = static_cast<M86Device*>(calloc(1, sizeof(*wrapper)));
    if (wrapper == nullptr) {
        raw_device->close(raw_device);
        dlclose(handle);
        return -ENOMEM;
    }
    wrapper->flyme_device = reinterpret_cast<FlymeDevice*>(raw_device);
    wrapper->flyme_handle = handle;
    m86_load_hifi_properties(wrapper);
    (void)m86_apply_hifi_gain(wrapper);
    wrapper->public_device.common.tag = HARDWARE_DEVICE_TAG;
    /*
     * Keep the same legacy capability advertised by the known-good direct
     * Flyme HAL.  Android 10 then routes through Stream::set_parameters()
     * instead of calling the modern create_audio_patch callback.  The public
     * object is still fully translated, but its API level is intentionally
     * 2.0 because the vendor route contract is the 2.0 contract.
     */
    wrapper->public_device.common.version = AUDIO_DEVICE_API_VERSION_2_0;
    wrapper->public_device.common.module = const_cast<hw_module_t*>(module);
    wrapper->public_device.common.close = m86_device_close;
    wrapper->public_device.get_supported_devices = m86_get_supported_devices;
    wrapper->public_device.init_check = m86_init_check;
    wrapper->public_device.set_voice_volume = m86_set_voice_volume;
    wrapper->public_device.set_master_volume = m86_set_master_volume;
    wrapper->public_device.get_master_volume = m86_get_master_volume;
    wrapper->public_device.set_mode = m86_set_mode;
    wrapper->public_device.set_mic_mute = m86_set_mic_mute;
    wrapper->public_device.get_mic_mute = m86_get_mic_mute;
    wrapper->public_device.set_headphone_volume = m86_set_headphone_volume;
    wrapper->public_device.set_parameters = m86_set_parameters;
    wrapper->public_device.get_parameters = m86_get_parameters;
    wrapper->public_device.get_input_buffer_size = m86_get_input_buffer_size;
    wrapper->public_device.open_output_stream = m86_open_output;
    wrapper->public_device.close_output_stream = m86_close_output;
    wrapper->public_device.open_input_stream = m86_open_input;
    wrapper->public_device.close_input_stream = m86_close_input;
    wrapper->public_device.get_microphones = m86_get_microphones;
    wrapper->public_device.dump = m86_dump;
    wrapper->public_device.set_master_mute = m86_set_master_mute;
    wrapper->public_device.get_master_mute = m86_get_master_mute;
    wrapper->public_device.create_audio_patch = m86_create_audio_patch;
    wrapper->public_device.release_audio_patch = m86_release_audio_patch;
    wrapper->public_device.get_audio_port = m86_get_audio_port;
    wrapper->public_device.set_audio_port_config = m86_set_audio_port_config;
    *device = &wrapper->public_device.common;
    return 0;
}

static hw_module_methods_t g_methods = {
    .open = m86_module_open,
};

}  // namespace

extern "C" struct audio_module HAL_MODULE_INFO_SYM = {
    {
        HARDWARE_MODULE_TAG,
        AUDIO_MODULE_API_VERSION_0_1,
        HARDWARE_HAL_API_VERSION,
        AUDIO_HARDWARE_MODULE_ID,
        "Meizu PRO 5 m86 audio wrapper",
        "LineageOS",
        &g_methods,
        nullptr,
    },
};
