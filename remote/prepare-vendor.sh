#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

# Stage and verify immutable inputs before install-local-trees requires the
# locked DTB to exist on the builder.
"$script_dir/push-stock-blobs.sh"
"$script_dir/install-local-trees.sh"

"${pro5_ssh[@]}" bash -s -- "$PRO5_REMOTE_ROOT" <<'REMOTE'
set -euo pipefail

remote_root="$1"
source_root="$remote_root/src/lineage-17.1"
device_tree="$source_root/device/meizu/m86"
vendor_tree="$source_root/vendor/meizu/m86"
stock_dump="$remote_root/stock/flyme-8.0.5.0A/blob-dump"
stock_source="$stock_dump/system"
blob_list="$device_tree/proprietary-files.txt"
extract_script="$device_tree/extract-files.sh"
hash_lock="$remote_root/logs/m86-proprietary-sha256s.txt"

for required in \
  "$source_root/vendor/lineage/build/tools/extract_utils.sh" \
  "$stock_dump/PROPRIETARY_SHA256SUMS" \
  "$stock_source" \
  "$blob_list" \
  "$extract_script"; do
  if [[ ! -e "$required" ]]; then
    printf 'Required vendor input is missing: %s\n' "$required" >&2
    exit 1
  fi
done

chmod 0755 "$extract_script" "$device_tree/setup-makefiles.sh"
"$extract_script" "$stock_source"

expected_count="$(awk 'NF && $1 !~ /^#/ { count++ } END { print count + 0 }' "$blob_list")"
actual_count="$(find "$vendor_tree/proprietary" -type f -print | wc -l | tr -d ' ')"
if [[ "$actual_count" != "$expected_count" ]]; then
  printf 'Expected %s extracted blobs, found %s\n' \
    "$expected_count" "$actual_count" >&2
  exit 1
fi

while IFS= read -r relative_path; do
  cmp --quiet \
    "$stock_source/$relative_path" \
    "$vendor_tree/proprietary/$relative_path"
done < <(awk 'NF && $1 !~ /^#/ { print }' "$blob_list")

for generated in Android.mk BoardConfigVendor.mk m86-vendor.mk; do
  if [[ ! -s "$vendor_tree/$generated" ]]; then
    printf 'Generated vendor definition is missing: %s\n' "$generated" >&2
    exit 1
  fi
done

vendor_makefile="$vendor_tree/m86-vendor.mk"
nfc_experiment_makefile="$vendor_tree/m86-nfc-experiment-vendor.mk"
fingerprint_experiment_makefile="$vendor_tree/m86-fingerprint-experiment-vendor.mk"
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
nfc_experiment_copy_paths=(
  vendor/firmware/libpn547_fw.so
)
fingerprint_experiment_copy_paths=(
  app/020a0000000000000000000000000000.drbin
  app/mcRegistry/04010000000000000000000000000000.tlbin
  app/mcRegistry/04020000000000000000000000000000.tlbin
  app/mcRegistry/07020000000000000000000000000000.tlbin
  app/mcRegistry/07060000000000000000000000000000.tlbin
  app/mcRegistry/07061000000000000000000000000000.tlbin
  bin/mcDriverDaemon
  lib64/hw/fingerprint.m86.so
  lib64/lib_fpc_tac_shared.so
  vendor/lib/libMcClient.so
  vendor/lib/libMcRegistry.so
  vendor/lib64/libMcClient.so
  vendor/lib64/libMcRegistry.so
)

# Retain and hash the replaced Flyme graphics family as extraction evidence,
# but never install it. Android 10 source modules own every HWC dependency,
# which prevents PRODUCT_COPY_FILES from silently replacing the libraries that
# hwcomposer linked against. The Flyme HWC1/libdisplay pair uses the Android 7
# layer ABI and crashes SurfaceFlinger when driven through HWC2On1.
for relative_path in "${source_owned_paths[@]}"; do
  sed -i "\\|vendor/meizu/m86/proprietary/$relative_path:|d" \
    "$vendor_makefile"
done

# The Flyme HWC service has no enabled service, build flag, or DT_NEEDED
# consumer in the selected A10 stack. Keep it in the immutable inventory for
# provenance, but do not publish a dead 32/64 runtime owner.
for relative_path in "${deferred_graphics_paths[@]}"; do
  sed -i "\|vendor/meizu/m86/proprietary/$relative_path:|d" \
    "$vendor_makefile"
done

# Keep obsolete pre-HIDL radio helpers in the immutable inventory, but do not
# install them in the default product. Platform rild plus SITRIL is the only
# selected radio owner on Android 10.
for relative_path in "${deferred_radio_paths[@]}"; do
  sed -i "\|vendor/meizu/m86/proprietary/$relative_path:|d" \
    "$vendor_makefile"
done

# The m86-owned wrapper is the only default audio.primary producer. Keep the
# locked 32-bit Flyme object as a renamed input for the wrapper, and defer the
# unused 64-bit object until an independently validated 64-bit consumer exists.
sed -i 's|vendor/meizu/m86/proprietary/lib/hw/audio.primary.m86.so:$(TARGET_COPY_OUT_SYSTEM)/lib/hw/audio.primary.m86.so|vendor/meizu/m86/proprietary/lib/hw/audio.primary.m86.so:$(TARGET_COPY_OUT_SYSTEM)/lib/hw/audio.primary.m86.flyme.so|' \
  "$vendor_makefile"
for relative_path in "${deferred_audio_paths[@]}"; do
  sed -i "\|vendor/meizu/m86/proprietary/$relative_path:|d" \
    "$vendor_makefile"
done

write_experiment_makefile() {
  local output_makefile="$1"
  local product_name="$2"
  local relative_path
  local output_path
  local rule
  local index
  shift 2
  local experiment_paths=("$@")

  {
    printf '%s\n' \
      '# Copyright (C) 2026 The LineageOS Project' \
      '# SPDX-License-Identifier: Apache-2.0' \
      '' \
      "# Inert by default. Only $product_name inherits this file."
    printf 'PRODUCT_COPY_FILES += \\\n'
    for index in "${!experiment_paths[@]}"; do
      relative_path="${experiment_paths[$index]}"
      if [[ "$relative_path" == vendor/* ]]; then
        output_path="\$(TARGET_COPY_OUT_VENDOR)/${relative_path#vendor/}"
      else
        output_path="\$(TARGET_COPY_OUT_SYSTEM)/$relative_path"
      fi
      rule="vendor/meizu/m86/proprietary/$relative_path:$output_path"
      if ((index + 1 < ${#experiment_paths[@]})); then
        printf '    %s \\\n' "$rule"
      else
        printf '    %s\n' "$rule"
      fi
      sed -i "\\|vendor/meizu/m86/proprietary/$relative_path:|d" \
        "$vendor_makefile"
    done
  } > "$output_makefile"
}

# Keep NFC and Trustonic bytes in the verified inventory, but give each
# experiment an independent product, init owner, blob group, and rollback.
write_experiment_makefile \
  "$nfc_experiment_makefile" \
  lineage_m86_nfc_experiment \
  "${nfc_experiment_copy_paths[@]}"
write_experiment_makefile \
  "$fingerprint_experiment_makefile" \
  lineage_m86_fingerprint_experiment \
  "${fingerprint_experiment_copy_paths[@]}"

copy_rule_count="$(
  grep -c '^    vendor/meizu/m86/proprietary/' "$vendor_makefile"
)"
expected_copy_count="$((
  expected_count -
  ${#source_owned_paths[@]} -
  ${#deferred_graphics_paths[@]} -
  ${#deferred_radio_paths[@]} -
  ${#deferred_audio_paths[@]} -
  ${#nfc_experiment_copy_paths[@]} -
  ${#fingerprint_experiment_copy_paths[@]}
))"
if [[ "$copy_rule_count" != "$expected_copy_count" ]]; then
  printf 'Expected %s generated copy rules, found %s.\n' \
    "$expected_copy_count" "$copy_rule_count" >&2
  exit 1
fi

# extract_utils maps paths beginning with vendor/ below TARGET_COPY_OUT_VENDOR
# and all other stock-system paths below TARGET_COPY_OUT_SYSTEM. Check every
# generated rule so firmware can never silently become vendor/vendor/*.
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
  else
    output_path="\$(TARGET_COPY_OUT_SYSTEM)/$relative_path"
  fi
  expected_rule="vendor/meizu/m86/proprietary/$relative_path:$output_path"
  owner_count=0
  for makefile in \
    "$vendor_makefile" \
    "$nfc_experiment_makefile" \
    "$fingerprint_experiment_makefile"; do
    if grep -F -q -- "$expected_rule" "$makefile"; then
      owner_count=$((owner_count + 1))
    fi
  done
  if [[ "$owner_count" != 1 ]]; then
    printf 'Generated vendor mapping has %s owners: %s\n' \
      "$owner_count" "$expected_rule" >&2
    exit 1
  fi
done < <(awk 'NF && $1 !~ /^#/ { print }' "$blob_list")

if grep -F -q -- '\$(TARGET_COPY_OUT_VENDOR)/vendor/' \
    "$vendor_makefile" \
    "$nfc_experiment_makefile" \
    "$fingerprint_experiment_makefile"; then
  printf 'Generated vendor mapping contains a duplicated vendor/ prefix.\n' >&2
  exit 1
fi

(
  cd "$vendor_tree/proprietary"
  find . -type f -print0 |
    LC_ALL=C sort -z |
    xargs -0 sha256sum > "$hash_lock"
)

printf 'Prepared and byte-verified %s proprietary files.\n' "$actual_count"
printf 'Vendor definitions: %s\n' "$vendor_tree"
printf 'Blob hash lock: %s\n' "$hash_lock"
REMOTE

# Generated build definitions are adaptation source and must also live in the
# local authoritative repository. Proprietary bytes deliberately remain remote.
generated_files=(
  Android.mk
  BoardConfigVendor.mk
  m86-vendor.mk
  m86-nfc-experiment-vendor.mk
  m86-fingerprint-experiment-vendor.mk
)
for generated in "${generated_files[@]}"; do
  rsync -a \
    -e "$pro5_rsync_ssh" \
    "$PRO5_BUILDER_HOST:$PRO5_REMOTE_ROOT/src/lineage-17.1/vendor/meizu/m86/$generated" \
    "$project_root/vendor/meizu/m86/$generated"
done

printf 'Fetched generated vendor definitions into %s\n' \
  "$project_root/vendor/meizu/m86"
