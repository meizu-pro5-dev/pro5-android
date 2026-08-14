#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf '%s\n' \
    "Usage: ${0##*/} [--serial SERIAL] [--cycles COUNT] [--restart-hal] [--suspend] [--allow-permissive] [--output DIRECTORY]" \
    '' \
    'Runs reader/HCE NFC regression checks on a flashed userdebug NFC experiment.' \
    'It never flashes a device. Tag read/write and HCE are recorded as manual checks.'
}

serial=""
cycles=20
restart_hal=0
suspend_cycles=0
allow_permissive=0
output_dir=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --serial)
      serial="${2:?--serial requires a value}"
      shift 2
      ;;
    --cycles)
      cycles="${2:?--cycles requires a value}"
      shift 2
      ;;
    --restart-hal)
      restart_hal=1
      shift
      ;;
    --suspend)
      suspend_cycles=1
      shift
      ;;
    --allow-permissive)
      allow_permissive=1
      shift
      ;;
    --output)
      output_dir="${2:?--output requires a directory}"
      shift 2
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! "$cycles" =~ ^[1-9][0-9]*$ ]] || ((cycles > 100)); then
  printf 'Invalid cycle count: %s\n' "$cycles" >&2
  exit 2
fi

command -v adb >/dev/null 2>&1 || {
  printf 'adb is required for NFC runtime testing.\n' >&2
  exit 1
}
command -v rg >/dev/null 2>&1 || {
  printf 'rg is required for NFC runtime log triage.\n' >&2
  exit 1
}

if [[ -z "$output_dir" ]]; then
  project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  output_dir="$project_root/evidence/nfc-runtime-$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$output_dir"

adb_args=()
if [[ -n "$serial" ]]; then
  adb_args=(-s "$serial")
fi

run_adb() {
  adb "${adb_args[@]}" "$@"
}

fail() {
  printf 'NFC runtime test failed: %s\n' "$*" >&2
  exit 1
}

require_nfc_on() {
  local phase="$1"
  local dump

  dump="$(run_adb shell dumpsys nfc)"
  printf '%s\n' "$dump" > "$output_dir/dumpsys-$phase.txt"
  if ! grep -F -q 'mState=on' <<<"$dump"; then
    fail "NFC is not on after $phase"
  fi
}

run_adb wait-for-device
run_adb root >/dev/null || fail 'the flashed NFC experiment must permit adb root'
run_adb wait-for-device
run_adb logcat -b all -c

run_adb shell \
  'getprop; getenforce; lshal; service list; dumpsys nfc; cat /proc/interrupts; ls -lZ /dev/pn544 /dev/p61 /data/nfc /data/vendor/nfc 2>&1' \
  > "$output_dir/baseline.txt"

if ! rg -q 'android\.hardware\.nfc@1\.1::INfc/default' \
    "$output_dir/baseline.txt"; then
  fail 'NFC 1.1 HIDL service is unavailable at baseline'
fi
if ! rg -q 'vendor\.nxp\.nxpnfc@1\.0::INxpNfc/default' \
    "$output_dir/baseline.txt"; then
  fail 'NXP NFC extension HIDL service is unavailable at baseline'
fi
if ! rg -q '^Enforcing$' "$output_dir/baseline.txt"; then
  if ((allow_permissive)); then
    printf '%s\n' \
      'SELinux is Permissive: this is a temporary bring-up result, not release evidence.' \
      > "$output_dir/TEST-LIMITATIONS.txt"
  else
    fail 'NFC runtime validation requires SELinux enforcing (use --allow-permissive only for temporary bring-up)'
  fi
fi
require_nfc_on baseline

for cycle in $(seq 1 "$cycles"); do
  run_adb shell svc nfc disable
  sleep 3
  run_adb shell svc nfc enable
  sleep 8
  require_nfc_on "toggle-$cycle"
done

if ((restart_hal)); then
  for cycle in $(seq 1 "$cycles"); do
    run_adb shell setprop ctl.restart vendor.nfc_hal_service
    sleep 10
    require_nfc_on "hal-restart-$cycle"
  done
fi

if ((suspend_cycles)); then
  for cycle in $(seq 1 "$cycles"); do
    run_adb shell input keyevent KEYCODE_SLEEP
    sleep 10
    run_adb shell input keyevent KEYCODE_WAKEUP
    sleep 10
    require_nfc_on "suspend-$cycle"
  done
fi

run_adb shell \
  'getenforce; lshal; service list; dumpsys nfc; cat /proc/interrupts; dmesg; ls -lZ /dev/pn544 /dev/p61 /data/nfc /data/vendor/nfc 2>&1' \
  > "$output_dir/final-state.txt"
run_adb logcat -b all -v threadtime -d > "$output_dir/logcat.txt"

# dumpsys nfc prints an NFCSNOOP section named "NATIVE CRASH LOG" even during a
# healthy idle interval. Only treat concrete watchdog/JNI/process failures as
# fatal, alongside the kernel transport failures.
fatal_pattern='Unbalanced IRQ|irq_set_irq_wake|NfcService: Watchdog triggered|JNI FatalError called: applyRouting|nfcManager_doAbort|Fatal signal.*(NfcNci|com\.android\.nfc)|i2c_master_(send|recv) returned -6|FATAL EXCEPTION.*Nfc'
if rg -n -i "$fatal_pattern" \
    "$output_dir/logcat.txt" "$output_dir/final-state.txt" \
    > "$output_dir/fatal-findings.txt"; then
  cat "$output_dir/fatal-findings.txt" >&2
  fail 'kernel/HAL/native NFC failure signature found'
fi

if rg -n -i 'avc: +denied.*(hal_nfc_default|nfc)' \
    "$output_dir/logcat.txt" "$output_dir/final-state.txt" \
    > "$output_dir/nfc-avc-findings.txt"; then
  cat "$output_dir/nfc-avc-findings.txt" >&2
  fail 'NFC SELinux denial found while enforcing'
fi

printf '%s\n' \
  'Manual acceptance still required:' \
  '- Read a known NDEF tag after the final toggle; record payload and timestamp.' \
  '- Write a known NDEF payload, re-read it, and record the matching payload.' \
  '- Exercise HCE with a second device or terminal and record APDU request/response.' \
  '- Perform one deep-suspend run without USB keeping the device awake; record its limitation.' \
  > "$output_dir/MANUAL-TESTS.txt"

(
  cd "$output_dir"
  find . -maxdepth 1 -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum
) > "$output_dir/SHA256SUMS"

printf 'NFC runtime scripted regression passed: %s\n' "$output_dir"
