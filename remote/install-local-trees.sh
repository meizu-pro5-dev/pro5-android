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

overlay_root="$local_root/overlays/kernel-meizu-m86-case-sensitive"
overlay_hashes="$overlay_root/SHA256SUMS"
if [[ -f "$overlay_hashes" ]]; then
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
fi
REMOTE
