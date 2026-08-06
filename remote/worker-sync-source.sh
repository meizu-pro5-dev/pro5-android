#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
local_root="$(cd "$script_dir/.." && pwd)"
remote_root="$(cd "$local_root/.." && pwd)"
source_root="$remote_root/src/lineage-17.1"
log_dir="$remote_root/logs"
manifest_lock="$log_dir/lineage-17.1-manifest.xml"
sync_jobs="${1:-4}"

if [[ ! "$sync_jobs" =~ ^[1-9][0-9]*$ ]] || ((sync_jobs > 16)); then
  printf 'Invalid source sync job count: %s\n' "$sync_jobs" >&2
  exit 2
fi

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

repo_sync_args=(
  -c
  --no-clone-bundle
  --no-tags
  --optimized-fetch
  --prune
  --no-auto-gc
  --retry-fetches=10
)

# Fetch and check out the two legacy GCC trees first. This makes the
# standalone Image + DTB gate available while the rest of Android continues
# syncing, and is harmless on a resumed checkout.
kernel_toolchains=(
  prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9
  prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9
)
printf 'Syncing kernel toolchains first\n'
repo sync \
  "${repo_sync_args[@]}" \
  --no-interleaved \
  --jobs-network=2 \
  --jobs-checkout=2 \
  -j2 \
  "${kernel_toolchains[@]}"

# Separating fetch and checkout avoids the repo interleaved-worker deadlock
# observed on this builder while retaining bounded parallel downloads.
printf 'Syncing the full LineageOS checkout with %s jobs\n' "$sync_jobs"
repo sync \
  "${repo_sync_args[@]}" \
  --no-interleaved \
  --jobs-network="$sync_jobs" \
  --jobs-checkout="$sync_jobs" \
  -j"$sync_jobs"

repo manifest -r -o "$manifest_lock"
printf 'Source sync completed at %s\n' "$(date --iso-8601=seconds)"
du -sh "$source_root" "$remote_root/ccache"
df -h "$remote_root"
