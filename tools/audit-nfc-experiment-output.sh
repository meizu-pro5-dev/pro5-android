#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -lt 2 ]] || [[ "$#" -gt 3 ]]; then
  printf 'Usage: %s <product-out-or-target-files> <product-out|target-files> [source-root]\n' \
    "${0##*/}" >&2
  exit 2
fi

output_root="$1"
layout="$2"
source_root="${3:-}"

case "$layout" in
  product-out)
    system_root="$output_root/system"
    vendor_root="$system_root/vendor"
    ;;
  target-files)
    system_root="$output_root/SYSTEM"
    vendor_root="$system_root/vendor"
    if [[ ! -d "$vendor_root" && -d "$output_root/VENDOR" ]]; then
      vendor_root="$output_root/VENDOR"
    fi
    ;;
  *)
    printf 'Unsupported NFC audit layout: %s\n' "$layout" >&2
    exit 2
    ;;
esac

require_regular_file() {
  local path="$1"

  if [[ ! -s "$path" ]]; then
    printf 'Missing NFC experiment output: %s\n' "$path" >&2
    exit 1
  fi
}

require_unique_name() {
  local root="$1"
  local name="$2"
  local label="$3"
  local -a matches=()

  mapfile -t matches < <(
    find "$root" -type f -name "$name" -print 2>/dev/null | LC_ALL=C sort
  )
  if [[ "${#matches[@]}" -ne 1 ]]; then
    printf 'Expected one %s named %s, found %s.\n' \
      "$label" "$name" "${#matches[@]}" >&2
    printf '  %s\n' "${matches[@]:-none}" >&2
    exit 1
  fi
  printf '%s\n' "${matches[0]}"
}

[[ -d "$system_root" ]] || {
  printf 'NFC audit system tree is missing: %s\n' "$system_root" >&2
  exit 1
}
[[ -d "$vendor_root" ]] || {
  printf 'NFC audit vendor tree is missing: %s\n' "$vendor_root" >&2
  exit 1
}

nfc_service="$vendor_root/bin/hw/android.hardware.nfc@1.1-service"
nfc_firmware="$vendor_root/firmware/libpn547_fw.so"
nfc_config="$vendor_root/etc/libnfc-nxp.conf"
nci_config="$vendor_root/etc/libnfc-nci.conf"
nfc_experiment_init="$vendor_root/etc/init/init.m86.nfc-experiment.rc"
nfc_nci_library_32="$vendor_root/lib/nfc_nci_nxp.so"
nfc_nci_library_64="$vendor_root/lib64/nfc_nci_nxp.so"
nci_framework_library="$system_root/lib64/libnfc-nci.so"
nci_jni_library="$system_root/lib64/libnfc_nci_jni.so"
require_regular_file "$nfc_service"
require_regular_file "$nfc_firmware"
require_regular_file "$nfc_config"
require_regular_file "$nci_config"
require_regular_file "$nfc_experiment_init"
require_regular_file "$nfc_nci_library_32"
require_regular_file "$nfc_nci_library_64"
require_regular_file "$nci_framework_library"
require_regular_file "$nci_jni_library"

if ! grep -F -x -q 'NXP_ESE_CLIENT_ENABLE=0x00' "$nfc_config"; then
  printf 'NFC reader/HCE output must disable the optional eSE client bridge.\n' >&2
  exit 1
fi

mapfile -t nfc_service_files < <(
  find "$vendor_root/bin/hw" -maxdepth 1 -type f \
    -name 'android.hardware.nfc@*-service' -print 2>/dev/null | LC_ALL=C sort
)
if [[ "${#nfc_service_files[@]}" -ne 1 || \
      "${nfc_service_files[0]:-}" != "$nfc_service" ]]; then
  printf 'NFC experiment service ownership is not unique.\n' >&2
  printf '  %s\n' "${nfc_service_files[@]:-none}" >&2
  exit 1
fi

if ! readelf -h "$nfc_service" | grep -Eq 'Class:[[:space:]]+ELF64' || \
    ! readelf -h "$nfc_service" | grep -Eq 'Machine:[[:space:]]+AArch64'; then
  printf 'NFC service is not an AArch64 ELF64 binary: %s\n' "$nfc_service" >&2
  exit 1
fi

if ! readelf -d "$nfc_service" | \
    grep -F -q 'Shared library: [nfc_nci_nxp.so]'; then
  printf 'NFC service does not link its NXP HAL library: %s\n' "$nfc_service" >&2
  exit 1
fi
if ! readelf -h "$nfc_nci_library_32" | grep -Eq 'Class:[[:space:]]+ELF32' || \
    ! readelf -h "$nfc_nci_library_32" | grep -Eq 'Machine:[[:space:]]+ARM'; then
  printf 'NFC 32-bit NXP HAL library has the wrong ABI: %s\n' \
    "$nfc_nci_library_32" >&2
  exit 1
fi
if ! readelf -h "$nfc_nci_library_64" | grep -Eq 'Class:[[:space:]]+ELF64' || \
    ! readelf -h "$nfc_nci_library_64" | grep -Eq 'Machine:[[:space:]]+AArch64'; then
  printf 'NFC 64-bit NXP HAL library has the wrong ABI: %s\n' \
    "$nfc_nci_library_64" >&2
  exit 1
fi
if ! readelf -h "$nci_framework_library" | grep -Eq 'Class:[[:space:]]+ELF64' || \
    ! readelf -h "$nci_jni_library" | grep -Eq 'Class:[[:space:]]+ELF64'; then
  printf 'NFC framework/JNI library has the wrong ABI.\n' >&2
  exit 1
fi

for apk_name in NfcNci.apk Tag.apk; do
  apk_path="$(require_unique_name "$system_root" "$apk_name" 'NFC APK')"
  if ! unzip -tq "$apk_path" >/dev/null; then
    printf 'NFC APK is not a valid ZIP/APK: %s\n' "$apk_path" >&2
    exit 1
  fi
done

for permission_name in \
  android.hardware.nfc.hce.xml \
  android.hardware.nfc.xml; do
  permission_file="$vendor_root/etc/permissions/$permission_name"
  require_regular_file "$permission_file"
  if ! grep -F -q '<feature name=' "$permission_file"; then
    printf 'NFC feature declaration is missing: %s\n' "$permission_file" >&2
    exit 1
  fi
done
nfc_extras_permission="$vendor_root/etc/permissions/com.android.nfc_extras.xml"
require_regular_file "$nfc_extras_permission"
if ! grep -F -q '<library name="com.android.nfc_extras"' \
    "$nfc_extras_permission"; then
  printf 'NFC extras library declaration is missing: %s\n' \
    "$nfc_extras_permission" >&2
  exit 1
fi

mapfile -t nfc_service_rc_files < <(
  find "$vendor_root/etc/init" -type f \
    -exec grep -F -a -l -- \
      'service vendor.nfc_hal_service /vendor/bin/hw/android.hardware.nfc@1.1-service' {} + \
    2>/dev/null | LC_ALL=C sort
)
if [[ "${#nfc_service_rc_files[@]}" -ne 1 ]] || \
    [[ "${nfc_service_rc_files[0]:-}" != \
       "$vendor_root/etc/init/android.hardware.nfc@1.1-service.rc" ]]; then
  printf 'NFC init service owner is not unique.\n' >&2
  printf '  %s\n' "${nfc_service_rc_files[@]:-none}" >&2
  exit 1
fi

for required_init_line in \
  'restorecon_recursive /data/nfc' \
  'restorecon_recursive /data/vendor/nfc' \
  'chown nfc nfc /dev/pn544' \
  'chmod 0660 /dev/pn544'; do
  if ! grep -F -x -q "    $required_init_line" "$nfc_experiment_init"; then
    printf 'NFC experiment init contract is missing: %s\n' "$required_init_line" >&2
    exit 1
  fi
done
if grep -F -q /dev/p61 "$nfc_experiment_init"; then
  printf 'Reader/HCE NFC experiment must not grant the deferred /dev/p61 node.\n' >&2
  exit 1
fi

vintf_root="$vendor_root/etc/vintf"
[[ -d "$vintf_root" ]] || {
  printf 'NFC VINTF directory is missing: %s\n' "$vintf_root" >&2
  exit 1
}
for manifest_contract in \
  '<name>android.hardware.nfc</name>' \
  '<version>1.1</version>' \
  '<name>INfc</name>' \
  '<name>vendor.nxp.nxpnfc</name>' \
  '<name>INxpNfc</name>'; do
  if ! rg -F -q -- "$manifest_contract" "$vintf_root"; then
    printf 'NFC VINTF contract is missing: %s\n' "$manifest_contract" >&2
    exit 1
  fi
done
if [[ "$(rg -F -l '<name>android.hardware.nfc</name>' "$vintf_root" | wc -l | tr -d ' ')" != 1 ]] || \
    [[ "$(rg -F -l '<name>vendor.nxp.nxpnfc</name>' "$vintf_root" | wc -l | tr -d ' ')" != 1 ]]; then
  printf 'NFC VINTF ownership is not unique.\n' >&2
  exit 1
fi

for property_file in "$system_root/build.prop" "$vendor_root/build.prop"; do
  if [[ -f "$property_file" ]] && \
      grep -F -x -q 'ro.nfc.platform=nxppn547' "$property_file" && \
      grep -F -x -q 'ro.nfc.port=I2C' "$property_file"; then
    properties_found=1
    break
  fi
done
if [[ "${properties_found:-0}" != 1 ]]; then
  printf 'NFC product properties are missing from the packaged build properties.\n' >&2
  exit 1
fi

if [[ -n "$source_root" ]]; then
  if ! cmp --quiet \
      "$nfc_config" \
      "$source_root/device/meizu/m86/nfc/libnfc-nxp.conf" || \
      ! cmp --quiet \
      "$nci_config" \
      "$source_root/hardware/nxp/nfc/halimpl/libnfc-nci.conf"; then
    printf 'Packaged NFC configuration differs from its selected source input.\n' >&2
    exit 1
  fi
fi

nfc_firmware_hash="$(sha256sum "$nfc_firmware" | awk '{ print $1 }')"
if [[ "$nfc_firmware_hash" != \
    54bcd84264b652d8d0fdc72a63ebfe47bcd4e271a228f5958c67c7ce787f02fa ]]; then
  printf 'NFC firmware does not match the locked Flyme input: %s\n' \
    "$nfc_firmware_hash" >&2
  exit 1
fi

printf 'nfc_service=%s\n' "${nfc_service#"$output_root/"}"
printf 'nfc_service_sha256=%s\n' "$(sha256sum "$nfc_service" | awk '{ print $1 }')"
printf 'nfc_nci_library_32=%s\n' "${nfc_nci_library_32#"$output_root/"}"
printf 'nfc_nci_library_64=%s\n' "${nfc_nci_library_64#"$output_root/"}"
printf 'nfc_firmware_sha256=%s\n' "$nfc_firmware_hash"
printf 'nfc_hidl=1.1/default\n'
printf 'nxpnfc_hidl=1.0/default\n'
printf 'secure_element=disabled\n'
printf 'nfc output audit passed.\n'
