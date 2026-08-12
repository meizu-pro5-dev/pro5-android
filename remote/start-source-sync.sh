#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

"$script_dir/push-local.sh"

"${pro5_ssh[@]}" bash -s -- "$PRO5_REMOTE_ROOT" <<'REMOTE'
set -euo pipefail

remote_root="$1"
session_name="pro5-source-sync"
worker="$remote_root/local/remote/worker-sync-source.sh"
launcher="$remote_root/local/remote/detached-worker.sh"

chmod 0755 "$worker" "$launcher"
"$launcher" start "$session_name" "$worker"
printf 'Started detached worker %s: bounded per-project sync\n' "$session_name"
REMOTE

"$script_dir/source-sync-status.sh"
