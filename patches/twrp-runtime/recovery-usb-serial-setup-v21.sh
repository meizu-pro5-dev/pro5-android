#!/sbin/sh

# Flyme obtains the handset serial from slot 0 of the signed Meizu "private"
# partition.  The slot is 1024 bytes: RSA signature [0,256), little-endian
# payload length [256,258), then the serial payload.  Read only that slot and
# accept a narrowly validated serial; never embed another handset's value.
serial_value=
serial_wait=0

while [ "$serial_wait" -lt 5 ]; do
  for private_path in \
    /dev/block/platform/15570000.ufs/by-name/private \
    /dev/block/by-name/private \
    /dev/block/sda1; do
    if [ -r "$private_path" ]; then
      serial_length="$(/sbin/busybox hexdump -s 256 -n 2 -e '1/2 "%u"' \
        "$private_path" 2>/dev/null)"
      case "$serial_length" in
        ''|*[!0-9]*) serial_length=0 ;;
      esac
      if [ "$serial_length" -ge 4 ] && [ "$serial_length" -le 64 ]; then
        serial_value="$(/sbin/busybox hexdump -s 258 -n "$serial_length" \
          -e '1/1 "%c"' "$private_path" 2>/dev/null)"
      fi
      case "$serial_value" in
        ''|*[!A-Za-z0-9]*) serial_value= ;;
      esac
      [ -n "$serial_value" ] && break
    fi
  done
  [ -n "$serial_value" ] && break

  # Secondary fallback: this identifies the UFS device, not Flyme's phone SN,
  # but remains unique to the physical handset when private cannot be read.
  for serial_path in \
    /sys/bus/platform/devices/15570000.ufs/unique_number \
    /sys/devices/platform/15570000.ufs/unique_number \
    /sys/devices/15570000.ufs/unique_number; do
    if [ -r "$serial_path" ]; then
      serial_value="$(/sbin/busybox cat "$serial_path" 2>/dev/null)"
      break
    fi
  done
  [ -n "$serial_value" ] && break
  /sbin/busybox sleep 1
  serial_wait=$((serial_wait + 1))
done

case "$serial_value" in
  ''|*[!A-Za-z0-9]*) serial_value=PRO5-RECOVERY ;;
esac

echo "pro5_recovery_usb_serial=$serial_value" >/dev/kmsg
/sbin/toolbox setprop recovery.usb.serial "$serial_value"
