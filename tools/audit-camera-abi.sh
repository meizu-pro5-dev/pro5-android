#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 3 ]]; then
  printf 'Usage: %s <lineage-source-root> <out-root> <libm86camera_shim.so>\n' \
    "${0##*/}" >&2
  exit 2
fi

source_root="$1"
out_root="$2"
camera_shim="$3"
vendor_lib_root="$source_root/vendor/meizu/m86/proprietary/lib"
camera_hal="$vendor_lib_root/hw/camera.m86.so"
camera_core="$vendor_lib_root/libexynoscamera.so"
audit_root="$(mktemp -d /tmp/pro5-camera-abi.XXXXXX)"

cleanup() {
  rm -rf -- "$audit_root"
}
trap cleanup EXIT

for required_input in \
  "$camera_hal" \
  "$camera_core" \
  "$camera_shim"; do
  if [[ ! -s "$required_input" ]]; then
    printf 'Missing camera ABI input: %s\n' "$required_input" >&2
    exit 1
  fi
done

require_sha256() {
  local expected="$1"
  local source_file="$2"
  local actual

  actual="$(sha256sum "$source_file" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    printf 'Camera blob SHA-256 mismatch for %s: expected %s, got %s\n' \
      "$source_file" "$expected" "$actual" >&2
    exit 1
  fi
}

require_sha256 \
  f04fd70069e88822bca2c8c8650f0d823c3da4f4c573ae8b0f170775c830d250 \
  "$camera_hal"
require_sha256 \
  f82f5fead94fe3c187da0bcf5aa6ce121c3ff3922e78568bd49eedcc7110f15f \
  "$camera_core"

for elf_file in "$camera_hal" "$camera_core" "$camera_shim"; do
  if ! readelf -h "$elf_file" | rg -q 'Class:[[:space:]]+ELF32'; then
    printf 'Camera ABI input is not ELF32: %s\n' "$elf_file" >&2
    exit 1
  fi
done

if ! nm -D --defined-only "$camera_hal" | awk '$NF == "HMI" { found=1 } END { exit !found }'; then
  printf 'The Flyme camera HAL does not export HAL_MODULE_INFO_SYM (HMI).\n' >&2
  exit 1
fi

if ! readelf -d "$camera_shim" |
    rg -q 'Shared library: \[libsensor\.so\]'; then
  printf 'The m86 camera shim must retain its explicit libsensor dependency.\n' >&2
  exit 1
fi

mapfile -t shim_exports < <(
  nm -D --defined-only "$camera_shim" | awk '{print $NF}' | LC_ALL=C sort -u
)
for required_symbol in \
  androidGetTid \
  set_value \
  _ZN7android5FenceD1Ev \
  _ZNK7android10GLConsumer16getCurrentBufferEv \
  _ZN7android13GraphicBuffer4lockEjPPv \
  _ZN7android16CameraParameters17EFFECT_POINT_BLUEE \
  _ZN7android16CameraParameters26PIXEL_FORMAT_YUV420SP_NV21E; do
  if ! printf '%s\n' "${shim_exports[@]}" | rg -F -x -q "$required_symbol"; then
    printf 'Missing m86 camera shim export: %s\n' "$required_symbol" >&2
    exit 1
  fi
done

resolve_library() {
  local soname="$1"
  local candidate

  for candidate in \
    "$vendor_lib_root/$soname" \
    "$out_root/target/product/m86/symbols/system/lib/$soname" \
    "$out_root/target/product/m86/system/lib/$soname"; do
    if [[ -s "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  candidate="$(
    find "$out_root/soong/.intermediates" -type f \
      -path "*/android_arm_*shared/unstripped/$soname" -print -quit
  )"
  if [[ -n "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  printf 'Cannot resolve camera dependency from current output: %s\n' \
    "$soname" >&2
  return 1
}

append_exports() {
  local elf_file="$1"
  local destination="$2"

  nm -D --defined-only "$elf_file" 2>/dev/null |
    awk '{name=$NF; sub(/@.*/, "", name); if (name != "") print name}' \
      >> "$destination"
}

audit_target() {
  local label="$1"
  local target_file="$2"
  shift 2
  local undefined_file="$audit_root/$label.undefined"
  local defined_file="$audit_root/$label.defined"
  local missing_file="$audit_root/$label.missing"
  local soname
  local dependency

  nm -D -u "$target_file" |
    awk '{name=$NF; sub(/@.*/, "", name); if (name != "") print name}' |
    LC_ALL=C sort -u > "$undefined_file"
  : > "$defined_file"

  while IFS= read -r soname; do
    dependency="$(resolve_library "$soname")"
    append_exports "$dependency" "$defined_file"
  done < <(
    readelf -d "$target_file" |
      sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'
  )

  for dependency in "$@"; do
    append_exports "$dependency" "$defined_file"
  done

  LC_ALL=C sort -u -o "$defined_file" "$defined_file"
  comm -23 "$undefined_file" "$defined_file" > "$missing_file"
  if [[ -s "$missing_file" ]]; then
    printf 'Unresolved %s camera imports:\n' "$label" >&2
    sed 's/^/  /' "$missing_file" >&2
    return 1
  fi

  printf '%s: %s imports, 0 unresolved\n' \
    "$label" "$(wc -l < "$undefined_file" | tr -d ' ')"
}

sensor_lib="$(resolve_library libsensor.so)"
audit_target camera-hal "$camera_hal"
audit_target camera-core "$camera_core" "$sensor_lib" "$camera_shim"
printf 'm86 camera ABI closure passed.\n'
