#!/usr/bin/env bash

set -euo pipefail

workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="${1:-}"
source_tree="$workspace_root/hardware/meizu/m86"
target_tree="$source_root/hardware/meizu/m86"

if [[ -z "$source_root" || ! -d "$source_root/.repo" ]]; then
  printf 'Usage: %s /path/to/lineage-19.1\n' "$0" >&2
  exit 2
fi

mkdir -p "$target_tree"
rsync -a --delete \
  --exclude='.git/' \
  --exclude='camera/libexynoscamera_stock/libexynoscamera.so' \
  "$source_tree/" "$target_tree/"
printf 'Installed public m86 hardware sources into %s\n' "$target_tree"
