/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 *
 * The imported lineage-19.1-old-r15 chooser has one legacy uint64_t log
 * specifier that is rejected by the arm64 -Werror build. Keep that source
 * unchanged and scope the warning compatibility to this translation unit.
 */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat"
#include "hardware/meizu/m86/graphics/gralloc/a10-contract/format_chooser.cpp"
#pragma clang diagnostic pop
