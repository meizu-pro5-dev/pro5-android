#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

"$script_dir/push-local.sh"

"${pro5_ssh[@]}" bash -s -- "$PRO5_REMOTE_ROOT" <<'REMOTE'
set -euo pipefail

remote_root="$1"
session_name="pro5-twrp-source-sync"
worker="$remote_root/local/remote/worker-sync-twrp-source.sh"

for conflicting_session in pro5-source-sync pro5-platform-sync; do
  if tmux has-session -t "$conflicting_session" 2>/dev/null; then
    printf 'Refusing concurrent source traffic while %s is running.\n' \
      "$conflicting_session" >&2
    exit 1
  fi
done

if tmux has-session -t "$session_name" 2>/dev/null; then
  printf 'tmux session %s is already running\n' "$session_name"
  exit 0
fi

chmod 0755 "$worker"
tmux new-session -d -s "$session_name" "$worker"
printf 'Started tmux session %s: bounded TWRP 9.0 source sync\n' \
  "$session_name"
REMOTE

"$script_dir/twrp-source-sync-status.sh"
