#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
device_root="$project_root/device/meizu/m86"
board_config="$device_root/BoardConfig.mk"
android_makefile="$device_root/Android.mk"
recovery_fstab="$device_root/rootdir/etc/recovery.fstab"
releasetools="$device_root/releasetools/releasetools.py"
kernel_config="$project_root/kernel/meizu/m86/arch/arm64/configs/cm_pro5_defconfig"

for required_file in \
  "$board_config" \
  "$android_makefile" \
  "$recovery_fstab" \
  "$releasetools" \
  "$kernel_config"; do
  if [[ ! -s "$required_file" ]]; then
    printf 'Missing required LineageOS source: %s\n' "$required_file" >&2
    exit 1
  fi
done

require_fixed() {
  local pattern="$1"
  local source_file="$2"

  if ! rg -F -q -- "$pattern" "$source_file"; then
    printf 'Required LineageOS setting is absent from %s: %s\n' \
      "$source_file" "$pattern" >&2
    exit 1
  fi
}

require_fixed 'BOARD_KERNEL_BASE := 0x40000000' "$board_config"
require_fixed 'BOARD_KERNEL_PAGESIZE := 4096' "$board_config"
require_fixed '--kernel_offset 0x00080000' "$board_config"
require_fixed '--ramdisk_offset 0x02000000' "$board_config"
require_fixed '--second_offset 0x00f00000' "$board_config"
require_fixed '--tags_offset 0x00000100' "$board_config"
require_fixed 'BOARD_PACK_RADIOIMAGES += dtb' "$board_config"
require_fixed 'TARGET_RELEASETOOLS_EXTENSIONS := $(M86_PATH)/releasetools' \
  "$board_config"
require_fixed 'INSTALLED_RADIOIMAGE_TARGET += $(M86_INSTALLED_DTB)' \
  "$android_makefile"
require_fixed 'DTB_TARGET_FILES_ENTRY = "RADIO/dtb.img"' "$releasetools"
require_fixed 'info.script.WriteRawImage("/dtb", DTB_OTA_ENTRY)' "$releasetools"
require_fixed 'CONFIG_CMDLINE="androidboot.hardware=m86"' "$kernel_config"
require_fixed 'CONFIG_RD_GZIP=y' "$kernel_config"

if ! rg -q '^BOARD_KERNEL_CMDLINE :=[[:space:]]*$' "$board_config"; then
  printf 'The verified m86 v0 boot header must have an empty command line.\n' >&2
  exit 1
fi
if rg -q '^[[:space:]]*BOARD_INCLUDE_DTB_IN_BOOTIMG[[:space:]]*:=' \
    "$board_config"; then
  printf 'The m86 DTB must not be embedded in boot or recovery images.\n' >&2
  exit 1
fi

active_fstab="$(rg -v '^[[:space:]]*(#|$)' "$recovery_fstab")"
if rg -q '/dev/block/sdb|by-name/(ldfw|param|proinfo|private|rstinfo|bootloader)([[:space:]]|$)' \
    <<<"$active_fstab"; then
  printf 'A forbidden bootloader, firmware, or identity target is active.\n' >&2
  exit 1
fi

for mount_point in /system /data /cache /boot /recovery /dtb /misc; do
  if ! rg -q "[[:space:]]${mount_point}[[:space:]]" <<<"$active_fstab"; then
    printf 'Required LineageOS recovery mount is absent: %s\n' \
      "$mount_point" >&2
    exit 1
  fi
done

python3 - "$releasetools" <<'PY'
import sys

with open(sys.argv[1], "rb") as source_file:
    compile(source_file.read(), sys.argv[1], "exec")
PY
printf 'LineageOS source validation passed: %s\n' "$device_root"
