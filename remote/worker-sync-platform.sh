#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
local_root="$(cd "$script_dir/.." && pwd)"
remote_root="$(cd "$local_root/.." && pwd)"
source_root="$remote_root/src/lineage-17.1"
log_dir="$remote_root/logs"
local_manifest="$local_root/manifests/pro5.xml"

mkdir -p "$log_dir"
exec > >(tee -a "$log_dir/platform-sync.log") 2>&1

# shellcheck source=builder-network.sh
source "$script_dir/builder-network.sh"
configure_builder_network

export GIT_TERMINAL_PROMPT=0

if [[ ! -f "$source_root/.repo/manifest.xml" ]]; then
  printf 'LineageOS checkout is not initialized: %s\n' "$source_root" >&2
  exit 1
fi

if [[ ! -f "$log_dir/lineage-17.1-manifest.xml" ]]; then
  printf 'Base source sync has not completed successfully.\n' >&2
  exit 1
fi

install -D -m 0644 \
  "$local_manifest" \
  "$source_root/.repo/local_manifests/pro5.xml"

printf 'Platform sync started at %s\n' "$(date --iso-8601=seconds)"
cd "$source_root"
repo sync \
  -c \
  --no-clone-bundle \
  --no-tags \
  --optimized-fetch \
  --prune \
  --retry-fetches=10 \
  -j8 \
  build/soong \
  device/samsung/universal7420-common \
  hardware/samsung \
  hardware/samsung_slsi/exynos \
  hardware/samsung_slsi/exynos5 \
  hardware/samsung_slsi/exynos7420 \
  hardware/samsung_slsi/openmax \
  kernel/samsung/universal7420

repo manifest -r -o "$log_dir/lineage-17.1-pro5-manifest.xml"
printf 'Platform sync completed at %s\n' "$(date --iso-8601=seconds)"
du -sh \
  device/samsung/universal7420-common \
  hardware/samsung \
  hardware/samsung_slsi \
  kernel/samsung/universal7420
