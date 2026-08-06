#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

"${pro5_ssh[@]}" bash -s -- "$PRO5_REMOTE_ROOT" <<'REMOTE'
set -euo pipefail

remote_root="$1"
session_name="pro5-twrp-source-sync"
log_file="$remote_root/logs/twrp-source-sync.log"
progress_file="$remote_root/run/twrp-source-sync-progress.tsv"

if tmux has-session -t "$session_name" 2>/dev/null; then
  printf 'state: running\n'
else
  printf 'state: stopped\n'
fi

if [[ -s "$progress_file" ]]; then
  tail -n 3 "$progress_file"
fi
if [[ -f "$log_file" ]]; then
  tail -c 65536 "$log_file" | tr '\r' '\n' | tail -n 40
else
  printf 'No TWRP source sync log yet.\n'
fi

df -h "$remote_root"
REMOTE
