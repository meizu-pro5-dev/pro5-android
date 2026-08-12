#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
local_root="$(cd "$script_dir/.." && pwd)"
remote_root="$(cd "$local_root/.." && pwd)"
source_root="$remote_root/src/lineage-17.1"
log_dir="$remote_root/logs"
local_manifest="$local_root/manifests/pro5.xml"
patch_series="$local_root/patches/series.tsv"
manifest_lock="$log_dir/lineage-17.1-pro5-manifest.xml"
manifest_tmp="${manifest_lock}.tmp"

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

if [[ ! -s "$log_dir/lineage-17.1-manifest.xml" ]]; then
  printf 'Base source sync has not completed successfully.\n' >&2
  exit 1
fi

rm -f -- "$manifest_lock" "$manifest_tmp"

install -D -m 0644 \
  "$local_manifest" \
  "$source_root/.repo/local_manifests/pro5.xml"

printf 'Platform sync started at %s\n' "$(date --iso-8601=seconds)"
cd "$source_root"
repo_sync_args=(
  -c
  # Every entry below deliberately replaces the base manifest project with a
  # same-path universal7420 fork. repo requires this flag when object-store
  # ownership changes, even when the checkout is clean.
  --force-sync
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

remove_reviewed_project_patches() {
  local project="$1"
  local patch_file
  local patch_index
  local -a project_patches=()

  if [[ ! -s "$patch_series" ]]; then
    printf 'Reviewed platform patch series is missing: %s\n' \
      "$patch_series" >&2
    return 1
  fi
  if ! git -C "$project" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi
  mapfile -t project_patches < <(
    awk -F '\t' -v project="$project" '$1 == project { print $2 }' \
      "$patch_series"
  )
  for ((patch_index = ${#project_patches[@]} - 1;
       patch_index >= 0;
       --patch_index)); do
    patch_file="$local_root/${project_patches[$patch_index]}"
    if [[ ! -f "$patch_file" ]]; then
      printf 'Reviewed platform patch is missing: %s\n' "$patch_file" >&2
      return 1
    fi
    if git -C "$project" apply --reverse --check "$patch_file" \
        2>/dev/null; then
      git -C "$project" apply --reverse "$patch_file"
      printf 'Removed reviewed patch before sync: %s\n' \
        "${project_patches[$patch_index]}"
    elif git -C "$project" apply --check "$patch_file" 2>/dev/null; then
      :
    else
      printf 'Platform checkout does not match reviewed patch state: %s\n' \
        "$patch_file" >&2
      return 1
    fi
  done
}

platform_projects=(
  build/soong
  device/samsung/universal7420-common
  hardware/samsung
  hardware/samsung_slsi/exynos
  hardware/samsung_slsi/exynos5
  hardware/samsung_slsi/exynos7420
  hardware/samsung_slsi/openmax
)

for index in "${!platform_projects[@]}"; do
  project="${platform_projects[$index]}"
  phase="Platform project $((index + 1))/${#platform_projects[@]}"

  remove_reviewed_project_patches "$project"

  # --force-sync may replace git metadata, so never apply it over local work.
  if git -C "$project" rev-parse --is-inside-work-tree >/dev/null 2>&1 && \
      [[ -n "$(git -C "$project" status --porcelain)" ]]; then
    printf 'Refusing to replace dirty platform checkout: %s\n' "$project" >&2
    exit 1
  fi

  sync_one_project "$project" "$phase"
done

repo manifest -r -o "$manifest_tmp"
if [[ ! -s "$manifest_tmp" ]]; then
  printf 'Pinned PRO 5 platform manifest generation produced no data.\n' >&2
  exit 1
fi
mv "$manifest_tmp" "$manifest_lock"
printf 'Platform sync completed at %s\n' "$(date --iso-8601=seconds)"
du -sh \
  device/samsung/universal7420-common \
  hardware/samsung \
  hardware/samsung_slsi
