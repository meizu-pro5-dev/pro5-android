#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

"${pro5_ssh[@]}" bash -s -- "$PRO5_REMOTE_ROOT" <<'REMOTE'
set -euo pipefail

remote_root="$1"
session_name="pro5-platform-sync"
log_file="$remote_root/logs/platform-sync.log"
launcher="$remote_root/local/remote/detached-worker.sh"

if [[ -x "$launcher" ]] && \
    "$launcher" running "$session_name" >/dev/null 2>&1; then
  printf 'state: running\n'
else
  printf 'state: stopped\n'
fi

if [[ -f "$log_file" ]]; then
  tail -c 65536 "$log_file" | tr '\r' '\n' | tail -n 40
else
  printf 'No platform sync log yet.\n'
fi
REMOTE
