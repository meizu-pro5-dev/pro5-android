#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
local_root="$(cd "$script_dir/.." && pwd)"
remote_root="$(cd "$local_root/.." && pwd)"
source_root="$remote_root/src/lineage-17.1"
log_dir="$remote_root/logs"
manifest_lock="$log_dir/lineage-17.1-manifest.xml"
progress_file="$remote_root/run/source-sync-progress.tsv"
progress_manifest_file="$remote_root/run/source-sync-progress.manifest.sha256"

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

lineage_sources=(direct tuna direct tuna)
aosp_sources=(ustc bfsu tuna direct)
project_timeout="${PRO5_SYNC_PROJECT_TIMEOUT:-15m}"

sync_one_project() {
  local project="$1"
  local phase="$2"
  local route_index
  local lineage_source
  local aosp_source
  local status

  for route_index in "${!aosp_sources[@]}"; do
    lineage_source="${lineage_sources[$route_index]}"
    aosp_source="${aosp_sources[$route_index]}"
    configure_builder_lineage_source "$lineage_source"
    configure_builder_aosp_source "$aosp_source"
    printf '%s: %s via LineageOS %s / AOSP %s\n' \
      "$phase" "$project" "$lineage_source" "$aosp_source"

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
      configure_builder_lineage_source "${PRO5_LINEAGE_SOURCE:-direct}"
      configure_builder_aosp_source "${PRO5_AOSP_SOURCE:-ustc}"
      return 0
    fi

    printf 'Sync attempt failed: project=%s lineage=%s aosp=%s status=%s\n' \
      "$project" "$lineage_source" "$aosp_source" "$status" >&2
  done

  configure_builder_lineage_source "${PRO5_LINEAGE_SOURCE:-direct}"
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
# Without --all, repo list omits manifest projects that have not yet acquired a
# worktree. That would make a resumed partial checkout look deceptively whole.
mapfile -t projects < <(repo list --all -p | LC_ALL=C sort)
project_total="${#projects[@]}"
failed_projects=()
declare -A completed_projects=()

# A full manifest has hundreds of projects, so a failed late fetch must not
# force all successful checkouts through another network pass. Resume only
# when the prior progress belongs to this exact manifest and the checkout is
# still present. A changed manifest automatically invalidates this cache.
manifest_identity="$(repo manifest | sha256sum | cut -d' ' -f1)"
if [[ -s "$progress_manifest_file" ]] && \
    [[ "$(<"$progress_manifest_file")" == "$manifest_identity" ]] && \
    [[ -s "$progress_file" ]]; then
  while IFS=$'\t' read -r _ prior_total prior_state prior_project _; do
    [[ "$prior_state" == complete ]] || continue
    [[ "$prior_total" == "$project_total" ]] || continue
    [[ -d "$prior_project" ]] || continue
    if git -C "$prior_project" rev-parse --verify HEAD >/dev/null 2>&1; then
      completed_projects["$prior_project"]=1
    fi
  done < "$progress_file"
fi

printf '# index\ttotal\tstate\tproject\tfinished_at\n' > "$progress_file"
printf '%s\n' "$manifest_identity" > "$progress_manifest_file"
printf 'Syncing %s manifest projects one at a time\n' "$project_total"
if [[ "${#completed_projects[@]}" -ne 0 ]]; then
  printf 'Resuming %s completed projects from the matching manifest\n' \
    "${#completed_projects[@]}"
fi

for index in "${!projects[@]}"; do
  project="${projects[$index]}"
  project_number=$((index + 1))
  phase="Project ${project_number}/${project_total}"

  if [[ -n "${completed_projects[$project]+complete}" ]]; then
    printf '%s: %s retained from matching progress\n' "$phase" "$project"
    state=complete
  elif [[ "$project" == "${kernel_toolchains[0]}" ]] || \
      [[ "$project" == "${kernel_toolchains[1]}" ]]; then
    printf '%s: %s already completed by the toolchain gate\n' \
      "$phase" "$project"
    state=complete
  elif sync_one_project "$project" "$phase"; then
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
