#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
workspace_root="$(cd "$project_root/.." && pwd)"
stamp="${M86_EVIDENCE_STAMP:-$(date +%Y%m%d-%H%M%S)}"
evidence_root="${M86_EVIDENCE_ROOT:-$project_root/evidence/m0-a10-dirty-oracle-$stamp}"
backup_root="${M86_BASELINE_BACKUP:-$workspace_root/backups/pro5-lineage17-final-20260809}"
stock_dtb="${M86_STOCK_DTB:-$workspace_root/work/pro5-flyme-8.0.5.0A/dtb-inspect/dtb}"

if [[ -e "$evidence_root" ]]; then
  printf 'Refusing to overwrite existing evidence: %s\n' "$evidence_root" >&2
  exit 1
fi

for required in \
  "$project_root/.git" \
  "$project_root/device/meizu/m86/.git" \
  "$project_root/kernel/meizu/m86/.git" \
  "$project_root/vendor/meizu/m86/.git" \
  "$project_root/patches/series.tsv" \
  "$backup_root/SHA256SUMS" \
  "$stock_dtb"; do
  [[ -e "$required" ]] || {
    printf 'Required oracle input is missing: %s\n' "$required" >&2
    exit 1
  }
done

mkdir -p "$evidence_root/repos" "$evidence_root/untracked"

hash_file() {
  sha256sum "$1"
}

capture_repo() {
  local name="$1"
  local repository="$2"
  local repo_out="$evidence_root/repos/$name"
  local untracked_list="$repo_out.untracked.zlist"
  local -a untracked_files=()

  mkdir -p "$repo_out"
  git -C "$repository" rev-parse HEAD > "$repo_out/head.txt"
  git -C "$repository" branch --show-current > "$repo_out/branch.txt"
  git -C "$repository" status --porcelain=v2 -uall > "$repo_out/status-porcelain-v2.txt"
  git -C "$repository" diff --binary --full-index > "$repo_out/worktree.patch"
  git -C "$repository" diff --binary --full-index --cached > "$repo_out/index.patch"
  git -C "$repository" ls-files --others --exclude-standard -z > "$untracked_list"

  while IFS= read -r -d '' path; do
    untracked_files+=("$path")
  done < "$untracked_list"

  if [[ "${#untracked_files[@]}" -gt 0 ]]; then
    (
      cd "$repository"
      sha256sum -- "${untracked_files[@]}" > "$repo_out/untracked-sha256.txt"
      tar -czf "$evidence_root/untracked/$name.tar.gz" -- "${untracked_files[@]}"
    )
  else
    : > "$repo_out/untracked-sha256.txt"
  fi
}

capture_repo workspace "$project_root"
capture_repo device-meizu-m86 "$project_root/device/meizu/m86"
capture_repo kernel-meizu-m86 "$project_root/kernel/meizu/m86"
capture_repo vendor-meizu-m86 "$project_root/vendor/meizu/m86"

(
  cd "$project_root"
  find patches -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum \
    > "$evidence_root/patch-queue-sha256.txt"
)

hash_file "$stock_dtb" > "$evidence_root/stock-dtb-sha256.txt"
cp "$backup_root/SHA256SUMS" "$evidence_root/baseline-SHA256SUMS"
(
  cd "$backup_root"
  sha256sum -c SHA256SUMS
) > "$evidence_root/baseline-verify.txt"

{
  printf 'M0 A10 dirty-oracle evidence\n'
  printf 'captured_at=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
  printf 'project_root=%s\n' "$project_root"
  printf 'baseline_backup=%s\n' "$backup_root"
  printf 'stock_dtb=%s\n\n' "$stock_dtb"
  printf '%s\n' \
    'This package seals the pre-cleanup Git state for the workspace and the m86' \
    'device, kernel, and vendor repositories. It is evidence, not a claim that any' \
    'runtime gate passed. The archived LineageOS 17.1 build has static/hash evidence;' \
    'device validation remains pending unless a separate runtime record says so.'
} > "$evidence_root/README.txt"

(
  cd "$evidence_root"
  find . -type f ! -name SHA256SUMS -print0 | LC_ALL=C sort -z | \
    xargs -0 sha256sum > SHA256SUMS
)

printf 'Sealed local source oracle: %s\n' "$evidence_root"
printf 'Evidence files: %s\n' "$(find "$evidence_root" -type f | wc -l | tr -d ' ')"
