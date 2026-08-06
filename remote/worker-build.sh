#!/usr/bin/env bash

set -eo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
local_root="$(cd "$script_dir/.." && pwd)"
remote_root="$(cd "$local_root/.." && pwd)"
source_root="$remote_root/src/lineage-17.1"
out_root="$remote_root/out/lineage-17.1"
run_root="$remote_root/run"
artifact_root="$remote_root/artifacts"

target="${1:-bootimage}"
jobs="${2:-24}"
status_file="${3:-$run_root/build-latest.status}"
log_file="${4:-$run_root/build-latest.log}"
build_stamp="${5:-$(date +%Y%m%d-%H%M%S)}"

case "$target" in
  kernel | bootimage | recoveryimage | bacon) ;;
  *)
    printf 'Unsupported build target: %s\n' "$target" >&2
    exit 2
    ;;
esac

if [[ ! "$jobs" =~ ^[1-9][0-9]*$ ]] || ((jobs > 64)); then
  printf 'Invalid build job count: %s\n' "$jobs" >&2
  exit 2
fi

mkdir -p "$run_root" "$artifact_root" "$(dirname "$log_file")"
exec > >(tee -a "$log_file") 2>&1

write_status() {
  local exit_code="$1"
  local status_tmp="${status_file}.tmp"

  {
    printf 'target=%s\n' "$target"
    printf 'exit_code=%d\n' "$exit_code"
    printf 'finished_at=%s\n' "$(date --iso-8601=seconds)"
  } > "$status_tmp"
  mv "$status_tmp" "$status_file"

  trap - EXIT
  exit "$exit_code"
}
trap 'write_status $?' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
trap 'exit 129' HUP

# shellcheck source=builder-network.sh
source "$script_dir/builder-network.sh"
configure_builder_network

if [[ ! -f "$source_root/build/envsetup.sh" ]]; then
  printf 'LineageOS source is incomplete: %s\n' "$source_root" >&2
  exit 1
fi

if [[ ! -f "$source_root/kernel/meizu/m86/arch/arm64/configs/cm_pro5_defconfig" ]]; then
  printf 'The maintained m86 kernel tree is not installed.\n' >&2
  exit 1
fi

export USE_CCACHE=1
export CCACHE_DIR="$remote_root/ccache"
export CCACHE_BASEDIR="$source_root"
export CCACHE_EXEC="$(command -v ccache)"
export OUT_DIR="$out_root"

ccache --max-size=25G
ccache --zero-stats

printf 'Build started at %s\n' "$(date --iso-8601=seconds)"
printf 'Source: %s\nTarget: %s\nJobs: %s\nOutput: %s\n' \
  "$source_root" "$target" "$jobs" "$out_root"

cd "$source_root"
# Android's envsetup and shell functions are not nounset-safe.
# shellcheck disable=SC1091
source build/envsetup.sh
lunch lineage_m86-userdebug
mka "$target" -j"$jobs"

product_out="$out_root/target/product/m86"
artifact_dir="$artifact_root/$build_stamp-$target"
mkdir -p "$artifact_dir"

find "$product_out" -maxdepth 1 -type f \
  \( -name 'lineage-17.1*.zip' -o -name 'boot.img' \
     -o -name 'recovery.img' -o -name 'system.img' \
     -o -name 'target_files*.zip' \) \
  -exec cp -a {} "$artifact_dir/" \;

if [[ -n "$(find "$artifact_dir" -maxdepth 1 -type f -print -quit)" ]]; then
  sha256sum "$artifact_dir"/* > "$artifact_dir/SHA256SUMS"
fi
repo manifest -r -o "$artifact_dir/lineage-17.1-m86-lock.xml"

ccache --show-stats
printf 'Build completed at %s\n' "$(date --iso-8601=seconds)"
printf 'Artifacts: %s\n' "$artifact_dir"
