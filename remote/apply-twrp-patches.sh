#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

"$script_dir/push-local.sh"

"${pro5_ssh[@]}" bash -s -- "$PRO5_REMOTE_ROOT" <<'REMOTE'
set -euo pipefail

remote_root="$1"
local_root="$remote_root/local"
source_root="$remote_root/src/twrp-9.0"
series="$local_root/patches/twrp-series.tsv"

if [[ ! -s "$series" ]]; then
  printf 'Missing reviewed TWRP patch series: %s\n' "$series" >&2
  exit 1
fi

while IFS=$'\t' read -r repository patch_path; do
  [[ -z "$repository" || "$repository" == \#* ]] && continue

  repository_root="$source_root/$repository"
  patch_file="$local_root/$patch_path"

  if [[ ! -d "$repository_root/.git" ]]; then
    printf 'Missing TWRP source repository: %s\n' "$repository" >&2
    exit 1
  fi
  if [[ ! -f "$patch_file" ]]; then
    printf 'Missing reviewed TWRP patch: %s\n' "$patch_path" >&2
    exit 1
  fi

  if git -C "$repository_root" apply --reverse --check "$patch_file" \
      2>/dev/null; then
    printf 'Already applied: %s\n' "$patch_path"
  elif git -C "$repository_root" apply --check "$patch_file" 2>/dev/null; then
    git -C "$repository_root" apply "$patch_file"
    printf 'Applied: %s\n' "$patch_path"
  else
    printf 'TWRP checkout does not match reviewed patch state: %s\n' \
      "$patch_file" >&2
    exit 1
  fi
done < "$series"
REMOTE
