#!/usr/bin/env bash

# Copyright (C) 2015 The CyanogenMod Project
# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

device="m86"
vendor="meizu"
initial_copyright_year="2015"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lineage_root="$(cd "$script_dir/../../.." && pwd)"
helper="$lineage_root/vendor/lineage/build/tools/extract_utils.sh"

if [[ ! -f "$helper" ]]; then
  printf 'Unable to find extract helper: %s\n' "$helper" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$helper"

DEVICE="$device"
VENDOR="$vendor"
INITIAL_COPYRIGHT_YEAR="$initial_copyright_year"

# LineageOS 17.1's helper reads its nominally optional arguments even when the
# caller enables nounset. Supplying all six retains the default non-common,
# clean vendor/m86 layout while keeping this script in strict mode.
set +u
setup_vendor \
  "$DEVICE" \
  "$VENDOR" \
  "$lineage_root" \
  false \
  true \
  "$DEVICE"
write_headers
write_makefiles "$script_dir/proprietary-files.txt" true
write_footers
set -u
