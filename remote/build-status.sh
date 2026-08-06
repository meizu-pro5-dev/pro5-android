#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

tail_lines="${1:-60}"
if [[ ! "$tail_lines" =~ ^[1-9][0-9]*$ ]] || ((tail_lines > 500)); then
  printf 'Invalid tail line count: %s\n' "$tail_lines" >&2
  exit 2
fi

"${pro5_ssh[@]}" bash -s -- "$PRO5_REMOTE_ROOT" "$tail_lines" <<'REMOTE'
set -euo pipefail

remote_root="$1"
tail_lines="$2"
session_name="pro5-build"
run_root="$remote_root/run"
status_file="$run_root/build-latest.status"
log_file="$run_root/build-latest.log"

if tmux has-session -t "$session_name" 2>/dev/null; then
  printf 'state: running\n'
  tmux list-panes -t "$session_name" \
    -F 'pid=#{pane_pid} active=#{pane_active} command=#{pane_current_command}'
else
  printf 'state: stopped\n'
fi

if [[ -f "$status_file" ]]; then
  cat "$status_file"
fi

df -h "$remote_root" | awk \
  'NR == 2 {print "disk_used=" $3, "disk_free=" $4}'
ccache --show-stats | sed -n '1,12p'

if [[ -f "$log_file" ]]; then
  tail -c 131072 "$log_file" | tr '\r' '\n' | tail -n "$tail_lines"
else
  printf 'No build log yet.\n'
fi
REMOTE
