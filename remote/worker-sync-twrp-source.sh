#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
local_root="$(cd "$script_dir/.." && pwd)"
remote_root="$(cd "$local_root/.." && pwd)"
source_root="$remote_root/src/twrp-9.0"
lineage_reference="$remote_root/src/lineage-17.1"
log_dir="$remote_root/logs"
manifest_lock="$log_dir/twrp-9.0-manifest.xml"
manifest_tmp="${manifest_lock}.tmp"
progress_file="$remote_root/run/twrp-source-sync-progress.tsv"
progress_manifest_file="$remote_root/run/twrp-source-sync-progress.manifest.sha256"

mkdir -p "$source_root" "$log_dir" "$remote_root/run"
rm -f -- "$manifest_lock" "$manifest_tmp"
exec > >(tee -a "$log_dir/twrp-source-sync.log") 2>&1

# shellcheck source=builder-network.sh
source "$script_dir/builder-network.sh"
configure_builder_network

export GIT_TERMINAL_PROMPT=0

printf 'TWRP source sync started at %s\n' "$(date --iso-8601=seconds)"
printf 'Checkout: %s\n' "$source_root"

cd "$source_root"
if [[ ! -f .repo/manifest.xml ]]; then
  init_args=(
    -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_omni.git
    -b twrp-9.0
    --repo-url=https://github.com/GerritCodeReview/git-repo.git
    --repo-rev=stable
    --no-clone-bundle
    --depth=1
    --partial-clone
    --clone-filter=blob:limit=10M
  )
  if [[ -f "$lineage_reference/.repo/manifest.xml" ]]; then
    init_args+=(--reference="$lineage_reference")
  fi
  repo init "${init_args[@]}"
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
project_timeout="${PRO5_TWRP_SYNC_PROJECT_TIMEOUT:-15m}"

sync_one_project() {
  local project="$1"
  local phase="$2"
  local aosp_source
  local status

  for aosp_source in "${aosp_sources[@]}"; do
    configure_builder_lineage_source direct
    configure_builder_aosp_source "$aosp_source"
    printf '%s: %s via GitHub accelerated / AOSP %s\n' \
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

    printf 'TWRP sync attempt failed: project=%s aosp=%s status=%s\n' \
      "$project" "$aosp_source" "$status" >&2
  done

  configure_builder_aosp_source "${PRO5_AOSP_SOURCE:-ustc}"
  return 1
}

mapfile -t projects < <(repo list --all -p | LC_ALL=C sort)
project_total="${#projects[@]}"
failed_projects=()
declare -A completed_projects=()

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
printf 'Syncing %s TWRP manifest projects one at a time\n' "$project_total"
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
  printf 'TWRP source sync left %s failed project(s):\n' \
    "${#failed_projects[@]}" >&2
  printf '  %s\n' "${failed_projects[@]}" >&2
  exit 1
fi

if [[ ! -s bootable/recovery/variables.h ]] || \
    ! rg -q 'TW_MAIN_VERSION_STR[[:space:]]+"3\.7\.0_9"' \
      bootable/recovery/variables.h; then
  printf 'The synchronized recovery tree is not TWRP 3.7.0_9.\n' >&2
  exit 1
fi

repo manifest -r -o "$manifest_tmp"
if [[ ! -s "$manifest_tmp" ]]; then
  printf 'Pinned TWRP manifest generation produced no data.\n' >&2
  exit 1
fi
mv "$manifest_tmp" "$manifest_lock"
printf 'TWRP source sync completed at %s\n' "$(date --iso-8601=seconds)"
du -sh "$source_root"
df -h "$remote_root"
