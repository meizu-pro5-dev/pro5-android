/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 *
 * The imported chooser has one legacy uint64_t log specifier that is rejected
 * by the A10 arm64 -Werror build.  Keep that source unchanged and scope the
 * warning compatibility to this translation unit.
 */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat"
#include "hardware/samsung_slsi/exynos/gralloc/format_chooser.cpp"
#pragma clang diagnostic pop
