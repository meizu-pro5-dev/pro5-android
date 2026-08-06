#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
device_root="$project_root/twrp/device/meizu/m86"
board_config="$device_root/BoardConfig.mk"
device_makefile="$device_root/device.mk"
recovery_fstab="$device_root/recovery.fstab"
kernel_config="$project_root/kernel/meizu/m86/arch/arm64/configs/cm_pro5_defconfig"
stock_lock="$project_root/locks/stock-flyme-8.0.5.0A.sha256"

for required_file in \
  "$board_config" \
  "$device_makefile" \
  "$recovery_fstab" \
  "$device_root/rootdir/fstab.m86" \
  "$device_root/recovery/root/init.recovery.m86.rc" \
  "$device_root/recovery/root/ueventd.m86.rc" \
  "$kernel_config" \
  "$stock_lock"; do
  if [[ ! -s "$required_file" ]]; then
    printf 'Missing required TWRP source: %s\n' "$required_file" >&2
    exit 1
  fi
done

require_fixed() {
  local pattern="$1"
  local source_file="$2"

  if ! rg -F -q -- "$pattern" "$source_file"; then
    printf 'Required TWRP setting is absent from %s: %s\n' \
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
require_fixed 'BOARD_RECOVERYIMAGE_PARTITION_SIZE := 33550336' "$board_config"
require_fixed 'TW_INCLUDE_CRYPTO := true' "$board_config"
require_fixed 'RECOVERY_SDCARD_ON_DATA := true' "$board_config"
require_fixed 'TW_USE_NEW_MINADBD := true' "$board_config"
require_fixed 'TW_INCLUDE_NTFS_3G := true' "$board_config"
require_fixed 'TW_NO_EXFAT_FUSE := true' "$board_config"
require_fixed 'TW_EXTRA_LANGUAGES := true' "$board_config"
require_fixed 'encryptable=/cache/metadata' "$recovery_fstab"
require_fixed 'recovery/root/etc/firmware/st_fts.bin:recovery/root/etc/firmware/st_fts.bin' \
  "$device_makefile"
require_fixed 'CONFIG_RD_GZIP=y' "$kernel_config"
require_fixed '# CONFIG_RD_LZMA is not set' "$kernel_config"
require_fixed 'CONFIG_DM_CRYPT=y' "$kernel_config"
require_fixed 'CONFIG_FMP=y' "$kernel_config"
require_fixed 'CONFIG_UFS_FMP_DM_CRYPT=y' "$kernel_config"
require_fixed \
  '6362b3058217451a29638c6538ec2dc0f8910702679363bf0a4a96e11c63896d  system.img/vendor/firmware/st_fts.bin' \
  "$stock_lock"

if rg -q '^[[:space:]]*TARGET_HW_DISK_ENCRYPTION[[:space:]]*:=[[:space:]]*true' \
    "$board_config"; then
  printf 'm86 FMP uses the kernel dm-crypt target, not QCOM cryptfs_hw.\n' >&2
  exit 1
fi

if [[ -e "$device_root/recovery/root/etc/firmware/st_fts.bin" ]]; then
  printf 'The proprietary STM firmware must be injected from verified stock.\n' >&2
  exit 1
fi

if rg -q '^[[:space:]]*LZMA_RAMDISK_TARGETS[[:space:]]*:=' "$board_config"; then
  printf 'The m86 kernel cannot unpack an LZMA recovery ramdisk.\n' >&2
  exit 1
fi

active_fstab="$(rg -v '^[[:space:]]*(#|$)' "$recovery_fstab")"
if rg -q '/dev/block/sdb|by-name/(ldfw|param|proinfo|private|rstinfo|bootloader)([[:space:]]|$)' \
    <<<"$active_fstab"; then
  printf 'A forbidden bootloader, firmware, or identity target is active.\n' >&2
  exit 1
fi

for mount_point in \
  /system \
  /data \
  /cache \
  /boot \
  /recovery \
  /dtb \
  /external_sd \
  /usb-otg; do
  if ! rg -q "^${mount_point}[[:space:]]|[[:space:]]${mount_point}[[:space:]]" \
      <<<"$active_fstab"; then
    printf 'Required recovery mount is absent: %s\n' "$mount_point" >&2
    exit 1
  fi
done

printf 'TWRP source validation passed: %s\n' "$device_root"
