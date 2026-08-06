#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
local_root="$(cd "$script_dir/.." && pwd)"
remote_root="$(cd "$local_root/.." && pwd)"
source_root="$remote_root/src/lineage-17.1"
log_dir="$remote_root/logs"
local_manifest="$local_root/manifests/pro5.xml"

mkdir -p "$log_dir"
exec > >(tee -a "$log_dir/platform-sync.log") 2>&1

# shellcheck source=builder-network.sh
source "$script_dir/builder-network.sh"
configure_builder_network

export GIT_TERMINAL_PROMPT=0

if [[ ! -f "$source_root/.repo/manifest.xml" ]]; then
  printf 'LineageOS checkout is not initialized: %s\n' "$source_root" >&2
  exit 1
fi

if [[ ! -f "$log_dir/lineage-17.1-manifest.xml" ]]; then
  printf 'Base source sync has not completed successfully.\n' >&2
  exit 1
fi

install -D -m 0644 \
  "$local_manifest" \
  "$source_root/.repo/local_manifests/pro5.xml"

printf 'Platform sync started at %s\n' "$(date --iso-8601=seconds)"
cd "$source_root"
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

lineage_sources=(direct cernet tuna direct)
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

platform_projects=(
  build/soong
  device/samsung/universal7420-common
  hardware/samsung
  hardware/samsung_slsi/exynos
  hardware/samsung_slsi/exynos5
  hardware/samsung_slsi/exynos7420
  hardware/samsung_slsi/openmax
  kernel/samsung/universal7420
)

for index in "${!platform_projects[@]}"; do
  project="${platform_projects[$index]}"
  phase="Platform project $((index + 1))/${#platform_projects[@]}"
  sync_one_project "$project" "$phase"
done

repo manifest -r -o "$log_dir/lineage-17.1-pro5-manifest.xml"
printf 'Platform sync completed at %s\n' "$(date --iso-8601=seconds)"
du -sh \
  device/samsung/universal7420-common \
  hardware/samsung \
  hardware/samsung_slsi \
  kernel/samsung/universal7420
