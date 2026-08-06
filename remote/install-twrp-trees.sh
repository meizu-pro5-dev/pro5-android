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
source_root="$remote_root/src/twrp-9.0"

if [[ ! -f "$source_root/.repo/manifest.xml" ]]; then
  printf 'TWRP checkout is not initialized: %s\n' "$source_root" >&2
  exit 1
fi

for source_and_target in \
  twrp/device/meizu/m86:device/meizu/m86 \
  kernel/meizu/m86:kernel/meizu/m86; do
  local_relative="${source_and_target%%:*}"
  target_relative="${source_and_target#*:}"
  local_tree="$local_root/$local_relative"
  build_tree="$source_root/$target_relative"

  if [[ ! -d "$local_tree" ]] || \
      [[ -z "$(find "$local_tree" -type f -print -quit)" ]]; then
    printf 'Missing local TWRP tree: %s\n' "$local_relative" >&2
    exit 1
  fi

  mkdir -p "$build_tree"
  rsync -a --delete-delay "$local_tree/" "$build_tree/"
  printf 'Installed TWRP tree: %s\n' "$target_relative"
done

overlay_root="$local_root/overlays/kernel-meizu-m86-case-sensitive"
overlay_hashes="$overlay_root/SHA256SUMS"
if [[ ! -f "$overlay_hashes" ]]; then
  printf 'Missing case-sensitive kernel overlay hashes.\n' >&2
  exit 1
fi

overlay_count="$(
  find "$overlay_root/upper" "$overlay_root/lower" -type f -print |
    wc -l |
    tr -d ' '
)"
if [[ "$overlay_count" != "24" ]]; then
  printf 'Expected 24 case-sensitive kernel files, found %s\n' \
    "$overlay_count" >&2
  exit 1
fi

(
  cd "$overlay_root"
  sha256sum --quiet -c SHA256SUMS
)

for variant in upper lower; do
  while IFS= read -r -d '' overlay_file; do
    relative_path="${overlay_file#"$overlay_root/$variant/"}"
    target_file="$source_root/kernel/meizu/m86/$relative_path"
    install -D -m 0644 "$overlay_file" "$target_file"
  done < <(find "$overlay_root/$variant" -type f -print0)
done
printf 'Installed: 24 case-sensitive m86 kernel files\n'
REMOTE
