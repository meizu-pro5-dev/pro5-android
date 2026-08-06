#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

mkdir -p "$project_root/locks"

for remote_name in \
  lineage-17.1-manifest.xml \
  lineage-17.1-pro5-manifest.xml \
  reference-revisions.tsv; do
  if "${pro5_ssh[@]}" test -f "$PRO5_REMOTE_ROOT/logs/$remote_name"; then
    rsync -az \
      -e "$pro5_rsync_ssh" \
      "$PRO5_BUILDER_HOST:$PRO5_REMOTE_ROOT/logs/$remote_name" \
      "$project_root/locks/$remote_name"
  else
    printf 'Not available yet: %s\n' "$remote_name"
  fi
done
