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
if [[ -x "${kernel_toolchains[0]}/bin/aarch64-linux-android-gcc" ]] && \
    [[ -x "${kernel_toolchains[1]}/bin/arm-linux-androideabi-gcc" ]]; then
  printf 'Kernel toolchains are already checked out\n'
else
  printf 'Syncing kernel toolchains first\n'
  repo sync \
    "${repo_sync_args[@]}" \
    --no-interleaved \
    --jobs-network=2 \
    --jobs-checkout=2 \
    -j2 \
    "${kernel_toolchains[@]}"
fi

# repo 2.65's multiprocessing workers deadlock on this builder when processing
# the complete manifest, including in no-interleaved mode. A serial full sync
# is slower but resumes existing objects and has no worker-pool failure mode.
printf 'Syncing the full LineageOS checkout serially\n'
repo sync \
  "${repo_sync_args[@]}" \
  -j1

repo manifest -r -o "$manifest_lock"
printf 'Source sync completed at %s\n' "$(date --iso-8601=seconds)"
du -sh "$source_root" "$remote_root/ccache"
df -h "$remote_root"
