#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
remote_root="$(cd "$script_dir/../.." && pwd)"
run_root="$remote_root/run"
action="${1:-}"
name="${2:-}"
pid_file="$run_root/$name.pid"
lock_file="$run_root/$name.lock"

if [[ ! "$name" =~ ^pro5-[a-z0-9-]+$ ]]; then
  printf 'Invalid detached worker name: %s\n' "$name" >&2
  exit 2
fi

mkdir -p "$run_root"
exec 9>"$lock_file"
flock -x 9

worker_running() {
  local pid
  local saved_starttime
  local expected_command
  local actual_starttime
  [[ -s "$pid_file" ]] || return 1
  pid="$(sed -n 's/^pid=//p' "$pid_file")"
  saved_starttime="$(sed -n 's/^starttime=//p' "$pid_file")"
  expected_command="$(sed -n 's/^command=//p' "$pid_file")"
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
  [[ "$saved_starttime" =~ ^[1-9][0-9]*$ ]] || return 1
  [[ -n "$expected_command" ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  [[ -r "/proc/$pid/stat" ]] || return 1
  actual_starttime="$(awk '{ print $22 }' "/proc/$pid/stat")"
  [[ "$actual_starttime" == "$saved_starttime" ]] || return 1
  tr '\0' '\n' < "/proc/$pid/cmdline" | \
    grep -F -x -q -- "$expected_command"
}

case "$action" in
  running)
    if worker_running; then
      printf 'running pid=%s\n' "$(sed -n 's/^pid=//p' "$pid_file")"
      exit 0
    fi
    rm -f -- "$pid_file"
    printf 'stopped\n'
    exit 1
    ;;
  start)
    shift 2
    [[ "$#" -gt 0 ]] || {
      printf 'Detached worker command is missing.\n' >&2
      exit 2
    }
    if worker_running; then
      printf 'already running pid=%s\n' \
        "$(sed -n 's/^pid=//p' "$pid_file")"
      exit 0
    fi
    rm -f -- "$pid_file"
    expected_command="$1"
    nohup "$@" 9>&- </dev/null >/dev/null 2>&1 &
    pid="$!"
    for _ in {1..20}; do
      if [[ -r "/proc/$pid/stat" ]]; then
        starttime="$(awk '{ print $22 }' "/proc/$pid/stat")"
        if [[ "$starttime" =~ ^[1-9][0-9]*$ ]] && \
            tr '\0' '\n' < "/proc/$pid/cmdline" | \
              grep -F -x -q -- "$expected_command"; then
          break
        fi
      fi
      sleep 0.05
    done
    if ! kill -0 "$pid" 2>/dev/null || \
        [[ ! "${starttime:-}" =~ ^[1-9][0-9]*$ ]]; then
      printf 'Detached worker failed to start: %s\n' "$expected_command" >&2
      exit 1
    fi
    {
      printf 'pid=%s\n' "$pid"
      printf 'starttime=%s\n' "$starttime"
      printf 'command=%s\n' "$expected_command"
    } > "${pid_file}.tmp"
    mv "${pid_file}.tmp" "$pid_file"
    printf 'started pid=%s\n' "$pid"
    ;;
  *)
    printf 'Usage: %s {start|running} pro5-name [command ...]\n' \
      "${0##*/}" >&2
    exit 2
    ;;
esac
