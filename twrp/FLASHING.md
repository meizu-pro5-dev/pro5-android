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

The current isolation test combines the exact kernel and boot-header contract
from the known-working recovery with the new TWRP ramdisk. It must be tested
with the stock Flyme 8 DTB already present: flash only its reviewed
`recovery.img`, never a DTB from the rejected source build. This diagnostic is
not a final, fully source-built TWRP release.

After recovery starts, verify display, touch, ADB, partition discovery, and
rollback access before testing any write operation. If it stalls at the logo,
return to fastboot and restore the known-working recovery; do not change DTB.
