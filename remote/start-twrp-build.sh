#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

jobs="${PRO5_TWRP_BUILD_JOBS:-24}"
if [[ ! "$jobs" =~ ^[1-9][0-9]*$ ]] || ((jobs > 64)); then
  printf 'Invalid PRO5_TWRP_BUILD_JOBS: %s\n' "$jobs" >&2
  exit 2
fi

"$project_root/tools/validate-twrp-tree.sh"

local_revision="$(git -C "$project_root" rev-parse HEAD)"
if [[ -n "$(git -C "$project_root" status --porcelain --untracked-files=normal)" ]]; then
  local_revision="${local_revision}-dirty"
fi

# TWRP needs the verified Flyme 8 STM touch firmware during recovery boot.
# This is an incremental, hash-verified transfer and keeps proprietary bytes
# outside the authoritative source repository.
"$script_dir/push-stock-blobs.sh"
"$script_dir/apply-twrp-patches.sh"
"$script_dir/install-twrp-trees.sh"

"${pro5_ssh[@]}" bash -s -- \
  "$PRO5_REMOTE_ROOT" "$jobs" "$local_revision" <<'REMOTE'
set -euo pipefail

remote_root="$1"
jobs="$2"
local_revision="$3"
session_name="pro5-twrp-build"
worker="$remote_root/local/remote/worker-build-twrp.sh"
run_root="$remote_root/run"
build_stamp="$(date +%Y%m%d-%H%M%S)"
status_file="$run_root/twrp-build-latest.status"
log_file="$run_root/twrp-build-$build_stamp.log"

for conflicting_session in \
  pro5-source-sync \
  pro5-platform-sync \
  pro5-twrp-source-sync; do
  if tmux has-session -t "$conflicting_session" 2>/dev/null; then
    printf 'Required sync is still running: %s\n' "$conflicting_session" >&2
    exit 1
  fi
done

if [[ ! -s "$remote_root/logs/twrp-9.0-manifest.xml" ]]; then
  printf 'TWRP source sync has not completed successfully.\n' >&2
  exit 1
fi
if tmux has-session -t "$session_name" 2>/dev/null; then
  printf 'tmux session %s is already running\n' "$session_name"
  exit 0
fi

mkdir -p "$run_root"
rm -f -- "$status_file"
: > "$log_file"
ln -sfn "$(basename "$log_file")" "$run_root/twrp-build-latest.log"
chmod 0755 "$worker"

printf -v worker_command '%q %q %q %q %q %q' \
  "$worker" "$jobs" "$status_file" "$log_file" "$build_stamp" \
  "$local_revision"
tmux new-session -d -s "$session_name" "$worker_command"
printf 'Started tmux session %s: target=recoveryimage jobs=%s\n' \
  "$session_name" "$jobs"
REMOTE

"$script_dir/twrp-build-status.sh"
