#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

stock_dtb="${PRO5_STOCK_DTB:-$project_root/../work/pro5-flyme-8.0.5.0A/dtb-inspect/dtb}"
stock_lock="$project_root/locks/stock-flyme-8.0.5.0A.sha256"
remote_stock="$PRO5_REMOTE_ROOT/stock/flyme-8.0.5.0A"
expected_hash="$(awk '$2 == "dtb" { print $1 }' "$stock_lock")"

if [[ ! "$expected_hash" =~ ^[0-9a-f]{64}$ ]] || [[ ! -s "$stock_dtb" ]]; then
  printf 'Verified stock DTB input or lock is missing.\n' >&2
  exit 1
fi
actual_hash="$(sha256sum "$stock_dtb" | awk '{ print $1 }')"
if [[ "$actual_hash" != "$expected_hash" ]]; then
  printf 'Stock DTB hash mismatch: %s (expected %s)\n' \
    "$actual_hash" "$expected_hash" >&2
  exit 1
fi

"${pro5_ssh[@]}" mkdir -p -- "$remote_stock"
rsync -az --checksum \
  -e "$pro5_rsync_ssh" \
  "$stock_dtb" \
  "$PRO5_BUILDER_HOST:$remote_stock/dtb"

"${pro5_ssh[@]}" bash -s -- \
  "$remote_stock/dtb" "$expected_hash" <<'REMOTE'
set -euo pipefail

stock_dtb="$1"
expected_hash="$2"
actual_hash="$(sha256sum "$stock_dtb" | awk '{ print $1 }')"
if [[ "$actual_hash" != "$expected_hash" ]]; then
  printf 'Builder stock DTB hash mismatch: %s\n' "$actual_hash" >&2
  exit 1
fi
printf 'Verified builder stock DTB: sha256=%s size=%s\n' \
  "$actual_hash" "$(stat -c %s "$stock_dtb")"
REMOTE
