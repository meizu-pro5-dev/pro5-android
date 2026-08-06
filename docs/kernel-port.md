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

Android 10's released kernel-config repository contains Q requirements for
4.9, 4.14, and 4.19 only; its 4.9 conditional file requires at least 4.9.165.
The m86 Linux 3.10.61 base is therefore a deliberate legacy compatibility
port, not a claim of Android 10 FCM or VTS kernel compliance. Required-looking
options are accepted only when both Android userspace and this 3.10 base can
support them. In particular, the Q condition permits the legacy Android low
memory killer instead of `MEMCG` plus swap accounting. Since m86 already has
the former and enabling `MEMCG` adds per-page overhead, memory cgroups remain
off until runtime evidence requires them.

The first low-risk subset taken from the
[released Q 4.9 base fragment](https://android.googlesource.com/kernel/configs/+/refs/tags/android-10.0.0_r41/q/android-4.9/android-base.config)
and confirmed in the same-SoC donor is:

```text
CONFIG_IKCONFIG=y
CONFIG_IKCONFIG_PROC=y
CONFIG_TASKSTATS=y
CONFIG_TASK_XACCT=y
CONFIG_TASK_IO_ACCOUNTING=y
```

This makes the exact running configuration available through
`/proc/config.gz` and provides task/I/O accounting without enabling delay
accounting. Two clean builds compiled and linked `configs.o` and `taskstats.o`
and produced byte-identical target artifacts:

| Artifact | Size | SHA-256 |
| --- | ---: | --- |
| `Image` | 17,133,912 | `1e2319675e6dbf9d50a68e25efc218d7d867b99da58060a2cc16a92715ea4f35` |
| config-aware DTB | 146,172 | `0b537be248ed155a925d58c9a6b927ec1c4cdfaa0624ea714e848abddfba7d84` |
| generated config | 99,780 | `2d5b26afc6afd525819d81df808a4b5bd929daf51069d58236075487d81a5d19` |

The retained local evidence directories are
`artifacts/pro5-a10-kernel-20260807-002347-q-base-config` and
`artifacts/pro5-a10-kernel-20260807-002602-q-base-config-repro` in the parent
Android workspace.

The same Q base fragment disables both `/dev/mem` and `/dev/kmem`, as do all
of the locked universal7420 Android 10 donor defconfigs. An exhaustive
read-only scan of Flyme 8.0.5.0A's ext4 system image covered 2,008 regular
files and 2,017,698,942 file bytes. The only `/dev/mem` prefix occurred in
stock `lmkd`, where the complete strings were
`/dev/memcg/memory.pressure_level` and `/dev/memcg/cgroup.event_control`;
`/dev/kmem` did not occur. Neither raw-memory character device is therefore a
stock userspace dependency, and the maintained defconfig disables both. The
scan is reproducible with:

```bash
PYTHONPATH=../work/pro5-flyme-8.0.5.0A/python-deps \
  ./tools/search-ext4-bytes.py \
  ../work/pro5-flyme-8.0.5.0A/extracted/system.img \
  /dev/mem /dev/kmem
```

Two clean builds of `58c5a5c353b6` confirm both options remain unset and
produce byte-identical target artifacts:

| Artifact | Size | SHA-256 |
| --- | ---: | --- |
| `Image` | 17,117,528 | `dd55cd5b3f23041e9a0bf7a57166305fdc362ddfe5d17c9d655e2357936b1df4` |
| config-aware DTB | 146,172 | `0b537be248ed155a925d58c9a6b927ec1c4cdfaa0624ea714e848abddfba7d84` |
| generated config | 99,802 | `77d05e1f275e00cf09beb29311933435d80b07583ca64c1d96d765af9db2c064` |

The retained local evidence directories are
`artifacts/pro5-a10-kernel-20260807-003632-no-devmem` and
`artifacts/pro5-a10-kernel-20260807-003738-no-devmem-repro` in the parent
Android workspace.

### Effective Android boot arguments

The current separate DTB contains a non-empty `/chosen/bootargs`. Under
arm64's default `CMDLINE_FROM_BOOTLOADER` mode, that string replaces the
compiled `CONFIG_CMDLINE`, so merely setting `androidboot.hardware=m86` in the
defconfig did not guarantee that Android init would receive it. The bring-up
configuration now enables `CONFIG_CMDLINE_EXTEND` and uses:

```text
CONFIG_CMDLINE="androidboot.hardware=m86 androidboot.selinux=permissive"
CONFIG_CMDLINE_EXTEND=y
```

The stock-compatible Android v0 boot-image header remains empty. Android 10's
build core appends `buildvariant=<variant>` unconditionally, so the m86
`BOARD_MKBOOTIMG_ARGS` supplies a final empty `--cmdline`; the generated image
validator checks the resulting header rather than trusting Make variables.
Permissive is
limited to the R1/U1 userdebug bring-up gate and must be removed before S1;
runtime confirmation of the effective command line remains a device test.
Two clean builds of local revision `a418461c` are byte-identical:

| Artifact | Size | SHA-256 |
| --- | ---: | --- |
| `Image` | 17,117,528 | `9664bac0687eee391a42995841e3f90863d401ae6c1517e27ea8c66155e79cf6` |
| config-aware DTB | 146,172 | `0b537be248ed155a925d58c9a6b927ec1c4cdfaa0624ea714e848abddfba7d84` |
| generated config | 99,833 | `6753d53b9084b3c0902dbcd8f4fb053bfe3723649181f8481dbd373485702e81` |

The retained local evidence directories are
`artifacts/pro5-a10-kernel-20260807-020526-cmdline-extend` and
`artifacts/pro5-a10-kernel-20260807-020654-cmdline-extend-repro` in the parent
Android workspace.

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
while retaining the driver version and source path.

Two consecutive clean builds of commit
`b068e2feeb933a742a06a82734e5211f34964153` then produced byte-identical
target artifacts. Their metadata differs only in the expected `built_at`
value:

| Artifact | Size | SHA-256 |
| --- | ---: | --- |
| `Image` | 17,031,920 | `6208611881777050b8350032c43cdb3a36ee58caf5555cd5979a9909ac01560d` |
| config-aware DTB | 146,172 | `0b537be248ed155a925d58c9a6b927ec1c4cdfaa0624ea714e848abddfba7d84` |
| generated config | 99,498 | `e82ea521a12a9142a5dc405fb8a37c2d19db67183f610765042e89a48ad60040` |

A subsequent CPUSETS build exposed one more imported build artifact:
`include/generated/autoconf.h` had been committed in the Meizu source tree.
During an external `O=` build, Make selected objects from the new output-tree
configuration while C headers resolved this stale source-tree configuration
first. Enabling CPUSETS therefore selected `kernel/cpuset.o` but compiled it
as though CPUSETS were disabled. Commit `0f5ab13f3088` removes and ignores the
stale header, so both object selection and C preprocessing now use the same
generated configuration. The earlier images remain useful host-build and DTB
evidence, but are not treated as a release kernel baseline.

With `CONFIG_CPUSETS=y`, two clean builds of commit `0f5ab13f3088` produced
byte-identical artifacts:

| Artifact | Size | SHA-256 |
| --- | ---: | --- |
| `Image` | 17,051,440 | `6a28b7cf2258f06140a3cb3097a1f065d80db586f38e0d9cbf33999e5312d3eb` |
| config-aware DTB | 146,172 | `0b537be248ed155a925d58c9a6b927ec1c4cdfaa0624ea714e848abddfba7d84` |
| generated config | 99,512 | `f60cc976a0f572c7b2b1437f2d11aeb6bc0e6a6e5e503119a6904524ee2bc96d` |

## Android 10 Binder gate

Commit `b5977e0430f0` replaces the monolithic staging Binder and old private
UAPI with the final driver set from the locked universal7420 LineageOS 17.1
donor. Only Binder is moved: ashmem, ION, lowmemorykiller, synchronization,
alarm, and device-specific Android staging drivers remain on the Meizu base.
The root Kconfig/Makefile integration is added once even though the donor
snapshot contains duplicate include lines.

The first compile isolated the remaining base-kernel dependency to
`READ_ONCE`/`WRITE_ONCE`. Commit `abd0fc50203f` ports the donor's single-access
helpers; no Samsung peripheral or unrelated scheduler code is imported.
After that change, `drivers/android/binder.o`, `binder_alloc.o`, and their
combined built-in object compiled and linked successfully. The generated
configuration contains:

```text
CONFIG_ANDROID_BINDER_IPC=y
CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"
```

The linked kernel contains `binder_init`, `binder_transaction`, and
`binder_alloc_new_buf`, plus the three-device parameter string. A separate
`headers_install` gate exports `include/linux/android/binder.h` and confirms
protocol v8 on 64-bit, `BR_TRANSACTION_SEC_CTX`,
`BINDER_GET_NODE_INFO_FOR_REF`, and the transaction security-context flag.
Two clean builds of `abd0fc50203f` are byte-identical:

| Artifact | Size | SHA-256 |
| --- | ---: | --- |
| `Image` | 17,084,376 | `02d6d8c8dfce7b51c2283271be44d369a57cdb460ea0a490e5688fb727f736e1` |
| config-aware DTB | 146,172 | `0b537be248ed155a925d58c9a6b927ec1c4cdfaa0624ea714e848abddfba7d84` |
| generated config | 99,633 | `9ab352d4e7339e96de7c20c698b435c9572e504a13bc04faff4b261c6f5ea584` |

The retained local evidence directories are
`artifacts/pro5-a10-kernel-20260806-{215537,215912}-cpusets*` and
`artifacts/pro5-a10-kernel-20260806-{220329,220551}-binder*` in the parent
Android workspace.

## Android 10 socket-destroy gate

The Meizu source already exposed `SOCK_DESTROY_BACKPORT` in its UAPI header
and mapped that request to SELinux's netlink write permission, but its
sock/inet_diag implementation could only dump sockets. Android 10's network
stack uses the privileged destroy operation to terminate TCP connections that
belong to a network which is being torn down. Leaving only the request number
in the UAPI would therefore advertise an operation that always failed with
`EINVAL`.

The implementation is ported from the Android common 3.10 sequence
`9eaff90`, `d60326c`, `3d4ce85`, `529dfc6`, `9c712fe`, and `15d65ff`.
This splits lookup from dump, wires the destroy callbacks through sock_diag
and inet_diag, implements `tcp_abort()`, handles listening and IPv4-mapped
IPv6 sockets, and retains the Meizu network tree around those focused hunks.
The matching SELinux change `2c33242` and UAPI request number were already in
the Meizu baseline and are not duplicated. The locked universal7420 Android
10 donor independently contains the same core callbacks.

The defconfig now enables:

```text
CONFIG_INET_DIAG=y
CONFIG_INET_TCP_DIAG=y
CONFIG_INET_UDP_DIAG=y
CONFIG_INET_DIAG_DESTROY=y
```

`INET_UDP_DIAG` provides UDP socket monitoring; this gate only implements the
official 3.10 TCP destroy sequence and does not claim UDP destroy support.
The generated objects `sock_diag.o`, `inet_diag.o`, `tcp_diag.o`, and
`udp_diag.o` all compile, and the linked kernel exports
`inet_diag_find_one_icsk`, `sock_diag_destroy`, and `tcp_abort` while retaining
the local `tcp_diag_destroy` callback.

Two consecutive clean builds produced byte-identical target artifacts:

| Artifact | Size | SHA-256 |
| --- | ---: | --- |
| `Image` | 17,100,952 | `d7530cb7af6387bf4b430f0118e8cbc7eda2599766e943914735fd78d8502f41` |
| config-aware DTB | 146,172 | `0b537be248ed155a925d58c9a6b927ec1c4cdfaa0624ea714e848abddfba7d84` |
| generated config | 99,695 | `d5baa7b11ac82b5dff8299498f0e38d2a7100fa4c009588c8dd2fab089c168f8` |

The retained local evidence directories are
`artifacts/pro5-a10-kernel-20260807-001237-sock-destroy` and
`artifacts/pro5-a10-kernel-20260807-001407-sock-destroy-repro` in the parent
Android workspace.

## Android 10 exported-UAPI gate

The first full product compile exposed two differences that a kernel-only
build cannot detect. Android 10's fortified `fcntl.h` expects the standard
`O_TMPFILE` constants in the generated target headers, and the Exynos 7420
scaler includes `linux/m2m1shot.h`. The m86 kernel already contains the exact
M2M one-shot UAPI and its in-kernel implementation, but omitted that header
from `include/uapi/linux/Kbuild`; it is now exported, matching the locked
universal7420 donor at `736c1818f71e981fbc3ec1b434e8201de3130ff3`.

The standard `__O_TMPFILE`, `O_TMPFILE`, and `O_TMPFILE_MASK` values are added
to the m86 asm-generic UAPI so Bionic and target code compile against a
self-consistent Android header set. This gate does not claim functional
anonymous temporary-file support: the 3.10 VFS lacks the later implementation
and will reject that flag. A future VFS/filesystem backport must be evaluated
separately if a runtime consumer requires it; hiding the constant or disabling
Bionic FORTIFY would instead break the Android 10 userspace contract at build
time.

The same product compile then reached the Exynos video codec and found the
m86 UAPI stopped at MFC control 98 before resuming at the HEVC range. The
locked universal7420 kernel defines the contiguous controls 99 through 108
used by its matching Android 10 `libvideocodec`, so that exact numeric block is
exported by m86 as well. Basic codec operation does not depend on the optional
Skype/LTR/frame-QP controls. Their definitions make the shared UAPI compile;
runtime support is not claimed where the older m86 MFC driver returns an
unsupported-control error.

The stock Flyme DTB remains a separate hardware reference. It has the same
root model and compatible strings but uses the older `fpc,fpc_irq` fingerprint
node and a `meizu,simple_adc` thermistor node, while the community/current tree
uses `fpc,fpc1020` and adds hardboot, PMU, and key-booster nodes. These deltas
must be reconciled by subsystem testing before the generated DTB is flashed.

## exFAT source closure

The archived `cm_pro5_defconfig` selected Samsung's `CONFIG_EXFAT_FS` plus its
virtual-xattr and storage-log options, but Meizu's published tree omitted the
entire driver. The storage-log selection depended on donor-only `PROC_STLOG`,
so generated m86 configurations silently discarded it; that stale option and
three similarly undefined FAT options are now absent by validation. Android
10 vold only declares exFAT supported when the kernel reports an `exfat`
filesystem and then performs a kernel mount; packaging `fsck.exfat` and
`mkfs.exfat` alone is therefore insufficient.

The missing 25-file GPL implementation is restored from the locked
Exynos7420 Linux 3.10 tree at
`218eaf61af9e4ef2fe9f6debc1e6af9746de8b10`, where it entered through commit
`0637e90f17aea8aca4356b63b786328a3ca1224a`. The import has a per-file SHA-256
lock, while each Android and TWRP build requires the generated config and both
linked exFAT objects. This establishes source and build closure; disposable
media tests remain mandatory before runtime support is accepted.

## Explicit non-decisions

- The donor's forced permissive SELinux change is not a production solution.
  The current `androidboot.selinux=permissive` argument is a visible R1/U1
  bring-up gate and must be removed for the S1 enforcing build. The kernel uses
  `CONFIG_CMDLINE_EXTEND` because the non-empty DT `bootargs` would otherwise
  replace `CONFIG_CMDLINE`, losing `androidboot.hardware=m86`; the verified v0
  boot-image header itself stays empty.
- The donor's Samsung DTBs, defconfigs, USB stack, battery, and display switch
  are not inherited by default.
- No GPT-derived cache geometry is claimed until the paused backup phase is
  resumed; the inherited Samsung cache-image settings are cleared meanwhile.
