#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
local_root="$(cd "$script_dir/.." && pwd)"
remote_root="$(cd "$local_root/.." && pwd)"
source_root="$remote_root/src/lineage-17.1"
log_dir="$remote_root/logs"
manifest_lock="$log_dir/lineage-17.1-manifest.xml"
progress_file="$remote_root/run/source-sync-progress.tsv"

mkdir -p "$source_root" "$log_dir" "$remote_root/run"
exec > >(tee -a "$log_dir/source-sync.log") 2>&1

# shellcheck source=builder-network.sh
source "$script_dir/builder-network.sh"
configure_builder_network

export CCACHE_DIR="$remote_root/ccache"
export USE_CCACHE=1
export GIT_TERMINAL_PROMPT=0

printf 'Source sync started at %s\n' "$(date --iso-8601=seconds)"
printf 'Checkout: %s\n' "$source_root"

cd "$source_root"
if [[ ! -f .repo/manifest.xml ]]; then
  repo init \
    -u https://github.com/LineageOS/android.git \
    -b lineage-17.1 \
    --repo-url=https://github.com/GerritCodeReview/git-repo.git \
    --repo-rev=stable \
    --no-clone-bundle \
    --partial-clone \
    --clone-filter=blob:limit=10M
fi

repo_sync_args=(
  -c
  --no-clone-bundle
  --no-tags
  --optimized-fetch
  --prune
  --no-auto-gc
  --retry-fetches=0
  --fail-fast
)

aosp_sources=(ustc bfsu tuna direct)
project_timeout="${PRO5_SYNC_PROJECT_TIMEOUT:-15m}"

sync_one_project() {
  local project="$1"
  local phase="$2"
  local aosp_source
  local status

  for aosp_source in "${aosp_sources[@]}"; do
    configure_builder_aosp_source "$aosp_source"
    printf '%s: %s via AOSP source %s\n' \
      "$phase" "$project" "$aosp_source"

    set +e
    timeout \
      --signal=TERM \
      --kill-after=30s \
      "$project_timeout" \
      repo sync \
        "${repo_sync_args[@]}" \
        --no-manifest-update \
        --no-interleaved \
        -j1 \
        "$project"
    status=$?
    set -e

    if [[ "$status" -eq 0 ]]; then
      configure_builder_aosp_source "${PRO5_AOSP_SOURCE:-ustc}"
      return 0
    fi

    printf 'Sync attempt failed: project=%s source=%s status=%s\n' \
      "$project" "$aosp_source" "$status" >&2
  done

  configure_builder_aosp_source "${PRO5_AOSP_SOURCE:-ustc}"
  return 1
}

# Fetch and check out the two legacy GCC trees first. This makes the
# standalone Image + DTB gate available while the rest of Android continues
# syncing, and is harmless on a resumed checkout.
kernel_toolchains=(
  prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9
  prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9
)
if [[ -x "${kernel_toolchains[0]}/bin/aarch64-linux-android-gcc" ]] && \
    [[ -x "${kernel_toolchains[1]}/bin/arm-linux-androideabi-gcc" ]]; then
  printf 'Kernel toolchains are already checked out\n'
else
  printf 'Syncing kernel toolchains first\n'
  for project in "${kernel_toolchains[@]}"; do
    sync_one_project "$project" 'Kernel toolchain sync'
  done
fi

# repo 2.65's worker pool can deadlock on this builder after a project fetch
# fails, even at -j1. Give each manifest project its own bounded repo process,
# retain successful objects/checkouts, and continue collecting failures.
mapfile -t projects < <(repo list -p | LC_ALL=C sort)
project_total="${#projects[@]}"
failed_projects=()

printf '# index\ttotal\tstate\tproject\tfinished_at\n' > "$progress_file"
printf 'Syncing %s manifest projects one at a time\n' "$project_total"

for index in "${!projects[@]}"; do
  project="${projects[$index]}"
  project_number=$((index + 1))
  phase="Project ${project_number}/${project_total}"

  if sync_one_project "$project" "$phase"; then
    state=complete
  else
    state=failed
    failed_projects+=("$project")
  fi

  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$project_number" \
    "$project_total" \
    "$state" \
    "$project" \
    "$(date --iso-8601=seconds)" >> "$progress_file"
done

if [[ "${#failed_projects[@]}" -ne 0 ]]; then
  printf 'Source sync left %s failed project(s):\n' \
    "${#failed_projects[@]}" >&2
  printf '  %s\n' "${failed_projects[@]}" >&2
  exit 1
fi

repo manifest -r -o "$manifest_lock"
printf 'Source sync completed at %s\n' "$(date --iso-8601=seconds)"
du -sh "$source_root" "$remote_root/ccache"
df -h "$remote_root"
