# m86 kernel provenance

This maintained tree was imported as an exact source snapshot from:

- repository: `https://github.com/meizu-m86/android_kernel_meizu_m86.git`
- branch: `cm-14.1`
- commit: `67699d9442a9557eca24ba7a489ffa1b0601e806`
- imported: 2026-08-06
- baseline version: Linux 3.10.61
- device defconfig: `arch/arm64/configs/cm_pro5_defconfig`
- defconfig SHA-256:
  `628091dcab3eb72ee5e282c9f91380a4edaa9f245adaa802f8c433a69491232c`

The snapshot was transferred from the locked AutoDL reference checkout and
verified against it with per-file rsync checksums before import. The GitHub
history is not embedded as a nested repository; all Android 10 port changes
are maintained by the enclosing local repository.

The `cm-14.1` head is used instead of `staging/lineage-15.1` because the latter
is one commit behind and has no unique commits. Samsung universal7420 Android
10 kernel work is a comparison and patch source, not a replacement for Meizu's
board, display, camera, modem, UFS, and boot-chain implementation.
