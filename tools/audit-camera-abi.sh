#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  printf 'Usage: %s <product-out>\n' "${0##*/}" >&2
  exit 2
fi

product_out="$1"
camera_hal="$product_out/system/lib/hw/camera.m86.so"
camera_engine="$product_out/system/lib/libexynoscamera3_m86.so"
camera_hal_obj="$product_out/obj_arm/SHARED_LIBRARIES/camera.m86_intermediates/camera.m86.so"
camera_engine_obj="$product_out/obj_arm/SHARED_LIBRARIES/libexynoscamera3_m86_intermediates/libexynoscamera3_m86.so"

for required_input in \
  "$camera_hal" \
  "$camera_engine" \
  "$camera_hal_obj" \
  "$camera_engine_obj"; do
  if [[ ! -s "$required_input" ]]; then
    printf 'Missing native HAL3 output: %s\n' "$required_input" >&2
    exit 1
  fi
done

for elf_file in "$camera_hal" "$camera_engine"; do
  elf_header="$(readelf -h "$elf_file")"
  if ! grep -Eq 'Class:[[:space:]]+ELF32' <<<"$elf_header"; then
    printf 'Native HAL3 output is not ELF32: %s\n' "$elf_file" >&2
    exit 1
  fi
done

if ! nm -D --defined-only "$camera_hal" |
    awk '$NF == "HMI" { found=1 } END { exit !found }'; then
  printf 'Native camera HAL does not export HAL_MODULE_INFO_SYM (HMI).\n' >&2
  exit 1
fi

camera_hal_dynamic="$(readelf -d "$camera_hal")"
camera_engine_dynamic="$(readelf -d "$camera_engine")"
if ! grep -Fq 'Shared library: [libexynoscamera3_m86.so]' \
    <<<"$camera_hal_dynamic"; then
  printf 'camera.m86 does not link the native m86 Camera3 engine.\n' >&2
  exit 1
fi

for forbidden in \
  libexynoscamera.so \
  libm86camera3_bridge.so \
  libm86camera_shim.so; do
  if grep -Fq "Shared library: [$forbidden]" \
      <<<"$camera_hal_dynamic$camera_engine_dynamic"; then
    printf 'Native HAL3 output retains retired dependency: %s\n' "$forbidden" >&2
    exit 1
  fi
done

if ! cmp --quiet "$camera_hal" "$camera_hal_obj"; then
  printf 'Installed camera.m86 is not the source-built native HAL3 output.\n' >&2
  exit 1
fi
if ! cmp --quiet "$camera_engine" "$camera_engine_obj"; then
  printf 'Installed libexynoscamera3_m86 is not the source-built output.\n' >&2
  exit 1
fi

printf 'camera_hal=%s\n' "$camera_hal"
printf 'camera_engine=%s\n' "$camera_engine"
printf 'camera_abi=ELF32\n'
printf 'camera_route=native-exynos-hal3\n'
