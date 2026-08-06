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
  rsync_args=(-a --delete-delay)
  if [[ "$relative_path" == vendor/meizu/m86 ]]; then
    # Proprietary bytes are staged separately from the verified stock dump.
    # They are intentionally absent from the local Git tree and must survive
    # repeated installation of the generated vendor definitions.
    rsync_args+=(--exclude proprietary/)
  fi
  rsync "${rsync_args[@]}" "$local_tree/" "$build_tree/"
  printf 'Installed: %s\n' "$relative_path"
done

# The last m86 community tree is immutable local evidence. Copy only its
# FPC1020/libfprint implementation into the generated Android build tree, then
# apply the reviewed Android 10 fixes kept with the active device sources.
legacy_fprint="$local_root/legacy/device-meizu-m86-cm14/libfprint"
build_fprint="$source_root/device/meizu/m86/fingerprint/libfprint"
fprint_patch="$local_root/patches/legacy-m86-libfprint/0001-port-m86-fpc-to-android10.patch"

if [[ ! -f "$legacy_fprint/fpc1150.c" ]] || \
    [[ ! -f "$legacy_fprint/nbis/mindtct/detect.c" ]]; then
  printf 'Missing archived m86 libfprint source.\n' >&2
  exit 1
fi
if [[ ! -f "$fprint_patch" ]]; then
  printf 'Missing Android 10 m86 libfprint patch.\n' >&2
  exit 1
fi

mkdir -p "$build_fprint"
rsync -a --delete \
  --exclude Android.mk \
  --exclude '*_' \
  --exclude '*__' \
  "$legacy_fprint/" "$build_fprint/"

if [[ "$(find "$build_fprint" -type f | wc -l | tr -d ' ')" != "42" ]]; then
  printf 'Expected 42 archived m86 libfprint build files.\n' >&2
  exit 1
fi
git -C "$build_fprint" apply --check "$fprint_patch"
git -C "$build_fprint" apply "$fprint_patch"
printf 'Installed: patched m86 FPC1020/libfprint source\n'

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
