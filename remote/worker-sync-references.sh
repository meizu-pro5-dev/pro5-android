#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
local_root="$(cd "$script_dir/.." && pwd)"
remote_root="$(cd "$local_root/.." && pwd)"
reference_root="$remote_root/reference"
source_list="$local_root/manifests/reference-repositories.tsv"
lock_file="$remote_root/logs/reference-revisions.tsv"
log_file="$remote_root/logs/reference-sync.log"

mkdir -p "$reference_root" "$remote_root/logs"
exec > >(tee -a "$log_file") 2>&1

if [[ -r /etc/network_turbo ]]; then
  set +u
  # shellcheck disable=SC1091
  source /etc/network_turbo >/dev/null 2>&1
  set -u
fi

export GIT_TERMINAL_PROMPT=0

printf 'Reference sync started at %s\n' "$(date --iso-8601=seconds)"
printf '# name\turl\tbranch\tcommit\tcommit_date\tsubject\n' > "$lock_file"

while IFS=$'\t' read -r name url branch; do
  [[ -z "$name" || "$name" == \#* ]] && continue

  checkout="$reference_root/$name"
  if [[ ! -d "$checkout/.git" ]]; then
    git clone --single-branch --branch "$branch" "$url" "$checkout"
  else
    if [[ -n "$(git -C "$checkout" status --porcelain)" ]]; then
      printf 'Refusing to update modified reference checkout: %s\n' "$checkout" >&2
      exit 1
    fi
    git -C "$checkout" fetch --prune origin "$branch"
    git -C "$checkout" checkout "$branch"
    git -C "$checkout" merge --ff-only "origin/$branch"
  fi

  commit_record="$(git -C "$checkout" show -s --format='%H%x09%cI%x09%s' HEAD)"
  printf '%s\t%s\t%s\t%s\n' \
    "$name" "$url" "$branch" "$commit_record" >> "$lock_file"
done < "$source_list"

printf 'Reference sync completed at %s\n' "$(date --iso-8601=seconds)"
du -sh "$reference_root"
