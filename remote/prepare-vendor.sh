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
