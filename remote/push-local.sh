#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

printf 'Synchronizing local source of truth to %s:%s/local/\n' \
  "$PRO5_BUILDER_HOST" "$PRO5_REMOTE_ROOT"

"${pro5_ssh[@]}" mkdir -p -- "$PRO5_REMOTE_ROOT/local"

rsync -az --delete-delay \
  --exclude '/.git/' \
  --exclude '/.DS_Store' \
  --exclude '__pycache__/' \
  --exclude '*.pyc' \
  --exclude '/artifacts/' \
  --exclude '/backups/' \
  --exclude '/evidence/' \
  --exclude '/legacy/' \
  --exclude '/out/' \
  --exclude '/work/' \
  --exclude '/vendor/meizu/m86/proprietary/' \
  --exclude '*.img' \
  --exclude '*.bin' \
  --exclude '*.tar' \
  --exclude '*.tar.*' \
  --exclude '*.zip' \
  -e "$pro5_rsync_ssh" \
  "$project_root/" \
  "$PRO5_BUILDER_HOST:$PRO5_REMOTE_ROOT/local/"
