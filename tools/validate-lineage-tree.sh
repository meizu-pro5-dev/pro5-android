#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
device_root="$project_root/device/meizu/m86"
kernel_root="$project_root/kernel/meizu/m86"
vendor_root="$project_root/vendor/meizu/m86"
hardware_graphics_root="$project_root/hardware/meizu/m86/graphics"
hardware_bluetooth_root="$project_root/hardware/meizu/m86/bluetooth"
hardware_audio_root="$project_root/hardware/meizu/m86/audio"

board_config="$device_root/BoardConfig.mk"
platform_config="$device_root/BoardConfigPlatform.mk"
android_makefile="$device_root/Android.mk"
device_makefile="$device_root/device.mk"
device_manifest="$device_root/manifest.xml"
nfc_experiment_product="$device_root/experiments/nfc-product.mk"
nfc_experiment_config="$device_root/nfc/libnfc-nxp.conf"
fingerprint_experiment_product="$device_root/experiments/fingerprint-product.mk"
nfc_experiment_init="$device_root/experiments/init.m86.nfc-experiment.rc"
nfc_sepolicy="$device_root/sepolicy/hal_nfc_default.te"
fingerprint_experiment_init="$device_root/experiments/init.m86.fingerprint-experiment.rc"
experiment_nfc_manifest="$device_root/experiments/manifest-nfc.xml"
experiment_fingerprint_manifest="$device_root/experiments/manifest-fingerprint.xml"
usb_product="$device_root/usb/product.mk"
usb_rc="$device_root/usb/rootdir/etc/init.m86.usb.rc"
parts_product="$device_root/parts/product.mk"
parts_makefile="$device_root/parts/Android.mk"
m86parts_manifest="$device_root/parts/M86Parts/AndroidManifest.xml"
m86parts_makefile="$device_root/parts/M86Parts/Android.mk"
m86parts_proguard="$device_root/parts/M86Parts/proguard.flags"
m86parts_privapp_permissions="$device_root/parts/M86Parts/privapp-permissions-org.lineageos.settings.m86.xml"
mback_contract="$device_root/parts/M86Parts/src/org/lineageos/settings/m86/mback/MbackContract.java"
mback_handler="$device_root/parts/M86Parts/src/org/lineageos/settings/m86/mback/KeyHandler.java"
mback_policy="$device_root/parts/M86Parts/src/org/lineageos/settings/m86/mback/MbackKeyPolicy.java"
mback_policy_test="$device_root/parts/M86Parts/tests/src/org/lineageos/settings/m86/mback/MbackKeyPolicyTest.java"
mback_policy_runner="$project_root/tools/test-mback-key-policy.sh"
mback_dtb_tool="$device_root/tools/build-mback-dtb.py"
mback_overlay="$device_root/overlay/lineage-sdk/lineage/res/res/values/config.xml"
init_rc="$device_root/rootdir/etc/init.m86.rc"
ueventd_rc="$device_root/rootdir/etc/ueventd.m86.rc"
releasetools="$device_root/releasetools/releasetools.py"
kernel_config="$kernel_root/arch/arm64/configs/cm_pro5_defconfig"
kernel_config_legacy="$kernel_root/arch/arm64/configs/pro5_defconfig"
fingerprint_experiment_kernel_config="$kernel_root/arch/arm64/configs/cm_pro5_fingerprint_experiment_defconfig"
kernel_fpc_driver="$kernel_root/drivers/input/fingerprint/fpc/fpc1020_main.c"
kernel_fpc_common="$kernel_root/drivers/input/fingerprint/fpc/fpc1020_common.c"
kernel_dhd_linux="$kernel_root/drivers/net/wireless/bcmdhd/dhd_linux.c"
kernel_nfc_driver="$kernel_root/drivers/misc/pn547_i2c_driver.c"
patch_series="$project_root/patches/series.tsv"
nfc_ese_patch="$project_root/patches/hardware-nxp-nfc/0001-reader-only-allow-disabling-ese-client-bridge.patch"
ownership_ledger="$project_root/docs/module-ownership.tsv"
debt_ledger="$project_root/docs/platform-debt.tsv"
retired_debt_ledger="$project_root/docs/retired-platform-debt.tsv"
gate_ledger="$project_root/docs/domain-gates.tsv"
waiver_ledger="$project_root/docs/domain-gate-waivers.tsv"
graphics_product="$device_root/graphics/product.mk"
graphics_board_config="$device_root/graphics/BoardConfigGraphics.mk"
graphics_manifest="$device_root/graphics/manifest.xml"
graphics_android_makefile="$device_root/graphics/Android.mk"
m86_gralloc_makefile="$hardware_graphics_root/gralloc/Android.mk"
m86_gralloc_source="$hardware_graphics_root/gralloc/framebuffer.cpp"
bluetooth_build="$hardware_bluetooth_root/Android.bp"
bluetooth_service_rc="$hardware_bluetooth_root/android.hardware.bluetooth@1.0-service.m86.rc"
bluetooth_manifest="$hardware_bluetooth_root/android.hardware.bluetooth@1.0-service.m86.xml"
bluetooth_file_contexts="$device_root/sepolicy/file_contexts"
bluetooth_genfs_contexts="$device_root/sepolicy/genfs_contexts"
bluetooth_address="$hardware_bluetooth_root/bluetooth_address.cc"
bluetooth_vendor_interface="$hardware_bluetooth_root/vendor_interface.cc"
wifi_product="$device_root/wifi/product.mk"
wifi_board_config="$device_root/wifi/BoardConfigWifi.mk"
wifi_manifest="$device_root/wifi/manifest.xml"
wifi_init="$device_root/wifi/rootdir/etc/init.m86.wifi.rc"
wifi_readme="$device_root/wifi/README.md"
radio_product="$device_root/radio/product.mk"
radio_readme="$device_root/radio/README.md"
radio_init="$device_root/radio/rootdir/etc/init.m86.radio.rc"
audio_product="$device_root/audio/product.mk"
audio_readme="$device_root/audio/README.md"
audio_evidence="$device_root/audio/proprietary-evidence.tsv"
audio_abi_contract="$hardware_audio_root/LegacyAudioAbiContract.h"
audio_wrapper_readme="$hardware_audio_root/README.md"
audio_abi_auditor="$project_root/tools/audit-m86-audio-abi.py"
audio_abi_test="$project_root/tools/test-m86-audio-abi-contract.sh"
audio_hifi_patch="$project_root/patches/frameworks-base/0003-audio-restore-meizu-hifi-routing.patch"
audio_hifi_global_patch="$project_root/patches/frameworks-base/0005-audio-hifi-global-settings.patch"
audio_hifi_settings_patch="$project_root/patches/packages-apps-settings/0001-system-add-meizu-hifi-sound.patch"
audio_hifi_audioflinger_patch="$project_root/patches/frameworks-av/0002-audioflinger-route-meizu-hifi-state-to-output.patch"
audio_hifi_settings_activity="$device_root/parts/M86Parts/src/org/lineageos/settings/m86/hifi/HifiSettingsActivity.java"
audio_hifi_settings_fragment="$device_root/parts/M86Parts/src/org/lineageos/settings/m86/hifi/HifiSettingsFragment.java"
audio_hifi_policy="$device_root/parts/M86Parts/src/org/lineageos/settings/m86/hifi/HifiPolicy.java"
audio_hifi_settings_xml="$device_root/parts/M86Parts/res/xml/hifi_settings.xml"
kernel_selinux_security="$kernel_root/security/selinux/include/security.h"
kernel_selinux_hooks="$kernel_root/security/selinux/hooks.c"
vendor_product="$vendor_root/m86-vendor.mk"
nfc_experiment_vendor_product="$vendor_root/m86-nfc-experiment-vendor.mk"
fingerprint_experiment_vendor_product="$vendor_root/m86-fingerprint-experiment-vendor.mk"
blob_list="$device_root/proprietary-files.txt"
build_worker="$project_root/remote/worker-build.sh"
kernel_build_worker="$project_root/remote/worker-build-kernel.sh"
twrp_build_worker="$project_root/remote/worker-build-twrp.sh"
memory_preflight="$project_root/remote/prepare-builder-memory.sh"
cache_releaser="$project_root/remote/release-build-cache.py"
install_worker="$project_root/remote/install-local-trees.sh"
apply_worker="$project_root/remote/apply-patches.sh"
start_build="$project_root/remote/start-build.sh"
push_stock_dtb="$project_root/remote/push-stock-dtb.sh"
prepare_vendor="$project_root/remote/prepare-vendor.sh"
detached_worker="$project_root/remote/detached-worker.sh"
dev_null_guard="$project_root/remote/assert-builder-dev-null.sh"
patch_auditor="$project_root/tools/audit-reviewed-patch-state.sh"
input_hasher="$project_root/tools/hash-authoritative-inputs.sh"
nfc_output_audit="$project_root/tools/audit-nfc-experiment-output.sh"
nfc_runtime_test="$project_root/tools/test-nfc-runtime.sh"
stock_lock="$project_root/locks/stock-flyme-8.0.5.0A.sha256"

fail() {
  printf 'LineageOS tree validation failed: %s\n' "$*" >&2
  exit 1
}

require_file() {
  [[ -s "$1" ]] || fail "missing required file: $1"
}

require_fixed() {
  local pattern="$1"
  local source_file="$2"
  rg -F -q -- "$pattern" "$source_file" || \
    fail "missing '$pattern' in $source_file"
}

require_absent() {
  local pattern="$1"
  local source_file="$2"
  if rg -F -q -- "$pattern" "$source_file"; then
    fail "forbidden '$pattern' in $source_file"
  fi
}

require_count() {
  local expected="$1"
  local pattern="$2"
  local source_file="$3"
  local actual
  actual="$(rg -F -c -- "$pattern" "$source_file" || true)"
  [[ "$actual" == "$expected" ]] || \
    fail "expected $expected occurrence(s) of '$pattern' in $source_file, got $actual"
}

for required in \
  "$board_config" \
  "$platform_config" \
  "$android_makefile" \
  "$device_makefile" \
  "$device_manifest" \
  "$nfc_experiment_product" \
  "$nfc_experiment_config" \
  "$fingerprint_experiment_product" \
  "$nfc_experiment_init" \
  "$nfc_sepolicy" \
  "$fingerprint_experiment_init" \
  "$experiment_nfc_manifest" \
  "$experiment_fingerprint_manifest" \
  "$usb_product" \
  "$usb_rc" \
  "$parts_product" \
  "$parts_makefile" \
  "$m86parts_manifest" \
  "$m86parts_makefile" \
  "$m86parts_proguard" \
  "$m86parts_privapp_permissions" \
  "$mback_contract" \
  "$mback_handler" \
  "$mback_policy" \
  "$mback_policy_test" \
  "$mback_policy_runner" \
  "$audio_hifi_settings_activity" \
  "$audio_hifi_settings_fragment" \
  "$audio_hifi_policy" \
  "$audio_hifi_settings_xml" \
  "$mback_dtb_tool" \
  "$mback_overlay" \
  "$init_rc" \
  "$ueventd_rc" \
  "$releasetools" \
  "$kernel_config" \
  "$kernel_config_legacy" \
  "$fingerprint_experiment_kernel_config" \
  "$kernel_fpc_driver" \
  "$kernel_fpc_common" \
  "$kernel_dhd_linux" \
  "$kernel_nfc_driver" \
  "$patch_series" \
  "$nfc_ese_patch" \
  "$ownership_ledger" \
  "$debt_ledger" \
  "$retired_debt_ledger" \
  "$gate_ledger" \
  "$waiver_ledger" \
  "$graphics_product" \
  "$graphics_board_config" \
  "$graphics_manifest" \
  "$graphics_android_makefile" \
  "$m86_gralloc_makefile" \
  "$m86_gralloc_source" \
  "$bluetooth_build" \
  "$bluetooth_service_rc" \
  "$bluetooth_manifest" \
  "$bluetooth_address" \
  "$bluetooth_vendor_interface" \
  "$bluetooth_file_contexts" \
  "$bluetooth_genfs_contexts" \
  "$wifi_product" \
  "$wifi_board_config" \
  "$wifi_manifest" \
  "$wifi_init" \
  "$wifi_readme" \
  "$radio_product" \
  "$radio_readme" \
  "$radio_init" \
  "$audio_product" \
  "$audio_readme" \
  "$audio_evidence" \
  "$audio_abi_contract" \
  "$audio_wrapper_readme" \
  "$audio_abi_auditor" \
  "$audio_abi_test" \
  "$kernel_selinux_security" \
  "$kernel_selinux_hooks" \
  "$vendor_product" \
  "$nfc_experiment_vendor_product" \
  "$fingerprint_experiment_vendor_product" \
  "$blob_list" \
  "$build_worker" \
  "$kernel_build_worker" \
  "$twrp_build_worker" \
  "$memory_preflight" \
  "$cache_releaser" \
  "$install_worker" \
  "$apply_worker" \
  "$start_build" \
  "$push_stock_dtb" \
  "$prepare_vendor" \
  "$detached_worker" \
  "$dev_null_guard" \
  "$patch_auditor" \
  "$input_hasher" \
  "$nfc_output_audit" \
  "$nfc_runtime_test" \
  "$stock_lock"; do
require_file "$required"
done

if find "$device_root" \
    \( -type d -name __pycache__ -o -type f -name '*.pyc' \) -print -quit | \
    grep -q .; then
  fail "Python cache output entered the authoritative m86 device tree"
fi
if [[ -e "$project_root/tools/build-pro5-hybrid-dtb.py" ]]; then
  fail "retired top-level hybrid DTB tool still has a duplicate owner"
fi
require_fixed 'tools/build-pro5-hybrid-dtb.py' "$retired_debt_ledger"
require_fixed 'workspace\ tooling)' "$apply_worker"
require_fixed 'Retired workspace tool is still present' "$apply_worker"

# Both full-system targets consume the WebView prebuilt. A Git LFS pointer is
# sufficient for boot/recovery iteration, but must be materialized and verified
# before either systemimage or bacon enters Ninja.
require_fixed '[[ "$target" == systemimage ]] || ((full_zip_target))' \
  "$build_worker"
require_fixed 'kernel | graphics | wifi | bluetooth | nfc | bootimage | recoveryimage | systemimage | testzip | bacon' \
  "$build_worker"
require_fixed 'kernel | graphics | wifi | bluetooth | nfc | bootimage | recoveryimage | systemimage | testzip | bacon' \
  "$start_build"
require_fixed 'android_build_target=bacon' "$build_worker"
require_fixed '"outputs",' \
  "$project_root/tools/hash-authoritative-inputs.sh"
require_fixed "--exclude '/outputs/'" "$project_root/remote/push-local.sh"
require_fixed '[[ "$target" != testzip ]]' "$build_worker"

# Every compile entrypoint must measure the real cgroup budget before doing
# build work. Full Android builds additionally serialize the two dexpreopt boot
# image edges that previously exhausted the 60 GiB builder limit.
for memory_guarded_worker in \
  "$build_worker" \
  "$kernel_build_worker" \
  "$twrp_build_worker"; do
  require_fixed 'prepare-builder-memory.sh' "$memory_guarded_worker"
  require_fixed 'effective_jobs' "$memory_guarded_worker"
  require_fixed 'BUILD-MEMORY.txt' "$memory_guarded_worker"
done
require_fixed 'POSIX_FADV_DONTNEED' "$cache_releaser"
require_fixed 'memory.current' "$memory_preflight"
require_fixed 'memory.max' "$memory_preflight"
require_fixed 'memory.events' "$memory_preflight"
require_fixed 'release-build-cache.py' "$memory_preflight"
require_fixed 'ART_BOOT_IMAGE_EXTRA_ARGS="-j$art_boot_image_jobs"' \
  "$build_worker"
require_fixed 'art_boot_image_jobs=1' "$build_worker"
  require_fixed 'combined-$product.ninja' "$build_worker"
  require_fixed 'ota_product_suffix="${product#lineage_}"' "$build_worker"
require_fixed 'for boot_arch in arm arm64' "$build_worker"
require_fixed 'for boot_art_attempt in 1 2' "$build_worker"
require_fixed 'record_boot_art_memory_snapshot "${boot_art_prefix}_before"' \
  "$build_worker"
require_fixed 'record_boot_art_memory_snapshot "${boot_art_prefix}_after"' \
  "$build_worker"
require_fixed 'cgroup_memory_current_bytes' "$build_worker"
require_fixed 'cgroup_memory_stat_' "$build_worker"
require_fixed 'cgroup_memory_event_' "$build_worker"
require_fixed 'host_mem_available_kib' "$build_worker"
require_fixed 'host_commit_limit_kib' "$build_worker"
require_fixed 'host_committed_as_kib' "$build_worker"
require_fixed 'build-$build_stamp-$boot_arch-boot-art-attempt-$boot_art_attempt.log' \
  "$build_worker"
require_fixed 'tee "$boot_art_log"' "$build_worker"
require_fixed "grep -E -q 'Failed anonymous mmap.*Cannot allocate memory'" \
  "$build_worker"
require_fixed 'retry_reason=transient_anonymous_mmap_failure' \
  "$build_worker"
require_fixed 'sleep 2' "$build_worker"
require_fixed 'exit "$boot_art_status"' "$build_worker"
require_fixed '"$ninja_binary" -f "$combined_ninja" -j1 "$boot_art" 2>&1' \
  "$build_worker"

validate_m0_ledgers() {
  awk -F '\t' '
    NR == 1 {
      if (NF != 11 || $1 != "milestone" || $11 != "evidence") exit 1
      next
    }
    NF != 11 { exit 1 }
    $10 !~ /^(facts-sealed|cleanup-planned|cleanup-built|device-passed|a11-ported|sealed|blocked)$/ { exit 1 }
    $10 ~ /^(device-passed|a11-ported|sealed)$/ &&
      $11 ~ /(pending|static|known incomplete)/ { exit 1 }
    END { if (NR < 2) exit 1 }
  ' "$ownership_ledger" || fail "invalid module ownership ledger"

  awk -F '\t' '
    NR == 1 {
      if (NF != 5 || $1 != "domain" || $5 != "status") exit 1
      next
    }
    NF != 5 || $1 !~ /^M[2-8]$/ || $5 != "deferred" { exit 1 }
    END { if (NR < 2) exit 1 }
  ' "$debt_ledger" || fail "invalid platform debt ledger"

  awk -F '\t' '
    NR == 1 {
      if (NF != 5 || $1 != "domain" || $4 != "retired_by") exit 1
      next
    }
    NF != 5 || $1 !~ /^M(1|2|3|4|5|8)$/ { exit 1 }
    END { if (NR < 9) exit 1 }
  ' "$retired_debt_ledger" || fail "invalid retired platform debt ledger"

  awk -F '\t' '
    NR == 1 {
      if (NF != 9 || $1 != "milestone" || $9 != "seal") exit 1
      next
    }
    NF != 9 { exit 1 }
    $3 !~ /^(pending|passed|blocked)$/ ||
    $4 !~ /^(pending|passed|blocked)$/ ||
    $6 !~ /^(pending|passed|blocked)$/ ||
    $7 !~ /^(pending|passed|blocked)$/ ||
    $9 !~ /^(pending|passed|blocked)$/ { exit 1 }
    $4 == "passed" && $5 ~ /^(-|.*static.*|.*pending.*)$/ { exit 1 }
    $7 == "passed" && $8 ~ /^(-|.*static.*|.*pending.*)$/ { exit 1 }
    $9 == "passed" && ($4 != "passed" || $7 != "passed") { exit 1 }
    END { if (NR < 2) exit 1 }
  ' "$gate_ledger" || fail "invalid A10/A11 domain gate ledger"

  awk -F '\t' '
    NR == 1 {
      if (NF != 8 || $1 != "date" || $8 != "evidence") exit 1
      next
    }
    NF != 8 { exit 1 }
    $2 !~ /^M[0-8]$/ || $5 != "user" ||
      $7 !~ /^(accepted-risk|closed)$/ { exit 1 }
    $7 == "accepted-risk" && $8 ~ /^(-|.*static.*|.*pending.*)$/ { exit 1 }
    END { if (NR < 2) exit 1 }
  ' "$waiver_ledger" || fail "invalid domain gate waiver ledger"

  if ! diff -u \
      <(awk -F '\t' 'NR > 1 { print $2 "\t" $3 }' "$debt_ledger" | LC_ALL=C sort) \
      <(awk -F '\t' 'NF == 2 && $1 !~ /^#/ { print }' "$patch_series" | LC_ALL=C sort) \
      >/dev/null; then
    fail "patch series and platform debt ledger differ"
  fi

  for retired_patch in \
    patches/build-make/0001-releasetools-allow-full-ota-without-cache-size.patch \
    patches/system-core/0001-adbd-support-legacy-android-usb-transport.patch \
    patches/system-core/0002-adbd-enter-native-android-usb-without-functionfs.patch \
    patches/external-glib/0001-build-libglib-for-m86-vendor.patch \
    patches/external-glib/0003-clang-port-legacy-android-stubs.patch \
    patches/legacy-m86-libfprint/0001-port-m86-fpc-to-android10.patch; do
    require_absent "$retired_patch" "$patch_series"
  done

  require_fixed 'capture_repo workspace' \
    "$project_root/tools/seal-local-source-state.sh"
  require_fixed '`device/meizu/m86`' "$project_root/docs/m0-baseline-index.md"
  require_fixed 'Build and static artifact evidence: available.' \
    "$project_root/docs/m0-baseline-index.md"
}

validate_m1_boot_and_ownership() {
  require_absent 'device/samsung/universal7420-common/BoardConfigCommon.mk' \
    "$board_config"
  require_fixed 'include $(M86_PATH)/BoardConfigPlatform.mk' "$board_config"
  require_fixed 'TARGET_USES_64_BIT_BINDER := true' "$platform_config"
  require_fixed 'TARGET_SLSI_VARIANT := bsp' "$platform_config"
  require_fixed 'TARGET_DEVICE_IS_M86 := true' "$platform_config"
  require_fixed 'Temporary A10 compatibility route' "$platform_config"

  for setting in \
    'BOARD_KERNEL_BASE := 0x40000000' \
    'BOARD_KERNEL_PAGESIZE := 4096' \
    'M86_KERNEL_BUILD_JOBS ?= 4' \
    'TARGET_KERNEL_ADDITIONAL_FLAGS += -j$(M86_KERNEL_BUILD_JOBS)' \
    '--kernel_offset 0x00080000' \
    '--ramdisk_offset 0x02000000' \
    '--second_offset 0x00f00000' \
    '--tags_offset 0x00000100' \
    'BOARD_BOOTIMAGE_PARTITION_SIZE := 25161728' \
    'BOARD_RECOVERYIMAGE_PARTITION_SIZE := 33550336' \
    'BOARD_SYSTEMIMAGE_PARTITION_SIZE := 2684350464' \
    'BOARD_CACHEIMAGE_PARTITION_SIZE := 536870912' \
    'BOARD_PACK_RADIOIMAGES += dtb'; do
    require_fixed "$setting" "$board_config"
  done
  if ! rg -q '^BOARD_KERNEL_CMDLINE :=[[:space:]]*$' "$board_config"; then
    fail "m86 boot header command line is not explicitly empty"
  fi
  require_absent 'BOARD_INCLUDE_DTB_IN_BOOTIMG' "$board_config"
  require_absent 'BOARD_CUSTOM_BOOTIMG_MK' "$board_config"
  require_absent 'TARGET_CUSTOM_DTBTOOL' "$board_config"

  require_fixed 'M86_DEVICE_PATH := $(LOCAL_PATH)' "$android_makefile"
  require_fixed 'M86_STOCK_DTB := $(M86_DEVICE_PATH)/prebuilt/dtb.img' \
    "$android_makefile"
  require_fixed 'M86_MBACK_DTB_TOOL := $(M86_DEVICE_PATH)/tools/build-mback-dtb.py' \
    "$android_makefile"
  require_fixed 'M86_FPC_BACKEND := raw-navigation' "$board_config"
  require_fixed 'M86_FPC_BACKEND := tee' "$board_config"
  require_fixed 'TARGET_KERNEL_CONFIG := cm_pro5_defconfig' "$board_config"
  require_fixed 'M86_ENABLE_FINGERPRINT_EXPERIMENT ?= false' \
    "$device_root/lineage_m86.mk"
  require_fixed 'M86_ENABLE_FINGERPRINT_EXPERIMENT := true' \
    "$device_root/lineage_m86_fingerprint_experiment.mk"
  require_fixed \
    'TARGET_KERNEL_CONFIG := cm_pro5_fingerprint_experiment_defconfig' \
    "$board_config"
  require_fixed '--stock $(M86_STOCK_DTB)' "$android_makefile"
  require_fixed '--output $@' "$android_makefile"
  require_fixed 'm86-dtbimage: $(M86_INSTALLED_DTB)' "$android_makefile"
  require_fixed 'INSTALLED_RADIOIMAGE_TARGET += $(M86_INSTALLED_DTB)' \
    "$android_makefile"
  require_absent 'M86_KERNEL_DTB' "$android_makefile"
  require_fixed 'expected_dtb_hash="8b9121f25a78716ac1710536cea562967bd77ad0cf2df283ae25715808cff1cc"' \
    "$build_worker"
  require_fixed 'M3-DTB.txt' "$build_worker"
  require_fixed '--verify "$release_dtb"' "$build_worker"
  require_fixed 'kernel-generated.dtb' "$build_worker"
  require_fixed 'kernel_generated_dtb=diagnostic-only' "$build_worker"
  require_fixed 'M86_KERNEL_BUILD_JOBS="$jobs"' "$build_worker"
  require_fixed 'vendor_blob_audit=not-run-for-%s' "$build_worker"
  require_absent 'zip -q -u' "$build_worker"
  require_absent 'ota_from_target_files.py' "$build_worker"
  require_fixed 'locked stock DTB' "$install_worker"
  require_fixed 'sha256sum "$stock_dtb"' "$push_stock_dtb"

  expected_stock_hash="$(awk '$2 == "dtb" { print $1 }' "$stock_lock")"
  [[ "$expected_stock_hash" == \
    b45054fa87a5ffe114843953172d48d36408e1f93db35a6cbdfb0a8fc58a2165 ]] || \
    fail "stock lock contains the wrong DTB hash"
  local_stock_dtb="$project_root/../work/pro5-flyme-8.0.5.0A/dtb-inspect/dtb"
  if [[ -s "$local_stock_dtb" ]]; then
    actual_stock_hash="$(sha256sum "$local_stock_dtb" | awk '{ print $1 }')"
    [[ "$actual_stock_hash" == "$expected_stock_hash" ]] || \
      fail "local stock DTB differs from its lock"
    if ! (
      mback_dtb="$(mktemp "${TMPDIR:-/tmp}/m86-mback-dtb.XXXXXX")"
      trap 'rm -f -- "$mback_dtb"' EXIT
      python3 "$mback_dtb_tool" \
        --stock "$local_stock_dtb" --output "$mback_dtb" | \
        grep -F -x -q \
          'mback_dtb_sha256=8b9121f25a78716ac1710536cea562967bd77ad0cf2df283ae25715808cff1cc'
      python3 "$mback_dtb_tool" \
        --stock "$local_stock_dtb" --verify "$mback_dtb" >/dev/null
    ); then
      fail "m86 mBack DTB derivation or structure audit failed"
    fi
  fi

  require_count 1 '$(call inherit-product, $(LOCAL_PATH)/storage/product.mk)' \
    "$device_makefile"
  require_count 1 'rootdir/etc/fstab.m86:$(TARGET_COPY_OUT_RAMDISK)/fstab.m86' \
    "$device_root/storage/product.mk"
  require_count 1 'rootdir/etc/fstab.m86:root/fstab.m86' \
    "$device_root/storage/product.mk"
  require_fixed 'BOARD_ROOT_EXTRA_FOLDERS += custom efs mnv' "$board_config"
  require_fixed 'mount_all /fstab.m86' "$init_rc"
  require_absent 'mkdir /efs' "$init_rc"
  require_fixed 'BOOT/RAMDISK/fstab.m86' "$build_worker"
  require_fixed 'ROOT/fstab.m86' "$build_worker"
  require_fixed 'for mountpoint in cache custom data efs mnv' "$build_worker"
  require_fixed 'second_stage_mountpoint=ROOT/%s' "$build_worker"
  require_absent 'on property:sys.usb.config=adb && property:sys.usb.configfs=0' \
    "$usb_rc"
  require_absent 'start vendor.bluetooth-1-0' "$usb_rc"
  require_fixed 'on property:vendor.m86.identity.ready=1' "$usb_rc"
  require_fixed '$(call inherit-product, $(LOCAL_PATH)/usb/product.mk)' \
    "$device_makefile"
  require_fixed 'ro.adb.nonblocking_ffs=false' "$usb_product"
  require_fixed 'persist.sys.usb.config=none' "$usb_product"
  require_absent 'IncrementalOTA_InstallEnd' "$releasetools"
  require_fixed 'Installing the verified m86 FPC-backend DTB' "$releasetools"

  require_fixed 'device_revision=' "$build_worker"
  require_fixed 'kernel_revision=' "$build_worker"
  require_fixed 'vendor_revision=' "$build_worker"
  require_fixed 'PRO5_ALLOW_DIRTY_SOURCE=1' "$start_build"
  require_fixed 'Refusing build from dirty local source inputs:' "$start_build"
  require_fixed 'Refusing a release bacon build from dirty source inputs.' \
    "$start_build"
  require_fixed 'authoritative_input_sha256=' "$build_worker"
  require_fixed 'Development or experiment artifact was not promoted to lineage-latest.' \
    "$build_worker"
  require_fixed 'audit-reviewed-patch-state.sh' \
    "$project_root/remote/apply-patches.sh"
  require_fixed 'Platform diff exceeds reviewed patch queue:' "$patch_auditor"
  require_fixed 'Required authoritative local tree is missing or empty:' \
    "$install_worker"
  require_fixed 'Fingerprinting:' "$install_worker"
  require_absent 'Skipping empty local tree:' "$install_worker"

  stock_push_line="$(rg -n -F '"$script_dir/push-stock-blobs.sh"' \
    "$prepare_vendor" | cut -d: -f1)"
  tree_install_line="$(rg -n -F '"$script_dir/install-local-trees.sh"' \
    "$prepare_vendor" | cut -d: -f1)"
  [[ "$stock_push_line" =~ ^[0-9]+$ ]] && \
    [[ "$tree_install_line" =~ ^[0-9]+$ ]] && \
    ((stock_push_line < tree_install_line)) || \
    fail "prepare-vendor must stage stock inputs before installing trees"

  require_fixed 'flock -x 9' "$detached_worker"
  require_fixed 'starttime=' "$detached_worker"
  require_fixed '/proc/$pid/cmdline' "$detached_worker"
}

validate_m2_graphics() {
  require_fixed '$(call inherit-product, $(LOCAL_PATH)/graphics/product.mk)' \
    "$device_makefile"
  require_absent 'gralloc.exynos5' "$device_makefile"
  for package in \
    android.hardware.graphics.allocator@2.0-impl \
    android.hardware.graphics.composer@2.1-impl \
    android.hardware.graphics.mapper@2.0-impl \
    gralloc.m86 \
    hwcomposer.exynos5 \
    memtrack.exynos5 \
    libexynosdisplay \
    libhdmi \
    libhwc2on1adapter \
    libhwc2onfbadapter \
    libion; do
    require_fixed "$package" "$graphics_product"
  done
  require_absent 'libcec' "$graphics_product"
  require_absent 'libfimg' "$graphics_product"
  require_absent 'libExynosHWCService' "$graphics_product"
  require_absent 'libExynosHWCService' "$vendor_product"
  require_fixed 'deferred_graphics_paths=(' "$prepare_vendor"
  require_fixed 'PRODUCT_PROPERTY_OVERRIDES += \' "$graphics_product"
  require_fixed 'ro.hardware.gralloc=m86' "$graphics_product"
  require_fixed 'include $(M86_PATH)/graphics/BoardConfigGraphics.mk' \
    "$board_config"
  require_fixed 'BOARD_USES_EXYNOS5_COMMON_GRALLOC := true' \
    "$graphics_board_config"
  require_absent 'BOARD_USES_EXYNOS5_COMMON_GRALLOC := true' \
    "$platform_config"
  require_fixed '$(M86_PATH)/graphics/manifest.xml' "$board_config"
  for graphics_hal in \
    android.hardware.graphics.allocator \
    android.hardware.graphics.composer \
    android.hardware.graphics.mapper \
    android.hardware.memtrack; do
    require_fixed "<name>$graphics_hal</name>" "$graphics_manifest"
    require_absent "<name>$graphics_hal</name>" "$device_manifest"
  done
  require_fixed 'M86_VULKAN_HAL_SYMLINKS' "$graphics_android_makefile"
  require_absent 'M86_VULKAN_HAL_SYMLINKS' "$android_makefile"
  require_fixed 'LOCAL_MODULE := gralloc.m86' "$m86_gralloc_makefile"
  require_fixed 'hardware/samsung_slsi/exynos/gralloc/gralloc.cpp' \
    "$m86_gralloc_makefile"
  require_fixed 'fb_post: invalid copy size' "$m86_gralloc_source"
  require_fixed 'buffer_vaddr[3]' "$m86_gralloc_source"
  require_absent \
    'patches/hardware-samsung-slsi-exynos/0001-gralloc-harden-fbdev-copy-post.patch' \
    "$patch_series"
  require_fixed \
    'patches/hardware-samsung-slsi-exynos/0001-gralloc-harden-fbdev-copy-post.patch' \
    "$retired_debt_ledger"
  require_fixed 'Retired and reversed:' \
    "$project_root/remote/apply-patches.sh"
  require_fixed 'Already absent (touched paths clean):' \
    "$project_root/remote/apply-patches.sh"
  require_fixed 'hardware/meizu/m86' "$install_worker"
  require_fixed \
    'include hardware/meizu/m86/graphics/gralloc/Android.mk' \
    "$android_makefile"
  require_fixed 'source_built_gralloc_count=2' "$build_worker"
  for module in \
    gralloc.m86 \
    hwcomposer.exynos5 \
    memtrack.exynos5 \
    libexynosdisplay \
    libexynosgscaler \
    libexynosscaler \
    libexynosutils \
    libexynosv4l2 \
    libhwcutils \
    libmpp \
    libhdmi \
    libion \
    libhwc2on1adapter \
    libhwc2onfbadapter; do
    require_fixed "$module-target32" "$build_worker"
    require_fixed "$module-target64" "$build_worker"
  done
  require_fixed 'source_built_hwcomposer_count=2' "$build_worker"
  require_fixed 'source_built_libexynosdisplay_count=2' "$build_worker"
  require_fixed 'source_built_graphics_dependency_count=14' "$build_worker"
  require_fixed 'source_built_libhdmi_count=2' "$build_worker"
  require_fixed 'source_built_libion_count=2' "$build_worker"
  require_fixed 'source_built_replaced_graphics_destination_count=24' \
    "$build_worker"
  require_fixed 'source_built_graphics_adapter_count=4' "$build_worker"
  require_fixed 'source_built_graphics_interface_count=9' "$build_worker"
  require_fixed 'source_built_graphics_runtime_destination_count=37' \
    "$build_worker"
  require_fixed 'source_owned_graphics_family_destination_count=' \
    "$build_worker"
  require_fixed 'source_owned_graphics_interface_destination_count=' \
    "$build_worker"
  require_fixed 'source_owned_graphics_runtime_destination_count=' \
    "$build_worker"
  require_fixed 'GRAPHICS-OUTPUT.txt' "$build_worker"
  require_fixed 'GRAPHICS-TARGET-FILES.txt' "$build_worker"
  require_fixed 'assert_graphics_elf_identity' "$build_worker"
  require_fixed 'assert_graphics_target_files' "$build_worker"
  require_fixed 'Packaged graphics SONAME owner is not the unique 32/64 pair' \
    "$build_worker"
  require_fixed 'Packaged target-files retained retired graphics output' \
    "$build_worker"
  for relative_path in \
    lib/libexynosdisplay.so \
    lib64/libexynosdisplay.so \
    lib/libhdmi.so \
    lib64/libhdmi.so \
    lib/libion.so \
    lib64/libion.so \
    vendor/lib/libhwc2on1adapter.so \
    vendor/lib64/libhwc2on1adapter.so \
    vendor/lib/libhwc2onfbadapter.so \
    vendor/lib64/libhwc2onfbadapter.so \
    vendor/bin/hw/android.hardware.graphics.allocator@2.0-service \
    vendor/lib/hw/android.hardware.graphics.allocator@2.0-impl.so \
    vendor/lib64/hw/android.hardware.graphics.allocator@2.0-impl.so \
    vendor/lib/hw/android.hardware.graphics.composer@2.1-impl.so \
    vendor/lib64/hw/android.hardware.graphics.composer@2.1-impl.so \
    vendor/lib/hw/android.hardware.graphics.mapper@2.0-impl.so \
    vendor/lib64/hw/android.hardware.graphics.mapper@2.0-impl.so \
    vendor/lib/hw/android.hardware.memtrack@1.0-impl.so \
    vendor/lib64/hw/android.hardware.memtrack@1.0-impl.so; do
    require_fixed "$relative_path" "$build_worker"
  done
  require_fixed 'assert_single_ninja_owner' "$build_worker"
  require_fixed 'Expected one Ninja producer' "$build_worker"
  require_fixed 'kernel_dtb_audit=not-run-for-%s' "$build_worker"
}

validate_m3_storage_usb_input() {
  for default_kernel_config in "$kernel_config" "$kernel_config_legacy"; do
    require_fixed 'CONFIG_FINGERPRINT_FPC_FPC1020_FAMILY=y' \
      "$default_kernel_config"
    require_fixed '# CONFIG_FINGERPRINT_FPC_TEE is not set' \
      "$default_kernel_config"
    require_fixed '# CONFIG_SECURE_OS_BOOSTER_API is not set' \
      "$default_kernel_config"
  done
  require_fixed '# CONFIG_FINGERPRINT_FPC_FPC1020_FAMILY is not set' \
    "$fingerprint_experiment_kernel_config"
  require_fixed 'CONFIG_FINGERPRINT_FPC_TEE=y' \
    "$fingerprint_experiment_kernel_config"
  require_fixed '# CONFIG_SECURE_OS_BOOSTER_API is not set' \
    "$fingerprint_experiment_kernel_config"
  require_fixed '{ .compatible = "fpc,fpc_irq", },' "$kernel_fpc_driver"
  require_fixed 'of_get_named_gpio(node, "gx,gpio_irq", 0)' \
    "$kernel_fpc_driver"
  require_fixed 'of_get_named_gpio(node, "gx,gpio_reset", 0)' \
    "$kernel_fpc_driver"
  require_fixed 'fpc1020->chip.spi_max_khz    = 4800;' "$kernel_fpc_common"
  require_fixed 'SPI_PATH = "/spi@14d70000"' "$mback_dtb_tool"
  require_fixed 'FPC_PATH = SPI_PATH + "/securefpc_spidev@0"' \
    "$mback_dtb_tool"
  require_fixed 'struct.pack_into(">I", output, nop_offset, FDT_NOP)' \
    "$mback_dtb_tool"
  require_fixed 'changed_bytes != 4' "$mback_dtb_tool"
  require_fixed 'output_properties.get(FPC_PATH) != stock_properties.get(FPC_PATH)' \
    "$mback_dtb_tool"
  require_fixed 'encryptable=/cache/metadata' \
    "$device_root/storage/rootdir/etc/fstab.m86"
  require_fixed 'storage/rootdir/etc/recovery.fstab' "$board_config"
  require_fixed 'Android 10 resolves that same state' \
    "$device_root/storage/README.md"
  require_count 1 'm86_usb_serial' "$usb_product"
  require_count 1 'android.hardware.usb@1.0-service.basic' "$usb_product"
  require_count 1 'rootdir/etc/init.m86.usb.rc:root/init.m86.usb.rc' \
    "$usb_product"
  require_absent 'vendor.bluetooth' "$usb_rc"
  require_fixed 'patches/system-core/0001-adbd-support-legacy-android-usb-transport.patch' \
    "$retired_debt_ledger"
  require_fixed 'patches/system-core/0002-adbd-enter-native-android-usb-without-functionfs.patch' \
    "$retired_debt_ledger"
  require_fixed '$(call inherit-product, $(LOCAL_PATH)/input/standard-keys/product.mk)' \
    "$device_makefile"
  require_count 1 'keylayout/gpio-keys.kl:system/usr/keylayout/gpio-keys.kl' \
    "$device_root/input/standard-keys/product.mk"
  require_count 1 'keylayout/fts.kl:system/usr/keylayout/fts.kl' \
    "$device_root/input/standard-keys/product.mk"
  require_fixed 'key 102   HOME' \
    "$device_root/input/standard-keys/keylayout/gpio-keys.kl"
  require_fixed 'key 114   VOLUME_DOWN' \
    "$device_root/input/standard-keys/keylayout/gpio-keys.kl"
  require_fixed 'key 115   VOLUME_UP' \
    "$device_root/input/standard-keys/keylayout/gpio-keys.kl"
  require_fixed 'key 116   POWER' \
    "$device_root/input/standard-keys/keylayout/gpio-keys.kl"
  require_absent 'F9' "$device_root/input/standard-keys/product.mk"
  require_absent 'fpc' "$device_root/input/standard-keys/product.mk"
  require_fixed '$(call inherit-product, $(LOCAL_PATH)/parts/product.mk)' \
    "$device_makefile"
  require_count 1 'include $(call all-subdir-makefiles,$(LOCAL_PATH))' \
    "$android_makefile"
  require_count 1 'include $(call all-subdir-makefiles,$(LOCAL_PATH))' \
    "$parts_makefile"
  require_count 1 '    M86Parts' "$parts_product"
  require_count 1 'keylayout/fpc1020.kl:system/usr/keylayout/fpc1020.kl' \
    "$parts_product"
  require_count 1 'keylayout/uinput-fpc.kl:system/usr/keylayout/uinput-fpc.kl' \
    "$parts_product"
  require_count 1 \
    'M86Parts/privapp-permissions-org.lineageos.settings.m86.xml:system/etc/permissions/privapp-permissions-org.lineageos.settings.m86.xml' \
    "$parts_product"
  require_fixed 'LOCAL_PRIVATE_PLATFORM_APIS := true' "$m86parts_makefile"
  require_fixed 'LOCAL_PRIVILEGED_MODULE := true' "$m86parts_makefile"
  require_count 1 'LOCAL_PROGUARD_FLAG_FILES := proguard.flags' \
    "$m86parts_makefile"
  require_fixed 'org.lineageos.platform.internal' "$m86parts_makefile"
  require_count 1 \
    '-keep,allowoptimization public final class org.lineageos.settings.m86.mback.KeyHandler {' \
    "$m86parts_proguard"
  require_count 1 '    public <init>(android.content.Context);' \
    "$m86parts_proguard"
  require_count 1 \
    '    public android.view.KeyEvent handleKeyEvent(android.view.KeyEvent);' \
    "$m86parts_proguard"
  require_fixed 'org.lineageos.settings.m86.hifi.HifiSettingsActivity {' \
    "$m86parts_proguard"
  require_fixed 'org.lineageos.settings.m86.hifi.HifiSettingsFragment {' \
    "$m86parts_proguard"
  require_absent '-dontobfuscate' "$m86parts_proguard"
  require_absent '-dontshrink' "$m86parts_proguard"
  require_absent 'allowobfuscation' "$m86parts_proguard"
  require_absent 'org.lineageos.settings.m86.**' "$m86parts_proguard"
  require_absent '    *;' "$m86parts_proguard"
  if [[ "$(rg -c '^-' "$m86parts_proguard" || true)" != 3 ]]; then
    fail "M86Parts must have exactly three narrow ProGuard keep directives"
  fi
  require_fixed 'android.permission.WRITE_SECURE_SETTINGS' "$m86parts_manifest"
  require_fixed 'lineageos.permission.WRITE_SETTINGS' "$m86parts_manifest"
  require_fixed 'com.android.settings.action.EXTRA_SETTINGS' "$m86parts_manifest"
  require_count 1 \
    '<privapp-permissions package="org.lineageos.settings.m86">' \
    "$m86parts_privapp_permissions"
  require_count 1 \
    '<permission name="android.permission.WRITE_SECURE_SETTINGS" />' \
    "$m86parts_privapp_permissions"
  require_absent 'lineageos.permission.WRITE_SETTINGS' \
    "$m86parts_privapp_permissions"
  if [[ "$(xmllint --xpath 'count(/permissions/privapp-permissions)' \
      "$m86parts_privapp_permissions")" != 1 ]] || \
      [[ "$(xmllint --xpath \
        'count(/permissions/privapp-permissions/permission)' \
        "$m86parts_privapp_permissions")" != 1 ]] || \
      [[ "$(xmllint --xpath \
        'string(/permissions/privapp-permissions/@package)' \
        "$m86parts_privapp_permissions")" != org.lineageos.settings.m86 ]] || \
      [[ "$(xmllint --xpath \
        'string(/permissions/privapp-permissions/permission/@name)' \
        "$m86parts_privapp_permissions")" != \
        android.permission.WRITE_SECURE_SETTINGS ]]; then
    fail "M86Parts privapp whitelist is not the exact one-package/one-permission contract"
  fi
  require_fixed '/system/priv-app/M86Parts/M86Parts.apk' "$mback_overlay"
  require_fixed 'org.lineageos.settings.m86.mback.KeyHandler' "$mback_overlay"
  require_fixed 'implements DeviceKeyHandler' "$mback_handler"
  require_fixed 'DEVICE_FPC1020 = "fpc1020"' "$mback_policy"
  require_fixed 'DEVICE_UINPUT_FPC = "uinput-fpc"' "$mback_policy"
  require_fixed 'DEVICE_GPIO_KEYS = "gpio-keys"' "$mback_policy"
  require_fixed 'KEYCODE_F9 = 139' "$mback_policy"
  require_fixed 'KEYCODE_F10 = 140' "$mback_policy"
  require_fixed 'KEYCODE_F11 = 141' "$mback_policy"
  require_fixed 'KEYCODE_F12 = 142' "$mback_policy"
  require_fixed 'switch (scanCode)' "$mback_policy"
  require_fixed 'case 190:' "$mback_policy"
  require_fixed 'case 191:' "$mback_policy"
  require_fixed 'keyCode == KEYCODE_HOME && scanCode == 102' "$mback_policy"
  for scan_code in 305; do
    require_fixed "scanCode == $scan_code" "$mback_policy"
  done
  for raw_scan_code in 139 158 190 191; do
    require_fixed "case $raw_scan_code:" "$mback_policy"
  done
  require_fixed 'return null;' "$mback_handler"
  require_fixed 'MbackKeyPolicy.shouldExecute(gesture, enabled)' \
    "$mback_handler"
  require_fixed 'MbackKeyPolicy.shouldConsume(gesture)' "$mback_handler"
  require_fixed 'gesture == MbackKeyPolicy.GESTURE_PHYSICAL_HOME' \
    "$mback_handler"
  require_fixed 'return enabled ? event : null;' "$mback_handler"
  require_fixed 'MbackContract.isMbackNavigationEnabled' "$mback_handler"
  require_absent 'performAction(MbackContract.ACTION_HOME, deviceId, userId)' \
    "$mback_handler"
  require_fixed 'actionId=" + action' "$mback_handler"
  require_fixed '"USB Keyboard", 139, 158' "$mback_policy_test"
  require_fixed '"gpio-keys", 3, 102' "$mback_policy_test"
  require_fixed 'shouldExecute(gesture, false)' "$mback_policy_test"
  require_fixed 'shouldConsume(gesture)' "$mback_policy_test"
  require_fixed '"$javac_bin" -d "$test_root"' "$mback_policy_runner"
  require_fixed 'test-mback-key-policy.sh' "$build_worker"
  require_fixed 'M3-MBACK-POLICY-TEST.txt' "$build_worker"
  require_fixed 'stale_m3_keylayout' "$build_worker"
  require_fixed 'rm -f -- "$product_out/system/usr/keylayout/' "$build_worker"
  require_fixed 'get_build_var TARGET_KERNEL_CONFIG' "$build_worker"
  require_fixed 'get_build_var M86_FPC_BACKEND' "$build_worker"
  require_fixed 'actual_fpc_backend" != "$expected_fpc_backend"' "$build_worker"
  require_fixed 'expected_kernel_config=cm_pro5_fingerprint_experiment_defconfig' \
    "$build_worker"
  require_fixed 'expected_fpc_backend=tee' "$build_worker"
  require_fixed 'fingerprint_dtb=stock-secure-mode' "$build_worker"
  require_fixed '# CONFIG_SECURE_OS_BOOSTER_API is not set' "$build_worker"
  require_fixed 'audit-fingerprint-output.sh" "$product_out" experiment' \
    "$build_worker"
  require_fixed 'Settings.Secure.getIntForUser' "$mback_contract"
  require_fixed 'Settings.Secure.putIntForUser' "$mback_contract"
  require_absent 'LineageSettings.System.MBACK_' "$mback_contract"
  require_absent 'android.accessibilityservice' "$device_root/parts"
  require_absent 'fingerprint@' "$device_root/parts"
  require_absent 'ro.meizu.hardware.mback=true' "$device_root/system.prop"
  require_absent 'qemu.hw.mainkeys=' "$device_root/system.prop"
  for retired_mback_patch in \
    patches/lineage-sdk/0001-input-add-meizu-mback-actions-and-settings.patch \
    patches/frameworks-base/0004-input-handle-configurable-meizu-mback-gestures.patch \
    patches/packages-apps-lineageparts/0001-buttons-add-meizu-mback-controls.patch; do
    require_absent "$retired_mback_patch" "$patch_series"
    require_fixed "$retired_mback_patch" "$retired_debt_ledger"
  done
  require_fixed 'assert_m3_target_files "$target_files_tree"' "$build_worker"
  require_fixed 'M3-TARGET-FILES.txt' "$build_worker"
  require_fixed 'SYSTEM/priv-app/M86Parts/M86Parts.apk' "$build_worker"
  require_fixed \
    'Lorg/lineageos/settings/m86/mback/KeyHandler;' "$build_worker"
  require_fixed \
    'local dexdump="$out_root/host/linux-x86/bin/dexdump"' "$build_worker"
  require_fixed \
    'mktemp "$artifact_dir/.M86Parts-dexdump.XXXXXX"' "$build_worker"
  require_fixed \
    "trap 'rm -f -- \"\$m86parts_dexdump\"' EXIT" "$build_worker"
  require_fixed '"$dexdump" -d "$packaged_apk"' "$build_worker"
  require_fixed 'Class descriptor  : ' "$build_worker"
  require_fixed 'm86parts_keyhandler_descriptor_count=%s' "$build_worker"
  require_fixed \
    'reflected DeviceKeyHandler classes; expected 1.' \
    "$build_worker"
  if sed -n '/^assert_m3_target_files()/,/^}/p' "$build_worker" | \
      grep -F 'strings' >/dev/null; then
    fail "M3 APK class audit must use dexdump, not raw strings"
  fi
  require_fixed \
    'SYSTEM/etc/permissions/privapp-permissions-org.lineageos.settings.m86.xml' \
    "$build_worker"
  require_fixed 'local packaged_dtb="$target_files_tree/RADIO/dtb.img"' \
    "$build_worker"
  require_fixed '--verify "$packaged_dtb"' "$build_worker"
  require_fixed 'dtb_sha256=%s' "$build_worker"
  require_fixed 'default_fingerprint_userspace=absent' "$build_worker"
  require_fixed 'default_fingerprint_feature=absent' "$build_worker"
  require_fixed 'default_fingerprint_vintf=absent' "$build_worker"
  require_fixed 'SYSTEM/bin/m86_usb_serial' "$build_worker"
  require_fixed 'SYSTEM/vendor/bin/hw/android.hardware.usb@1.0-service.basic' \
    "$build_worker"
  require_fixed 'SYSTEM/usr/keylayout/fts.kl' "$build_worker"
  require_fixed 'SYSTEM/usr/keylayout/gpio-keys.kl' "$build_worker"
  require_fixed 'SYSTEM/usr/keylayout/fpc1020.kl' "$build_worker"
  require_fixed 'SYSTEM/usr/keylayout/uinput-fpc.kl' "$build_worker"
  require_fixed 'old_m3_owner_path' "$build_worker"
}

validate_m4_connectivity_radio() {
  for package in \
    android.hardware.wifi@1.0-service.legacy \
    hostapd \
    wpa_supplicant; do
    require_fixed "$package" "$wifi_product"
    require_absent "$package" "$device_makefile"
  done
  for package in \
    android.hardware.bluetooth@1.0-impl.m86 \
    android.hardware.bluetooth@1.0-service.m86 \
    rild \
    libril; do
    require_fixed "$package" "$device_makefile"
  done
  require_count 1 \
    '$(call inherit-product, $(LOCAL_PATH)/wifi/product.mk)' \
    "$device_makefile"
  require_count 1 \
    'android.hardware.wifi.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.xml' \
    "$wifi_product"
  require_count 1 \
    'android.hardware.wifi.direct.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.direct.xml' \
    "$wifi_product"
  require_count 1 'wifi.interface=wlan0' "$wifi_product"
  require_count 1 'wifi.direct.interface=p2p-dev-wlan0' "$wifi_product"
  require_absent 'wifi.interface=' "$device_root/system.prop"
  require_absent 'android.hardware.wifi.xml' "$device_makefile"
  require_count 1 'include $(M86_PATH)/wifi/BoardConfigWifi.mk' \
    "$board_config"
  for wifi_board_contract in \
    'BOARD_WLAN_DEVICE := bcmdhd' \
    'WPA_SUPPLICANT_USE_HIDL := true' \
    'BOARD_WPA_SUPPLICANT_PRIVATE_LIB := lib_driver_cmd_bcmdhd' \
    'BOARD_HOSTAPD_PRIVATE_LIB := lib_driver_cmd_bcmdhd' \
    'WIFI_DRIVER_FW_PATH_PARAM := /sys/module/bcmdhd/parameters/firmware_path' \
    'WIFI_DRIVER_FW_PATH_STA := /system/vendor/firmware/fw_bcmdhd.bin' \
    'WIFI_DRIVER_FW_PATH_AP := /system/vendor/firmware/fw_bcmdhd_apsta.bin'; do
    require_fixed "$wifi_board_contract" "$wifi_board_config"
    require_absent "$wifi_board_contract" "$board_config"
  done
  require_fixed 'int dtim_suspended = CUSTOM_SUSPEND_BCN_LI_DTIM;' \
    "$kernel_dhd_linux"
  require_absent 'int dtim_suspended = 0;' "$kernel_dhd_linux"
  require_count 1 'DEVICE_MANIFEST_FILE += $(M86_PATH)/wifi/manifest.xml' \
    "$wifi_board_config"
  for wifi_hal in \
    android.hardware.wifi \
    android.hardware.wifi.hostapd \
    android.hardware.wifi.supplicant; do
    require_absent "<name>$wifi_hal</name>" "$device_manifest"
  done
  [[ "$(xmllint --xpath \
      "count(/manifest/hal[name='android.hardware.wifi' and version='1.3' and transport='hwbinder']/interface[name='IWifi']/instance[text()='default'])" \
      "$wifi_manifest")" == "1" ]] || \
    fail "Wi-Fi fragment must own exactly one IWifi default instance"
  [[ "$(xmllint --xpath \
      "count(/manifest/hal[name='android.hardware.wifi.hostapd' and version='1.1' and transport='hwbinder']/interface[name='IHostapd']/instance[text()='default'])" \
      "$wifi_manifest")" == "1" ]] || \
    fail "Wi-Fi fragment must own exactly one hostapd default instance"
  [[ "$(xmllint --xpath \
      "count(/manifest/hal[name='android.hardware.wifi.supplicant' and version='1.2' and transport='hwbinder']/interface[name='ISupplicant']/instance[text()='default'])" \
      "$wifi_manifest")" == "1" ]] || \
    fail "Wi-Fi fragment must own exactly one supplicant default instance"
  require_count 1 'import /init.m86.wifi.rc' "$init_rc"
  require_absent 'service wpa_supplicant ' "$init_rc"
  require_absent '/data/vendor/wifi' "$init_rc"
  require_count 1 \
    'chown wifi wifi /sys/module/bcmdhd/parameters/firmware_path' "$init_rc"
  require_count 1 \
    'chmod 0660 /sys/module/bcmdhd/parameters/firmware_path' "$init_rc"
  require_count 1 \
    'service wpa_supplicant /vendor/bin/hw/wpa_supplicant \' "$wifi_init"
  require_count 1 'mkdir /data/vendor/wifi/wpa/sockets 0770 wifi wifi' \
    "$wifi_init"
  require_count 1 \
    '/sys/module/bcmdhd/parameters firmware_path 0660 wifi wifi' \
    "$ueventd_rc"
  require_count 1 \
    'genfscon sysfs /module/bcmdhd/parameters/firmware_path u:object_r:sysfs_wlan_fwpath:s0' \
    "$bluetooth_genfs_contexts"
  for wifi_mapping in \
    'vendor/meizu/m86/proprietary/etc/wifi/bcmdhd.cal:$(TARGET_COPY_OUT_SYSTEM)/etc/wifi/bcmdhd.cal' \
    'vendor/meizu/m86/proprietary/vendor/firmware/fw_bcmdhd.bin:$(TARGET_COPY_OUT_VENDOR)/firmware/fw_bcmdhd.bin' \
    'vendor/meizu/m86/proprietary/vendor/firmware/fw_bcmdhd_apsta.bin:$(TARGET_COPY_OUT_VENDOR)/firmware/fw_bcmdhd_apsta.bin'; do
    require_count 1 "$wifi_mapping" "$vendor_product"
  done
  require_count 1 'etc/wifi/bcmdhd.cal' "$blob_list"
  require_count 1 'vendor/firmware/fw_bcmdhd.bin' "$blob_list"
  require_count 1 'vendor/firmware/fw_bcmdhd_apsta.bin' "$blob_list"
  require_fixed 'CONFIG_BCMDHD_FW_PATH="/system/vendor/firmware/fw_bcmdhd.bin"' \
    "$kernel_config"
  require_fixed 'CONFIG_BCMDHD_NVRAM_PATH="/system/etc/wifi/bcmdhd.cal"' \
    "$kernel_config"
  for forbidden_wifi_owner in wifiloader macloader; do
    require_absent "$forbidden_wifi_owner" "$device_makefile"
    require_absent "$forbidden_wifi_owner" "$init_rc"
    require_absent "$forbidden_wifi_owner" "$wifi_init"
  done
  require_fixed 'assert_wifi_outputs' "$build_worker"
  require_fixed 'WIFI-OUTPUT.txt' "$build_worker"
  require_fixed 'assert_wifi_target_files' "$build_worker"
  require_fixed 'WIFI-TARGET-FILES.txt' "$build_worker"
  require_fixed 'compiled_firmware_path_genfs_count=%s' "$build_worker"
  require_fixed 'android.hardware.wifi@1.0-service.legacy' "$build_worker"
  require_fixed 'fw_bcmdhd_apsta.bin' "$build_worker"

  require_absent 'android.hardware.bluetooth@1.0-impl.zero' "$device_makefile"
  require_absent '    android.hardware.bluetooth@1.0-service \' "$device_makefile"
  require_count 2 'compile_multilib: "32"' "$bluetooth_build"
  require_fixed 'name: "android.hardware.bluetooth@1.0-impl.m86"' \
    "$bluetooth_build"
  require_fixed 'name: "android.hardware.bluetooth@1.0-service.m86"' \
    "$bluetooth_build"
  require_absent 'stem:' "$bluetooth_build"
  require_fixed \
    'vintf_fragments: ["android.hardware.bluetooth@1.0-service.m86.xml"]' \
    "$bluetooth_build"
  require_count 1 \
    'service vendor.bluetooth-m86 /vendor/bin/hw/android.hardware.bluetooth@1.0-service.m86' \
    "$bluetooth_service_rc"
  require_count 1 \
    'interface android.hardware.bluetooth@1.0::IBluetoothHci default' \
    "$bluetooth_service_rc"
  require_count 1 'on property:vendor.m86.identity.ready=1' \
    "$bluetooth_service_rc"
  require_count 1 'start vendor.bluetooth-m86' "$bluetooth_service_rc"
  require_absent 'vendor.bluetooth' "$usb_rc"
  require_absent 'vendor.bluetooth' "$init_rc"
  require_absent 'android.hardware.bluetooth' "$device_manifest"
  [[ "$(xmllint --xpath \
      "count(/manifest/hal[name='android.hardware.bluetooth' and version='1.0' and transport='hwbinder']/interface[name='IBluetoothHci']/instance[text()='default'])" \
      "$bluetooth_manifest")" == "1" ]] || \
    fail "Bluetooth fragment must own exactly one HCI default instance"
  require_fixed 'BT_VND_OP_SCO_CFG' "$bluetooth_vendor_interface"
  require_fixed '/sys/class/android_usb/android0/iSerial' "$bluetooth_address"
  require_absent 'ro.serialno' "$bluetooth_address"
  require_absent 'ro.boot.serialno' "$bluetooth_address"
  require_count 1 \
    '/(vendor|system/vendor)/bin/hw/android\.hardware\.bluetooth@1\.0-service\.m86  u:object_r:hal_bluetooth_default_exec:s0' \
    "$bluetooth_file_contexts"
  require_fixed '/dev/ttySAC4' "$bluetooth_file_contexts"
  require_fixed 'hci_attach_dev:s0' "$bluetooth_file_contexts"
  require_fixed '/devices/11460000.uart/bluetooth.13/rfkill/rfkill0/state' \
    "$bluetooth_genfs_contexts"
  require_count 1 'sysfs_bluetooth_writable:s0' \
    "$bluetooth_genfs_contexts"
  require_absent \
    '/devices/11460000.uart/bluetooth.13/rfkill/rfkill0/type' \
    "$bluetooth_genfs_contexts"
  require_count 1 \
    '/sys/devices/11460000.uart/bluetooth.13/rfkill/rfkill0 state 0660 bluetooth bluetooth' \
    "$ueventd_rc"
  require_absent '/sys/class/rfkill/rfkill0' "$init_rc"
  require_absent 'chown bluetooth bluetooth /dev/ttySAC4' "$init_rc"
  require_fixed '/devices/virtual/android_usb/android0/iSerial' \
    "$bluetooth_genfs_contexts"
  require_fixed 'SE_SBGENFS' "$kernel_selinux_security"
  require_fixed 'selinux_genfs_get_sid' "$kernel_selinux_hooks"
  require_fixed '!strcmp(sb->s_type->name, "sysfs")' "$kernel_selinux_hooks"
  require_fixed 'sbsec->flags & SE_SBGENFS' "$kernel_selinux_hooks"
  for forbidden_bluetooth_allow in \
    'allow hal_bluetooth_default device:chr_file' \
    'allow hal_bluetooth_default sysfs:file' \
    'allow hal_bluetooth_default debugfs:file' \
    'allow hal_bluetooth_default kernel:system' \
    'allow hal_bluetooth_default serialno_prop' \
    'allow init sysfs_bluetooth_writable:file'; do
    require_absent "$forbidden_bluetooth_allow" "$device_root/sepolicy"
  done
  for retired_device_bluetooth_file in \
    "$device_root/bluetooth/Android.bp" \
    "$device_root/bluetooth/service.cpp" \
    "$device_root/bluetooth/android.hardware.bluetooth@1.0-service.m86.rc"; do
    [[ ! -e "$retired_device_bluetooth_file" ]] || \
      fail "retired device Bluetooth owner remains: $retired_device_bluetooth_file"
  done
  require_absent \
    'patches/device-samsung-universal7420-common/0002-bluetooth-add-m86-address-fallback.patch' \
    "$patch_series"
  require_fixed 'android.hardware.bluetooth@1.0-impl.m86' "$build_worker"
  require_fixed 'assert_bluetooth_outputs' "$build_worker"
  require_fixed 'BLUETOOTH-OUTPUT.txt' "$build_worker"
  require_fixed 'BLUETOOTH-TARGET-FILES.txt' "$build_worker"
  require_fixed 'count_regular_file_matches' "$build_worker"
  require_fixed 'find "$root" -type f' "$build_worker"
  require_fixed 'target_vendor_init="$target_files_tree/SYSTEM/vendor/etc/init"' \
    "$build_worker"
  require_fixed 'target_vendor_vintf="$target_files_tree/SYSTEM/vendor/etc/vintf"' \
    "$build_worker"
  require_fixed 'target_vendor_file_contexts="$target_files_tree/SYSTEM/vendor/etc/selinux/vendor_file_contexts"' \
    "$build_worker"
  require_fixed 'target_vendor_sepolicy_cil="$target_files_tree/SYSTEM/vendor/etc/selinux/vendor_sepolicy.cil"' \
    "$build_worker"
  require_fixed 'target_combined_sepolicy="$target_files_tree/ROOT/sepolicy"' \
    "$build_worker"
  require_fixed 'packaged_service_exec_context_count=%s' "$build_worker"
  require_fixed 'compiled_rfkill_state_genfs_count=%s' "$build_worker"
  require_fixed 'compiled_rfkill_type_writable_genfs_count=%s' "$build_worker"
  require_fixed 'compiled_iserial_genfs_count=%s' "$build_worker"
  require_fixed 'kernel_sysfs_genfs_inode_labeling=enabled' "$build_worker"
  if sed -n '/^assert_bluetooth_target_files()/,/^}/p' "$build_worker" | \
      grep -F -q 'grep -R'; then
    fail "Bluetooth target-files audit must not recursively follow symlinks"
  fi
  require_fixed 'kernel_dtb_audit=not-run-for-%s' "$build_worker"
  require_fixed 'rild.libpath=/system/lib64/libsitril.so' \
    "$device_root/system.prop"
  require_fixed 'inherit-product, $(LOCAL_PATH)/radio/product.mk' \
    "$device_makefile"
  require_count 1 'on property:sys.rild_reset=1' "$radio_init"
  require_count 1 'stop ril-daemon' "$radio_init"
  require_count 1 'start ril-daemon' "$radio_init"
  require_absent 'vendor.ril-daemon' "$radio_init"
  require_absent 'sys.rild_reset' "$init_rc"
  require_fixed 'deferred_radio_paths=(' "$prepare_vendor"
  require_absent \
    'bin/rild_exynos:$(TARGET_COPY_OUT_SYSTEM)/bin/rild_exynos' \
    "$vendor_product"
  require_absent \
    'bin/radiooptions_exynos:$(TARGET_COPY_OUT_SYSTEM)/bin/radiooptions_exynos' \
    "$vendor_product"
  require_fixed 'assert_radio_target_files' "$build_worker"
  require_fixed 'RADIO-TARGET-FILES.txt' "$build_worker"
  require_fixed 'deferred_rild_exynos=absent' "$build_worker"
  require_fixed 'deferred_radiooptions_exynos=absent' "$build_worker"
  require_fixed '$2 != "./bin/rild_exynos"' "$build_worker"
  require_fixed '$2 != "./bin/radiooptions_exynos"' "$build_worker"
  require_fixed 'installed_vendor_blob_count="$((vendor_blob_count - 43))"' \
    "$build_worker"
  require_fixed '$2 != "./lib/hw/audio.primary.m86.so"' "$build_worker"
  require_fixed '$2 != "./lib64/hw/audio.primary.m86.so"' "$build_worker"
}

validate_m5_audio() {
  for package in \
    audio.primary.m86 \
    android.hardware.audio@5.0-impl \
    android.hardware.audio.effect@5.0-impl \
    audio.r_submix.default \
    audio.usb.default; do
    require_fixed "$package" "$audio_product"
    require_absent "$package" "$device_makefile"
  done
  require_count 1 \
    '$(call inherit-product, $(LOCAL_PATH)/audio/product.mk)' \
    "$device_makefile"
  for audio_copy in \
    'audio/audio_effects.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_effects.xml' \
    'audio/audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_policy_configuration.xml' \
    'audio/mixer_paths.xml:$(TARGET_COPY_OUT_SYSTEM)/etc/mixer_paths.xml'; do
    require_count 1 "$audio_copy" "$audio_product"
    require_absent "$audio_copy" "$device_makefile"
  done
  require_fixed 'AUDIOSERVER_MULTILIB := 32' "$board_config"
  require_fixed 'ro.meizu.hardware.hifi=true' "$device_root/system.prop"
  require_file "$hardware_audio_root/Android.mk"
  require_file "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed 'kFlymeModulePath' "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed 'audio.primary.m86.flyme.so' "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed 'M86StreamOut* active_output' \
    "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed 'm86_apply_output_device' \
    "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed 'sinks[i].type == AUDIO_PORT_TYPE_DEVICE' \
    "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed 'active_output->flyme_stream->common.set_parameters' \
    "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed 'AUDIO_DEVICE_API_VERSION_2_0' \
    "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed 'routing=%u' "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed \
    'wrapper->public_device.common.version = AUDIO_DEVICE_API_VERSION_2_0' \
    "$hardware_audio_root/audio_primary_m86.cpp"
  require_absent 'parameter_result' "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed 'return 0;' \
    "$hardware_audio_root/audio_primary_m86.cpp"
  # Every optional audio_hw_device slot is explicitly populated. The wrapper
  # advertises API 2.0, so the normal Android 10 path does not call
  # create_audio_patch; the defensive slot is still non-NULL for direct users.
  for audio_wrapper_callback in \
    get_microphones \
    set_headphone_volume \
    set_master_mute \
    get_master_mute \
    create_audio_patch \
    release_audio_patch \
    get_audio_port \
    set_audio_port_config; do
    require_fixed \
      "wrapper->public_device.$audio_wrapper_callback = m86_$audio_wrapper_callback;" \
      "$hardware_audio_root/audio_primary_m86.cpp"
  done
  require_fixed 'audio.primary.m86.flyme.so' "$vendor_product"
  require_absent \
    'lib64/hw/audio.primary.m86.so:$(TARGET_COPY_OUT_SYSTEM)/lib64/hw/audio.primary.m86.so' \
    "$vendor_product"

  require_count 1 \
    $'lib/hw/audio.primary.m86.so\t50e97ee55ac9408ecb0017e3dc0c0541e520e102cea0b8ec87682e51c6cadeac\tELF32 ARM' \
    "$audio_evidence"
  require_count 1 \
    $'lib64/hw/audio.primary.m86.so\tc7c69dd92097c4e6ba1df2d76112912ef12c610d814d0bf2b6b26f2a26169aba\tELF64 AArch64' \
    "$audio_evidence"
  for private_offset_contract in \
    'vendor_reserved0) == 96' \
    'vendor_reserved1) == 100' \
    'set_headphone_volume) == 104' \
    'set_parameters) == 108' \
    'legacy_dump) == 136' \
    'FlymeStreamOutV2Layout, pcm_config_channels) == 116' \
    'sizeof(FlymeStreamInV2Layout) == 176'; do
    require_fixed "$private_offset_contract" "$audio_abi_contract"
  done
  require_fixed 'kObservedOutputMetadataAlias = 0x2' "$audio_abi_contract"
  require_fixed 'audio.primary.m86.so' "$audio_abi_auditor"
  require_fixed '32-bit HMI open entry changed' "$audio_abi_auditor"
  require_fixed 'm86 audio private ABI contract: PASS' "$audio_abi_test"
  require_fixed 'audit-m86-audio-abi.py' "$build_worker"
  require_fixed 'M5-AUDIO-ABI.txt' "$build_worker"
  require_fixed 'assert_m5_audio_baseline_target_files' "$build_worker"
  require_fixed 'M5-AUDIO-TARGET-FILES.txt' "$build_worker"
  require_fixed 'assert_m5_hifi_target_files' "$build_worker"
  require_fixed 'M5-HIFI-TARGET-FILES.txt' "$build_worker"
  require_fixed 'wrapper=SYSTEM/lib/hw/audio.primary.m86.so' "$build_worker"
  require_fixed 'M5 systemimage audio ownership' "$build_worker"
  require_fixed 'rm -f -- "$product_out/system/lib64/hw/audio.primary.m86.so"' \
    "$build_worker"
  require_fixed 'flyme64=absent' "$build_worker"
  require_fixed 'primary64_removal=passed' "$build_worker"
}

validate_m5_hifi() {
  require_fixed 'hifi.HifiSettingsActivity' "$m86parts_manifest"
  require_fixed 'hifi_music_enabled' "$audio_hifi_settings_xml"
  require_fixed 'hifi_music_param' "$audio_hifi_settings_xml"
  require_absent 'Settings.System' "$audio_hifi_settings_fragment"
  require_fixed 'Settings.Global' "$audio_hifi_policy"
  require_fixed 'AudioManager' "$audio_hifi_policy"
  require_fixed 'setParameters("hifi_state=' "$audio_hifi_policy"
  require_fixed 'HifiPolicy.setEnabled' "$audio_hifi_settings_fragment"
  require_fixed 'HifiPolicy.setGain' "$audio_hifi_settings_fragment"
  require_fixed 'HifiPolicy.sync' \
    "$device_root/parts/M86Parts/src/org/lineageos/settings/m86/mback/MbackMigrationReceiver.java"
  require_fixed 'hifi_gain_values' \
    "$device_root/parts/M86Parts/res/values/arrays.xml"
  require_fixed 'hifi_state' "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed 'hifi_gain' "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed 'm86_find_parameter' "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed 'm86_apply_hifi_state' "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed 'm86_apply_hifi_gain' "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed 'm86_apply_hifi_policy' "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed 'm86_apply_headphone_volume' "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed 'Unable to normalize Flyme headphone volume before stream volume' \
    "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed 'framework stream volume is' \
    "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed 'persist.vendor.m86.hifi.enabled' \
    "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed 'persist.vendor.m86.hifi.gain' "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed 'property_get' "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed 'property_set' "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed 'routing' "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed 'm86_apply_headphone_volume(wrapper)' \
    "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed 'active_output_devices' "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed 'wrapper->active_output_devices = devices' \
    "$hardware_audio_root/audio_primary_m86.cpp"
  require_fixed 'wrapper->active_output_devices = AUDIO_DEVICE_NONE' \
    "$hardware_audio_root/audio_primary_m86.cpp"
  require_absent 'setStreamVolume' "$audio_hifi_settings_fragment"
  require_absent '4 / 5' "$audio_hifi_settings_fragment"
  require_absent \
    'patches/frameworks-av/0001-audioflinger-restore-meizu-headphone-volume.patch' \
    "$patch_series"
  require_absent \
    'patches/hardware-interfaces/0004-audio-call-meizu-headphone-volume-hook.patch' \
    "$patch_series"
  require_absent '0003-audio-restore-meizu-hifi-routing.patch' "$patch_series"
  require_absent '0005-audio-hifi-global-settings.patch' "$patch_series"
  require_absent '0002-audioflinger-route-meizu-hifi-state-to-output.patch' \
    "$patch_series"
  require_absent '0001-system-add-meizu-hifi-sound.patch' \
    "$patch_series"
  require_fixed 'patches/frameworks-av/0002-audioflinger-route-meizu-hifi-state-to-output.patch' \
    "$retired_debt_ledger"
  require_fixed 'patches/packages-apps-settings/0001-system-add-meizu-hifi-sound.patch' \
    "$retired_debt_ledger"
  require_fixed 'patches/frameworks-base/0003-audio-restore-meizu-hifi-routing.patch' \
    "$retired_debt_ledger"
  require_fixed $'M5\tframeworks/base\t-\tM5 m86 audio wrapper ownership' \
    "$retired_debt_ledger"
  require_fixed \
    'patches/frameworks-av/0001-audioflinger-restore-meizu-headphone-volume.patch' \
    "$retired_debt_ledger"
  require_fixed \
    'patches/hardware-interfaces/0004-audio-call-meizu-headphone-volume-hook.patch' \
    "$retired_debt_ledger"
}

validate_m6_small_domains() {
  for package in \
    lights.m86 \
    power.m86 \
    vibrator.default \
    android.hardware.sensors@1.0-service \
    libm86gps_shim; do
    require_fixed "$package" "$device_makefile"
  done
  require_absent '/proc/nav_switch' "$device_root/power/PowerHAL.c"
}

validate_m7_media_camera() {
  require_fixed 'libm86omx_shim' "$device_makefile"
  require_fixed 'libm86camera_shim' "$device_makefile"
  require_fixed 'compile_multilib: "32"' "$device_root/media/Android.bp"
  require_fixed 'compile_multilib: "32"' "$device_root/camera/Android.bp"
  require_fixed 'audit-camera-abi.sh' "$build_worker"
}

validate_m8_default_hidden() {
  for forbidden in \
    android.hardware.fingerprint.xml \
    android.hardware.nfc.hce.xml \
    android.hardware.nfc.xml \
    com.android.nfc_extras.xml \
    android.hardware.biometrics.fingerprint@2.1-service \
    android.hardware.nfc@1.1-service \
    android.hardware.nfc@1.2-service \
    nfc_nci_nxp \
    libnfc-nxp.conf; do
    require_absent "$forbidden" "$device_makefile"
  done
  for forbidden in \
    android.hardware.biometrics.fingerprint \
    android.hardware.nfc \
    vendor.nxp.nxpnfc; do
    require_absent "$forbidden" "$device_manifest"
  done
  for forbidden in \
    'service mobicore' \
    'start mobicore' \
    '/data/nfc' \
    '/dev/pn544' \
    '/dev/p61' \
    '/dev/mobicore'; do
    require_absent "$forbidden" "$init_rc"
  done
  require_absent '/dev/pn544' "$ueventd_rc"
  require_absent '/dev/mobicore' "$ueventd_rc"
  require_absent 'ro.nfc.platform=' "$device_root/system.prop"
  require_absent 'ro.nfc.port=' "$device_root/system.prop"
  require_fixed 'M86_ENABLE_NFC_EXPERIMENT := true' \
    "$device_root/lineage_m86_nfc_experiment.mk"
  require_fixed 'M86_ENABLE_FINGERPRINT_EXPERIMENT := true' \
    "$device_root/lineage_m86_fingerprint_experiment.mk"
  require_absent 'lineage_m86_experiments' \
    "$device_root/AndroidProducts.mk"
  require_fixed 'android.hardware.nfc@1.1-service' "$nfc_experiment_product"
  require_fixed 'android.hardware.biometrics.fingerprint@2.1-service' \
    "$fingerprint_experiment_product"
  require_fixed 'ro.nfc.platform=nxppn547' "$nfc_experiment_product"
  require_fixed 'libnfc-nci.conf' "$nfc_experiment_product"
  require_fixed 'NXP_ESE_CLIENT_ENABLE=0x00' "$nfc_experiment_config"
  require_fixed $'hardware/nxp/nfc\tpatches/hardware-nxp-nfc/0001-reader-only-allow-disabling-ese-client-bridge.patch' \
    "$patch_series"
  require_fixed 'NAME_NXP_ESE_CLIENT_ENABLE' "$nfc_ese_patch"
  require_fixed 'eSE client bridge disabled by configuration' "$nfc_ese_patch"
  require_fixed 'service mobicore' "$fingerprint_experiment_init"
  require_absent 'mobicore' "$nfc_experiment_init"
  require_absent '/dev/pn544' "$fingerprint_experiment_init"
  require_absent '/dev/p61' "$nfc_experiment_init"
  require_fixed 'restorecon_recursive /data/nfc' "$nfc_experiment_init"
  require_fixed 'restorecon_recursive /data/vendor/nfc' "$nfc_experiment_init"
  require_fixed '/data/nfc(/.*)?' "$bluetooth_file_contexts"
  require_fixed '/data/vendor/nfc(/.*)?' "$bluetooth_file_contexts"
  require_fixed 'm86_nfc_vendor_data_file' "$bluetooth_file_contexts"
  require_fixed 'type m86_nfc_vendor_data_file, file_type, data_file_type;' \
    "$device_root/sepolicy/nfc_vendor_data.te"
  require_fixed 'allow hal_nfc_default m86_nfc_vendor_data_file:dir rw_dir_perms;' \
    "$nfc_sepolicy"
  require_fixed 'allow hal_nfc_default m86_nfc_vendor_data_file:file create_file_perms;' \
    "$nfc_sepolicy"
  require_fixed 'bool irq_wake_enabled;' "$kernel_nfc_driver"
  require_fixed 'pn544_enable_irq_wake(pn544_dev);' "$kernel_nfc_driver"
  require_fixed 'pn544_disable_irq_wake(pn544_dev);' "$kernel_nfc_driver"
  require_fixed 'M86_ENABLE_LEGACY_RAW_FINGERPRINT' \
    "$device_root/fingerprint/Android.mk"
  require_fixed 'fingerprint output absence audit passed.' \
    "$project_root/tools/audit-fingerprint-output.sh"
  require_fixed 'Default NFC/fingerprint output absence audit passed.' \
    "$project_root/tools/audit-default-hidden-output.sh"
  require_fixed 'audit-default-hidden-output.sh' "$build_worker"
  require_fixed 'audit-nfc-experiment-output.sh' "$build_worker"
  require_fixed 'PRO5_BUILD_PRODUCT' "$start_build"
  require_fixed 'PRO5_FORCE_BOOT_DEXPREOPT' "$start_build"
  require_fixed 'lineage_m86_nfc_experiment' "$build_worker"
  require_fixed 'if [[ "$target" == nfc ]] && (( !nfc_experiment )); then' \
    "$build_worker"
  require_fixed 'forced_boot_dexpreopt=%s' "$build_worker"
  require_fixed 'Forced %s boot ART did not execute single-threaded dex2oat.' \
    "$build_worker"
  require_fixed '$vendor_root/lib/nfc_nci_nxp.so' "$nfc_output_audit"
  require_fixed '$vendor_root/lib64/nfc_nci_nxp.so' "$nfc_output_audit"
  require_fixed 'NFC service does not link its NXP HAL library:' \
    "$nfc_output_audit"
  require_fixed 'NFC extras library declaration is missing:' \
    "$nfc_output_audit"
  require_fixed 'NFC init service owner is not unique.' \
    "$nfc_output_audit"
  require_fixed 'nfc_hidl=1.1/default' "$nfc_output_audit"
  require_fixed 'secure_element=disabled' "$nfc_output_audit"
  require_fixed 'vendor.nfc_hal_service' "$nfc_runtime_test"
  require_fixed 'Unbalanced IRQ' "$nfc_runtime_test"
}

validate_vendor_mapping_owners() {
  expected_blob_count="$(
    awk 'NF && $1 !~ /^#/ { count++ } END { print count + 0 }' "$blob_list"
  )"
  [[ "$expected_blob_count" == 224 ]] || \
    fail "expected 224 locked proprietary inputs, got $expected_blob_count"

  source_owned_paths=(
    lib/hw/gralloc.exynos5.so
    lib64/hw/gralloc.exynos5.so
    lib/hw/hwcomposer.exynos5.so
    lib64/hw/hwcomposer.exynos5.so
    lib/libdisplay.so
    lib64/libdisplay.so
    lib/libhdmi.so
    lib64/libhdmi.so
    lib/libion.so
    lib64/libion.so
    lib/hw/memtrack.exynos5.so
    lib64/hw/memtrack.exynos5.so
    lib/libexynosgscaler.so
    lib64/libexynosgscaler.so
    lib/libexynosscaler.so
    lib64/libexynosscaler.so
    lib/libexynosutils.so
    lib64/libexynosutils.so
    lib/libexynosv4l2.so
    lib64/libexynosv4l2.so
    lib/libhwcutils.so
    lib64/libhwcutils.so
    lib/libmpp.so
    lib64/libmpp.so
  )
  deferred_graphics_paths=(
    lib/libExynosHWCService.so
    lib64/libExynosHWCService.so
  )
  deferred_radio_paths=(
    bin/rild_exynos
    bin/radiooptions_exynos
  )
  deferred_audio_paths=(
    lib64/hw/audio.primary.m86.so
  )

  main_count="$(rg -c '^    vendor/meizu/m86/proprietary/' "$vendor_product")"
  nfc_experiment_count="$(
    rg -c '^    vendor/meizu/m86/proprietary/' \
      "$nfc_experiment_vendor_product"
  )"
  fingerprint_experiment_count="$(
    rg -c '^    vendor/meizu/m86/proprietary/' \
      "$fingerprint_experiment_vendor_product"
  )"
  [[ "$main_count" == 179 ]] || \
    fail "expected 179 default vendor mappings, got $main_count"
  [[ "$nfc_experiment_count" == 2 ]] || \
    fail "expected 2 NFC experiment vendor mappings, got $nfc_experiment_count"
  require_fixed \
    'vendor/meizu/m86/proprietary/vendor/firmware/libpn547_fw.so:$(TARGET_COPY_OUT_VENDOR)/firmware/libpn547_fw.so' \
    "$nfc_experiment_vendor_product"
  require_fixed \
    'vendor/meizu/m86/proprietary/vendor/firmware/libpn547_fw.so:$(TARGET_COPY_OUT_VENDOR)/lib64/libpn547_fw.so' \
    "$nfc_experiment_vendor_product"
  [[ "$fingerprint_experiment_count" == 15 ]] || \
    fail "expected 15 fingerprint experiment vendor mappings, got $fingerprint_experiment_count"

  while IFS= read -r relative_path; do
    source_owned=false
    for source_path in "${source_owned_paths[@]}"; do
      if [[ "$relative_path" == "$source_path" ]]; then
        source_owned=true
        break
      fi
    done
    if [[ "$source_owned" == true ]]; then
      continue
    fi
    deferred_graphics=false
    for deferred_path in "${deferred_graphics_paths[@]}"; do
      if [[ "$relative_path" == "$deferred_path" ]]; then
        deferred_graphics=true
        break
      fi
    done
    if [[ "$deferred_graphics" == true ]]; then
      continue
    fi
    deferred_radio=false
    for deferred_path in "${deferred_radio_paths[@]}"; do
      if [[ "$relative_path" == "$deferred_path" ]]; then
        deferred_radio=true
        break
      fi
    done
    if [[ "$deferred_radio" == true ]]; then
      continue
    fi
    deferred_audio=false
    for deferred_path in "${deferred_audio_paths[@]}"; do
      if [[ "$relative_path" == "$deferred_path" ]]; then
        deferred_audio=true
        break
      fi
    done
    if [[ "$deferred_audio" == true ]]; then
      continue
    fi
    if [[ "$relative_path" == vendor/* ]]; then
      output_path="\$(TARGET_COPY_OUT_VENDOR)/${relative_path#vendor/}"
    elif [[ "$relative_path" == lib/hw/audio.primary.m86.so ]]; then
      output_path="\$(TARGET_COPY_OUT_SYSTEM)/lib/hw/audio.primary.m86.flyme.so"
    elif [[ "$relative_path" == lib/hw/gatekeeper.exynos7420.so ]]; then
      output_path="\$(TARGET_COPY_OUT_SYSTEM)/lib/hw/gatekeeper.m86.so"
    elif [[ "$relative_path" == lib64/hw/gatekeeper.exynos7420.so ]]; then
      output_path="\$(TARGET_COPY_OUT_SYSTEM)/lib64/hw/gatekeeper.m86.so"
    else
      output_path="\$(TARGET_COPY_OUT_SYSTEM)/$relative_path"
    fi
    mapping="vendor/meizu/m86/proprietary/$relative_path:$output_path"
    owner_count=0
    for makefile in \
      "$vendor_product" \
      "$nfc_experiment_vendor_product" \
      "$fingerprint_experiment_vendor_product"; do
      if rg -F -q -- "$mapping" "$makefile"; then
        owner_count=$((owner_count + 1))
      fi
    done
    [[ "$owner_count" == 1 ]] || \
      fail "vendor mapping has $owner_count owners: $mapping"
  done < <(awk 'NF && $1 !~ /^#/ { print }' "$blob_list")
}

validate_xml_and_python() {
  command -v xmllint >/dev/null 2>&1 || fail "xmllint is required"
  for xml_file in \
    "$device_manifest" \
    "$wifi_manifest" \
    "$bluetooth_manifest" \
    "$experiment_nfc_manifest" \
    "$experiment_fingerprint_manifest" \
    "$m86parts_privapp_permissions" \
    "$device_root/audio/audio_policy_configuration.xml" \
    "$device_root/audio/audio_effects.xml" \
    "$device_root/gps/gps.xml"; do
    xmllint --noout "$xml_file"
  done
  python3 -c \
    'import pathlib,sys; p=pathlib.Path(sys.argv[1]); compile(p.read_bytes(), str(p), "exec")' \
    "$releasetools"
  bash -n \
    "$prepare_vendor" \
    "$detached_worker" \
    "$dev_null_guard" \
    "$patch_auditor" \
    "$input_hasher" \
    "$start_build" \
    "$build_worker" \
    "$nfc_output_audit" \
    "$nfc_runtime_test" \
    "$kernel_build_worker" \
    "$twrp_build_worker" \
    "$memory_preflight" \
    "$install_worker"
  python3 -c \
    'import pathlib,sys; p=pathlib.Path(sys.argv[1]); compile(p.read_bytes(), str(p), "exec")' \
    "$cache_releaser"
}

validate_m0_ledgers
validate_m1_boot_and_ownership
validate_m2_graphics
validate_m3_storage_usb_input
validate_m4_connectivity_radio
validate_m5_audio
validate_m5_hifi
validate_m6_small_domains
validate_m7_media_camera
validate_m8_default_hidden
validate_vendor_mapping_owners
validate_xml_and_python

printf 'LineageOS source validation passed: %s\n' "$device_root"
