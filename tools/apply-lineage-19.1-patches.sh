#!/usr/bin/env bash

set -euo pipefail

workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="${1:-}"
series="$workspace_root/patches/lineage-19.1/series.tsv"

if [[ -z "$source_root" || ! -d "$source_root/.repo" ]]; then
  printf 'Usage: %s /path/to/lineage-19.1\n' "$0" >&2
  exit 2
fi

current_repository=""
skip_repository=false

while IFS=$'\t' read -r repository base_revision validated_revision patch_path; do
  [[ -z "$repository" || "$repository" == \#* ]] && continue
  repository_root="$source_root/$repository"
  patch_file="$workspace_root/$patch_path"

  git -C "$repository_root" rev-parse --git-dir >/dev/null 2>&1 || {
    printf 'Missing repository: %s\n' "$repository" >&2
    exit 1
  }
  [[ -s "$patch_file" ]] || {
    printf 'Missing patch: %s\n' "$patch_path" >&2
    exit 1
  }

  if [[ "$repository" != "$current_repository" ]]; then
    current_repository="$repository"
    actual_revision="$(git -C "$repository_root" rev-parse HEAD)"
    if [[ "$actual_revision" == "$validated_revision" ]]; then
      skip_repository=true
      printf 'Already at validated revision: %s\n' "$repository"
    elif [[ "$actual_revision" == "$base_revision" ]]; then
      skip_repository=false
      if [[ -n "$(git -C "$repository_root" status --porcelain)" ]]; then
        printf 'Base repository has local changes: %s\n' "$repository" >&2
        exit 1
      fi
    else
      printf 'Unexpected revision for %s: expected %s or %s, found %s\n' \
        "$repository" "$base_revision" "$validated_revision" "$actual_revision" >&2
      exit 1
    fi
  fi

  if [[ "$skip_repository" == false ]]; then
    git -C "$repository_root" apply --check "$patch_file"
    git -C "$repository_root" apply "$patch_file"
    printf 'Applied: %s\n' "$patch_path"
  fi
done < "$series"
