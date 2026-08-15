#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -lt 1 ]] || [[ "$#" -gt 2 ]]; then
  printf 'Usage: %s <product-out> [absent|experiment]\n' "${0##*/}" >&2
  exit 2
fi

product_out="$1"
mode="${2:-absent}"
vendor_out="$product_out/system/vendor"
system_out="$product_out/system"
fingerprint_hal="$system_out/lib64/hw/fingerprint.m86.so"
fingerprint_flyme_hal="$system_out/lib64/hw/fingerprint.m86.flyme.so"
fingerprint_tac="$system_out/lib64/lib_fpc_tac_shared.so"
mc_daemon="$system_out/bin/mcDriverDaemon"
mc_driver="$system_out/app/020a0000000000000000000000000000.drbin"
fingerprint_ta="$system_out/app/mcRegistry/04010000000000000000000000000000.tlbin"
fingerprint_service="$vendor_out/bin/hw/android.hardware.biometrics.fingerprint@2.1-service"
fingerprint_rc="$vendor_out/etc/init/android.hardware.biometrics.fingerprint@2.1-service.rc"
vendor_manifest="$vendor_out/etc/vintf/manifest.xml"
fingerprint_permission="$vendor_out/etc/permissions/android.hardware.fingerprint.xml"
shadow_fingerprint_hal="$vendor_out/lib64/hw/fingerprint.m86.so"
gatekeeper_hal32="$system_out/lib/hw/gatekeeper.m86.so"
gatekeeper_hal64="$system_out/lib64/hw/gatekeeper.m86.so"
gatekeeper_service="$vendor_out/bin/hw/android.hardware.gatekeeper@1.0-service.m86"
gatekeeper_service_rc="$vendor_out/etc/init/android.hardware.gatekeeper@1.0-service.m86.rc"
gatekeeper_impl="$vendor_out/lib64/hw/android.hardware.gatekeeper@1.0-impl.so"
generic_gatekeeper_service="$vendor_out/bin/hw/android.hardware.gatekeeper@1.0-service"
generic_gatekeeper_service_rc="$vendor_out/etc/init/android.hardware.gatekeeper@1.0-service.rc"

case "$mode" in
  absent)
    for forbidden_output in \
      "$fingerprint_hal" \
      "$fingerprint_flyme_hal" \
      "$fingerprint_tac" \
      "$mc_daemon" \
      "$mc_driver" \
      "$fingerprint_ta" \
      "$fingerprint_service" \
      "$fingerprint_rc" \
      "$fingerprint_permission" \
      "$shadow_fingerprint_hal" \
      "$gatekeeper_hal32" \
      "$gatekeeper_hal64" \
      "$gatekeeper_service" \
      "$gatekeeper_service_rc" \
      "$generic_gatekeeper_service" \
      "$generic_gatekeeper_service_rc" \
      "$gatekeeper_impl"; do
      if [[ -e "$forbidden_output" ]]; then
        printf 'Default product exposes deferred fingerprint output: %s\n' \
          "$forbidden_output" >&2
        exit 1
      fi
    done
    if [[ -f "$vendor_manifest" ]] && \
        grep -F -q '<name>android.hardware.biometrics.fingerprint</name>' \
          "$vendor_manifest"; then
      printf 'Default product declares the deferred fingerprint HAL.\n' >&2
      exit 1
    fi
    printf 'fingerprint_default=hidden\n'
    printf 'fingerprint output absence audit passed.\n'
    exit 0
    ;;
  experiment) ;;
  *)
    printf 'Unsupported fingerprint audit mode: %s\n' "$mode" >&2
    exit 2
    ;;
esac

if [[ -e "$shadow_fingerprint_hal" ]]; then
  printf 'A higher-priority vendor fingerprint HAL shadows Flyme 8: %s\n' \
    "$shadow_fingerprint_hal" >&2
  exit 1
fi

for retired_gatekeeper_output in \
  "$generic_gatekeeper_service" \
  "$generic_gatekeeper_service_rc"; do
  if [[ -e "$retired_gatekeeper_output" ]]; then
    printf 'Generic Gatekeeper output competes with the m86 service: %s\n' \
      "$retired_gatekeeper_output" >&2
    exit 1
  fi
done

for required_output in \
  "$fingerprint_hal" \
  "$fingerprint_flyme_hal" \
  "$fingerprint_tac" \
  "$mc_daemon" \
  "$mc_driver" \
  "$fingerprint_ta" \
  "$fingerprint_service" \
  "$fingerprint_rc" \
  "$vendor_manifest" \
  "$fingerprint_permission" \
  "$gatekeeper_hal32" \
  "$gatekeeper_hal64" \
  "$gatekeeper_service" \
  "$gatekeeper_service_rc" \
  "$gatekeeper_impl"; do
  if [[ ! -s "$required_output" ]]; then
    printf 'Missing fingerprint output: %s\n' "$required_output" >&2
    exit 1
  fi
done

for elf_file in "$fingerprint_hal" "$fingerprint_flyme_hal" \
  "$fingerprint_tac" "$mc_daemon" \
  "$fingerprint_service" "$gatekeeper_hal64" "$gatekeeper_service" \
  "$gatekeeper_impl"; do
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

for fingerprint_module in "$fingerprint_hal" "$fingerprint_flyme_hal"; do
  if ! nm -D --defined-only "$fingerprint_module" |
      awk '$NF == "HMI" { found=1 } END { exit !found }'; then
    printf 'The m86 fingerprint HAL does not export HMI: %s\n' \
      "$fingerprint_module" >&2
    exit 1
  fi
done

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

require_needed "$fingerprint_hal" libdl.so
require_needed "$fingerprint_flyme_hal" lib_fpc_tac_shared.so
require_needed "$fingerprint_tac" libMcClient.so
require_needed "$fingerprint_service" \
  android.hardware.biometrics.fingerprint@2.1.so
require_needed "$fingerprint_service" libhardware.so

if strings "$fingerprint_flyme_hal" | grep -F -q '/dev/fpc1020'; then
  printf 'The active fingerprint HAL still contains the raw FPC1020 backend.\n' >&2
  exit 1
fi
if ! strings "$fingerprint_hal" | \
    grep -F -q '/system/lib64/hw/fingerprint.m86.flyme.so'; then
  printf 'Fingerprint compatibility HAL omits its locked Flyme provider.\n' >&2
  exit 1
fi
if ! strings "$fingerprint_hal" | \
    grep -F -q 'Remapped Flyme fingerprint callbacks to the AOSP 2.1 ABI'; then
  printf 'Fingerprint compatibility HAL omits its ABI remap marker.\n' >&2
  exit 1
fi

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

for gatekeeper_contract in \
  '<name>android.hardware.gatekeeper</name>' \
  '<version>1.0</version>' \
  '<name>IGatekeeper</name>'; do
  if ! grep -F -q "$gatekeeper_contract" "$vendor_manifest"; then
    printf 'Vendor manifest omits gatekeeper contract: %s\n' \
      "$gatekeeper_contract" >&2
    exit 1
  fi
done
if ! grep -F -q \
    'service vendor.gatekeeper-1-0 /vendor/bin/hw/android.hardware.gatekeeper@1.0-service.m86' \
    "$gatekeeper_service_rc"; then
  printf 'Gatekeeper service rc has an unexpected service command.\n' >&2
  exit 1
fi
if ! strings "$gatekeeper_service" | \
    grep -F -q '/data/misc/gatekeeper'; then
  printf 'Gatekeeper service does not enter the legacy retry-record directory.\n' >&2
  exit 1
fi
require_needed "$gatekeeper_hal64" libMcClient.so
require_needed "$gatekeeper_hal64" libgatekeeper.so
require_needed "$gatekeeper_impl" libhardware.so

printf 'gatekeeper_hal32_sha256=%s\n' \
  "$(sha256sum "$gatekeeper_hal32" | awk '{ print $1 }')"
printf 'gatekeeper_hal64_sha256=%s\n' \
  "$(sha256sum "$gatekeeper_hal64" | awk '{ print $1 }')"
if [[ "$(sha256sum "$gatekeeper_hal32" | awk '{ print $1 }')" != \
    "651cc8076212f7f151fb40bd2006b5bb044cb1cd839a6ccbd7aa63aa94f06bf2" ]] || \
   [[ "$(sha256sum "$gatekeeper_hal64" | awk '{ print $1 }')" != \
    "c7c34c727ce0a5b219873c8092c9b497a264ef92f71cc90062e5a4da9079467b" ]]; then
  printf 'Gatekeeper HAL does not match Flyme 8.0.5.0A.\n' >&2
  exit 1
fi

printf 'fingerprint_hal_sha256=%s\n' \
  "$(sha256sum "$fingerprint_hal" | awk '{ print $1 }')"
printf 'fingerprint_flyme_hal_sha256=%s\n' \
  "$(sha256sum "$fingerprint_flyme_hal" | awk '{ print $1 }')"
if [[ "$(sha256sum "$fingerprint_flyme_hal" | awk '{ print $1 }')" != \
    "aff55391dbc02df8657257d917ed83a56f6a19fe6a9a8834eba5e54d8df58fbe" ]]; then
  printf 'Fingerprint provider does not match Flyme 8.0.5.0A.\n' >&2
  exit 1
fi
if [[ "$(sha256sum "$fingerprint_tac" | awk '{ print $1 }')" != \
    "3915223313767fcd30c84b1cb41a1c975fd4fe52e90f03e7e3c082d1cdfdd09c" ]]; then
  printf 'Fingerprint TAC does not match Flyme 8.0.5.0A.\n' >&2
  exit 1
fi
if [[ "$(sha256sum "$fingerprint_ta" | awk '{ print $1 }')" != \
    "8aa172d0d34428151fa10d8232e56c8ef664e159e96a88a2477cd1718d05851f" ]]; then
  printf 'Fingerprint TA does not match Flyme 8.0.5.0A.\n' >&2
  exit 1
fi
printf 'fingerprint_tac_sha256=%s\n' \
  "$(sha256sum "$fingerprint_tac" | awk '{ print $1 }')"
printf 'fingerprint_ta_sha256=%s\n' \
  "$(sha256sum "$fingerprint_ta" | awk '{ print $1 }')"
printf 'fingerprint_service_sha256=%s\n' \
  "$(sha256sum "$fingerprint_service" | awk '{ print $1 }')"
printf 'gatekeeper_service_sha256=%s\n' \
  "$(sha256sum "$gatekeeper_service" | awk '{ print $1 }')"
printf 'gatekeeper_retry_record_directory=/data/misc/gatekeeper\n'
printf 'fingerprint_abi=ELF64 AArch64\n'
printf 'fingerprint_legacy_abi=Flyme callbacks remapped to AOSP 2.1\n'
printf 'fingerprint_hidl=2.1/default\n'
printf 'fingerprint_backend=Flyme8 FPC Trustonic secure world\n'
printf 'fingerprint output audit passed.\n'
