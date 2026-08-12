#!/usr/bin/env bash

set -euo pipefail

source_root="${1:?source root is required}"
local_root="${2:?local input root is required}"
report_file="${3:?report path is required}"
series="$local_root/patches/series.tsv"
repo_launcher="$source_root/.repo/repo/repo"

for required in "$source_root/.repo/manifest.xml" "$repo_launcher" "$series"; do
  [[ -s "$required" ]] || {
    printf 'Reviewed patch audit input is missing: %s\n' "$required" >&2
    exit 1
  }
done

report_tmp="${report_file}.tmp"
mkdir -p "$(dirname "$report_file")"
: > "$report_tmp"

mapfile -t reviewed_repositories < <(
  awk -F '\t' 'NF == 2 && $1 !~ /^#/ { print $1 }' "$series" |
    LC_ALL=C sort -u
)

is_reviewed_repository() {
  local candidate="$1"
  local reviewed
  for reviewed in "${reviewed_repositories[@]}"; do
    [[ "$candidate" == "$reviewed" ]] && return 0
  done
  return 1
}

while IFS= read -r repository; do
  [[ -n "$repository" ]] || continue
  if is_reviewed_repository "$repository"; then
    continue
  fi
  printf 'Unreviewed dirty platform repository: %s\n' "$repository" >&2
  exit 1
done < <(
  cd "$source_root"
  "$repo_launcher" forall -j8 -c '
    if test -n "$(git status --porcelain --untracked-files=all)"; then
      printf "%s\n" "$REPO_PATH"
    fi
  ' | LC_ALL=C sort
)

for repository in "${reviewed_repositories[@]}"; do
  repository_root="$source_root/$repository"
  if [[ ! -d "$repository_root/.git" ]]; then
    printf 'Reviewed patch repository is missing: %s\n' "$repository" >&2
    exit 1
  fi
  if ! git -C "$repository_root" diff --cached --quiet; then
    printf 'Reviewed patch repository has staged changes: %s\n' \
      "$repository" >&2
    exit 1
  fi

  actual_index="$(mktemp)"
  expected_index="$(mktemp)"
  rm -f -- "$actual_index" "$expected_index"

  GIT_INDEX_FILE="$actual_index" git -C "$repository_root" read-tree HEAD
  GIT_INDEX_FILE="$actual_index" git -C "$repository_root" add -A
  actual_tree="$(
    GIT_INDEX_FILE="$actual_index" git -C "$repository_root" write-tree
  )"

  GIT_INDEX_FILE="$expected_index" git -C "$repository_root" read-tree HEAD
  while IFS=$'\t' read -r _ patch_path; do
    [[ -n "$patch_path" ]] || continue
    patch_file="$local_root/$patch_path"
    [[ -s "$patch_file" ]] || {
      printf 'Reviewed patch is missing: %s\n' "$patch_file" >&2
      rm -f -- "$actual_index" "$expected_index"
      exit 1
    }
    GIT_INDEX_FILE="$expected_index" \
      git -C "$repository_root" apply --cached --check "$patch_file"
    GIT_INDEX_FILE="$expected_index" \
      git -C "$repository_root" apply --cached "$patch_file"
  done < <(awk -F '\t' -v repository="$repository" \
    '$1 == repository { print }' "$series")
  expected_tree="$(
    GIT_INDEX_FILE="$expected_index" git -C "$repository_root" write-tree
  )"
  rm -f -- "$actual_index" "$expected_index"

  if [[ "$actual_tree" != "$expected_tree" ]]; then
    printf 'Platform diff exceeds reviewed patch queue: %s\n' \
      "$repository" >&2
    exit 1
  fi
  printf '%s\t%s\t%s\n' "$repository" "$actual_tree" "$expected_tree" \
    >> "$report_tmp"
done

printf 'series_sha256\t%s\n' "$(sha256sum "$series" | awk '{ print $1 }')" \
  >> "$report_tmp"
mv "$report_tmp" "$report_file"
printf 'Reviewed platform patch state passed: %s\n' "$report_file"
