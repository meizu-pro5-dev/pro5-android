/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#include <cstddef>
#include <cstdint>

namespace m86::audio {

// These are serialized 32-bit Flyme ABI layouts, not public Android structs.
// Use fixed-width fields so the contract can be compiled and reviewed on a
// 64-bit host without pretending the proprietary object is host-loadable.
using FlymePtr32 = std::uint32_t;

struct FlymeAudioHwDeviceV2Layout {
    std::uint8_t public_prefix[96];
    FlymePtr32 vendor_reserved0;
    FlymePtr32 vendor_reserved1;
    FlymePtr32 set_headphone_volume;
    FlymePtr32 set_parameters;
    FlymePtr32 get_parameters;
    FlymePtr32 get_input_buffer_size;
    FlymePtr32 open_output_stream;
    FlymePtr32 close_output_stream;
    FlymePtr32 open_input_stream;
    FlymePtr32 close_input_stream;
    FlymePtr32 legacy_dump;
};

struct FlymeStreamOutV2Layout {
    std::uint8_t callbacks_through_presentation_position[100];
    FlymePtr32 private_reserved[4];
    std::uint32_t pcm_config_channels;
};

struct FlymeStreamInV2Layout {
    std::uint8_t callbacks_through_frames_lost[68];
    std::uint8_t private_state[108];
};

static_assert(sizeof(FlymePtr32) == 4);
static_assert(offsetof(FlymeAudioHwDeviceV2Layout, vendor_reserved0) == 96);
static_assert(offsetof(FlymeAudioHwDeviceV2Layout, vendor_reserved1) == 100);
static_assert(offsetof(FlymeAudioHwDeviceV2Layout, set_headphone_volume) == 104);
static_assert(offsetof(FlymeAudioHwDeviceV2Layout, set_parameters) == 108);
static_assert(offsetof(FlymeAudioHwDeviceV2Layout, get_parameters) == 112);
static_assert(offsetof(FlymeAudioHwDeviceV2Layout, get_input_buffer_size) == 116);
static_assert(offsetof(FlymeAudioHwDeviceV2Layout, open_output_stream) == 120);
static_assert(offsetof(FlymeAudioHwDeviceV2Layout, close_output_stream) == 124);
static_assert(offsetof(FlymeAudioHwDeviceV2Layout, open_input_stream) == 128);
static_assert(offsetof(FlymeAudioHwDeviceV2Layout, close_input_stream) == 132);
static_assert(offsetof(FlymeAudioHwDeviceV2Layout, legacy_dump) == 136);
static_assert(sizeof(FlymeAudioHwDeviceV2Layout) == 140);
static_assert(offsetof(FlymeStreamOutV2Layout, pcm_config_channels) == 116);
static_assert(sizeof(FlymeStreamOutV2Layout) == 120);
static_assert(sizeof(FlymeStreamInV2Layout) == 176);

inline constexpr std::uint32_t kFlymeDeviceAllocationSize = 0x140;
inline constexpr std::uint32_t kFlymeOutputAllocationSize = 0xe0;
inline constexpr std::uint32_t kFlymeInputAllocationSize = 176;
inline constexpr std::uint32_t kFlymeAudioDeviceVersion = 0x200;
inline constexpr std::uint32_t kObservedOutputMetadataAlias = 0x2;

}  // namespace m86::audio
