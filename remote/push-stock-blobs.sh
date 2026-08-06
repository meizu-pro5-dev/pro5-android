#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

stock_dump="${PRO5_STOCK_DUMP:-$project_root/../work/pro5-flyme-8.0.5.0A/blob-dump}"
remote_dump="$PRO5_REMOTE_ROOT/stock/flyme-8.0.5.0A/blob-dump"
manifest="$stock_dump/PROPRIETARY_SHA256SUMS"

if [[ ! -f "$manifest" ]] || [[ ! -d "$stock_dump/system" ]]; then
  printf 'Verified stock blob dump is missing: %s\n' "$stock_dump" >&2
  exit 1
fi

(
  cd "$stock_dump"
  shasum -a 256 -c PROPRIETARY_SHA256SUMS >/dev/null
)

printf 'Synchronizing verified stock blobs to %s:%s/\n' \
  "$PRO5_BUILDER_HOST" "$remote_dump"
"${pro5_ssh[@]}" mkdir -p -- "$remote_dump"
rsync -az --delete-delay \
  -e "$pro5_rsync_ssh" \
  "$stock_dump/" \
  "$PRO5_BUILDER_HOST:$remote_dump/"

"${pro5_ssh[@]}" bash -s -- "$remote_dump" <<'REMOTE'
set -euo pipefail

remote_dump="$1"
cd "$remote_dump"
sha256sum -c PROPRIETARY_SHA256SUMS >/dev/null
printf 'Verified %s stock files on the builder (%s).\n' \
  "$(wc -l < PROPRIETARY_SHA256SUMS)" "$(du -sh . | cut -f1)"
REMOTE
