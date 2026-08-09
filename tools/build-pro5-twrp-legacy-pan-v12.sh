#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PRO5_TWRP_LEGACY_PAN_V12=1 \
  exec "$script_dir/build-pro5-twrp-single-buffer-v5.sh" "$@"
