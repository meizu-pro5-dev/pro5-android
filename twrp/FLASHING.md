# PRO 5 TWRP flashing boundary

`recovery.img` is a raw Android boot image for the UFS `recovery` partition.
`exynos7420-m86-codegen.dtb` is the matching raw device tree for the separate
UFS `dtb` partition. Neither file is authorized for flashing merely because
the build completed.

Before the first device test, retain verified rollback copies of the current
`recovery` and `dtb` partitions, check both artifact SHA-256 values, and obtain
explicit approval for the exact fastboot commands. Never write the recovery
artifact to `bootimg`, `/dev/block/sdb`, `ldfw`, or any parameter/identity
partition.

The first test should prefer a non-persistent recovery boot if the PRO 5
bootloader proves it supports one. If a persistent test is required, flash
only the reviewed `recovery` and matching `dtb` artifacts and immediately
verify display, touch, ADB, partition discovery, and rollback access before
testing any write operation.
