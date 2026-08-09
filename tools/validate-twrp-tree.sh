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
kernel_ramoops_driver="$project_root/kernel/meizu/m86/drivers/platform/exynos/exynos_ramoops.c"
kernel_reserved_mem="$project_root/kernel/meizu/m86/drivers/of/of_reserved_mem.c"
kernel_reserved_mem_header="$project_root/kernel/meizu/m86/include/linux/of_reserved_mem.h"
kernel_decon_driver="$project_root/kernel/meizu/m86/drivers/video/exynos/decon/decon-int_drv.c"
kernel_android_usb_driver="$project_root/kernel/meizu/m86/drivers/usb/gadget/android.c"
kernel_exfat_provenance="$project_root/kernel/meizu/m86/fs/exfat/PROVENANCE.md"
kernel_exfat_lock="$project_root/locks/kernel-exfat-exynos7420.sha256"
stock_lock="$project_root/locks/stock-flyme-8.0.5.0A.sha256"
twrp_build_worker="$project_root/remote/worker-build-twrp.sh"
twrp_pre_pstore_pan_builder="$project_root/remote/start-twrp-pre-pstore-note5-pan-build.sh"
twrp_pre_pstore_usb_builder="$project_root/remote/start-twrp-pre-pstore-usb-vbus-build.sh"
twrp_install_worker="$project_root/remote/install-twrp-trees.sh"
twrp_sync_worker="$project_root/remote/worker-sync-twrp-source.sh"
twrp_apply_patches="$project_root/remote/apply-twrp-patches.sh"
twrp_patch_series="$project_root/patches/twrp-series.tsv"
twrp_ramdisk_order_patch="$project_root/patches/twrp-build-make/0001-sort-recovery-ramdisk-inventories.patch"
twrp_pigz_symlink_patch="$project_root/patches/twrp-bootable-recovery/0001-make-pigz-own-gzip-recovery-symlinks.patch"
twrp_language_patch="$project_root/patches/twrp-bootable-recovery/0002-allow-selective-recovery-languages.patch"
twrp_fbdev_page_zero_patch="$project_root/patches/twrp-bootable-recovery/0003-fbdev-select-page-zero-for-forced-single-buffer.patch"
twrp_fbdev_command_refresh_patch="$project_root/patches/twrp-bootable-recovery/0004-fbdev-refresh-forced-single-buffer-with-pan.patch"
twrp_fbdev_precopy_vsync_patch="$project_root/patches/twrp-bootable-recovery/0005-fbdev-wait-for-vsync-before-single-buffer-copy.patch"
twrp_fbdev_legacy_pan_patch="$project_root/patches/twrp-bootable-recovery/0006-fbdev-match-legacy-single-buffer-pan-contract.patch"
twrp_file_contexts_patch="$project_root/patches/twrp-system-sepolicy/0001-omit-host-pcre2-bytecode.patch"
twrp_usb_vbus_patch="$project_root/patches/twrp-kernel-m86/0001-usb-force-gadget-vbus-on-enable.patch"
twrp_decon_no_lpd_patch="$project_root/patches/twrp-kernel-m86/0002-display-disable-decon-lpd.patch"
boot_image_inspector="$project_root/tools/inspect-android-boot-image.py"
boot_image_repacker="$project_root/tools/repack-android-boot-image.py"
ramdisk_rewriter="$project_root/tools/rewrite-newc-ramdisk.py"
reboot_property_patcher="$project_root/tools/patch-twrp-reboot-property.py"
twrp_log_capture_builder="$project_root/tools/build-pro5-twrp-log-capture-v3.sh"
twrp_log_wrapper_patch="$project_root/patches/twrp-diagnostics/0003-run-recovery-under-log-wrapper.patch"
twrp_log_wrapper="$project_root/patches/twrp-diagnostics/recovery-log-wrapper.sh"
twrp_sync_log_capture_builder="$project_root/tools/build-pro5-twrp-sync-log-capture-v4.sh"
twrp_sync_log_wrapper="$project_root/patches/twrp-diagnostics/recovery-sync-log-wrapper-v4.sh"
twrp_single_buffer_builder="$project_root/tools/build-pro5-twrp-single-buffer-v5.sh"
twrp_page_zero_builder="$project_root/tools/build-pro5-twrp-page-zero-v6.sh"
twrp_command_refresh_builder="$project_root/tools/build-pro5-twrp-command-refresh-v7.sh"
twrp_precopy_vsync_builder="$project_root/tools/build-pro5-twrp-precopy-vsync-v11.sh"
twrp_legacy_pan_builder="$project_root/tools/build-pro5-twrp-legacy-pan-v12.sh"
twrp_legacy_adb_builder="$project_root/tools/build-pro5-twrp-legacy-adb-v9.sh"
twrp_legacy_adb_init="$project_root/patches/twrp-diagnostics/recovery-legacy-adb-v9.rc"
twrp_direct_adb_builder="$project_root/tools/build-pro5-twrp-direct-adb-v10.sh"
twrp_direct_adb_init="$project_root/patches/twrp-diagnostics/recovery-direct-adb-v10.rc"
twrp_ready_first_adb_init="$project_root/patches/twrp-diagnostics/recovery-ready-first-adb-v13.rc"
twrp_ready_first_wrapper="$project_root/patches/twrp-diagnostics/recovery-ready-first-wrapper-v13.sh"
twrp_note5_pan_ready_adb_builder="$project_root/tools/build-pro5-twrp-note5-pan-ready-adb-v13.sh"
twrp_v11_kernel_pan_builder="$project_root/tools/build-pro5-twrp-v11-kernel-pan-v14.sh"
twrp_usb_vbus_v18_builder="$project_root/tools/build-pro5-twrp-usb-vbus-v18.sh"
twrp_no_lpd_v19_builder="$project_root/tools/build-pro5-twrp-no-lpd-v19.sh"
twrp_functional_v20_init="$project_root/patches/twrp-runtime/recovery-functional-v20.rc"
twrp_functional_v20_builder="$project_root/tools/build-pro5-twrp-functional-v20.sh"

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
  "$kernel_ramoops_driver" \
  "$kernel_reserved_mem" \
  "$kernel_reserved_mem_header" \
  "$kernel_decon_driver" \
  "$kernel_android_usb_driver" \
  "$kernel_exfat_provenance" \
  "$kernel_exfat_lock" \
  "$stock_lock" \
  "$twrp_build_worker" \
  "$twrp_pre_pstore_pan_builder" \
  "$twrp_pre_pstore_usb_builder" \
  "$twrp_install_worker" \
  "$twrp_sync_worker" \
  "$twrp_apply_patches" \
  "$twrp_patch_series" \
  "$twrp_ramdisk_order_patch" \
  "$twrp_pigz_symlink_patch" \
  "$twrp_language_patch" \
  "$twrp_fbdev_page_zero_patch" \
  "$twrp_fbdev_command_refresh_patch" \
  "$twrp_fbdev_precopy_vsync_patch" \
  "$twrp_fbdev_legacy_pan_patch" \
  "$twrp_file_contexts_patch" \
  "$twrp_usb_vbus_patch" \
  "$twrp_decon_no_lpd_patch" \
  "$boot_image_inspector" \
  "$boot_image_repacker" \
  "$ramdisk_rewriter" \
  "$reboot_property_patcher" \
  "$twrp_log_capture_builder" \
  "$twrp_log_wrapper_patch" \
  "$twrp_log_wrapper" \
  "$twrp_sync_log_capture_builder" \
  "$twrp_sync_log_wrapper" \
  "$twrp_single_buffer_builder" \
  "$twrp_page_zero_builder" \
  "$twrp_command_refresh_builder" \
  "$twrp_precopy_vsync_builder" \
  "$twrp_legacy_pan_builder" \
  "$twrp_legacy_adb_builder" \
  "$twrp_legacy_adb_init" \
  "$twrp_direct_adb_builder" \
  "$twrp_direct_adb_init" \
  "$twrp_ready_first_adb_init" \
  "$twrp_ready_first_wrapper" \
  "$twrp_note5_pan_ready_adb_builder" \
  "$twrp_v11_kernel_pan_builder" \
  "$twrp_usb_vbus_v18_builder" \
  "$twrp_no_lpd_v19_builder" \
  "$twrp_functional_v20_init" \
  "$twrp_functional_v20_builder"; do
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
require_fixed 'TW_EXTRA_LANGUAGES := false' "$board_config"
require_fixed 'Keep PAN as a lightweight command-mode refresh.' \
  "$kernel_decon_driver"
require_absent $'\tdecon_set_par(info);' "$kernel_decon_driver"
require_fixed 'PRO5_TWRP_LEGACY_PAN_V12=1' "$twrp_legacy_pan_builder"
require_fixed 'legacy single-buffer initialization contract repair' \
  "$twrp_single_buffer_builder"
require_fixed 'legacy single-buffer keeps kernel framebuffer geometry' \
  "$twrp_single_buffer_builder"
require_fixed '    write /sys/class/android_usb/android0/idVendor 2A45' \
  "$twrp_ready_first_adb_init"
require_fixed '    write /sys/class/android_usb/android0/idProduct 0C01' \
  "$twrp_ready_first_adb_init"
require_fixed '    start adbd' "$twrp_ready_first_adb_init"
require_absent '    write /sys/class/android_usb/android0/functions adb' \
  "$twrp_ready_first_adb_init"
require_fixed "grep -q 'adb_open'" "$twrp_ready_first_wrapper"
require_fixed 'echo adb >/sys/class/android_usb/android0/functions' \
  "$twrp_ready_first_wrapper"
require_fixed 'echo 1 >/sys/class/android_usb/android0/enable' \
  "$twrp_ready_first_wrapper"
require_fixed 'periodic_usb_snapshot' "$twrp_ready_first_wrapper"
require_fixed \
  'expected_base_sha256=4e4320b297c3ca086a697f488f0ddaca5017f62e40512fb1b980eb2f2b642463' \
  "$twrp_note5_pan_ready_adb_builder"
require_fixed \
  'expected_donor_sha256=dba0bf646c2e82a480c02fca94bb430cd7b2f6f902a5b00899224f2f73dc6a48' \
  "$twrp_note5_pan_ready_adb_builder"
require_fixed \
  'expected_kernel_sha256=aac6338d2b64f49e2988215fff186a2f229fc7d6e2545f7d9178ff307835a5e5' \
  "$twrp_note5_pan_ready_adb_builder"
require_fixed '--kernel-from-image "$donor_image"' \
  "$twrp_note5_pan_ready_adb_builder"
require_fixed 'changed_data_paths=init.rc,sbin/permissive.sh' \
  "$twrp_note5_pan_ready_adb_builder"
require_fixed 'cmp --silent "$pass_one/ramdisk.gzip"' \
  "$twrp_note5_pan_ready_adb_builder"
require_fixed 'adb_usb_identity=2A45:0C01 serial PRO5TWRPV13' \
  "$twrp_note5_pan_ready_adb_builder"
require_fixed \
  'expected_base_sha256=8e88e946ce04efe2ccc006147c7da654ad14d9c6c3cb0eb2c610067a72e327d8' \
  "$twrp_v11_kernel_pan_builder"
require_fixed \
  'expected_donor_sha256=02856bae0eb1e8ca4718b480e0adc8909852cdb410811ff5e331eeb90b2979cc' \
  "$twrp_v11_kernel_pan_builder"
require_fixed \
  'expected_kernel_sha256=7cb5b99f6ec849b4ab7b5508964ddb4641fede416cd8ab8611643f0bc6e454ff' \
  "$twrp_v11_kernel_pan_builder"
require_fixed 'changed_components=kernel only' "$twrp_v11_kernel_pan_builder"
require_fixed 'ramdisk_byte_identical_to_v11=yes' \
  "$twrp_v11_kernel_pan_builder"
require_fixed 'cmp --silent "$pass_one/recovery.img"' \
  "$twrp_v11_kernel_pan_builder"
require_fixed \
  'expected_base_sha256=e7d17b0dc4bd0136bb9338a2263f1bad602c75d3d0db123a9e6e512b804c6cda' \
  "$twrp_usb_vbus_v18_builder"
require_fixed \
  'expected_donor_sha256=85af306ec06daa18f403cca79ef217438fdfe46c7f33f0470d4a03fff6232e06' \
  "$twrp_usb_vbus_v18_builder"
require_fixed \
  'expected_kernel_sha256=959b97010805584b9935ba2004a684b9330b76de82a5ac911ee876d3f38e9b38' \
  "$twrp_usb_vbus_v18_builder"
require_fixed 'ramdisk_identical_to_v17=yes' "$twrp_usb_vbus_v18_builder"
require_fixed 'changed_components=kernel only' "$twrp_usb_vbus_v18_builder"
require_fixed 'usb_id=2A45:0C02' "$twrp_usb_vbus_v18_builder"
require_fixed '--kernel-from-image "$donor_image"' \
  "$twrp_usb_vbus_v18_builder"
require_fixed 'cmp --silent "$pass_one/recovery.img"' \
  "$twrp_usb_vbus_v18_builder"
require_fixed \
  'expected_base_sha256=975710e9214f8c471791748e42029c623ecb6b9a35e6fc6c856c4a6c77d0943f' \
  "$twrp_no_lpd_v19_builder"
require_fixed \
  'expected_donor_sha256=7ce879901169990f8aea6fa48ca436e16bd15345e6634b4384cd4a6237fb4614' \
  "$twrp_no_lpd_v19_builder"
require_fixed \
  'expected_kernel_sha256=45474fdcdd7f354b81e18d4aa13704d9d990838ff562f1625c6ba11f7c036d21' \
  "$twrp_no_lpd_v19_builder"
require_fixed \
  'expected_kernel_config_sha256=d8a081e100d581447fba72990cc3f2d738c0a18a3e6bba6f4fef51730ba5f909' \
  "$twrp_no_lpd_v19_builder"
require_fixed 'ramdisk_identical_to_v18=yes' \
  "$twrp_no_lpd_v19_builder"
require_fixed 'changed_components=kernel only' \
  "$twrp_no_lpd_v19_builder"
require_fixed 'usb_id=2A45:0C02' "$twrp_no_lpd_v19_builder"
require_fixed 'kernel_profile=pre-pstore-usb-vbus-no-lpd' \
  "$twrp_no_lpd_v19_builder"
require_fixed '--kernel-from-image "$donor_image"' \
  "$twrp_no_lpd_v19_builder"
require_fixed 'cmp --silent "$pass_one/recovery.img"' \
  "$twrp_no_lpd_v19_builder"
require_fixed \
  'expected_base_sha256=aa366fe911ccb31a71bf4ee3213a644b1973bb90229e243d4c9eaa76bb99902e' \
  "$twrp_functional_v20_builder"
require_fixed \
  'expected_unpatched_donor_sha256=faff297b31eab8aa1a6b85b31e801d72d0bc512cdee6850bd6d0451749013d31' \
  "$twrp_functional_v20_builder"
require_fixed \
  'expected_unpatched_recovery_sha256=fb86468df29070d51ec2ce63466cfb49249fac94d4c5a1e59b84fff127968678' \
  "$twrp_functional_v20_builder"
require_fixed \
  'expected_output_init_sha256=837c7ac469aa4de26a728781a9b77ecf9a31e8c848b0d989a22331735bc6d929' \
  "$twrp_functional_v20_builder"
require_fixed 'changed_data_paths=init.rc,sbin/recovery' \
  "$twrp_functional_v20_builder"
require_fixed 'cmp --silent "$pass_one/ramdisk.gzip"' \
  "$twrp_functional_v20_builder"
require_fixed 'on property:sys.usb.config=mtp,adb' \
  "$twrp_functional_v20_init"
require_fixed '    write /sys/class/android_usb/android0/functions mtp,adb' \
  "$twrp_functional_v20_init"
require_fixed 'on property:sys.powerctl=*' "$twrp_functional_v20_init"
require_fixed 'service recovery /sbin/recovery' "$twrp_functional_v20_init"
if rg -q '^[[:space:]]*setprop[[:space:]]+mtp\.crash_check' \
    "$twrp_functional_v20_init"; then
  printf 'The functional v20 init still forces MTP crash suppression.\n' >&2
  exit 1
fi
if rg -q '^service recovery .*/sbin/permissive\.sh' \
    "$twrp_functional_v20_init"; then
  printf 'The functional v20 init still launches the diagnostic wrapper.\n' >&2
  exit 1
fi
require_fixed 'TW_LANGUAGE_ALLOWLIST := en zh_CN' "$board_config"
require_fixed 'LZMA_RAMDISK_TARGETS := recovery' "$board_config"
require_fixed 'TW_SCREEN_BLANK_ON_BOOT := true' "$board_config"
require_fixed 'TW_NO_SCREEN_TIMEOUT := true' "$board_config"
require_fixed 'TW_NO_SCREEN_BLANK := true' "$board_config"
require_fixed 'RECOVERY_GRAPHICS_FORCE_SINGLE_BUFFER := true' "$board_config"
require_fixed 'TW_MTP_DEVICE := "/dev/mtp_usb"' "$board_config"
require_fixed 'TW_NO_USB_STORAGE := true' "$board_config"
require_fixed 'encryptable=/cache/metadata' "$recovery_fstab"
require_fixed 'setprop sys.usb.ffs.aio_compat 1' "$recovery_init"
require_fixed 'write /sys/class/android_usb/android0/idProduct 4EE7' \
  "$recovery_init"
require_fixed 'setprop service.adb.root 1' "$recovery_init"
require_fixed 'setprop sys.usb.config none' "$recovery_init"
require_fixed 'setprop sys.usb.config adb' "$recovery_init"
require_fixed 'M86_TWRP_DEVICE_PATH := device/meizu/m86' "$device_makefile"
require_fixed 'usb.vendor=18D1' "$device_makefile"
require_fixed 'usb.product.adb=4EE7' "$device_makefile"
require_fixed 'usb.product.mtpadb=4EE2' "$device_makefile"
require_fixed 'recovery/root/etc/firmware/st_fts.bin:recovery/root/etc/firmware/st_fts.bin' \
  "$device_makefile"
if rg -q '\$\(LOCAL_PATH\)/(recovery|rootdir)' "$device_makefile"; then
  printf 'Deferred product copy paths must not depend on mutable LOCAL_PATH.\n' >&2
  exit 1
fi
require_fixed 'CONFIG_RD_GZIP=y' "$kernel_config"
require_fixed 'CONFIG_RD_LZMA=y' "$kernel_config"
require_fixed 'CONFIG_DECOMPRESS_LZMA=y' "$kernel_config"
require_fixed 'CONFIG_PSTORE=y' "$kernel_config"
require_fixed 'CONFIG_PSTORE_CONSOLE=y' "$kernel_config"
require_fixed 'CONFIG_PSTORE_RAM=y' "$kernel_config"
require_fixed 'of_reserved_mem_lookup(struct device_node *np)' \
  "$kernel_reserved_mem"
require_fixed 'of_parse_phandle(dev->of_node, "memory-region", 0)' \
  "$kernel_ramoops_driver"
require_fixed 'if (ret || !base || !size)' "$kernel_ramoops_driver"
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
require_fixed 'jobs="${PRO5_KERNEL_BUILD_JOBS:-8}"' \
  "$project_root/remote/start-kernel-build.sh"
require_fixed 'jobs="${1:-8}"' \
  "$project_root/remote/worker-build-kernel.sh"
require_fixed "localedef -i en_US -f UTF-8 en_US.UTF-8" "$twrp_build_worker"
require_fixed 'external/python/cpython2' "$twrp_build_worker"
require_fixed 'gcc -m32 -O2 -fPIC -shared' "$twrp_build_worker"
require_fixed 'Modules/zlibmodule.c' "$twrp_build_worker"
require_fixed 'export PYTHONPATH="$python2_overlay"' "$twrp_build_worker"
require_fixed 'zlib.decompress(zlib.compress("m86")) == "m86"' \
  "$twrp_build_worker"
require_fixed 'python_zlib_source_revision=' "$twrp_build_worker"
require_fixed 'lib32z1-dev' "$project_root/remote/bootstrap-builder.sh"
require_fixed 'xz-utils' "$project_root/remote/bootstrap-builder.sh"
require_fixed 'source_checkout_validation=HEAD tree equals index and clean worktree' \
  "$twrp_build_worker"
require_fixed 'ramdisk_inventory_order=LC_ALL=C sorted' "$twrp_build_worker"
require_fixed 'file_contexts_regex_payload=omitted host PCRE2 bytecode' \
  "$twrp_build_worker"
require_fixed 'LC_ALL=C sort > ramdisk-files.txt' "$twrp_ramdisk_order_patch"
require_fixed 'LC_ALL=C sort | xargs sha256sum' "$twrp_ramdisk_order_patch"
require_fixed 'ALL_TOOLS := $(filter-out gzip gunzip,$(ALL_TOOLS))' \
  "$twrp_pigz_symlink_patch"
require_fixed 'TW_LANGUAGE_ALLOWLIST' "$twrp_language_patch"
require_fixed 'DroidSansFallback.ttf' "$twrp_language_patch"
require_fixed '#ifdef RECOVERY_GRAPHICS_FORCE_SINGLE_BUFFER' \
  "$twrp_fbdev_page_zero_patch"
require_fixed 'if (n != 0) return;' "$twrp_fbdev_page_zero_patch"
require_fixed 'forcing single-buffer scanout to framebuffer page 0' \
  "$twrp_fbdev_page_zero_patch"
require_fixed '#ifdef RECOVERY_GRAPHICS_FORCE_SINGLE_BUFFER' \
  "$twrp_fbdev_command_refresh_patch"
require_fixed 'forced single-buffer flips refresh with FBIOPAN_DISPLAY' \
  "$twrp_fbdev_command_refresh_patch"
require_fixed 'ioctl(fb_fd, FBIOPAN_DISPLAY, &vi)' \
  "$twrp_fbdev_command_refresh_patch"
require_fixed 'FBIO_WAITFORVSYNC' "$twrp_fbdev_precopy_vsync_patch"
require_fixed 'forced single-buffer pre-copy vsync failed' \
  "$twrp_fbdev_precopy_vsync_patch"
require_fixed 'legacy single-buffer keeps kernel framebuffer geometry' \
  "$twrp_fbdev_legacy_pan_patch"
require_fixed '#else' "$twrp_fbdev_legacy_pan_patch"
require_fixed 'set_displayed_framebuffer(0);' "$twrp_fbdev_legacy_pan_patch"
require_fixed 'vi.yoffset = 0;' "$twrp_fbdev_command_refresh_patch"
require_fixed 'sefcontext_compile -r -o $@ $<' "$twrp_file_contexts_patch"
require_fixed 'build/make' "$twrp_patch_series"
require_fixed 'bootable/recovery' "$twrp_patch_series"
require_fixed 'patches/twrp-bootable-recovery/0002-allow-selective-recovery-languages.patch' \
  "$twrp_patch_series"
require_fixed 'patches/twrp-bootable-recovery/0003-fbdev-select-page-zero-for-forced-single-buffer.patch' \
  "$twrp_patch_series"
require_fixed 'patches/twrp-bootable-recovery/0004-fbdev-refresh-forced-single-buffer-with-pan.patch' \
  "$twrp_patch_series"
require_fixed 'patches/twrp-bootable-recovery/0005-fbdev-wait-for-vsync-before-single-buffer-copy.patch' \
  "$twrp_patch_series"
require_fixed 'patches/twrp-bootable-recovery/0006-fbdev-match-legacy-single-buffer-pan-contract.patch' \
  "$twrp_patch_series"
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
require_fixed 'kernel_profile="${6:-maintained}"' "$twrp_build_worker"
require_fixed 'pre-pstore-note5-pan' "$twrp_build_worker"
require_fixed 'pre-pstore-usb-vbus' "$twrp_build_worker"
require_fixed 'pre-pstore-usb-vbus-no-lpd' "$twrp_build_worker"
require_fixed 'pstore_config=disabled to match proven v11 kernel baseline' \
  "$twrp_build_worker"
require_fixed 'baseline_revision=52bb509cf2ba6a8a21107080bfdedb5219ead70d' \
  "$twrp_pre_pstore_pan_builder"
require_fixed 'git -C "$project_root" archive "$baseline_revision"' \
  "$twrp_pre_pstore_pan_builder"
require_fixed 'pre-pstore-note5-pan' "$twrp_pre_pstore_pan_builder"
require_fixed \
  '11683809ee51d42d6a3c7a9e0e9ff6e2bfd9fd12b4f2b58b19cc31d562b057ae arch/arm64/configs/cm_pro5_defconfig' \
  "$twrp_pre_pstore_pan_builder"
require_fixed 'baseline_revision=52bb509cf2ba6a8a21107080bfdedb5219ead70d' \
  "$twrp_pre_pstore_usb_builder"
require_fixed 'git -C "$overlay_root/kernel/meizu/m86" apply --check "$usb_patch"' \
  "$twrp_pre_pstore_usb_builder"
require_fixed 'pre-pstore-usb-vbus' "$twrp_pre_pstore_usb_builder"
require_fixed 'PRO5_TWRP_DISABLE_DECON_LPD' \
  "$twrp_pre_pstore_usb_builder"
require_fixed 'pre-pstore-usb-vbus-no-lpd' \
  "$twrp_pre_pstore_usb_builder"
require_fixed \
  '3ed5fa4bc2303541df9b26de1dfd96737562b604c967d8615d66e27f5677d996' \
  "$twrp_pre_pstore_usb_builder"
require_fixed 'android_usb: forcing DWC3 gadget VBUS session' \
  "$kernel_android_usb_driver"
require_fixed 'dwc3_exynos_vbus_event(NULL, 1);' "$kernel_android_usb_driver"
require_fixed 'usb: force gadget VBUS session when android_usb is enabled' \
  "$twrp_usb_vbus_patch"
require_fixed 'defconfig: disable DECON LPD for recovery' \
  "$twrp_decon_no_lpd_patch"
require_fixed '# CONFIG_DECON_LPD_DISPLAY is not set' \
  "$twrp_decon_no_lpd_patch"
require_fixed '--expect-ramdisk-elf sbin/adbd' "$twrp_build_worker"
require_fixed '--expect-valid-image-id' "$twrp_build_worker"
require_fixed '--expect-ramdisk-compression lzma' "$twrp_build_worker"
require_fixed 'lzma.decompress' "$boot_image_inspector"
require_fixed 'twres/languages=en.xml,zh_CN.xml' "$twrp_build_worker"
require_fixed 'twres/fonts=DroidSansFallback.ttf,DroidSansMono.ttf,RobotoCondensed-Regular.ttf' \
  "$twrp_build_worker"
require_fixed 'conditional-dtb' "$boot_image_inspector"
require_fixed 'all-sections' "$boot_image_inspector"
require_fixed '--extract-ramdisk-file' "$boot_image_inspector"
require_fixed 'refusing to overwrite extraction output' "$boot_image_inspector"
require_fixed 'conditional-dtb' "$boot_image_repacker"
require_fixed 'all-sections' "$boot_image_repacker"
require_fixed 'base newc archive does not round-trip byte-identically' \
  "$ramdisk_rewriter"
require_fixed 'dict_size": 8 * 1024 * 1024' "$ramdisk_rewriter"
require_fixed '--replace-data' "$ramdisk_rewriter"
require_fixed 'replacement target is not a regular newc file' \
  "$ramdisk_rewriter"
require_fixed 'changed_data_paths=' "$ramdisk_rewriter"
require_fixed 'changed_metadata_paths=' "$ramdisk_rewriter"
require_fixed 'entry_order_identical=' "$ramdisk_rewriter"
require_fixed 'archive_tail_identical=' "$ramdisk_rewriter"
require_fixed 'OLD_PROPERTY = b"sys.powerctl\0"' \
  "$reboot_property_patcher"
require_fixed 'NEW_PROPERTY = b"twrp.loghold\0"' \
  "$reboot_property_patcher"
require_fixed 'expected exactly one sys.powerctl ELF literal' \
  "$reboot_property_patcher"
require_fixed 'service recovery /sbin/sh /sbin/permissive.sh' \
  "$twrp_log_wrapper_patch"
require_fixed 'seclabel u:r:recovery:s0' "$twrp_log_wrapper_patch"
require_fixed '/cache/recovery' "$twrp_log_wrapper"
require_fixed 'cache_is_read_write' "$twrp_log_wrapper"
require_fixed 'periodic_cache_sync' "$twrp_log_wrapper"
require_fixed 'pro5-twrp-diag-v3-' "$twrp_log_wrapper"
require_fixed 'hold_diagnostic_environment' "$twrp_log_wrapper"
require_fixed \
  'expected_base_sha256=34bed1046ecef38b13ca8eda20f97f1a0610af0c4fb4a3e3769fc6aaa73d8d4a' \
  "$twrp_log_capture_builder"
require_fixed 'changed_data_paths=init.rc,sbin/permissive.sh' \
  "$twrp_log_capture_builder"
require_fixed 'cmp --silent "$pass_one/ramdisk.gzip"' \
  "$twrp_log_capture_builder"
require_fixed 'persistent_device_write=/cache/recovery/pro5-twrp-diag-v3-*' \
  "$twrp_log_capture_builder"
require_fixed 'cache_is_read_write_and_synchronous' \
  "$twrp_sync_log_wrapper"
require_fixed 'mount -o remount,rw,sync /cache' \
  "$twrp_sync_log_wrapper"
require_fixed 'record_durable_stage launching_recovery' \
  "$twrp_sync_log_wrapper"
require_fixed 'pro5-twrp-diag-v4-' "$twrp_sync_log_wrapper"
require_fixed 'hold_diagnostic_environment' "$twrp_sync_log_wrapper"
require_fixed \
  'expected_base_sha256=61c7e16e706ab04cddc9801b6fa30f6f23683108591e9446dbf66e69e2594ea7' \
  "$twrp_sync_log_capture_builder"
require_fixed \
  'expected_v4_wrapper_sha256=136b881e587df48ddb9e272d41beb888a05c36fce0c5cc3bd00d5885ed6d864f' \
  "$twrp_sync_log_capture_builder"
require_fixed 'changed_data_paths=sbin/permissive.sh' \
  "$twrp_sync_log_capture_builder"
require_fixed 'cmp --silent "$pass_one/ramdisk.gzip"' \
  "$twrp_sync_log_capture_builder"
require_fixed 'persistent_device_write=/cache/recovery/pro5-twrp-diag-v4-*' \
  "$twrp_sync_log_capture_builder"
require_fixed \
  'expected_base_sha256=929308abf56395ab6ec74d5f53734d5b90f7ce6a45086680e207002e3f6f6029' \
  "$twrp_single_buffer_builder"
require_fixed \
  'expected_donor_sha256=370064ffa114783119fed8eea52ca6505a47954f62a1db309d7f268462b9c704' \
  "$twrp_single_buffer_builder"
require_fixed \
  'expected_single_buffer_minui_sha256=ecd2d3dedced81b9122c9fedcb32f278e9d914e2a923dc4bf85cd571ab4cc8f1' \
  "$twrp_single_buffer_builder"
require_fixed 'RECOVERY_GRAPHICS_FORCE_SINGLE_BUFFER := true' \
  "$twrp_single_buffer_builder"
require_fixed 'The donor minuitwrp still contains the double-buffer branch.' \
  "$twrp_single_buffer_builder"
require_fixed 'changed_data_paths=sbin/libminuitwrp.so' \
  "$twrp_single_buffer_builder"
require_fixed 'cmp --silent "$pass_one/ramdisk.gzip"' \
  "$twrp_single_buffer_builder"
require_fixed 'persistent_device_write=/cache/recovery/pro5-twrp-diag-v4-*' \
  "$twrp_single_buffer_builder"
require_fixed 'PRO5_TWRP_PAGE_ZERO_V6=1' "$twrp_page_zero_builder"
require_fixed 'build-pro5-twrp-single-buffer-v5.sh' \
  "$twrp_page_zero_builder"
require_fixed \
  'expected_base_sha256=23db8d86e7b6523b2a4ad1c8ed2b2bbd319d490d05d57381f3670dbad42f5fe1' \
  "$twrp_single_buffer_builder"
require_fixed \
  'expected_donor_sha256=7cbef6a30c2a380b479266b5399c6a6647c897950519e96f8473ff50e64f886c' \
  "$twrp_single_buffer_builder"
require_fixed \
  'expected_single_buffer_minui_sha256=e051032762c474654192460e85c94144b368d9a1d441435a603088955a032978' \
  "$twrp_single_buffer_builder"
require_fixed 'required_page_zero_marker=' "$twrp_single_buffer_builder"
require_fixed 'forcing single-buffer scanout to framebuffer page 0' \
  "$twrp_single_buffer_builder"
require_fixed 'single-buffer page-zero scanout repair v6' \
  "$twrp_single_buffer_builder"
require_fixed 'PRO5_TWRP_COMMAND_REFRESH_V7=1' \
  "$twrp_command_refresh_builder"
require_fixed 'build-pro5-twrp-single-buffer-v5.sh' \
  "$twrp_command_refresh_builder"
require_fixed \
  'expected_base_sha256=398dc69d5af4b9210b09c27d8a50e16edeaebbbf7f4844d3efefaa402c6934c8' \
  "$twrp_single_buffer_builder"
require_fixed \
  'expected_donor_sha256=dc2b15534fcb678889064fc1cedb55912398f523e0f03a6b5ae4563ce74590ab' \
  "$twrp_single_buffer_builder"
require_fixed \
  'expected_single_buffer_minui_sha256=d59012dd3491f0dc12b542a09648b1a1fdeba410cf360fca608f96abbc848cfe' \
  "$twrp_single_buffer_builder"
require_fixed 'required_refresh_marker=' "$twrp_single_buffer_builder"
require_fixed 'forced single-buffer flips refresh with FBIOPAN_DISPLAY' \
  "$twrp_single_buffer_builder"
require_fixed 'page-zero command refresh repair v7' \
  "$twrp_single_buffer_builder"
require_fixed 'PRO5_TWRP_PRECOPY_VSYNC_V11=1' \
  "$twrp_precopy_vsync_builder"
require_fixed 'build-pro5-twrp-single-buffer-v5.sh' \
  "$twrp_precopy_vsync_builder"
require_fixed \
  'expected_base_sha256=6d1455bd633e439158df6b13602cc26344eeea0bdcc56ac7614ceaef35fc5690' \
  "$twrp_single_buffer_builder"
require_fixed \
  'expected_donor_sha256=bdfc2aa9ac4401614572d92c48eb72a2151dacf569ee95b09032e062376e4697' \
  "$twrp_single_buffer_builder"
require_fixed \
  'expected_single_buffer_minui_sha256=14efd5195e0379669656d0866adcedaa6030a645b7071056ff08437386e682c0' \
  "$twrp_single_buffer_builder"
require_fixed 'required_precopy_vsync_marker=' \
  "$twrp_single_buffer_builder"
require_fixed 'pre-copy VSYNC pacing repair v11' \
  "$twrp_single_buffer_builder"
require_fixed \
  'expected_base_sha256=26c98728539ab21d723a67906e8250a78be633cdb481cdaa93f2ecdee2e7d43e' \
  "$twrp_legacy_adb_builder"
require_fixed \
  'expected_donor_sha256=433d10bc1acffc66521530fc13f439fd94b20e9849e17e1eec83738e98f23a04' \
  "$twrp_legacy_adb_builder"
require_fixed \
  'expected_v9_recovery_sha256=d1f1f6af440acda2929d99aae4e5877d03a1bdaf4e2934800a018629b1eea80d' \
  "$twrp_legacy_adb_builder"
require_fixed 'changed_data_paths=init.rc,sbin/recovery' \
  "$twrp_legacy_adb_builder"
require_fixed 'only gr_fb_blank undefined import removed from v7 surface' \
  "$twrp_legacy_adb_builder"
require_fixed 'cmp --silent "$pass_one/ramdisk.gzip"' \
  "$twrp_legacy_adb_builder"
require_fixed 'persistent_device_write=/cache/recovery/pro5-twrp-diag-v4-*' \
  "$twrp_legacy_adb_builder"
require_fixed '    setprop mtp.crash_check 1' "$twrp_legacy_adb_init"
require_fixed 'on property:sys.usb.config=adb' "$twrp_legacy_adb_init"
require_fixed '    write /sys/class/android_usb/android0/idProduct 4EE7' \
  "$twrp_legacy_adb_init"
require_fixed '    write /sys/class/android_usb/android0/iSerial PRO5TWRPV9' \
  "$twrp_legacy_adb_init"
require_fixed '    write /sys/class/android_usb/android0/functions adb' \
  "$twrp_legacy_adb_init"
require_fixed '    start adbd' "$twrp_legacy_adb_init"
require_fixed '/dev/android_adb' "$twrp_legacy_adb_init"
require_absent 'import /init.recovery.m86.rc' "$twrp_legacy_adb_init"
require_absent 'on property:ro.debuggable=1' "$twrp_legacy_adb_init"
require_absent 'on property:service.adb.root=1' "$twrp_legacy_adb_init"
require_absent 'mount functionfs' "$twrp_legacy_adb_init"
require_absent '${ro.serialno}' "$twrp_legacy_adb_init"
require_absent 'idProduct 4EE2' "$twrp_legacy_adb_init"
require_fixed 'PRO5_TWRP_DIRECT_ADB_V10=1' "$twrp_direct_adb_builder"
require_fixed 'build-pro5-twrp-legacy-adb-v9.sh' \
  "$twrp_direct_adb_builder"
require_fixed 'direct_adb_v10="${PRO5_TWRP_DIRECT_ADB_V10:-0}"' \
  "$twrp_legacy_adb_builder"
require_fixed \
  'expected_donor_sha256=faff297b31eab8aa1a6b85b31e801d72d0bc512cdee6850bd6d0451749013d31' \
  "$twrp_legacy_adb_builder"
require_fixed \
  'expected_v9_recovery_sha256=ee950be58363bd499c43af37464453ed6af8d3a50cf102855cc1b8ca5b63f079' \
  "$twrp_legacy_adb_builder"
require_fixed '/sbin/postscreenblank.sh' "$twrp_legacy_adb_builder"
require_fixed '/sbin/postscreenunblank.sh' "$twrp_legacy_adb_builder"
require_fixed 'TW_NO_SCREEN_TIMEOUT' "$twrp_legacy_adb_builder"
require_fixed '    setprop mtp.crash_check 1' "$twrp_direct_adb_init"
require_fixed '    write /dev/kmsg pro5_twrp_v10_usb_begin' \
  "$twrp_direct_adb_init"
require_fixed '    write /sys/class/android_usb/android0/idProduct 4EE7' \
  "$twrp_direct_adb_init"
require_fixed '    write /sys/class/android_usb/android0/iSerial PRO5TWRPV10' \
  "$twrp_direct_adb_init"
require_fixed '    write /sys/class/android_usb/android0/functions adb' \
  "$twrp_direct_adb_init"
require_fixed '    write /sys/class/android_usb/android0/enable 1' \
  "$twrp_direct_adb_init"
require_fixed '    start adbd' "$twrp_direct_adb_init"
require_fixed '/dev/android_adb' "$twrp_direct_adb_init"
require_absent 'import /init.recovery.m86.rc' "$twrp_direct_adb_init"
require_absent 'on property:sys.usb.config=' "$twrp_direct_adb_init"
require_absent 'mount functionfs' "$twrp_direct_adb_init"
require_absent '${ro.serialno}' "$twrp_direct_adb_init"
require_absent 'idProduct 4EE2' "$twrp_direct_adb_init"
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
require_fixed 'CONFIG_EXFAT_VIRTUAL_XATTR=y' "$twrp_build_worker"
require_fixed 'CONFIG_EXFAT_VIRTUAL_XATTR_SELINUX_LABEL=' \
  "$twrp_build_worker"
require_fixed 'fs/exfat/exfat_core.o' "$twrp_build_worker"
require_fixed 'fs/exfat/exfat_fs.o' "$twrp_build_worker"
require_fixed 'fs/pstore/ramoops.o' "$twrp_build_worker"
require_fixed 'drivers/platform/exynos/exynos_ramoops.o' "$twrp_build_worker"
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
  printf 'The currently gated recovery fallback requires exfat-fuse.\n' >&2
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
