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

disable_decon_lpd="${PRO5_TWRP_DISABLE_DECON_LPD:-0}"
if [[ "$disable_decon_lpd" != "0" && "$disable_decon_lpd" != "1" ]]; then
  printf 'Invalid PRO5_TWRP_DISABLE_DECON_LPD: %s\n' \
    "$disable_decon_lpd" >&2
  exit 2
fi

"$project_root/tools/validate-twrp-tree.sh"

usb_patch="$project_root/patches/twrp-kernel-m86/0001-usb-force-gadget-vbus-on-enable.patch"
if [[ ! -s "$usb_patch" ]]; then
  printf 'Missing USB gadget diagnostic patch: %s\n' "$usb_patch" >&2
  exit 1
fi
lpd_patch="$project_root/patches/twrp-kernel-m86/0002-display-disable-decon-lpd.patch"
if [[ "$disable_decon_lpd" == "1" && ! -s "$lpd_patch" ]]; then
  printf 'Missing DECON LPD diagnostic patch: %s\n' "$lpd_patch" >&2
  exit 1
fi

kernel_profile=pre-pstore-usb-vbus
expected_defconfig_sha256=11683809ee51d42d6a3c7a9e0e9ff6e2bfd9fd12b4f2b58b19cc31d562b057ae
if [[ "$disable_decon_lpd" == "1" ]]; then
  kernel_profile=pre-pstore-usb-vbus-no-lpd
  expected_defconfig_sha256=3ed5fa4bc2303541df9b26de1dfd96737562b604c967d8615d66e27f5677d996
fi

local_revision="$(git -C "$project_root" rev-parse HEAD)-$kernel_profile"
if [[ -n "$(git -C "$project_root" \
    status --porcelain --untracked-files=normal)" ]]; then
  local_revision="${local_revision}-dirty"
fi

# Start from the exact revision that produced the v11 kernel. Always apply the
# android_usb DWC3-session patch.  The opt-in no-LPD profile additionally
# changes only the DECON LPD defconfig bit; all source code and other kernel
# settings remain identical to that device-tested baseline.
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
  kernel/meizu/m86/drivers/video/exynos/decon/decon-int_drv.c
  kernel/meizu/m86/drivers/usb/gadget/android.c
)
git -C "$project_root" archive "$baseline_revision" \
  "${baseline_files[@]}" | tar -x -C "$overlay_root"
git -C "$overlay_root/kernel/meizu/m86" apply --check "$usb_patch"
git -C "$overlay_root/kernel/meizu/m86" apply "$usb_patch"
if [[ "$disable_decon_lpd" == "1" ]]; then
  git -C "$overlay_root/kernel/meizu/m86" apply --check "$lpd_patch"
  git -C "$overlay_root/kernel/meizu/m86" apply "$lpd_patch"
fi

for relative_file in "${baseline_files[@]}"; do
  rsync -a -e "$pro5_rsync_ssh" \
    "$overlay_root/$relative_file" \
    "$PRO5_BUILDER_HOST:$PRO5_REMOTE_ROOT/src/twrp-9.0/$relative_file"
done

"${pro5_ssh[@]}" bash -s -- \
  "$PRO5_REMOTE_ROOT" "$jobs" "$local_revision" "$kernel_profile" \
  "$expected_defconfig_sha256" <<'REMOTE'
set -euo pipefail

remote_root="$1"
jobs="$2"
local_revision="$3"
kernel_profile="$4"
expected_defconfig_sha256="$5"
session_name="pro5-twrp-build"
worker="$remote_root/local/remote/worker-build-twrp.sh"
run_root="$remote_root/run"
build_stamp="$(date +%Y%m%d-%H%M%S)"
status_file="$run_root/twrp-build-latest.status"
log_file="$run_root/twrp-build-$build_stamp.log"
kernel_root="$remote_root/src/twrp-9.0/kernel/meizu/m86"

for locked_source in \
  "$expected_defconfig_sha256 arch/arm64/configs/cm_pro5_defconfig" \
  'ff6b08939a17c25cd26a3e9fee919a2a52acc75a916fd7b3a1b86f4b75dd9b95 drivers/of/of_reserved_mem.c' \
  'bfcf91cc6a8f2c2bc1c9e8fb8f0bed74566a801e5b5b1728f9c997af6a725fe5 drivers/platform/exynos/exynos_ramoops.c' \
  '6174ccaf5ac2d8dfb8711a7dcf057dd53ca90478006ee8b88a3ace1c0d6d0349 include/linux/of_reserved_mem.h' \
  '455f1e7f71eafb4f4516c789a28fa3c90f3880a3a484c54d3a8dfd19f44112d0 drivers/video/exynos/decon/decon-int_drv.c' \
  'e0058fc84b4043aef966932507a190c655ef51b2f7c6e0d2c610dda64f1961ce drivers/usb/gadget/android.c'; do
  expected_sha256="${locked_source%% *}"
  relative_source="${locked_source#* }"
  actual_sha256="$(
    sha256sum "$kernel_root/$relative_source" | awk '{ print $1 }'
  )"
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    printf 'Remote USB diagnostic source mismatch: %s\n' \
      "$relative_source" >&2
    exit 1
  fi
done

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
  "$local_revision" "$kernel_profile"
tmux new-session -d -s "$session_name" "$worker_command"
printf 'Started tmux session %s: profile=%s jobs=%s\n' \
  "$session_name" "$kernel_profile" "$jobs"
REMOTE

trap - EXIT
cleanup
"$script_dir/twrp-build-status.sh"
