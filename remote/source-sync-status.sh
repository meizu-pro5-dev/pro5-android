#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

"${pro5_ssh[@]}" bash -s -- "$PRO5_REMOTE_ROOT" <<'REMOTE'
set -euo pipefail

remote_root="$1"
session_name="pro5-source-sync"
log_file="$remote_root/logs/source-sync.log"

if tmux has-session -t "$session_name" 2>/dev/null; then
  printf 'state: running\n'
else
  printf 'state: stopped\n'
fi

if [[ -f "$log_file" ]]; then
  tail -n 40 "$log_file"
else
  printf 'No source sync log yet.\n'
fi

df -h "$remote_root"
REMOTE
