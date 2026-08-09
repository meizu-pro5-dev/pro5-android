#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PRO5_TWRP_PRECOPY_VSYNC_V11=1 \
  exec "$script_dir/build-pro5-twrp-single-buffer-v5.sh" "$@"
