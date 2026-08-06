#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  printf 'Usage: %s <product-out>\n' "${0##*/}" >&2
  exit 2
fi

product_out="$1"
vendor_out="$product_out/system/vendor"
fingerprint_hal="$vendor_out/lib64/hw/fingerprint.m86.so"
fingerprint_service="$vendor_out/bin/hw/android.hardware.biometrics.fingerprint@2.1-service"
fingerprint_rc="$vendor_out/etc/init/android.hardware.biometrics.fingerprint@2.1-service.rc"
vendor_manifest="$vendor_out/etc/vintf/manifest.xml"
fingerprint_permission="$vendor_out/etc/permissions/android.hardware.fingerprint.xml"

for required_output in \
  "$fingerprint_hal" \
  "$fingerprint_service" \
  "$fingerprint_rc" \
  "$vendor_manifest" \
  "$fingerprint_permission"; do
  if [[ ! -s "$required_output" ]]; then
    printf 'Missing fingerprint output: %s\n' "$required_output" >&2
    exit 1
  fi
done

for elf_file in "$fingerprint_hal" "$fingerprint_service"; do
  if ! readelf -h "$elf_file" | \
      grep -Eq 'Class:[[:space:]]+ELF64'; then
    printf 'Fingerprint output is not ELF64: %s\n' "$elf_file" >&2
    exit 1
  fi
  if ! readelf -h "$elf_file" | \
      grep -Eq 'Machine:[[:space:]]+AArch64'; then
    printf 'Fingerprint output is not AArch64: %s\n' "$elf_file" >&2
    exit 1
  fi
done

if ! nm -D --defined-only "$fingerprint_hal" |
    awk '$NF == "HMI" { found=1 } END { exit !found }'; then
  printf 'The m86 fingerprint HAL does not export HMI.\n' >&2
  exit 1
fi

require_needed() {
  local elf_file="$1"
  local soname="$2"

  if ! readelf -d "$elf_file" |
      grep -F -q "Shared library: [$soname]"; then
    printf 'Fingerprint output %s does not need %s.\n' \
      "$elf_file" "$soname" >&2
    exit 1
  fi
}

require_needed "$fingerprint_hal" libglib.so
require_needed "$fingerprint_service" \
  android.hardware.biometrics.fingerprint@2.1.so
require_needed "$fingerprint_service" libhardware.so

for manifest_contract in \
  '<name>android.hardware.biometrics.fingerprint</name>' \
  '<version>2.1</version>' \
  '<name>IBiometricsFingerprint</name>' \
  '<instance>default</instance>'; do
  if ! grep -F -q "$manifest_contract" "$vendor_manifest"; then
    printf 'Vendor manifest omits fingerprint contract: %s\n' \
      "$manifest_contract" >&2
    exit 1
  fi
done

if ! grep -F -q \
    'service vendor.fps_hal /vendor/bin/hw/android.hardware.biometrics.fingerprint@2.1-service' \
    "$fingerprint_rc"; then
  printf 'Fingerprint service rc has an unexpected service command.\n' >&2
  exit 1
fi
if ! grep -F -q '<feature name="android.hardware.fingerprint"' \
    "$fingerprint_permission"; then
  printf 'Fingerprint feature permission is missing.\n' >&2
  exit 1
fi

printf 'fingerprint_hal_sha256=%s\n' \
  "$(sha256sum "$fingerprint_hal" | awk '{ print $1 }')"
printf 'fingerprint_service_sha256=%s\n' \
  "$(sha256sum "$fingerprint_service" | awk '{ print $1 }')"
printf 'fingerprint_abi=ELF64 AArch64\n'
printf 'fingerprint_hidl=2.1/default\n'
printf 'fingerprint output audit passed.\n'
