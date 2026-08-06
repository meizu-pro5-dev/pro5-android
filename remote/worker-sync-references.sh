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

# shellcheck source=builder-network.sh
source "$script_dir/builder-network.sh"
configure_builder_network

export GIT_TERMINAL_PROMPT=0

printf 'Reference sync started at %s\n' "$(date --iso-8601=seconds)"
printf '# name\turl\tbranch\tcommit\tcommit_date\tsubject\n' > "$lock_file"

while IFS=$'\t' read -r name url branch; do
  [[ -z "$name" || "$name" == \#* ]] && continue

  if [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
    printf 'Invalid reference name: %s\n' "$name" >&2
    exit 1
  fi

  github_slug="${url#https://github.com/}"
  github_slug="${github_slug%.git}"
  if [[ ! "$github_slug" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
    printf 'Unsupported reference URL: %s\n' "$url" >&2
    exit 1
  fi

  revision="$(
    git -c http.version=HTTP/1.1 ls-remote \
      "$url" "refs/heads/$branch" | cut -f1
  )"
  if [[ ! "$revision" =~ ^[0-9a-f]{40}$ ]]; then
    printf 'Unable to resolve %s branch %s\n' "$name" "$branch" >&2
    exit 1
  fi

  checkout="$reference_root/$name"
  if [[ -d "$checkout/.git" ]]; then
    if [[ -n "$(git -C "$checkout" status --porcelain)" ]]; then
      printf 'Refusing to update modified reference checkout: %s\n' "$checkout" >&2
      exit 1
    fi

    if [[ "$(git -C "$checkout" rev-parse HEAD)" != "$revision" ]]; then
      git -C "$checkout" -c http.version=HTTP/1.1 \
        fetch --prune origin "$branch"
      git -C "$checkout" checkout "$branch"
      git -C "$checkout" merge --ff-only "origin/$branch"
    fi

    commit_record="$(
      git -C "$checkout" show -s --format='%H%x09%cI%x09%s' HEAD
    )"
  elif [[ -f "$checkout/.reference-revision" ]] && \
      grep -qx "$revision" "$checkout/.reference-revision"; then
    printf 'Snapshot is current: %s\n' "$name"
    commit_record="$revision"$'\t-'$'\t-'
  else
    staging_root="$reference_root/.${name}.download"
    archive="$staging_root/source.tar.gz"
    staging_tree="$staging_root/tree"
    mkdir -p "$staging_root"

    curl \
      -fsSL \
      --connect-timeout 30 \
      --retry 10 \
      --retry-delay 2 \
      --retry-all-errors \
      "https://codeload.github.com/$github_slug/tar.gz/$revision" \
      -o "$archive"

    rm -rf -- "$staging_tree"
    mkdir -p "$staging_tree"
    tar -xzf "$archive" --strip-components=1 -C "$staging_tree"
    printf '%s\n' "$revision" > "$staging_tree/.reference-revision"

    if [[ -e "$checkout" ]]; then
      rm -rf -- "$checkout"
    fi
    mv "$staging_tree" "$checkout"
    rm -f -- "$archive"
    rmdir -- "$staging_root"

    printf 'Installed snapshot: %s @ %s\n' "$name" "$revision"
    commit_record="$revision"$'\t-'$'\t-'
  fi

  printf '%s\t%s\t%s\t%s\n' \
    "$name" "$url" "$branch" "$commit_record" >> "$lock_file"
done < "$source_list"

printf 'Reference sync completed at %s\n' "$(date --iso-8601=seconds)"
du -sh "$reference_root"
