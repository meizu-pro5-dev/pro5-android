#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

if [[ "${PRO5_SKIP_LOCAL_PUSH:-0}" != 1 ]]; then
  "$script_dir/push-local.sh"
fi

"${pro5_ssh[@]}" bash -s -- "$PRO5_REMOTE_ROOT" <<'REMOTE'
set -euo pipefail

remote_root="$1"
local_root="$remote_root/local"
source_root="$remote_root/src/lineage-17.1"
series="$local_root/patches/series.tsv"

while IFS=$'\t' read -r repository patch_path; do
  [[ -z "$repository" || "$repository" == \#* ]] && continue

  repository_root="$source_root/$repository"
  patch_file="$local_root/$patch_path"

  if [[ ! -d "$repository_root/.git" ]]; then
    printf 'Missing source repository: %s\n' "$repository" >&2
    exit 1
  fi
  if [[ ! -f "$patch_file" ]]; then
    printf 'Missing patch: %s\n' "$patch_path" >&2
    exit 1
  fi

  if git -C "$repository_root" apply --reverse --check "$patch_file"; then
    printf 'Already applied: %s\n' "$patch_path"
  else
    git -C "$repository_root" apply --check "$patch_file"
    git -C "$repository_root" apply "$patch_file"
    printf 'Applied: %s\n' "$patch_path"
  fi
done < "$series"

bash "$local_root/tools/audit-reviewed-patch-state.sh" \
  "$source_root" \
  "$local_root" \
  "$remote_root/logs/reviewed-patch-state.txt"
REMOTE
