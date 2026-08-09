#!/sbin/sh

# Test-only ready-first ADB and live display evidence wrapper for PRO 5 v15.
# Evidence is kept outside /cache/recovery because Flyme rotates that directory.
umask 022
exec >>/tmp/pro5-recovery-wrapper.log 2>&1

diag_cache_device=/dev/block/platform/15570000.ufs/by-name/cache
diag_cache_dir=/cache/pro5-twrp-diag-v15
diag_cache_ready=0
diag_wait_count=0

cache_has_mount_option() {
  /sbin/busybox awk -v option_name="$1" '
    $2 == "/cache" {
      option_count = split($4, mount_options, ",")
      for (option_index = 1; option_index <= option_count; option_index++) {
        if (mount_options[option_index] == option_name) {
          option_found = 1
        }
      }
    }
    END { exit(option_found ? 0 : 1) }
  ' /proc/mounts
}

cache_is_read_write_and_synchronous() {
  cache_has_mount_option rw && cache_has_mount_option sync
}

hold_diagnostic_environment() {
  echo "pro5_twrp_wrapper=holding"
  /sbin/busybox sync
  while true; do
    /sbin/busybox sleep 60
  done
}

echo "pro5_twrp_wrapper=start"
/sbin/busybox date

while [ ! -b "$diag_cache_device" ] && [ "$diag_wait_count" -lt 30 ]; do
  /sbin/busybox sleep 1
  diag_wait_count=$((diag_wait_count + 1))
done

if /sbin/busybox grep -q ' /cache ' /proc/mounts; then
  if /sbin/busybox mount -o remount,rw,sync /cache &&
      cache_is_read_write_and_synchronous; then
    diag_cache_ready=1
  fi
elif /sbin/busybox mount -t ext4 -o rw,sync,noatime,nosuid,nodev \
    "$diag_cache_device" /cache && cache_is_read_write_and_synchronous; then
  diag_cache_ready=1
fi

if [ "$diag_cache_ready" -ne 1 ]; then
  echo "pro5_twrp_wrapper=cache_sync_mount_failed"
  /sbin/busybox grep ' /cache ' /proc/mounts || true
  hold_diagnostic_environment
fi

if ! /sbin/busybox mkdir -p "$diag_cache_dir"; then
  echo "pro5_twrp_wrapper=cache_directory_failed"
  hold_diagnostic_environment
fi

diag_attempt_tag="$(/sbin/busybox date +%Y%m%d-%H%M%S 2>/dev/null)"
case "$diag_attempt_tag" in
  ''|*[!0-9-]*) diag_attempt_tag=unknown ;;
esac
diag_attempt_index=1
while [ "$diag_attempt_index" -le 99 ]; do
  diag_stem="$diag_cache_dir/session-$diag_attempt_tag-$diag_attempt_index"
  if [ ! -e "$diag_stem-recovery.log" ] && \
      [ ! -e "$diag_stem-wrapper.log" ]; then
    break
  fi
  diag_attempt_index=$((diag_attempt_index + 1))
done
if [ "$diag_attempt_index" -gt 99 ]; then
  echo "pro5_twrp_wrapper=unique_log_name_exhausted"
  hold_diagnostic_environment
fi

diag_recovery_log="$diag_stem-recovery.log"
diag_wrapper_log="$diag_stem-wrapper.log"
diag_usb_log="$diag_stem-usb.txt"
diag_runtime_log="$diag_stem-runtime.txt"
diag_dmesg_start_log="$diag_stem-dmesg-start.txt"
diag_dmesg_live_log="$diag_stem-dmesg-live.txt"
diag_dmesg_next_log="$diag_stem-dmesg-live.next"
diag_dmesg_exit_log="$diag_stem-dmesg-exit.txt"

if ! : >"$diag_recovery_log" || ! : >"$diag_usb_log" ||
    ! : >"$diag_runtime_log"; then
  echo "pro5_twrp_wrapper=cache_write_failed"
  hold_diagnostic_environment
fi
{
  echo "artifact_role=pro5 TWRP legacy framebuffer and live diagnostic v15"
  echo "wrapper_start=$(/sbin/busybox date)"
  echo "cache_device=$diag_cache_device"
  echo "diagnostic_stem=$diag_stem"
  /sbin/busybox grep ' /cache ' /proc/mounts || true
} >"$diag_recovery_log"
if ! /sbin/busybox cp /tmp/pro5-recovery-wrapper.log "$diag_wrapper_log"; then
  echo "wrapper_error=wrapper_log_copy_failed" >>"$diag_recovery_log"
  hold_diagnostic_environment
fi
/sbin/busybox chmod 0644 "$diag_recovery_log" "$diag_wrapper_log" \
  "$diag_usb_log" "$diag_runtime_log"
exec >>"$diag_wrapper_log" 2>&1

record_durable_stage() {
  diag_stage="$1"
  echo "wrapper_stage=$diag_stage" >>"$diag_recovery_log"
  echo "pro5_twrp_wrapper=$diag_stage"
  /sbin/busybox sync
}

record_usb_snapshot() {
  usb_stage="$1"
  {
    echo "snapshot=$usb_stage"
    echo "time=$(/sbin/busybox date)"
    for usb_attr in enable state functions idVendor idProduct \
        iManufacturer iProduct iSerial; do
      usb_path="/sys/class/android_usb/android0/$usb_attr"
      if [ -r "$usb_path" ]; then
        echo "$usb_attr=$(/sbin/busybox cat "$usb_path" 2>&1)"
      else
        echo "$usb_attr=unreadable"
      fi
    done
    /sbin/busybox ls -l /dev/android_adb /dev/android_adb_enable 2>&1
    /sbin/busybox ps 2>&1 | /sbin/busybox grep '[a]dbd' || true
    echo
  } >>"$diag_usb_log"
  /sbin/busybox sync
}

record_runtime_snapshot() {
  runtime_stage="$1"
  {
    echo "snapshot=$runtime_stage"
    echo "time=$(/sbin/busybox date)"
    echo "uptime=$(/sbin/busybox cat /proc/uptime 2>&1)"
    for runtime_path in \
        /sys/class/backlight/pwm-backlight.0/brightness \
        /sys/class/backlight/pwm-backlight.0/actual_brightness \
        /sys/class/graphics/fb0/blank \
        /sys/class/graphics/fb0/mode \
        /sys/class/graphics/fb0/modes \
        /sys/class/graphics/fb0/virtual_size \
        /sys/class/graphics/fb0/bits_per_pixel; do
      if [ -r "$runtime_path" ]; then
        echo "$runtime_path=$(/sbin/busybox tr '\n' ',' <"$runtime_path")"
      else
        echo "$runtime_path=unreadable"
      fi
    done
    echo "processes:"
    /sbin/busybox ps 2>&1 | /sbin/busybox grep -E \
      '[r]ecovery|[a]dbd|[h]ealthd|[p]ermissive' || true
    echo "display_interrupts:"
    /sbin/busybox grep -Ei 'decon|dsim|mipi|fimd|fb' /proc/interrupts || true
    echo
  } >>"$diag_runtime_log"
  /sbin/busybox sync
}

record_durable_stage cache_sync_ready
/sbin/busybox rm -f /tmp/recovery.log
if ! /sbin/busybox ln -s "$diag_recovery_log" /tmp/recovery.log; then
  echo "wrapper_error=recovery_log_symlink_failed" >>"$diag_recovery_log"
  hold_diagnostic_environment
fi
record_durable_stage recovery_log_linked

record_usb_snapshot before_adb_ready_wait
adb_ready_wait=0
while [ "$adb_ready_wait" -lt 10 ]; do
  if /sbin/dmesg | /sbin/busybox grep -q 'adb_open'; then
    break
  fi
  /sbin/busybox sleep 1
  adb_ready_wait=$((adb_ready_wait + 1))
done
echo "adb_open_wait_seconds=$adb_ready_wait" >>"$diag_usb_log"

echo 0 >/sys/class/android_usb/android0/enable
echo 18D1 >/sys/class/android_usb/android0/idVendor
echo 4EE7 >/sys/class/android_usb/android0/idProduct
echo Meizu >/sys/class/android_usb/android0/iManufacturer
echo PRO5_TWRP_V15 >/sys/class/android_usb/android0/iProduct
echo PRO5TWRPV15 >/sys/class/android_usb/android0/iSerial
echo 0 >/sys/class/android_usb/android0/bDeviceClass
echo 0 >/sys/class/android_usb/android0/bDeviceSubClass
echo 0 >/sys/class/android_usb/android0/bDeviceProtocol
echo adb >/sys/class/android_usb/android0/functions
echo 1 >/sys/class/android_usb/android0/enable
setprop sys.usb.state adb
echo pro5_twrp_v15_gadget_enabled_after_adb_open >/dev/kmsg
/sbin/busybox sleep 2
record_usb_snapshot after_first_enable

if [ "$(/sbin/busybox cat /sys/class/android_usb/android0/state 2>/dev/null)" = \
    "DISCONNECTED" ]; then
  echo 0 >/sys/class/android_usb/android0/enable
  /sbin/busybox sleep 1
  echo adb >/sys/class/android_usb/android0/functions
  echo 1 >/sys/class/android_usb/android0/enable
  echo pro5_twrp_v15_gadget_retry >/dev/kmsg
  /sbin/busybox sleep 2
fi
record_usb_snapshot after_optional_retry

/sbin/dmesg >"$diag_dmesg_start_log"
/sbin/busybox chmod 0644 "$diag_dmesg_start_log"
record_runtime_snapshot before_recovery
record_durable_stage evidence_ready

periodic_evidence() {
  evidence_index=1
  while true; do
    record_usb_snapshot "periodic_$evidence_index"
    record_runtime_snapshot "periodic_$evidence_index"
    /sbin/dmesg >"$diag_dmesg_next_log"
    /sbin/busybox sync
    /sbin/busybox mv -f "$diag_dmesg_next_log" "$diag_dmesg_live_log"
    /sbin/busybox chmod 0644 "$diag_dmesg_live_log"
    /sbin/busybox sync
    evidence_index=$((evidence_index + 1))
    /sbin/busybox sleep 5
  done
}

periodic_evidence &
diag_evidence_pid=$!
record_durable_stage launching_recovery

/sbin/recovery
diag_recovery_status=$?
kill "$diag_evidence_pid" 2>/dev/null || true
wait "$diag_evidence_pid" 2>/dev/null || true
echo "pro5_twrp_wrapper=recovery_exit status=$diag_recovery_status"
{
  echo "wrapper_recovery_exit=$diag_recovery_status"
  echo "wrapper_recovery_exit_time=$(/sbin/busybox date)"
} >>"$diag_recovery_log"
/sbin/dmesg >"$diag_dmesg_exit_log"
/sbin/busybox chmod 0644 "$diag_recovery_log" "$diag_wrapper_log" \
  "$diag_usb_log" "$diag_runtime_log" "$diag_dmesg_start_log" \
  "$diag_dmesg_exit_log"
record_runtime_snapshot recovery_exit
record_durable_stage recovery_exit_saved

hold_diagnostic_environment
