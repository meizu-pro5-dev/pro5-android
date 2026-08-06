#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
workspace_root="$(cd "$project_root/.." && pwd)"
artifact_store="$workspace_root/artifacts"
# shellcheck source=common.sh
source "$script_dir/common.sh"

remote_artifact_dir="$(
  "${pro5_ssh[@]}" readlink -f "$PRO5_REMOTE_ROOT/artifacts/twrp-latest"
)"
remote_artifact_name="${remote_artifact_dir##*/}"
if [[ ! "$remote_artifact_name" =~ ^twrp-[0-9]{8}-[0-9]{6}-recoveryimage$ ]]; then
  printf 'No validated TWRP artifact is available: %s\n' \
    "$remote_artifact_dir" >&2
  exit 1
fi

local_artifact_dir="$artifact_store/$remote_artifact_name"
if [[ -e "$local_artifact_dir" ]]; then
  printf 'Refusing to overwrite immutable local evidence: %s\n' \
    "$local_artifact_dir" >&2
  exit 1
fi

mkdir -p "$artifact_store"
rsync -az \
  -e "$pro5_rsync_ssh" \
  "$PRO5_BUILDER_HOST:$remote_artifact_dir/" \
  "$local_artifact_dir/"

(
  cd "$local_artifact_dir"
  sha256sum --quiet -c SHA256SUMS
)
printf 'Retained validated TWRP artifacts: %s\n' "$local_artifact_dir"
