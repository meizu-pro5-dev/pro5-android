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

The current LZMA candidate is 27,287,552 bytes with recovery SHA-256
`a360a6f1a269c9c730f8f288f4783cf9d2054a742718292abed03f2e3823e5aa`.
It passed two byte-identical clean builds but has not yet passed a device boot.
Keep the stock Flyme 8 DTB for this test and do not flash the generated DTB.

After recovery starts, verify display, touch, ADB, partition discovery, and
rollback access before testing any write operation. If it stalls at the logo,
return to fastboot and restore the known-working recovery; do not change DTB.
