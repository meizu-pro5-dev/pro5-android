/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 *
 * Keep the imported lineage-19.1-old-r15 mapper byte-clean. Its legacy log
 * statements use format specifiers that are valid for the original 32-bit
 * build but trigger -Wformat under the arm64 compiler. Scope the compatibility
 * exception to that imported translation unit instead of weakening warnings
 * for gralloc.m86.
 */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat"
#include "hardware/meizu/m86/graphics/gralloc/a10-contract/mapper.cpp"
#pragma clang diagnostic pop
