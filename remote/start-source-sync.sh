#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

jobs="${PRO5_SOURCE_SYNC_JOBS:-4}"
if [[ ! "$jobs" =~ ^[1-9][0-9]*$ ]] || ((jobs > 16)); then
  printf 'Invalid PRO5_SOURCE_SYNC_JOBS: %s\n' "$jobs" >&2
  exit 2
fi

"$script_dir/push-local.sh"

"${pro5_ssh[@]}" bash -s -- "$PRO5_REMOTE_ROOT" "$jobs" <<'REMOTE'
set -euo pipefail

remote_root="$1"
jobs="$2"
session_name="pro5-source-sync"
worker="$remote_root/local/remote/worker-sync-source.sh"

if tmux has-session -t "$session_name" 2>/dev/null; then
  printf 'tmux session %s is already running\n' "$session_name"
  exit 0
fi

chmod 0755 "$worker"
printf -v worker_command '%q %q' "$worker" "$jobs"
tmux new-session -d -s "$session_name" "$worker_command"
printf 'Started tmux session %s: jobs=%s\n' "$session_name" "$jobs"
REMOTE

"$script_dir/source-sync-status.sh"
