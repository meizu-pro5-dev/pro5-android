#!/usr/bin/env bash

# Copyright (C) 2015 The CyanogenMod Project
# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

device="m86"
vendor="meizu"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lineage_root="$(cd "$script_dir/../../.." && pwd)"
helper="$lineage_root/vendor/lineage/build/tools/extract_utils.sh"

if [[ ! -f "$helper" ]]; then
  printf 'Unable to find extract helper: %s\n' "$helper" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$helper"

clean_vendor=true
section=""
source_path="adb"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n | --no-cleanup)
      clean_vendor=false
      ;;
    -s | --section)
      if [[ $# -lt 2 ]]; then
        printf '%s requires a section name\n' "$1" >&2
        exit 2
      fi
      section="$2"
      clean_vendor=false
      shift
      ;;
    *)
      source_path="$1"
      ;;
  esac
  shift
done

setup_vendor "$device" "$vendor" "$lineage_root" false "$clean_vendor"
extract "$script_dir/proprietary-files.txt" "$source_path" "$section"
"$script_dir/setup-makefiles.sh"
