# m86 Bluetooth wrapper

This directory is the sole owner of the PRO 5 Bluetooth HIDL service and its
32-bit passthrough implementation. It compiles the unmodified LineageOS 17.1
HCI binder endpoint and owns only the two device-specific boundaries:

- a deterministic locally administered address derived from the validated
  private-slot identity published by `m86_usb_serial`;
- Flyme Broadcom vendor-interface SCO configuration after firmware download.

The service starts from the identity-ready input in this domain's init file.
No Samsung-common source or patch is part of the active Bluetooth owner.

Dynamic controller nodes use the m86 `ueventd` rules. Only rfkill `state` is
labeled writable; rfkill `type` keeps the platform's read-only sysfs label.
The main init file therefore performs no Bluetooth chmod/chown and needs no
device allow for `init` to mutate Bluetooth sysfs metadata.
