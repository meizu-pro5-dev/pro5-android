#!/usr/bin/env bash

set -euo pipefail

product_out="${1:?product output directory is required}"
system_root="$product_out/system"

[[ -d "$system_root" ]] || {
  printf 'Built system tree is missing: %s\n' "$system_root" >&2
  exit 1
}

for forbidden_relative in \
  app/020a0000000000000000000000000000.drbin \
  app/mcRegistry/04010000000000000000000000000000.tlbin \
  app/mcRegistry/04020000000000000000000000000000.tlbin \
  app/mcRegistry/07020000000000000000000000000000.tlbin \
  app/mcRegistry/07060000000000000000000000000000.tlbin \
  app/mcRegistry/07061000000000000000000000000000.tlbin \
  bin/mcDriverDaemon \
  lib64/hw/fingerprint.m86.so \
  lib64/lib_fpc_tac_shared.so \
  vendor/firmware/libpn547_fw.so \
  vendor/lib/libMcClient.so \
  vendor/lib/libMcRegistry.so \
  vendor/lib64/libMcClient.so \
  vendor/lib64/libMcRegistry.so \
  vendor/etc/permissions/android.hardware.fingerprint.xml \
  vendor/etc/permissions/android.hardware.nfc.hce.xml \
  vendor/etc/permissions/android.hardware.nfc.xml \
  vendor/etc/permissions/com.android.nfc_extras.xml \
  vendor/etc/init/init.m86.nfc-experiment.rc \
  vendor/etc/init/init.m86.fingerprint-experiment.rc \
  vendor/bin/hw/android.hardware.nfc@1.1-service \
  vendor/bin/hw/android.hardware.nfc@1.2-service \
  vendor/bin/hw/android.hardware.biometrics.fingerprint@2.1-service; do
  if [[ -e "$system_root/$forbidden_relative" ]]; then
    printf 'Default product installed deferred experiment output: %s\n' \
      "$forbidden_relative" >&2
    exit 1
  fi
done

for forbidden_apk in NfcNci.apk Tag.apk; do
  if find "$system_root" -type f -name "$forbidden_apk" -print -quit | \
      grep -q .; then
    printf 'Default product installed deferred experiment APK: %s\n' \
      "$forbidden_apk" >&2
    exit 1
  fi
done

while IFS= read -r vintf_file; do
  if rg -q \
      'android\.hardware\.(biometrics\.fingerprint|nfc)|vendor\.nxp\.nxpnfc' \
      "$vintf_file"; then
    printf 'Default product VINTF declares a deferred experiment: %s\n' \
      "$vintf_file" >&2
    exit 1
  fi
done < <(find "$system_root/vendor" -type f \
  \( -name 'manifest*.xml' -o -path '*/vintf/*.xml' \) -print 2>/dev/null)

for property_file in \
  "$system_root/build.prop" \
  "$system_root/vendor/build.prop"; do
  if [[ -f "$property_file" ]] && \
      rg -q '^ro\.nfc\.(platform|port)=' "$property_file"; then
    printf 'Default product publishes deferred NFC properties: %s\n' \
      "$property_file" >&2
    exit 1
  fi
done

printf 'Default NFC/fingerprint output absence audit passed.\n'
