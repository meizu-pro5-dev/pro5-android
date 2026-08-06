# Kernel forward-port ledger

## Locked baselines

- Meizu hardware base: `meizu-m86/android_kernel_meizu_m86`, branch
  `cm-14.1`, commit `67699d9442a9557eca24ba7a489ffa1b0601e806`.
- Android 10 donor: `universal7420/android_kernel_samsung_universal7420`,
  branch `lineage-17.1`, commit
  `736c1818f71e981fbc3ec1b434e8201de3130ff3`.
- Both report Linux 3.10.61. The local Meizu snapshot contains 30,952 regular
files and five symbolic links; its transfer was checksum-verified before the
provenance file was added.

The baseline contains 12 Netfilter filename pairs that differ only by letter
case. A default macOS working tree cannot represent both members at the same
path, so all 24 originals are stored under
`overlays/kernel-meizu-m86-case-sensitive/{upper,lower}` with locked hashes.
The ambiguous collapsed files are omitted from the normal kernel tree. The
builder installer verifies and restores both variants after every rsync; UAPI
header names and Kbuild object names therefore remain byte-for-byte unchanged.

The Meizu defconfig hash before any forward-port is
`628091dcab3eb72ee5e282c9f91380a4edaa9f245adaa802f8c433a69491232c`.
It enables `SOC_EXYNOS7420`, `MACH_M86`, Android drivers, seccomp, audit, and
SELinux, but does not enable cpusets.

## Confirmed Android 10 gaps

The donor has moved Binder out of staging into `drivers/android`, split the
allocator into its own source files, and accumulated the Android 8-10 Binder
locking, scatter-gather, security-context, and vulnerability fixes. The Meizu
tree still has the older monolithic `drivers/staging/android/binder.c` and its
old UAPI header. This is a runtime ABI/security gap, not merely a build-style
difference.

The donor also contains these directly relevant changes:

| Donor commit | Purpose for m86 |
| --- | --- |
| `b988a22a8aec` | move Binder from staging into the main Android driver area |
| `38d096480308`, `414897ecb0e2` | split Binder allocation and introduce its locking model |
| `d6885163444f` | sender security-context support used by newer Android userspace |
| `31875d6d7302`, `aa4dd2b90c70`, `f5df42bcc177` | Binder overflow, SG-boundary, and UAF fixes |
| `b405474dac10` | make the backported Binder compile on this 3.10 kernel |
| `073128f84cab` | add `READ_ONCE`/`WRITE_ONCE` compiler helpers needed by backports |
| `6fa3fc428d9a`, `01f4101e1210`, `ee9b0541d389` | repair external-output-directory builds |
| `b4d878517c2a` | enable cpusets expected by Android task profiles |

The exact final donor files are retained on the builder under the locked
reference snapshot. Individual commit identifiers are used to explain and
review the port; patches are applied to the local Meizu tree, never only to the
builder checkout.

## Port order and gates

1. Build the unchanged `cm_pro5_defconfig` with the LineageOS 17.1 GCC 4.9
   toolchain and retain its log, config, image size, and hash.
2. Port only host-build and `O=` fixes required to make that baseline
   reproducible. Keep these separate from runtime changes.
3. Enable cpusets and verify the generated config. Do not import unrelated
   Samsung defconfig options or Samsung board drivers.
4. Replace the old Binder implementation with the donor's final Binder/UAPI
   set plus its required compiler and SELinux hooks. Integrate the directory
   exactly once; the donor snapshot contains duplicated Kconfig/Makefile
   include lines from its history and those duplicates are not copied.
5. Compare and port sdcardfs, cgroup, SELinux, networking/qtaguid, ashmem, and
   ION changes only when Android 10 build or runtime evidence requires them.
6. Preserve the Meizu device tree, panel/touch, UFS, camera, radio, audio,
   sensor-hub, fingerprint, NFC, power, and thermal implementations throughout.

Each runtime group must pass a standalone kernel build before it is combined
with recovery or boot-image changes. A donor commit that touches a Samsung
peripheral is not accepted solely because the SoC matches.

## Standalone build evidence

The first unchanged-tree attempt on 2026-08-06 reached the host `dtc` link and
failed because both the shipped lexer and parser defined `yylloc`. Modern host
GCC defaults to `-fno-common`, so the duplicate tentative definition is a hard
link error. The lexer declaration is made `extern` in both its source and
shipped generated file; the parser remains the single owner. This is a
host-build-only compatibility change and does not alter target kernel code or
configuration.

The next attempt passed that gate and reached Netfilter, where the missing
lowercase `xt_mark.h` exposed the case-folding loss described above. This is
handled as a source-transport overlay rather than by renaming public headers or
kernel modules.

## Explicit non-decisions

- The donor's forced permissive SELinux change is not a production solution.
- The donor's Samsung DTBs, defconfigs, USB stack, battery, and display switch
  are not inherited by default.
- No GPT-derived cache geometry is claimed until the paused backup phase is
  resumed; the inherited Samsung cache-image settings are cleared meanwhile.
