#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
device_root="$project_root/twrp/device/meizu/m86"
board_config="$device_root/BoardConfig.mk"
device_makefile="$device_root/device.mk"
recovery_fstab="$device_root/recovery.fstab"
recovery_init="$device_root/recovery/root/init.recovery.m86.rc"
kernel_config="$project_root/kernel/meizu/m86/arch/arm64/configs/cm_pro5_defconfig"
kernel_fs_kconfig="$project_root/kernel/meizu/m86/fs/Kconfig"
kernel_fs_makefile="$project_root/kernel/meizu/m86/fs/Makefile"
kernel_exfat_provenance="$project_root/kernel/meizu/m86/fs/exfat/PROVENANCE.md"
kernel_exfat_lock="$project_root/locks/kernel-exfat-exynos7420.sha256"
stock_lock="$project_root/locks/stock-flyme-8.0.5.0A.sha256"
twrp_build_worker="$project_root/remote/worker-build-twrp.sh"
twrp_install_worker="$project_root/remote/install-twrp-trees.sh"
twrp_sync_worker="$project_root/remote/worker-sync-twrp-source.sh"
twrp_apply_patches="$project_root/remote/apply-twrp-patches.sh"
twrp_patch_series="$project_root/patches/twrp-series.tsv"
twrp_ramdisk_order_patch="$project_root/patches/twrp-build-make/0001-sort-recovery-ramdisk-inventories.patch"
twrp_pigz_symlink_patch="$project_root/patches/twrp-bootable-recovery/0001-make-pigz-own-gzip-recovery-symlinks.patch"
twrp_file_contexts_patch="$project_root/patches/twrp-system-sepolicy/0001-omit-host-pcre2-bytecode.patch"

for required_file in \
  "$board_config" \
  "$device_makefile" \
  "$recovery_fstab" \
  "$device_root/rootdir/fstab.m86" \
  "$device_root/recovery/root/init.recovery.m86.rc" \
  "$device_root/recovery/root/ueventd.m86.rc" \
  "$kernel_config" \
  "$kernel_fs_kconfig" \
  "$kernel_fs_makefile" \
  "$kernel_exfat_provenance" \
  "$kernel_exfat_lock" \
  "$stock_lock" \
  "$twrp_build_worker" \
  "$twrp_install_worker" \
  "$twrp_sync_worker" \
  "$twrp_apply_patches" \
  "$twrp_patch_series" \
  "$twrp_ramdisk_order_patch" \
  "$twrp_pigz_symlink_patch" \
  "$twrp_file_contexts_patch"; do
  if [[ ! -s "$required_file" ]]; then
    printf 'Missing required TWRP source: %s\n' "$required_file" >&2
    exit 1
  fi
done

if ! (
  cd "$project_root/kernel/meizu/m86"
  sha256sum --quiet -c "$kernel_exfat_lock"
); then
  printf 'The locked Exynos 7420 exFAT source import changed.\n' >&2
  exit 1
fi
if [[ "$(find "$project_root/kernel/meizu/m86/fs/exfat" -maxdepth 1 \
    -type f ! -name PROVENANCE.md | wc -l | tr -d ' ')" != "25" ]]; then
  printf 'Expected exactly 25 locked exFAT donor files.\n' >&2
  exit 1
fi

require_fixed() {
  local pattern="$1"
  local source_file="$2"

  if ! rg -F -q -- "$pattern" "$source_file"; then
    printf 'Required TWRP setting is absent from %s: %s\n' \
      "$source_file" "$pattern" >&2
    exit 1
  fi
}

require_absent() {
  local pattern="$1"
  local source_file="$2"

  if rg -F -q -- "$pattern" "$source_file"; then
    printf 'Unsupported TWRP setting is present in %s: %s\n' \
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
require_fixed 'TW_EXTRA_LANGUAGES := true' "$board_config"
require_fixed 'encryptable=/cache/metadata' "$recovery_fstab"
require_fixed 'setprop sys.usb.ffs.aio_compat 1' "$recovery_init"
require_fixed 'M86_TWRP_DEVICE_PATH := device/meizu/m86' "$device_makefile"
require_fixed 'recovery/root/etc/firmware/st_fts.bin:recovery/root/etc/firmware/st_fts.bin' \
  "$device_makefile"
if rg -q '\$\(LOCAL_PATH\)/(recovery|rootdir)' "$device_makefile"; then
  printf 'Deferred product copy paths must not depend on mutable LOCAL_PATH.\n' >&2
  exit 1
fi
require_fixed 'CONFIG_RD_GZIP=y' "$kernel_config"
require_fixed '# CONFIG_RD_LZMA is not set' "$kernel_config"
require_fixed 'CONFIG_DM_CRYPT=y' "$kernel_config"
require_fixed 'CONFIG_FMP=y' "$kernel_config"
require_fixed 'CONFIG_UFS_FMP_DM_CRYPT=y' "$kernel_config"
require_fixed 'CONFIG_INPUT_EVDEV=y' "$kernel_config"
require_fixed 'CONFIG_TOUCHSCREEN_FTS=y' "$kernel_config"
require_fixed 'CONFIG_USB_DWC3_DUAL_ROLE=y' "$kernel_config"
require_fixed 'CONFIG_USB_G_ANDROID=y' "$kernel_config"
require_fixed 'CONFIG_USB_ANDROID_SAMSUNG_COMPOSITE=y' "$kernel_config"
require_fixed 'CONFIG_USB_STORAGE=y' "$kernel_config"
require_fixed 'CONFIG_SCSI=y' "$kernel_config"
require_fixed 'CONFIG_BLK_DEV_SD=y' "$kernel_config"
require_fixed 'CONFIG_MMC=y' "$kernel_config"
require_fixed 'CONFIG_MMC_DW_EXYNOS=y' "$kernel_config"
require_fixed 'CONFIG_EXT4_FS=y' "$kernel_config"
require_fixed 'CONFIG_FAT_FS=y' "$kernel_config"
require_fixed 'CONFIG_VFAT_FS=y' "$kernel_config"
require_fixed 'CONFIG_EXFAT_FS=y' "$kernel_config"
require_fixed 'CONFIG_EXFAT_VIRTUAL_XATTR=y' "$kernel_config"
require_fixed 'CONFIG_EXFAT_VIRTUAL_XATTR_SELINUX_LABEL="u:object_r:sdcard_external:s0"' \
  "$kernel_config"
for stale_fs_option in \
  CONFIG_FAT_VIRTUAL_XATTR \
  CONFIG_FAT_VIRTUAL_XATTR_SELINUX_LABEL \
  CONFIG_FAT_SUPPORT_STLOG \
  CONFIG_EXFAT_SUPPORT_STLOG; do
  require_absent "$stale_fs_option" "$kernel_config"
done
require_fixed 'source "fs/exfat/Kconfig"' "$kernel_fs_kconfig"
require_fixed 'obj-$(CONFIG_EXFAT_FS)' "$kernel_fs_makefile"
require_fixed 'CONFIG_RTC_CLASS=y' "$kernel_config"
require_fixed 'CONFIG_RTC_DRV_SEC=y' "$kernel_config"
require_fixed 'export BUILD_DATETIME=1538238534' "$twrp_build_worker"
require_fixed 'jobs="${PRO5_TWRP_BUILD_JOBS:-8}"' \
  "$project_root/remote/start-twrp-build.sh"
require_fixed 'jobs="${1:-8}"' "$twrp_build_worker"
require_fixed "localedef -i en_US -f UTF-8 en_US.UTF-8" "$twrp_build_worker"
require_fixed 'external/python/cpython2' "$twrp_build_worker"
require_fixed 'gcc -m32 -O2 -fPIC -shared' "$twrp_build_worker"
require_fixed 'Modules/zlibmodule.c' "$twrp_build_worker"
require_fixed 'export PYTHONPATH="$python2_overlay"' "$twrp_build_worker"
require_fixed 'zlib.decompress(zlib.compress("m86")) == "m86"' \
  "$twrp_build_worker"
require_fixed 'python_zlib_source_revision=' "$twrp_build_worker"
require_fixed 'lib32z1-dev' "$project_root/remote/bootstrap-builder.sh"
require_fixed 'source_checkout_validation=HEAD tree equals index and clean worktree' \
  "$twrp_build_worker"
require_fixed 'ramdisk_inventory_order=LC_ALL=C sorted' "$twrp_build_worker"
require_fixed 'file_contexts_regex_payload=omitted host PCRE2 bytecode' \
  "$twrp_build_worker"
require_fixed 'LC_ALL=C sort > ramdisk-files.txt' "$twrp_ramdisk_order_patch"
require_fixed 'LC_ALL=C sort | xargs sha256sum' "$twrp_ramdisk_order_patch"
require_fixed 'ALL_TOOLS := $(filter-out gzip gunzip,$(ALL_TOOLS))' \
  "$twrp_pigz_symlink_patch"
require_fixed 'sefcontext_compile -r -o $@ $<' "$twrp_file_contexts_patch"
require_fixed 'build/make' "$twrp_patch_series"
require_fixed 'bootable/recovery' "$twrp_patch_series"
require_fixed 'system/sepolicy' "$twrp_patch_series"
require_fixed 'apply --reverse --check' "$twrp_apply_patches"
require_fixed 'apply-twrp-patches.sh' \
  "$project_root/remote/start-twrp-build.sh"
require_fixed 'build_out="$remote_root/out/twrp-9.0"' "$twrp_build_worker"
require_fixed 'build_twrp_pass 1' "$twrp_build_worker"
require_fixed 'cp -a "$recovery_image" "$snapshot_root/recovery.img"' \
  "$twrp_build_worker"
require_fixed 'build_twrp_pass 2' "$twrp_build_worker"
require_fixed 'cmp --silent "$first_file" "$second_file"' \
  "$twrp_build_worker"
require_fixed 'output_path_policy=same absolute OUT_DIR for both clean passes' \
  "$twrp_build_worker"
require_fixed 'REPRODUCIBILITY.txt' "$twrp_build_worker"
require_fixed 'reproducibility=byte-identical recovery.img dtb kernel.config' \
  "$twrp_build_worker"
require_fixed '--expect-ramdisk-elf sbin/adbd' "$twrp_build_worker"
require_fixed '--expect-ramdisk-elf sbin/libfusesideload.so' \
  "$twrp_build_worker"
require_fixed '--expect-ramdisk-elf sbin/libtwrpmtp-ffs.so' \
  "$twrp_build_worker"
require_fixed '--expect-ramdisk-elf sbin/libcryptfsfde.so' \
  "$twrp_build_worker"
require_fixed '--expect-ramdisk-elf sbin/exfat-fuse' "$twrp_build_worker"
require_fixed '--expect-ramdisk-elf sbin/fsck.exfat' "$twrp_build_worker"
require_fixed '--expect-ramdisk-elf sbin/mount.ntfs' "$twrp_build_worker"
require_fixed 'sbin/gzip=$pigz_link_hash' "$twrp_build_worker"
require_fixed 'sbin/gunzip=$pigz_link_hash' "$twrp_build_worker"
require_fixed 'etc/recovery.fstab=$recovery_fstab_hash' "$twrp_build_worker"
require_fixed 'required_kernel_setting' "$twrp_build_worker"
require_fixed 'fs/exfat/exfat_core.o' "$twrp_build_worker"
require_fixed 'fs/exfat/exfat_fs.o' "$twrp_build_worker"
require_fixed 'project_checkout_complete()' "$twrp_sync_worker"
require_fixed 'git -C "$project" ls-tree -r --name-only HEAD' \
  "$twrp_sync_worker"
require_fixed 'git -C "$project" ls-files' "$twrp_sync_worker"
require_fixed 'status --porcelain --untracked-files=normal' "$twrp_sync_worker"
require_fixed '[[ "$head_count" =~ ^[0-9]+$ ]]' "$twrp_sync_worker"
require_fixed 'repair_empty_index_checkout()' "$twrp_sync_worker"
require_fixed 'remove_reviewed_twrp_patches()' "$twrp_sync_worker"
require_fixed 'Removed reviewed patch before TWRP sync' "$twrp_sync_worker"
require_fixed '[[ "$index_count" != 0 ]]' "$twrp_sync_worker"
require_fixed 'git -C "$project" read-tree HEAD' "$twrp_sync_worker"
require_fixed 'git -C "$project" checkout-index --all --force' \
  "$twrp_sync_worker"
require_fixed 'for project in "${projects[@]}"; do' "$twrp_sync_worker"
require_fixed 'manifest_tmp="${manifest_lock}.tmp"' "$twrp_sync_worker"
require_fixed 'mv "$manifest_tmp" "$manifest_lock"' \
  "$twrp_sync_worker"
require_fixed \
  '6362b3058217451a29638c6538ec2dc0f8910702679363bf0a4a96e11c63896d  system.img/vendor/firmware/st_fts.bin' \
  "$stock_lock"

if rg -q '^[[:space:]]*TARGET_HW_DISK_ENCRYPTION[[:space:]]*:=[[:space:]]*true' \
    "$board_config"; then
  printf 'm86 FMP uses the kernel dm-crypt target, not QCOM cryptfs_hw.\n' >&2
  exit 1
fi

if rg -q '^[[:space:]]*TW_NO_EXFAT_FUSE[[:space:]]*:=[[:space:]]*true' \
    "$board_config"; then
  printf 'm86 has no in-kernel exFAT driver; TWRP must retain exfat-fuse.\n' >&2
  exit 1
fi

if [[ -e "$device_root/recovery/root/etc/firmware/st_fts.bin" ]]; then
  printf 'The proprietary STM firmware must be injected from verified stock.\n' >&2
  exit 1
fi

if rg -q 'mount[[:space:]]+functionfs|on property:sys\.usb\.config=' \
    "$recovery_init"; then
  printf 'Device rc must not duplicate TWRP upstream USB state handling.\n' >&2
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
