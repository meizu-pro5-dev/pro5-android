#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PRO5_TWRP_DIRECT_ADB_V10=1 \
  "$script_dir/build-pro5-twrp-legacy-adb-v9.sh" "$@"
