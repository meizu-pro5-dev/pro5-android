#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
workspace_root="$(cd "$project_root/.." && pwd)"
artifact_store="$workspace_root/artifacts"
# shellcheck source=common.sh
source "$script_dir/common.sh"

remote_artifact_dir="$(
  "${pro5_ssh[@]}" readlink -f "$PRO5_REMOTE_ROOT/artifacts/lineage-latest"
)"
remote_artifact_name="${remote_artifact_dir##*/}"
if [[ ! "$remote_artifact_name" =~ ^[0-9]{8}-[0-9]{6}-bacon$ ]]; then
  printf 'No validated full LineageOS artifact is available: %s\n' \
    "$remote_artifact_dir" >&2
  exit 1
fi

local_artifact_dir="$artifact_store/pro5-lineage-$remote_artifact_name"
if [[ -e "$local_artifact_dir" ]]; then
  printf 'Refusing to overwrite immutable local evidence: %s\n' \
    "$local_artifact_dir" >&2
  exit 1
fi
partial_artifact_dir="${local_artifact_dir}.partial"
if [[ -L "$partial_artifact_dir" ]]; then
  printf 'Refusing an unexpected partial-artifact symlink: %s\n' \
    "$partial_artifact_dir" >&2
  exit 1
fi

mkdir -p "$artifact_store" "$partial_artifact_dir"
rsync -az --partial \
  -e "$pro5_rsync_ssh" \
  "$PRO5_BUILDER_HOST:$remote_artifact_dir/" \
  "$partial_artifact_dir/"

(
  cd "$partial_artifact_dir"
  sha256sum --quiet -c SHA256SUMS
  grep -F -x -q 'target=lineage_m86-userdebug bacon' BUILD-METADATA

  for required_artifact in \
    boot.img \
    recovery.img \
    system.img \
    dtb.img \
    CAMERA-ABI.txt \
    FINGERPRINT-OUTPUT.txt \
    EXFAT-KERNEL.txt \
    lineage-17.1-m86-lock.xml; do
    if [[ ! -s "$required_artifact" ]]; then
      printf 'Downloaded LineageOS evidence is incomplete: %s\n' \
        "$required_artifact" >&2
      exit 1
    fi
  done

  shopt -s nullglob
  ota_packages=(lineage-17.1-*.zip)
  target_files_packages=(*-target_files-*.zip)
  shopt -u nullglob
  if [[ "${#ota_packages[@]}" -ne 1 ]]; then
    printf 'Expected one downloaded LineageOS OTA ZIP, found %s.\n' \
      "${#ota_packages[@]}" >&2
    exit 1
  fi
  if [[ "${#target_files_packages[@]}" -ne 1 ]]; then
    printf 'Expected one downloaded target-files ZIP, found %s.\n' \
      "${#target_files_packages[@]}" >&2
    exit 1
  fi
  unzip -tq "${ota_packages[0]}" >/dev/null
  unzip -tq "${target_files_packages[0]}" >/dev/null
)

mv "$partial_artifact_dir" "$local_artifact_dir"
printf 'Retained validated LineageOS artifacts: %s\n' "$local_artifact_dir"
