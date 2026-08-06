#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

"$script_dir/push-local.sh"

"${pro5_ssh[@]}" bash -s -- "$PRO5_REMOTE_ROOT" <<'REMOTE'
set -euo pipefail

remote_root="$1"
local_root="$remote_root/local"
source_root="$remote_root/src/lineage-17.1"

if [[ ! -f "$source_root/.repo/manifest.xml" ]]; then
  printf 'LineageOS checkout is not initialized: %s\n' "$source_root" >&2
  exit 1
fi

for relative_path in \
  device/meizu/m86 \
  kernel/meizu/m86 \
  vendor/meizu/m86; do
  local_tree="$local_root/$relative_path"
  build_tree="$source_root/$relative_path"

  if [[ ! -d "$local_tree" ]] || \
      [[ -z "$(find "$local_tree" -type f -print -quit)" ]]; then
    printf 'Skipping empty local tree: %s\n' "$relative_path"
    continue
  fi

  mkdir -p "$build_tree"
  rsync -a --delete-delay "$local_tree/" "$build_tree/"
  printf 'Installed: %s\n' "$relative_path"
done
REMOTE
