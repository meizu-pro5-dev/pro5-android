#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

target="${1:-${PRO5_BUILD_TARGET:-bootimage}}"
jobs="${PRO5_BUILD_JOBS:-24}"

case "$target" in
  kernel | bootimage | recoveryimage | bacon) ;;
  *)
    printf 'Unsupported build target: %s\n' "$target" >&2
    exit 2
    ;;
esac

if [[ ! "$jobs" =~ ^[1-9][0-9]*$ ]] || ((jobs > 64)); then
  printf 'Invalid PRO5_BUILD_JOBS: %s\n' "$jobs" >&2
  exit 2
fi

"$script_dir/push-local.sh"

"${pro5_ssh[@]}" bash -s -- "$PRO5_REMOTE_ROOT" <<'REMOTE'
set -euo pipefail

remote_root="$1"
for session_name in pro5-source-sync pro5-platform-sync; do
  if tmux has-session -t "$session_name" 2>/dev/null; then
    printf 'Required sync is still running: %s\n' "$session_name" >&2
    exit 1
  fi
done

if [[ ! -f "$remote_root/logs/lineage-17.1-pro5-manifest.xml" ]]; then
  printf 'Platform sync has not completed successfully.\n' >&2
  exit 1
fi
REMOTE

"$script_dir/apply-patches.sh"
"$script_dir/install-local-trees.sh"

"${pro5_ssh[@]}" bash -s -- \
  "$PRO5_REMOTE_ROOT" "$target" "$jobs" <<'REMOTE'
set -euo pipefail

remote_root="$1"
target="$2"
jobs="$3"
session_name="pro5-build"
worker="$remote_root/local/remote/worker-build.sh"
run_root="$remote_root/run"
build_stamp="$(date +%Y%m%d-%H%M%S)"
status_file="$run_root/build-latest.status"
log_file="$run_root/build-$build_stamp-$target.log"

if tmux has-session -t "$session_name" 2>/dev/null; then
  printf 'tmux session %s is already running\n' "$session_name"
  exit 0
fi

mkdir -p "$run_root"
rm -f -- "$status_file"
: > "$log_file"
ln -sfn "$(basename "$log_file")" "$run_root/build-latest.log"
chmod 0755 "$worker"

printf -v worker_command '%q %q %q %q %q %q' \
  "$worker" "$target" "$jobs" "$status_file" "$log_file" "$build_stamp"
tmux new-session -d -s "$session_name" "$worker_command"
printf 'Started tmux session %s: target=%s jobs=%s\n' \
  "$session_name" "$target" "$jobs"
REMOTE

"$script_dir/build-status.sh"
