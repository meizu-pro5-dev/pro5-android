#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
requested_jobs="${1:-8}"
profile="${2:-android}"
cache_root="${3:-}"
report_file="${4:-}"
cgroup_root=/sys/fs/cgroup
gib=1073741824

if [[ ! "$requested_jobs" =~ ^[1-9][0-9]*$ ]]; then
  printf 'Invalid requested job count: %s\n' "$requested_jobs" >&2
  exit 2
fi
case "$profile" in
  android)
    reserve_bytes=$((16 * gib))
    bytes_per_job=$((4 * gib))
    hard_job_cap=8
    ;;
  kernel)
    reserve_bytes=$((6 * gib))
    bytes_per_job=$((1536 * 1024 * 1024))
    hard_job_cap=8
    ;;
  twrp)
    reserve_bytes=$((8 * gib))
    bytes_per_job=$((2 * gib))
    hard_job_cap=8
    ;;
  *)
    printf 'Unknown builder memory profile: %s\n' "$profile" >&2
    exit 2
    ;;
esac

for required_cgroup_file in memory.current memory.max memory.stat memory.events; do
  if [[ ! -r "$cgroup_root/$required_cgroup_file" ]]; then
    printf 'Required cgroup v2 memory input is missing: %s\n' \
      "$cgroup_root/$required_cgroup_file" >&2
    exit 1
  fi
done

read_memory_stat() {
  local key="$1"
  awk -v key="$key" '$1 == key { print $2; found=1 } END { if (!found) print 0 }' \
    "$cgroup_root/memory.stat"
}

memory_limit="$(<"$cgroup_root/memory.max")"
if [[ "$memory_limit" == max ]] || \
    [[ "$memory_limit" =~ ^[0-9]+$ && "$memory_limit" -gt 1000000000000000 ]]; then
  memory_limit="$(
    awk '/^MemTotal:/ { printf "%.0f\n", $2 * 1024 }' /proc/meminfo
  )"
fi
if [[ ! "$memory_limit" =~ ^[0-9]+$ ]] || \
    ((memory_limit < 8 * gib)); then
  printf 'Invalid or insufficient builder memory limit: %s\n' \
    "$memory_limit" >&2
  exit 1
fi

memory_current_before="$(<"$cgroup_root/memory.current")"
file_bytes="$(read_memory_stat file)"
shmem_bytes="$(read_memory_stat shmem)"
file_dirty_bytes="$(read_memory_stat file_dirty)"
file_writeback_bytes="$(read_memory_stat file_writeback)"
reclaimable_file_bytes=$((
  file_bytes - shmem_bytes - file_dirty_bytes - file_writeback_bytes
))
((reclaimable_file_bytes < 0)) && reclaimable_file_bytes=0

cache_release_executed=0
cache_release_log="$(mktemp)"
report_tmp=
trap 'rm -f -- "$cache_release_log" ${report_tmp:+"$report_tmp"}' EXIT
if [[ -n "$cache_root" && -d "$cache_root" ]] && \
    ((memory_current_before * 100 >= memory_limit * 70)) && \
    ((reclaimable_file_bytes >= 4 * gib)); then
  cache_release_executed=1
  python3 "$script_dir/release-build-cache.py" \
    "$cache_root" --min-size $((1024 * 1024)) > "$cache_release_log"
fi

memory_current_after="$(<"$cgroup_root/memory.current")"
file_bytes="$(read_memory_stat file)"
shmem_bytes="$(read_memory_stat shmem)"
file_dirty_bytes="$(read_memory_stat file_dirty)"
file_writeback_bytes="$(read_memory_stat file_writeback)"
reclaimable_file_bytes=$((
  file_bytes - shmem_bytes - file_dirty_bytes - file_writeback_bytes
))
((reclaimable_file_bytes < 0)) && reclaimable_file_bytes=0
nonreclaimable_bytes=$((memory_current_after - reclaimable_file_bytes))
((nonreclaimable_bytes < 0)) && nonreclaimable_bytes=0
cgroup_budget_bytes=$((memory_limit - nonreclaimable_bytes))
host_available_bytes="$(
  awk '/^MemAvailable:/ { printf "%.0f\n", $2 * 1024 }' /proc/meminfo
)"
if [[ ! "$host_available_bytes" =~ ^[0-9]+$ ]]; then
  printf 'Invalid host MemAvailable value: %s\n' \
    "$host_available_bytes" >&2
  exit 1
fi
available_budget_bytes="$cgroup_budget_bytes"
if ((host_available_bytes < available_budget_bytes)); then
  available_budget_bytes="$host_available_bytes"
fi

minimum_budget_bytes=$((reserve_bytes + bytes_per_job))
if ((available_budget_bytes < minimum_budget_bytes)); then
  printf 'Builder memory safety gate failed: available=%s required=%s.\n' \
    "$available_budget_bytes" "$minimum_budget_bytes" >&2
  exit 1
fi
memory_job_capacity=$(((available_budget_bytes - reserve_bytes) / bytes_per_job))
((memory_job_capacity < 1)) && memory_job_capacity=1
cpu_capacity="$(nproc)"
effective_jobs="$requested_jobs"
for capacity in "$hard_job_cap" "$memory_job_capacity" "$cpu_capacity"; do
  if ((capacity < effective_jobs)); then
    effective_jobs="$capacity"
  fi
done

memory_events_max="$(
  awk '$1 == "max" { print $2 }' "$cgroup_root/memory.events"
)"
memory_events_oom="$(
  awk '$1 == "oom" { print $2 }' "$cgroup_root/memory.events"
)"
memory_events_oom_kill="$(
  awk '$1 == "oom_kill" { print $2 }' "$cgroup_root/memory.events"
)"

if [[ -z "$report_file" ]]; then
  report_file=/dev/stdout
else
  mkdir -p "$(dirname "$report_file")"
fi
report_tmp="$(mktemp)"
{
  printf 'profile=%s\n' "$profile"
  printf 'requested_jobs=%s\n' "$requested_jobs"
  printf 'effective_jobs=%s\n' "$effective_jobs"
  printf 'hard_job_cap=%s\n' "$hard_job_cap"
  printf 'memory_job_capacity=%s\n' "$memory_job_capacity"
  printf 'memory_limit_bytes=%s\n' "$memory_limit"
  printf 'memory_current_before_bytes=%s\n' "$memory_current_before"
  printf 'memory_current_after_bytes=%s\n' "$memory_current_after"
  printf 'reclaimable_file_bytes=%s\n' "$reclaimable_file_bytes"
  printf 'nonreclaimable_bytes=%s\n' "$nonreclaimable_bytes"
  printf 'available_budget_bytes=%s\n' "$available_budget_bytes"
  printf 'reserve_bytes=%s\n' "$reserve_bytes"
  printf 'bytes_per_job=%s\n' "$bytes_per_job"
  printf 'cache_release_executed=%s\n' "$cache_release_executed"
  cat "$cache_release_log"
  printf 'memory_events_max_before=%s\n' "$memory_events_max"
  printf 'memory_events_oom_before=%s\n' "$memory_events_oom"
  printf 'memory_events_oom_kill_before=%s\n' "$memory_events_oom_kill"
} > "$report_tmp"
if [[ "$report_file" == /dev/stdout ]]; then
  cat "$report_tmp"
else
  mv "$report_tmp" "$report_file"
  report_tmp=
  cat "$report_file"
fi
