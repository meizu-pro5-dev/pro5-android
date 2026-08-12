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
launcher="$remote_root/local/remote/detached-worker.sh"
worker="$remote_root/local/remote/worker-sync-source.sh"

if [[ -x "$launcher" ]] && "$launcher" running "$session_name"; then
  printf 'state: running\n'
elif pgrep -f "$worker" >/dev/null 2>&1; then
  printf 'state: running\n'
else
  printf 'state: stopped\n'
fi

if [[ -f "$log_file" ]]; then
  tail -c 65536 "$log_file" | tr '\r' '\n' | tail -n 40
else
  printf 'No source sync log yet.\n'
fi

df -h "$remote_root"
REMOTE
