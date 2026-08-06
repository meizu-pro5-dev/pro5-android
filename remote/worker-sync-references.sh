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

  if [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
    printf 'Invalid reference name: %s\n' "$name" >&2
    exit 1
  fi

  checkout="$reference_root/$name"
  if [[ ! -d "$checkout/.git" ]]; then
    clone_complete=false
    for attempt in 1 2 3 4; do
      if [[ -e "$checkout" && ! -d "$checkout/.git" ]]; then
        rm -rf -- "$checkout"
      fi

      if git \
          -c http.version=HTTP/1.1 \
          clone \
          --filter=blob:none \
          --single-branch \
          --branch "$branch" \
          "$url" \
          "$checkout"; then
        clone_complete=true
        break
      fi

      printf 'Clone attempt %d failed for %s\n' "$attempt" "$name" >&2
      sleep "$((attempt * 5))"
    done

    if [[ "$clone_complete" != true ]]; then
      printf 'Failed to clone reference after 4 attempts: %s\n' "$name" >&2
      exit 1
    fi
  else
    if [[ -n "$(git -C "$checkout" status --porcelain)" ]]; then
      printf 'Refusing to update modified reference checkout: %s\n' "$checkout" >&2
      exit 1
    fi
    git -C "$checkout" -c http.version=HTTP/1.1 \
      fetch --prune origin "$branch"
    git -C "$checkout" checkout "$branch"
    git -C "$checkout" merge --ff-only "origin/$branch"
  fi

  commit_record="$(git -C "$checkout" show -s --format='%H%x09%cI%x09%s' HEAD)"
  printf '%s\t%s\t%s\t%s\n' \
    "$name" "$url" "$branch" "$commit_record" >> "$lock_file"
done < "$source_list"

printf 'Reference sync completed at %s\n' "$(date --iso-8601=seconds)"
du -sh "$reference_root"
