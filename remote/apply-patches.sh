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
retired_ledger="$local_root/docs/retired-platform-debt.tsv"

# A cleanup milestone may retire a patch that is still applied in an existing
# builder checkout. Reverse only a byte-exact retired patch before validating
# the active queue; a partial or unknown platform diff remains a hard failure.
while IFS=$'\t' read -r domain repository patch_path _; do
  [[ "$domain" == domain ]] && continue
  [[ -n "$repository" && -n "$patch_path" ]] || continue
  if [[ "$patch_path" == "-" ]]; then
    # This row records a retired change whose original patch artifact was not
    # retained in the workspace. It is provenance-only; do not turn it into a
    # missing-file failure for every otherwise reproducible build.
    printf 'Retired patch has no retained artifact: %s/%s\n' \
      "$domain" "$repository"
    continue
  fi
  case "$repository" in
    workspace\ tooling)
      # Workspace tools are not patches against an Android source project.
      # Their retirement contract is simply that the old owner is absent.
      if [[ -e "$local_root/$patch_path" ]]; then
        printf 'Retired workspace tool is still present: %s\n' \
          "$patch_path" >&2
        exit 1
      fi
      continue
      ;;
    device/meizu/m86 | hardware/meizu/m86 | kernel/meizu/m86 | vendor/meizu/m86)
      # Authoritative local trees are installed after platform patch handling;
      # their retirement rows are provenance only, never builder mutations.
      continue
      ;;
  esac
  repository_root="$source_root/$repository"
  patch_file="$local_root/$patch_path"
  [[ -s "$patch_file" ]] || {
    printf 'Retired patch input is missing: %s\n' "$patch_path" >&2
    exit 1
  }
  if [[ ! -d "$repository_root/.git" ]]; then
    printf 'Retired project is absent from the pinned manifest: %s\n' \
      "$repository"
    continue
  fi
  if git -C "$repository_root" apply --reverse --check "$patch_file"; then
    git -C "$repository_root" apply --reverse "$patch_file"
    printf 'Retired and reversed: %s\n' "$patch_path"
  elif git -C "$repository_root" apply --check "$patch_file"; then
    printf 'Already absent: %s\n' "$patch_path"
  else
    # A retired patch can be absent after an earlier successful cleanup while
    # its old context is no longer applicable in either direction (for
    # example, when a second retired patch touched the same hunk).  Accept
    # that state only when every path touched by this patch is byte-clean in
    # the pinned source checkout; any residual diff remains fail-closed.
    retired_paths_clean=true
    while IFS= read -r touched_path; do
      [[ -n "$touched_path" ]] || continue
      if [[ -n "$(git -C "$repository_root" status --porcelain -- \
          "$touched_path")" ]]; then
        retired_paths_clean=false
        break
      fi
    done < <(awk '$1 == "diff" && $2 == "--git" {
      path = $4
      sub(/^b\//, "", path)
      print path
    }' "$patch_file")
    if [[ "$retired_paths_clean" == true ]]; then
      printf 'Already absent (touched paths clean): %s\n' "$patch_path"
    else
      printf 'Retired patch state is neither applied nor clean: %s\n' \
        "$patch_path" >&2
      exit 1
    fi
  fi
done < "$retired_ledger"

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
