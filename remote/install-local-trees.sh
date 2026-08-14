#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

if [[ "${PRO5_SKIP_LOCAL_PUSH:-0}" != 1 ]]; then
  "$script_dir/push-local.sh"
fi

"${pro5_ssh[@]}" bash -s -- "$PRO5_REMOTE_ROOT" <<'REMOTE'
set -euo pipefail

remote_root="$1"
local_root="$remote_root/local"
source_root="$remote_root/src/lineage-17.1"

if [[ ! -f "$source_root/.repo/manifest.xml" ]]; then
  printf 'LineageOS checkout is not initialized: %s\n' "$source_root" >&2
  exit 1
fi

tree_fingerprint() {
  local tree_root="$1"
  local exclude_proprietary="$2"

  (
    cd "$tree_root"
    if [[ "$exclude_proprietary" == true ]]; then
      find . \
        \( -type d \( -name .git -o -path './proprietary' \) -prune \) -o \
        \( -type f -o -type l \) -print0
    else
      find . -type d -name .git -prune -o \
        \( -type f -o -type l \) -print0
    fi |
      LC_ALL=C sort -z |
      while IFS= read -r -d '' input; do
        if [[ -L "$input" ]]; then
          printf 'link\t%s\t%s\n' "$input" "$(readlink "$input")"
        else
          printf 'file\t%s\t' "$input"
          sha256sum "$input" | awk '{ print $1 }'
        fi
      done
  ) | sha256sum | awk '{ print $1 }'
}

fingerprint_tree() {
  local tree_root="$1"
  local exclude_proprietary="$2"
  local heartbeat_pid
  local fingerprint

  # The kernel tree has tens of thousands of files. Keep the SSH stream active
  # while hashing it so an idle gateway cannot abort an otherwise valid,
  # fail-closed tree comparison.
  (
    while :; do
      sleep 10
      printf 'Fingerprinting: %s\n' "$tree_root" >&2
    done
  ) &
  heartbeat_pid=$!

  if ! fingerprint="$(tree_fingerprint "$tree_root" "$exclude_proprietary")"; then
    kill "$heartbeat_pid" 2>/dev/null || true
    wait "$heartbeat_pid" 2>/dev/null || true
    return 1
  fi
  kill "$heartbeat_pid" 2>/dev/null || true
  wait "$heartbeat_pid" 2>/dev/null || true
  printf '%s\n' "$fingerprint"
}

for relative_path in \
  device/meizu/m86 \
  hardware/meizu/m86 \
  kernel/meizu/m86 \
  vendor/meizu/m86; do
  local_tree="$local_root/$relative_path"
  build_tree="$source_root/$relative_path"

  if [[ ! -d "$local_tree" ]] || \
      [[ -z "$(find "$local_tree" -type f -print -quit)" ]]; then
    printf 'Required authoritative local tree is missing or empty: %s\n' \
      "$relative_path" >&2
    exit 1
  fi

  mkdir -p "$build_tree"
  # The build checkout may contain the 24 case-sensitive kernel overlay
  # files from a previous invocation.  They are reinstalled explicitly below
  # after the authoritative tree is fingerprinted.  Use immediate deletion
  # here so stale overlay files cannot survive into the fingerprint check.
  rsync_args=(-a --delete)
  if [[ "$relative_path" == vendor/meizu/m86 ]]; then
    # Proprietary bytes are staged separately from the verified stock dump.
    # They are intentionally absent from the local Git tree and must survive
    # repeated installation of the generated vendor definitions.
    rsync_args+=(--exclude proprietary/)
  fi
  rsync "${rsync_args[@]}" "$local_tree/" "$build_tree/"
  exclude_proprietary=false
  if [[ "$relative_path" == vendor/meizu/m86 ]]; then
    exclude_proprietary=true
  fi
  local_fingerprint="$(fingerprint_tree \
    "$local_tree" "$exclude_proprietary")"
  installed_fingerprint="$(fingerprint_tree \
    "$build_tree" "$exclude_proprietary")"
  if [[ "$local_fingerprint" != "$installed_fingerprint" ]]; then
    printf 'Installed tree fingerprint mismatch: %s\n' "$relative_path" >&2
    exit 1
  fi
  printf 'Installed: %s\n' "$relative_path"
done

# The only production DTB owner is the hash-locked Flyme input. Proprietary
# bytes stay outside Git and are staged into the generated source checkout.
stock_dtb="$remote_root/stock/flyme-8.0.5.0A/dtb"
stock_lock="$local_root/locks/stock-flyme-8.0.5.0A.sha256"
installed_dtb="$source_root/device/meizu/m86/prebuilt/dtb.img"
expected_dtb_hash="$(awk '$2 == "dtb" { print $1 }' "$stock_lock")"
if [[ ! "$expected_dtb_hash" =~ ^[0-9a-f]{64}$ ]] || [[ ! -s "$stock_dtb" ]]; then
  printf 'Verified stock DTB is not staged on the builder.\n' >&2
  exit 1
fi
actual_dtb_hash="$(sha256sum "$stock_dtb" | awk '{ print $1 }')"
if [[ "$actual_dtb_hash" != "$expected_dtb_hash" ]]; then
  printf 'Builder stock DTB hash mismatch: %s\n' "$actual_dtb_hash" >&2
  exit 1
fi
install -D -m 0644 "$stock_dtb" "$installed_dtb"
printf 'Installed: locked stock DTB (%s)\n' "$actual_dtb_hash"

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
