#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

# Install the extraction metadata first, then stage and verify the stock dump.
"$script_dir/install-local-trees.sh"
"$script_dir/push-stock-blobs.sh"

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
excluded_copy_paths=(
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
)

# Retain and hash the replaced Flyme graphics, HDMI, and libion blobs as extraction
# evidence, but never install them. Android 10 source modules own these
# destinations. The Flyme HWC1/libdisplay pair uses the Android 7 layer ABI and
# crashes SurfaceFlinger in ExynosDisplay::doPreProcessing when driven through
# Android 10's HWC2On1 adapter. Flyme libhdmi also has a DT_NEEDED entry for
# that incompatible libdisplay, so it must be replaced with the source output
# for the source-built HWC to load at all.
for relative_path in "${excluded_copy_paths[@]}"; do
  sed -i "\\|vendor/meizu/m86/proprietary/$relative_path:|d" \
    "$vendor_makefile"
done

copy_rule_count="$(
  grep -c '^    vendor/meizu/m86/proprietary/' "$vendor_makefile"
)"
expected_copy_count="$((expected_count - ${#excluded_copy_paths[@]}))"
if [[ "$copy_rule_count" != "$expected_copy_count" ]]; then
  printf 'Expected %s generated copy rules, found %s.\n' \
    "$expected_copy_count" "$copy_rule_count" >&2
  exit 1
fi

# extract_utils maps paths beginning with vendor/ below TARGET_COPY_OUT_VENDOR
# and all other stock-system paths below TARGET_COPY_OUT_SYSTEM. Check every
# generated rule so firmware can never silently become vendor/vendor/*.
while IFS= read -r relative_path; do
  excluded_copy=false
  for excluded_path in "${excluded_copy_paths[@]}"; do
    if [[ "$relative_path" == "$excluded_path" ]]; then
      excluded_copy=true
      break
    fi
  done
  if [[ "$excluded_copy" == true ]]; then
    continue
  fi
  if [[ "$relative_path" == vendor/* ]]; then
    output_path="\$(TARGET_COPY_OUT_VENDOR)/${relative_path#vendor/}"
  else
    output_path="\$(TARGET_COPY_OUT_SYSTEM)/$relative_path"
  fi
  expected_rule="vendor/meizu/m86/proprietary/$relative_path:$output_path"
  if ! grep -F -q -- "$expected_rule" "$vendor_makefile"; then
    printf 'Generated vendor mapping is missing or incorrect: %s\n' \
      "$expected_rule" >&2
    exit 1
  fi
done < <(awk 'NF && $1 !~ /^#/ { print }' "$blob_list")

if grep -F -q -- '\$(TARGET_COPY_OUT_VENDOR)/vendor/' "$vendor_makefile"; then
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
generated_files=(Android.mk BoardConfigVendor.mk m86-vendor.mk)
for generated in "${generated_files[@]}"; do
  rsync -a \
    -e "$pro5_rsync_ssh" \
    "$PRO5_BUILDER_HOST:$PRO5_REMOTE_ROOT/src/lineage-17.1/vendor/meizu/m86/$generated" \
    "$project_root/vendor/meizu/m86/$generated"
done

printf 'Fetched generated vendor definitions into %s\n' \
  "$project_root/vendor/meizu/m86"
