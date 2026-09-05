#!/usr/bin/env bash

set -euo pipefail

workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="${1:-}"
series="$workspace_root/patches/lineage-20.0/series.tsv"
locks="$workspace_root/locks/lineage-20.0-revisions.tsv"

if [[ -z "$source_root" || ! -d "$source_root/.repo" ]]; then
  printf 'Usage: %s /path/to/lineage-20.0\n' "$0" >&2
  exit 2
fi

scratch_dir="$(mktemp -d)"
trap 'rm -rf -- "$scratch_dir"' EXIT

# A separate index includes tracked edits and non-ignored additions without
# changing the caller's staging area. Trees also work after git apply, which
# deliberately leaves HEAD at the pinned upstream revision.
working_tree() {
  local repository_root="$1"
  local index_file="$scratch_dir/working.index"
  rm -f -- "$index_file"
  GIT_INDEX_FILE="$index_file" git -C "$repository_root" read-tree HEAD
  GIT_INDEX_FILE="$index_file" git -C "$repository_root" add -A
  GIT_INDEX_FILE="$index_file" git -C "$repository_root" write-tree
}

apply_repository() {
  local repository="$1" base_revision="$2" validated_revision="$3"
  shift 3
  local repository_root="$source_root/$repository"
  local actual_revision actual_tree expected_tree patch_file
  local index_file="$scratch_dir/queue.index"
  local -a patch_files=("$@")

  actual_revision="$(git -C "$repository_root" rev-parse HEAD)"
  expected_tree="$(awk -F '\t' -v p="$repository" -v v="$validated_revision" \
    '$1 == p && $3 == v { print $4 }' "$locks")"
  [[ "$expected_tree" =~ ^[0-9a-f]{40}$ ]] || {
    printf 'Missing or ambiguous tree lock for %s\n' "$repository" >&2
    return 1
  }
  if [[ "$actual_revision" != "$base_revision" && "$actual_revision" != "$validated_revision" ]]; then
    printf 'Unexpected revision for %s: expected %s or %s, found %s\n' \
      "$repository" "$base_revision" "$validated_revision" "$actual_revision" >&2
    return 1
  fi
  for patch_file in "${patch_files[@]}"; do
    [[ -s "$patch_file" ]] || {
      printf 'Missing patch: %s\n' "$patch_file" >&2
      return 1
    }
  done

  actual_tree="$(working_tree "$repository_root")"
  if [[ "$actual_tree" == "$expected_tree" ]]; then
    printf 'Already at validated tree: %s\n' "$repository"
    return 0
  fi
  if [[ "$actual_revision" != "$base_revision" || \
        "$actual_tree" != "$(git -C "$repository_root" rev-parse 'HEAD^{tree}')" ]]; then
    printf 'Repository has unvalidated local changes: %s\n' "$repository" >&2
    return 1
  fi

  # Preflight the complete ordered queue and its final tree before writing any
  # source file. A broken later patch must not leave a partially applied queue.
  rm -f -- "$index_file"
  GIT_INDEX_FILE="$index_file" git -C "$repository_root" read-tree "$base_revision"
  for patch_file in "${patch_files[@]}"; do
    GIT_INDEX_FILE="$index_file" git -C "$repository_root" apply --cached --check "$patch_file"
    GIT_INDEX_FILE="$index_file" git -C "$repository_root" apply --cached "$patch_file"
  done
  [[ "$(GIT_INDEX_FILE="$index_file" git -C "$repository_root" write-tree)" == "$expected_tree" ]] || {
    printf 'Patch queue does not produce the locked tree: %s\n' "$repository" >&2
    return 1
  }
  for patch_file in "${patch_files[@]}"; do
    git -C "$repository_root" apply --check "$patch_file"
    git -C "$repository_root" apply "$patch_file"
    printf 'Applied: %s\n' "$patch_file"
  done
  [[ "$(working_tree "$repository_root")" == "$expected_tree" ]] || {
    printf 'Applied tree differs from lock: %s\n' "$repository" >&2
    return 1
  }
}

current_repository=""
current_base=""
current_validated=""
declare -a current_patches=()
while IFS=$'\t' read -r repository base_revision validated_revision patch_path; do
  [[ -z "$repository" || "$repository" == \#* ]] && continue
  if [[ "$repository" != "$current_repository" ]]; then
    if [[ -n "$current_repository" ]]; then
      apply_repository "$current_repository" "$current_base" "$current_validated" "${current_patches[@]}"
    fi
    current_repository="$repository"
    current_base="$base_revision"
    current_validated="$validated_revision"
    current_patches=()
  fi
  [[ "$base_revision" == "$current_base" && "$validated_revision" == "$current_validated" ]] || {
    printf 'Inconsistent patch revisions for %s\n' "$repository" >&2
    exit 1
  }
  current_patches+=("$workspace_root/$patch_path")
done < "$series"
if [[ -n "$current_repository" ]]; then
  apply_repository "$current_repository" "$current_base" "$current_validated" "${current_patches[@]}"
fi
