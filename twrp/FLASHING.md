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

The next authorized candidate must be the all-old-content gzip load-envelope
control with SHA-256
`22a42a33516da36dcbc9ec3a1807716123430e2f5a256f25b5d5f16b2dee469d`
and size 32,571,392 bytes. Its declared ramdisk is 15,051,754 bytes, exactly
matching the pending gzip userspace diagnostic, while its old kernel and total
image are larger. Flash only this control to `recovery`, retain the stock DTB,
and do not perform any write test inside recovery.

Only after that control boots may the proven-source-kernel / new-userspace /
legacy-init gzip diagnostic with SHA-256
`0dad8b1710cd8eef39f6b3d632f71bc8cd5f3c857ed16055fbbf4b3224254ed3`
be tested. Do not use the pending userspace image to replace the required
control step.

After recovery starts, verify display, touch, ADB, partition discovery, and
rollback access before testing any write operation. If it stalls at the logo,
return to fastboot and restore the known-working recovery; do not change DTB.
