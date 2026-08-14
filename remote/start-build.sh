#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

target="${1:-${PRO5_BUILD_TARGET:-bootimage}}"
jobs="${PRO5_BUILD_JOBS:-8}"
product="${PRO5_BUILD_PRODUCT:-lineage_m86}"
force_boot_dexpreopt="${PRO5_FORCE_BOOT_DEXPREOPT:-0}"

case "$target" in
  kernel | graphics | wifi | bluetooth | nfc | bootimage | recoveryimage | systemimage | testzip | bacon) ;;
  *)
    printf 'Unsupported build target: %s\n' "$target" >&2
    exit 2
    ;;
esac

case "$product" in
  lineage_m86 | lineage_m86_nfc_experiment | lineage_m86_fingerprint_experiment) ;;
  *)
    printf 'Unsupported build product: %s\n' "$product" >&2
    exit 2
    ;;
esac

case "$force_boot_dexpreopt" in
  0 | 1) ;;
  *)
    printf 'PRO5_FORCE_BOOT_DEXPREOPT must be 0 or 1: %s\n' \
      "$force_boot_dexpreopt" >&2
    exit 2
    ;;
esac

if [[ "$target" == nfc && "$product" != lineage_m86_nfc_experiment ]]; then
  printf 'The nfc target is available only for lineage_m86_nfc_experiment.\n' >&2
  exit 2
fi
if [[ "$target" == bacon && "$product" != lineage_m86 ]]; then
  printf 'A release bacon build is available only for the default product.\n' >&2
  exit 2
fi
if [[ "$force_boot_dexpreopt" == 1 ]] && \
    [[ "$product" != lineage_m86_nfc_experiment || "$target" != testzip ]]; then
  printf 'Forced boot dexpreopt is available only for an NFC experiment testzip.\n' >&2
  exit 2
fi

if [[ ! "$jobs" =~ ^[1-9][0-9]*$ ]] || ((jobs > 64)); then
  printf 'Invalid PRO5_BUILD_JOBS: %s\n' "$jobs" >&2
  exit 2
fi

"$project_root/tools/validate-lineage-tree.sh"

local_revision="$(git -C "$project_root" rev-parse HEAD)"
device_revision="$(git -C "$project_root/device/meizu/m86" rev-parse HEAD)"
kernel_revision="$(git -C "$project_root/kernel/meizu/m86" rev-parse HEAD)"
vendor_revision="$(git -C "$project_root/vendor/meizu/m86" rev-parse HEAD)"
dirty_repositories=()
repositories=(
  "$project_root"
  "$project_root/device/meizu/m86"
  "$project_root/kernel/meizu/m86"
  "$project_root/vendor/meizu/m86"
)
revision_names=(local_revision device_revision kernel_revision vendor_revision)
for index in "${!repositories[@]}"; do
  repository="${repositories[$index]}"
  if [[ -n "$(git -C "$repository" status --porcelain --untracked-files=normal)" ]]; then
    dirty_repositories+=("$repository")
    printf -v "${revision_names[$index]}" '%s-dirty' \
      "${!revision_names[$index]}"
  fi
done
if [[ "${#dirty_repositories[@]}" -ne 0 ]]; then
  if [[ "${PRO5_ALLOW_DIRTY_SOURCE:-0}" != 1 ]]; then
    printf 'Refusing build from dirty local source inputs:\n' >&2
    printf '  %s\n' "${dirty_repositories[@]}" >&2
    printf 'Set PRO5_ALLOW_DIRTY_SOURCE=1 only for a non-release development build.\n' >&2
    exit 1
  fi
  if [[ "$target" == bacon ]]; then
    printf 'Refusing a release bacon build from dirty source inputs.\n' >&2
    exit 1
  fi
fi

local_input_hash="$(
  bash "$project_root/tools/hash-authoritative-inputs.sh" "$project_root"
)"

"$script_dir/push-local.sh"
"$script_dir/push-stock-dtb.sh"

"${pro5_ssh[@]}" bash -s -- \
  "$PRO5_REMOTE_ROOT" "$local_input_hash" <<'REMOTE'
set -euo pipefail

remote_root="$1"
expected_input_hash="$2"
"$remote_root/local/remote/assert-builder-dev-null.sh"
launcher="$remote_root/local/remote/detached-worker.sh"
for session_name in pro5-source-sync pro5-platform-sync; do
  if [[ -x "$launcher" ]] && \
      "$launcher" running "$session_name" >/dev/null 2>&1; then
    printf 'Required sync is still running: %s\n' "$session_name" >&2
    exit 1
  fi
done

if [[ ! -s "$remote_root/logs/lineage-17.1-pro5-manifest.xml" ]]; then
  printf 'Platform sync has not completed successfully.\n' >&2
  exit 1
fi

actual_input_hash="$(
  bash "$remote_root/local/tools/hash-authoritative-inputs.sh" \
    "$remote_root/local"
)"
if [[ "$actual_input_hash" != "$expected_input_hash" ]]; then
  printf 'Builder authoritative input snapshot mismatch.\n' >&2
  exit 1
fi
REMOTE

PRO5_SKIP_LOCAL_PUSH=1 "$script_dir/apply-patches.sh"
PRO5_SKIP_LOCAL_PUSH=1 "$script_dir/install-local-trees.sh"

final_local_input_hash="$(
  bash "$project_root/tools/hash-authoritative-inputs.sh" "$project_root"
)"
if [[ "$final_local_input_hash" != "$local_input_hash" ]]; then
  printf 'Local authoritative inputs changed after the sealed push.\n' >&2
  exit 1
fi
"${pro5_ssh[@]}" bash -s -- \
  "$PRO5_REMOTE_ROOT" "$local_input_hash" <<'REMOTE'
set -euo pipefail
remote_root="$1"
expected_input_hash="$2"
actual_input_hash="$(
  bash "$remote_root/local/tools/hash-authoritative-inputs.sh" \
    "$remote_root/local"
)"
[[ "$actual_input_hash" == "$expected_input_hash" ]] || {
  printf 'Builder inputs changed after patch/install preparation.\n' >&2
  exit 1
}
REMOTE

"${pro5_ssh[@]}" bash -s -- \
  "$PRO5_REMOTE_ROOT" "$target" "$jobs" "$local_revision" \
  "$device_revision" "$kernel_revision" "$vendor_revision" \
  "$local_input_hash" "$product" "$force_boot_dexpreopt" <<'REMOTE'
set -euo pipefail

remote_root="$1"
target="$2"
jobs="$3"
local_revision="$4"
device_revision="$5"
kernel_revision="$6"
vendor_revision="$7"
local_input_hash="$8"
product="$9"
force_boot_dexpreopt="${10}"
"$remote_root/local/remote/assert-builder-dev-null.sh"
session_name="pro5-build"
worker="$remote_root/local/remote/worker-build.sh"
launcher="$remote_root/local/remote/detached-worker.sh"
run_root="$remote_root/run"
build_stamp="$(date +%Y%m%d-%H%M%S)"
status_file="$run_root/build-latest.status"
log_file="$run_root/build-$build_stamp-$product-$target.log"

if [[ -x "$launcher" ]] && \
    "$launcher" running "$session_name" >/dev/null 2>&1; then
  printf 'Detached worker %s is already running.\n' "$session_name"
  exit 0
fi

mkdir -p "$run_root"
rm -f -- "$status_file"
: > "$log_file"
ln -sfn "$(basename "$log_file")" "$run_root/build-latest.log"
chmod 0755 "$worker" "$launcher"
"$launcher" start "$session_name" \
  "$worker" "$target" "$jobs" "$status_file" "$log_file" "$build_stamp" \
  "$local_revision" "$device_revision" "$kernel_revision" "$vendor_revision" \
  "$local_input_hash" "$product" "$force_boot_dexpreopt"
printf 'Started detached worker %s: product=%s target=%s jobs=%s forced_boot_dexpreopt=%s\n' \
  "$session_name" "$product" "$target" "$jobs" "$force_boot_dexpreopt"
REMOTE

"$script_dir/build-status.sh"
