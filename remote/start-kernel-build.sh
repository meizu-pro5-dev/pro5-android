#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

jobs="${PRO5_KERNEL_BUILD_JOBS:-8}"
if [[ ! "$jobs" =~ ^[1-9][0-9]*$ ]] || ((jobs > 64)); then
  printf 'Invalid PRO5_KERNEL_BUILD_JOBS: %s\n' "$jobs" >&2
  exit 2
fi

local_commit="$(git -C "$project_root" rev-parse HEAD)"
kernel_commit="$(git -C "$project_root/kernel/meizu/m86" rev-parse HEAD)"
if [[ -n "$(git -C "$project_root" status --porcelain --untracked-files=normal)" ]]; then
  local_commit="${local_commit}-dirty"
fi
if [[ -n "$(git -C "$project_root/kernel/meizu/m86" \
    status --porcelain --untracked-files=normal)" ]]; then
  kernel_commit="${kernel_commit}-dirty"
fi
"$script_dir/install-local-trees.sh"

"${pro5_ssh[@]}" bash -s -- \
  "$PRO5_REMOTE_ROOT" "$jobs" "$local_commit" "$kernel_commit" <<'REMOTE'
set -euo pipefail

remote_root="$1"
jobs="$2"
local_commit="$3"
kernel_commit="$4"
session_name="pro5-kernel-build"
worker="$remote_root/local/remote/worker-build-kernel.sh"
launcher="$remote_root/local/remote/detached-worker.sh"
run_root="$remote_root/run"
build_stamp="$(date +%Y%m%d-%H%M%S)"
status_file="$run_root/kernel-latest.status"
log_file="$run_root/kernel-$build_stamp.log"

if [[ -x "$launcher" ]] && \
    "$launcher" running "$session_name" >/dev/null 2>&1; then
  printf 'Detached worker %s is already running.\n' "$session_name"
  exit 0
fi

mkdir -p "$run_root"
rm -f -- "$status_file"
: > "$log_file"
ln -sfn "$(basename "$log_file")" "$run_root/kernel-latest.log"
chmod 0755 "$worker" "$launcher"
"$launcher" start "$session_name" \
  "$worker" "$jobs" "$status_file" "$log_file" "$build_stamp" "$local_commit" \
  "$kernel_commit"
printf 'Started detached worker %s: jobs=%s\n' "$session_name" "$jobs"
REMOTE

"$script_dir/kernel-build-status.sh"
