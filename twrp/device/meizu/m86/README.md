# Meizu PRO 5 TWRP device tree

This is the source-built recovery tree for the `m86` acceptance target. It is
intended for the maintained local m86 kernel and the official minimal TWRP
`twrp-9.0` manifest, whose recovery component reports TWRP `3.7.0_9`.

The partition names, FDE key location, boot-image geometry, display path, and
removable-storage sysfs paths come from the verified Flyme 8.0.5.0A base and
the previously booting PRO 5 recovery evidence. No old SuperSU payload, TWRP
app, prebuilt recovery kernel, or userland hardware blob is included.

The source intentionally does not expose `/dev/block/sdb`, `ldfw`, `param`,
`proinfo`, `private`, or `rstinfo`. These targets are unnecessary for normal
recovery operation and an accidental write can destroy the bootloader,
firmware, calibration, or unique device data.
