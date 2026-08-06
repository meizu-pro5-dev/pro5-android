#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
local_root="$(cd "$script_dir/.." && pwd)"
remote_root="$(cd "$local_root/.." && pwd)"
source_root="$remote_root/src/lineage-17.1"
log_dir="$remote_root/logs"
manifest_lock="$log_dir/lineage-17.1-manifest.xml"

mkdir -p "$source_root" "$log_dir"
exec > >(tee -a "$log_dir/source-sync.log") 2>&1

# shellcheck source=builder-network.sh
source "$script_dir/builder-network.sh"
configure_builder_network

export CCACHE_DIR="$remote_root/ccache"
export USE_CCACHE=1
export GIT_TERMINAL_PROMPT=0

printf 'Source sync started at %s\n' "$(date --iso-8601=seconds)"
printf 'Checkout: %s\n' "$source_root"

cd "$source_root"
if [[ ! -f .repo/manifest.xml ]]; then
  repo init \
    -u https://github.com/LineageOS/android.git \
    -b lineage-17.1 \
    --repo-url=https://github.com/GerritCodeReview/git-repo.git \
    --repo-rev=stable \
    --no-clone-bundle \
    --partial-clone \
    --clone-filter=blob:limit=10M
fi

repo sync \
  -c \
  --no-clone-bundle \
  --no-tags \
  --optimized-fetch \
  --prune \
  --retry-fetches=3 \
  -j8

repo manifest -r -o "$manifest_lock"
printf 'Source sync completed at %s\n' "$(date --iso-8601=seconds)"
du -sh "$source_root" "$remote_root/ccache"
df -h "$remote_root"
