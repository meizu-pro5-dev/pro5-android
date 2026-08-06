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

With the case pairs restored, commit `abc6c4261c393f06e035c4a947e6712b8a24c220`
built successfully using the locked GCC 4.9 revisions
`a61b4b9ea2a5098dbf113999526978aec683753b` (arm64) and
`0e7d16580dd5fb78734174d56887f1e681d0ee4a` (arm). The retained baseline
artifacts are:

| Artifact | Size | SHA-256 |
| --- | ---: | --- |
| `Image` | 17,031,920 | `aa4bc55de74f365854aecebd31a904951b785ba7c339aa2aea83cd0b81b6f9da` |
| generated DTB | 145,988 | `bea3523f946da2ce4fd61c57de5a75af1bba666e973774a7a16fab6694c176a2` |
| generated config | 99,498 | `e82ea521a12a9142a5dc405fb8a37c2d19db67183f610765042e89a48ad60040` |

The successful compile exposed a separate DTB correctness issue: the old DTC
preprocessor rule did not include generated `autoconf.h`. It therefore ignored
all `CONFIG_*` branches and silently omitted the S6E3FA3 panel phandle and both
panel regulators. A diagnostic build that explicitly included the generated
configuration restored every node and all but one property present in the
community CM14 DTB; only six values then differed, representing the current
source's bootargs, Mali clocks, and modem buffer counts. The DTC rule now
includes `$(objtree)/include/generated/autoconf.h` so external and in-tree
builds evaluate board conditionals consistently.

Two clean builds of the same target initially differed by 22 bytes. The only
variable payload was Broadcom DHD's debug version string containing
`__DATE__`/`__TIME__`; its two changed timestamp bytes also changed the
20-byte linker build ID. The runtime-irrelevant wall-clock suffix is removed
while retaining the driver version and source path. Consecutive clean builds
must now produce identical `Image`, DTB, and config hashes.

The stock Flyme DTB remains a separate hardware reference. It has the same
root model and compatible strings but uses the older `fpc,fpc_irq` fingerprint
node and a `meizu,simple_adc` thermistor node, while the community/current tree
uses `fpc,fpc1020` and adds hardboot, PMU, and key-booster nodes. These deltas
must be reconciled by subsystem testing before the generated DTB is flashed.

## Explicit non-decisions

- The donor's forced permissive SELinux change is not a production solution.
- The donor's Samsung DTBs, defconfigs, USB stack, battery, and display switch
  are not inherited by default.
- No GPT-derived cache geometry is claimed until the paused backup phase is
  resumed; the inherited Samsung cache-image settings are cleared meanwhile.
