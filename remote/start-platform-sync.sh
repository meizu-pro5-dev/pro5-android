#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

"$script_dir/push-local.sh"

"${pro5_ssh[@]}" bash -s -- "$PRO5_REMOTE_ROOT" <<'REMOTE'
set -euo pipefail

remote_root="$1"
session_name="pro5-platform-sync"
worker="$remote_root/local/remote/worker-sync-platform.sh"
launcher="$remote_root/local/remote/detached-worker.sh"

if [[ -x "$launcher" ]] && "$launcher" running pro5-source-sync >/dev/null 2>&1; then
  printf 'Base source sync is still running; platform sync was not started.\n' >&2
  exit 1
fi

if [[ ! -s "$remote_root/logs/lineage-17.1-manifest.xml" ]]; then
  printf 'Base source sync has no valid pinned manifest.\n' >&2
  exit 1
fi

chmod 0755 "$worker" "$launcher"
"$launcher" start "$session_name" "$worker"
printf 'Started detached worker %s\n' "$session_name"
REMOTE

"$script_dir/platform-sync-status.sh"
