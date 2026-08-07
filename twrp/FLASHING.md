# PRO 5 TWRP flashing boundary

`recovery.img` is a raw Android boot image for the UFS `recovery` partition.
The PRO 5 stores its device tree in the separate UFS `dtb` partition; the
recovery image does not embed a DTB. Neither file is authorized for flashing
merely because a build or repack completed.

The 2026-08-07 source-built recovery and generated
`exynos7420-m86-codegen.dtb` are rejected for device use: recovery boot stalled
at the Meizu logo both with the Flyme 8 DTB and with the generated DTB. The
generated DTB must not be flashed again until the maintained kernel is made
compatible with the stock board contract and a new pair is reviewed.

Before the first device test, retain verified rollback copies of the current
`recovery` and `dtb` partitions, check both artifact SHA-256 values, and obtain
explicit approval for the exact fastboot commands. Never write the recovery
artifact to `bootimg`, `/dev/block/sdb`, `ldfw`, or any parameter/identity
partition.

The first isolation image combined the exact kernel and boot-header contract
from the known-working recovery with the complete new TWRP ramdisk. It also
stalled at the logo and is rejected. Before another experimental image, first
reconfirm that the unmodified known-working recovery still boots with the
stock Flyme 8 DTB. Never flash a DTB from the rejected source build.

Subsequent source builds package only English and Simplified Chinese resources
to create a meaningful margin below the partition and bootloader boundary.
They use a kernel-supported LZMA-Alone recovery ramdisk while retaining the
kernel's gzip decoder for normal Android boot; no recovery feature or Chinese
font coverage is removed for compression.
Each new image still requires static review and explicit test approval; it is
not accepted merely because it is smaller.

The rejected LZMA candidate is 27,287,552 bytes with recovery SHA-256
`a360a6f1a269c9c730f8f288f4783cf9d2054a742718292abed03f2e3823e5aa`.
It passed two byte-identical clean builds but stalled at the Meizu logo after
the old recovery baseline was reconfirmed, so it is rejected. Do not flash it
or its generated DTB again.

The corrected device candidate restored the original booting m86 tree's initial
framebuffer blank/unblank and enabled persistent kernel-console capture for
both the stock-DTB reserved-memory layout and generated-DTB ION layout. Its
`recovery.img` is 27,308,032 bytes with SHA-256
`8c20eaa5301a9c70ad363cd765d5ba4cf33be69a37fc3f6a88d9b8cca5b07ca9`.
It passed two byte-identical clean builds but stalled at the Meizu logo and
returned automatically to Flyme. No recovery ADB, current recovery log or
pstore console payload was recovered, so the candidate is rejected. Keep the
verified stock Flyme 8 DTB and do not flash the generated DTB packaged beside
it.

The all-old-content current-envelope control with SHA-256
`f86fe878513b9df07bdfd7c32f8064564377067622b355a7a5c889f260dcedca`
reached recovery. The owner also confirmed that the maintained-source-kernel /
old-userspace diagnostic booted. A later LZMA hybrid that restored the legacy
startup chain, SHA-256
`14c0056ca835cd1599b70e892071458c6693cbdfaa5071ef0efefcc169fd83bb`,
stalled and is rejected; do not flash it again.

The all-old-content gzip load-envelope control with SHA-256
`22a42a33516da36dcbc9ec3a1807716123430e2f5a256f25b5d5f16b2dee469d`
and size 32,571,392 bytes reached the recovery UI. The matching
proven-source-kernel / new-userspace / legacy-init gzip diagnostic with SHA-256
`0dad8b1710cd8eef39f6b3d632f71bc8cd5f3c857ed16055fbbf4b3224254ed3`
then failed. A minimal new-runtime image and its fstab-corrected successor also
failed with the same black-screen/vibration/automatic-Flyme sequence. The last
test recorded a normal software `reboot`, with no panic or watchdog reset.

The next test-only image is the ADB log-capture recovery with SHA-256
`a2d6c1fd75c33d51af047c2bd94fb344f27a6bd887048854efc79b56bf147375`
and size 29,335,552 bytes. After explicit approval, flash only this image to
`recovery` and retain the verified stock Flyme 8 DTB. It deliberately disables
MTP and ignores an ordinary system reboot so that the known-working static adbd
can expose `/tmp/recovery.log`. It is expected to remain at a black screen or
otherwise stay in its recovery init environment after TWRP exits.

Pull `/tmp/recovery.log`, dmesg and properties before leaving the diagnostic.
Use `adb reboot bootloader` as the normal exit; that exact route remains
enabled. If ADB never enumerates, use the physical long-press/bootloader route
and restore the known-working recovery. Do not perform mount, wipe, install or
other write tests, and do not change the DTB.
