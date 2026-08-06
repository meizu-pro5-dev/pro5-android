# Samsung exFAT driver provenance

The released Meizu m86 defconfig named this driver, but the corresponding
source and Kconfig entry were absent from the published tree. The 25 build
files in this directory were imported from the Exynos 7420 kernel maintained
at:

- repository: `https://github.com/Exynos7420/android_kernel_samsung_universal7420`
- locked tree: `218eaf61af9e4ef2fe9f6debc1e6af9746de8b10`
- source-introduction commit: `0637e90f17aea8aca4356b63b786328a3ca1224a`
- donor package noted by that commit: `A810FXXU2CRL1`

That donor is Linux 3.10 on the same Exynos 7420 platform. Its Kconfig provides
the three functional exFAT symbols retained here. The archived defconfig also
selected `CONFIG_EXFAT_SUPPORT_STLOG`, but that donor-only diagnostic depends
on `PROC_STLOG`, which m86 does not implement, so generated configurations
always discarded it and the stale selection was removed. The source files
carry Samsung's GPL-2.0 notices. The only maintained code delta is an
`rcu_barrier()` before destroying the inode slab, matching the same Linux RCU
teardown fix already present in m86's FAT driver. The per-file maintained
source lock is `locks/kernel-exfat-exynos7420.sha256`; this provenance note is
intentionally outside that 25-file count.

Static acceptance requires the lock, generated `CONFIG_EXFAT_FS=y`, and both
linked exFAT objects. Runtime acceptance still requires read/write, large-file,
Unicode-name, clean-unmount, and repair-cycle tests on disposable exFAT media.
