# m86 Bluetooth wrapper

This directory is the sole owner of the PRO 5 Bluetooth HIDL service and its
32-bit passthrough implementation. It compiles the unmodified LineageOS 17.1
HCI binder endpoint and owns only the two device-specific boundaries:

- a deterministic locally administered address derived from the validated
  private-slot identity published by `m86_usb_serial`;
- Flyme Broadcom vendor-interface SCO configuration after firmware download.

The installed `libbt-vendor.so` is the Flyme prebuilt copied by
`vendor/meizu/m86/m86-vendor.mk`; `BOARD_HAVE_BLUETOOTH_BCM` is empty, so
`hardware/broadcom/libbt` is not the active implementation. In this prebuilt,
`hw_sco_config` sends I2SPCM (`0xfc6d`) and immediately calls `scocfg_cb` with
success. Its command completion callback instead reports controller status
through `audio_state_cb` (also used for allocation/transmit failures).

The wrapper keeps initialization ownership through firmware, SCO, and LPM
completion. It advances only after the vendor callback returns and its internal
command has completed, preserving failures across an early success callback.
Initialization is published once; subsequent audio callbacks cannot restart it.
Pending vendor commands cannot be overwritten, and unsuccessful H4/MCT writes
are rejected with buffer ownership retained by the vendor. No sleep or GD HCI
assertion change is needed.

The service starts from the identity-ready input in this domain's init file.
No Samsung-common source or patch is part of the active Bluetooth owner.

Dynamic controller nodes use the m86 `ueventd` rules. Only rfkill `state` is
labeled writable; rfkill `type` keeps the platform's read-only sysfs label.
The main init file therefore performs no Bluetooth chmod/chown and needs no
device allow for `init` to mutate Bluetooth sysfs metadata.
