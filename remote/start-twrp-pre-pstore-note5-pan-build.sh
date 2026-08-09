#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

jobs="${PRO5_TWRP_BUILD_JOBS:-8}"
if [[ ! "$jobs" =~ ^[1-9][0-9]*$ ]] || ((jobs > 64)); then
  printf 'Invalid PRO5_TWRP_BUILD_JOBS: %s\n' "$jobs" >&2
  exit 2
fi

"$project_root/tools/validate-twrp-tree.sh"

local_revision="$(git -C "$project_root" rev-parse HEAD)-pre-pstore-note5-pan"
if [[ -n "$(git -C "$project_root" \
    status --porcelain --untracked-files=normal)" ]]; then
  local_revision="${local_revision}-dirty"
fi

# Install the normal maintained trees first. Only the four files introduced by
# the later pstore/ramoops commit are then restored from the exact revision
# that produced the v11-proven kernel. The current DECON PAN source is retained.
"$script_dir/push-stock-blobs.sh"
"$script_dir/apply-twrp-patches.sh"
"$script_dir/install-twrp-trees.sh"

overlay_root="$(mktemp -d)"
cleanup() {
  if [[ -z "${overlay_root:-}" || ! -d "$overlay_root" ]]; then
    return
  fi
  case "$overlay_root" in
    /tmp/*|/private/tmp/*|/var/folders/*/T/*|/private/var/folders/*/T/*)
      rm -r -- "$overlay_root"
      ;;
    *)
      printf 'Refusing to clear unexpected overlay directory: %s\n' \
        "$overlay_root" >&2
      ;;
  esac
}
trap cleanup EXIT

baseline_revision=52bb509cf2ba6a8a21107080bfdedb5219ead70d
baseline_files=(
  kernel/meizu/m86/arch/arm64/configs/cm_pro5_defconfig
  kernel/meizu/m86/drivers/of/of_reserved_mem.c
  kernel/meizu/m86/drivers/platform/exynos/exynos_ramoops.c
  kernel/meizu/m86/include/linux/of_reserved_mem.h
)
git -C "$project_root" archive "$baseline_revision" \
  "${baseline_files[@]}" | tar -x -C "$overlay_root"

for relative_file in "${baseline_files[@]}"; do
  rsync -a -e "$pro5_rsync_ssh" \
    "$overlay_root/$relative_file" \
    "$PRO5_BUILDER_HOST:$PRO5_REMOTE_ROOT/src/twrp-9.0/$relative_file"
done

"${pro5_ssh[@]}" bash -s -- \
  "$PRO5_REMOTE_ROOT" "$jobs" "$local_revision" <<'REMOTE'
set -euo pipefail

remote_root="$1"
jobs="$2"
local_revision="$3"
session_name="pro5-twrp-build"
worker="$remote_root/local/remote/worker-build-twrp.sh"
run_root="$remote_root/run"
build_stamp="$(date +%Y%m%d-%H%M%S)"
status_file="$run_root/twrp-build-latest.status"
log_file="$run_root/twrp-build-$build_stamp.log"
kernel_root="$remote_root/src/twrp-9.0/kernel/meizu/m86"

for locked_source in \
  '11683809ee51d42d6a3c7a9e0e9ff6e2bfd9fd12b4f2b58b19cc31d562b057ae arch/arm64/configs/cm_pro5_defconfig' \
  'ff6b08939a17c25cd26a3e9fee919a2a52acc75a916fd7b3a1b86f4b75dd9b95 drivers/of/of_reserved_mem.c' \
  'bfcf91cc6a8f2c2bc1c9e8fb8f0bed74566a801e5b5b1728f9c997af6a725fe5 drivers/platform/exynos/exynos_ramoops.c' \
  '6174ccaf5ac2d8dfb8711a7dcf057dd53ca90478006ee8b88a3ace1c0d6d0349 include/linux/of_reserved_mem.h'; do
  expected_sha256="${locked_source%% *}"
  relative_source="${locked_source#* }"
  actual_sha256="$(
    sha256sum "$kernel_root/$relative_source" | awk '{ print $1 }'
  )"
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    printf 'Remote pre-pstore source mismatch: %s\n' "$relative_source" >&2
    exit 1
  fi
done
if ! grep -F -q 'Keep PAN as a lightweight command-mode refresh.' \
    "$kernel_root/drivers/video/exynos/decon/decon-int_drv.c"; then
  printf 'Remote kernel lost the Note5 PAN change.\n' >&2
  exit 1
fi

for conflicting_session in \
  pro5-source-sync \
  pro5-platform-sync \
  pro5-twrp-source-sync; do
  if tmux has-session -t "$conflicting_session" 2>/dev/null; then
    printf 'Required sync is still running: %s\n' "$conflicting_session" >&2
    exit 1
  fi
done
if tmux has-session -t "$session_name" 2>/dev/null; then
  printf 'tmux session %s is already running\n' "$session_name"
  exit 0
fi

mkdir -p "$run_root"
rm -f -- "$status_file"
: > "$log_file"
ln -sfn "$(basename "$log_file")" "$run_root/twrp-build-latest.log"
chmod 0755 "$worker"

printf -v worker_command '%q %q %q %q %q %q %q' \
  "$worker" "$jobs" "$status_file" "$log_file" "$build_stamp" \
  "$local_revision" pre-pstore-note5-pan
tmux new-session -d -s "$session_name" "$worker_command"
printf 'Started tmux session %s: profile=pre-pstore-note5-pan jobs=%s\n' \
  "$session_name" "$jobs"
REMOTE

trap - EXIT
cleanup
"$script_dir/twrp-build-status.sh"
