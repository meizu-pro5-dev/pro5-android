# PRO 5 TWRP runtime bring-up, 2026-08-07

## Observed results

The reproducible TWRP 3.7.0_9 source build did not reach the recovery UI, and
no recovery ADB evidence was collected. It stalled at the Meizu logo in both
combinations that were tested:

1. source-built `recovery.img` with the existing Flyme 8 DTB;
2. source-built `recovery.img` with the generated maintained-kernel DTB.

The handset owner then manually restored the Flyme 8.0.5.0A DTB. Flyme booted
normally. There was no automatic DTB rollback.

A third isolation image combined the exact known-working recovery kernel and
header with the complete new TWRP 3.7.0_9 ramdisk. It also stalled at the
Meizu logo with the verified stock DTB. No ADB or fastboot USB function
enumerated while it was stalled.

The handset owner subsequently reconfirmed the unmodified known-working TWRP:
it boots with the same stock Flyme 8 DTB and flashing procedure. The
27,287,552-byte English/zh_CN LZMA source build was then tested and again
stalled at the Meizu logo. This removes the recovery key sequence, current DTB
and basic flashing path as explanations for the new-image failures.

These observations reject the source-built recovery/DTB pair, but they do not
identify a single crashing instruction because no early console or recovery
ADB log was available. Static inspection also rules out the two most obvious
header theories:

- the Flyme 8 `bootimg` and source-built recovery both use
  `second_addr=0x40f00000`;
- the Flyme 8 boot header has a nonzero OS-version word, so a nonzero word is
  not by itself incompatible with the bootloader.

The maintained kernel/DTB path is therefore not the only failure boundary.
Both failed new-ramdisk images were unusually large (33,325,056 and
33,550,336 bytes), while the known-working TWRP is 23,654,400 bytes. The
maintained kernel configuration used by every failed source image had
`CONFIG_PSTORE` disabled. It could not have written a new ramoops record; the
retained pstore record was necessarily from the preceding Flyme kernel's
orderly reboot into recovery. Image/ramdisk size, early display handoff and
the new init/userspace remained live hypotheses at that point.

## Isolation image

The tested image was deliberately hybrid and test-only:

- kernel: byte-identical to the known-working TWRP kernel;
- header geometry and image-ID scheme: inherited from the known-working TWRP;
- ramdisk: byte-identical after decompression to the accepted TWRP 3.7.0_9
  ramdisk, recompressed with deterministic `gzip -9` so it fits;
- embedded DTB: none;
- required external DTB: stock Flyme 8.0.5.0A DTB;
- maximum recovery image size: 33,550,336 bytes, leaving one 4 KiB page below
  the confirmed 33,554,432-byte recovery partition.

This test had one decision boundary:

- if it boots, the new TWRP userspace/ramdisk can start on known-good kernel
  hardware support, and work should move to the maintained kernel/DTB path;
- if it stalls, investigate ramdisk/init compatibility or the much larger
  compressed/decompressed ramdisk before changing the DTB again.

The image failed at the logo. It remains rejected and cannot satisfy final
acceptance because it also uses a provenance-locked prebuilt kernel rather
than the maintained source build.

## Size reduction

The next source build keeps only the English (`en`) and Simplified Chinese
(`zh_CN`) TWRP translations. It retains `DroidSansFallback.ttf`, which
`zh_CN.xml` explicitly requires, and removes the other translation XML files
and the Japanese CJK font. The ramdisk inspector gates the exact language and
font inventories so an incremental build cannot silently restore all
languages.

The following size-isolation build also uses the Android 9 build system's
native LZMA-Alone recovery-ramdisk path. The maintained kernel enables
`CONFIG_RD_LZMA` and `CONFIG_DECOMPRESS_LZMA` while retaining
`CONFIG_RD_GZIP`, so this changes only how the standalone recovery ramdisk is
stored. It does not remove recovery features or affect the normal gzip Android
boot path. Both clean build passes must produce the same LZMA recovery image,
DTB, and kernel configuration, and the artifact inspector decompresses the
stream before enforcing the full ramdisk inventory.

Both reduction stages passed their static and two-clean-build gates:

| Artifact | Compression | Size | Recovery SHA-256 | Partition margin |
| --- | --- | ---: | --- | ---: |
| `twrp-20260807-114507-recoveryimage` | gzip | 32,538,624 | `163c0bae13424d78cbbc8661cc5fd9907762a415a2cb86e805f88f173b0dafef` | 1,011,712 |
| `twrp-20260807-115957-recoveryimage` | LZMA-Alone | 27,287,552 | `a360a6f1a269c9c730f8f288f4783cf9d2054a742718292abed03f2e3823e5aa` | 6,262,784 |

The LZMA image was tested after the old recovery baseline booted; it stalled at
the Meizu logo and is rejected. Its generated DTB still has SHA-256
`0b537be248ed155a925d58c9a6b927ec1c4cdfaa0624ea714e848abddfba7d84`
and must not be flashed; the test retains the verified Flyme 8 DTB.

## Early-display and persistent-diagnostic correction

The device source tree used by the known-working TWRP contains
`TW_SCREEN_BLANK_ON_BOOT := true`; the new source tree had omitted it. The
stock bootloader leaves its Meizu logo in the scanout buffer. TWRP implements
this setting as an initial framebuffer blank/unblank cycle before drawing its
splash, so a running recovery could otherwise remain visually
indistinguishable from a boot stall. The maintained tree now restores this
device-specific setting. The resulting handset test still stalled at the
logo, so the omission was real but not the complete boot failure.

Persistent diagnostics also required a kernel correction. The stock Flyme 8
DTB points the top-level `samsung,exynos_ramoops` device at a generic
reserved-memory node through `memory-region`; the generated community DTB
uses the Exynos ION ramoops heap. The original driver resolved only the latter.
The maintained kernel now enables `CONFIG_PSTORE`, `CONFIG_PSTORE_CONSOLE` and
`CONFIG_PSTORE_RAM`, resolves the stock DTB phandle first, and retains the ION
lookup as a fallback for the generated DTB. Kernel, Android and TWRP build
workers all fail if either the configuration or linked ramoops objects are
missing.

The commit-state standalone build of `7e2a4136` passed those gates:

| Artifact | Size | SHA-256 |
| --- | ---: | --- |
| `Image` | 17,256,216 | `aac717c04511f0b0374188e74c1672809aafbac2ebd9b47193a3f50fd06bcd94` |
| generated DTB | 146,172 | `0b537be248ed155a925d58c9a6b927ec1c4cdfaa0624ea714e848abddfba7d84` |
| generated config | 100,076 | `592fcde6b433a6f2af38cd30022f3b03159a184e198d15829a5735479e84b914` |

The retained local evidence directory is
`artifacts/pro5-a10-kernel-20260807-124633-pstore-ramoops` in the parent
Android workspace.

Two clean TWRP builds of the same source revision then produced
byte-identical outputs:

| Artifact | Size | SHA-256 | Partition margin |
| --- | ---: | --- | ---: |
| `twrp-20260807-125744-recoveryimage/recovery.img` | 27,308,032 | `8c20eaa5301a9c70ad363cd765d5ba4cf33be69a37fc3f6a88d9b8cca5b07ca9` | 6,242,304 |

The candidate was tested with the verified stock Flyme 8 DTB. It stalled at
the Meizu logo and later returned automatically to Flyme, without TWRP UI or
recovery ADB, and is rejected. Flyme then exposed a 43-byte
`console-ramoops-0` containing only `2 Corrected bytes, 0 unrecoverable
blocks`; there was no console payload. `/cache/recovery/last_log` still had a
12:35 modification time predating the 13:31-13:32 test. The persistent reset
record contained the preceding `reboot fastboot` request, one `system wreset`,
and no oops, panic or dedicated watchdog count. This is evidence of an early
warm reset, but it cannot prove whether the recovery kernel reached its late
ramoops probe. The retained evidence directory is
`artifacts/twrp-device-test-20260807-1332-screenblank-pstore` in the parent
Android workspace.

## Completed isolation results

The all-old-content current-envelope control with recovery SHA-256
`f86fe878513b9df07bdfd7c32f8064564377067622b355a7a5c889f260dcedca`
reached the recovery UI. Its kernel was larger than the corrected candidate,
its declared ramdisk was exactly 10,061,001 bytes, and its complete image was
larger. This excludes those component-load dimensions. The legacy recovery's
USB path did not expose host ADB during the test, so the result is limited to
the owner-observed UI and does not accept MTP or ADB.

The owner also confirmed that the earlier maintained-source-kernel / complete
old-userspace diagnostic with recovery SHA-256
`7a126febd9e3d12b221fd870effb4a835b9604265cf33ad556da60f0dbfa54e1`
had booted. Together with the failed old-kernel / new-ramdisk test, this makes
the new ramdisk content a sufficient failure boundary; the maintained kernel
used by that diagnostic is not the cause of that failure.

A subsequent image retained the corrected TWRP 3.7 executable stack but
restored the legacy init, ueventd, SELinux, healthd and toolbox startup chain.
It used the later pstore kernel and LZMA and had recovery SHA-256
`14c0056ca835cd1599b70e892071458c6693cbdfaa5071ef0efefcc169fd83bb`.
It also stalled at the logo and is rejected. The following stock boot exposed
only the same 43-byte pstore ECC notice; every reset-reason counter was zero.
The retained evidence directory is
`artifacts/twrp-device-test-20260807-1408-old-init-lzma-fail` in the parent
Android workspace. Because that image changed the later kernel and compression
path together, it does not cleanly reject the legacy startup-chain hypothesis.

## Completed clean gzip sequence and next isolation

The exact all-old-content gzip load-envelope control with SHA-256
`22a42a33516da36dcbc9ec3a1807716123430e2f5a256f25b5d5f16b2dee469d`
reached the recovery UI. Its kernel is 17,512,240 bytes, declared ramdisk is
15,051,754 bytes and complete image is 32,571,392 bytes. This proves that the
bootloader and early kernel can load every component dimension required by
the matching new-userspace test.

The proven-source-kernel / complete-new-userspace / legacy-init gzip image
with SHA-256
`0dad8b1710cd8eef39f6b3d632f71bc8cd5f3c857ed16055fbbf4b3224254ed3`
then stalled at the Meizu logo. Because its matching, larger load-envelope
control passed, this result excludes the boot header, proven source kernel,
gzip format, legacy init/ueventd/SELinux startup chain and component-load
sizes. The remaining failure boundary is new executable/runtime or rootfs
content.

The minimal-runtime diagnostic narrowed that boundary further. Recovery SHA-256
`c391de4d77392a6c8f2f2012d44746d0b46d18e4585faf953587222a36a3766d`
is 29,335,552 bytes and uses:

- the exact source kernel already confirmed to boot;
- the known-working recovery header, gzip format, init, rc, ueventd, SELinux,
  healthd, toolbox and adbd;
- the exact new TWRP 3.7 `recovery`, Android 9 linker and linker config;
- the new recovery's complete recursive ELF dependency closure, the `/sbin`
  tools it names, its resources, fstab and matching configuration files.

The deterministic gzip ramdisk is 12,104,107 bytes, below the already-passed
15,051,754-byte load envelope. Its runtime closure contains 69 entries and
496 dependency edges, totals 19,397,725 unique payload bytes, has no missing
dependency and is byte-identical to the corrected new-userspace donor. The
optional post-boot TWRP App APK and permission XML are absent.

On the handset it progressed from the Meizu logo to a black screen, vibrated,
then automatically rebooted into Flyme. The black transition is consistent
with reaching TWRP 3.7 `gui_init()`, whose device-specific blank/unblank runs
immediately after graphics initialization, but there is no log proving the
precise exit point. The 204,148-byte pstore file collected afterward contains
the subsequent stock Flyme kernel boot, not a recovery console. Reset-reason
storage was damaged with all counters zero, and the cache recovery log still
had a 14:24 modification time predating the approximately 14:36 test. Evidence
is retained at
`artifacts/twrp-device-test-20260807-143759-minimal-new-recovery-runtime` in
the parent Android workspace.

The retained legacy init, ueventd, healthd and adbd are statically linked, so
the recovery-wide Android 9 linker did not make a critical legacy service
unloadable. Post-test archive review instead found a concrete isolation flaw:
the old base contributed `/etc/twrp.fstab`, which TWRP 3.7 checks before
`/etc/recovery.fstab`. The stale old file therefore shadowed the reviewed new
fstab even though the corrected full donor contains no `/etc/twrp.fstab`.

The next one-variable diagnostic has recovery SHA-256
`7a648ed1a5bc86db96741931104bab8443a728bd1f2b90d8abac7182156f691b`.
It is 29,331,456 bytes with a 12,103,270-byte gzip ramdisk and removes only
the shadowing `etc/twrp.fstab`; all 488 surviving entries, the kernel and boot
header geometry remain identical.

The handset repeated the same Meizu-logo, black-screen, vibration and automatic
Flyme boot sequence. The immediately collected `/proc/reset_reason` is decisive:
it records `software reboot`, `Restart cmd : reboot`, at 14:47:56, with every
panic, oops, watchdog and hardware-reset counter at zero. Both cache recovery
logs still had their pre-test 14:24:07 modification time, while the 419,400-byte
pstore record begins with the subsequent Flyme boot. Deleting the stale fstab
therefore did not change the failure and excludes fstab selection as its cause.
The normal reboot strongly indicates that TWRP returned from its GUI path and
requested its default system reboot; the exact reason for that return still
requires its tmpfs log.

The next diagnostic keeps that corrected fstab image and changes only the data
payload of the legacy `init.rc`. Recovery SHA-256
`a2d6c1fd75c33d51af047c2bd94fb344f27a6bd887048854efc79b56bf147375`
is 29,335,552 bytes with a 12,103,719-byte gzip ramdisk. Its test-only init:

- sets `mtp.crash_check=1` before TWRP starts and exposes only the known-working
  static adbd through USB product `18d1:4ee7`;
- makes recovery a `oneshot` service and removes the wildcard power-control
  rc action, attempting to preserve `/tmp/recovery.log` after TWRP returns;
- retains exact `reboot,bootloader` and `reboot,recovery` handlers as explicit
  escape paths.

Independent cpio comparison shows 489 entries including the trailer, identical
path order and metadata, and only `init.rc` data changed. The proven kernel,
TWRP executable, linker, dependency closure, resources and reviewed recovery
fstab are byte-identical. This image is solely a volatile log-capture harness,
not a recovery candidate.

The handset still followed the same sequence and returned to Flyme. The next
reset record increments the software-reboot counter to two and records command
`reboot` at 15:03:57; all crash and watchdog counters remain zero. Cache logs
remain at 14:24:07 and pstore again contains the following Flyme boot. The
diagnostic therefore proves that deleting the rc wildcard does not intercept
this old init's special power-property path.

The pinned TWRP executable contains exactly one `sys.powerctl` string. Its
source calls `property_set(ANDROID_RB_PROPERTY, "reboot,")` after `gui_start()`
returns. The second ADB-only diagnostic makes only that property name inert:
the 935,176-byte recovery ELF replaces `sys.powerctl` with the same-length
`twrp.loghold` at byte offsets 774255 through 774266. Recovery ELF SHA-256
changes from
`baca28ef73ebba8367abf36018191d30a712425953ec1d4c90ef9d998b95086a`
to
`0b31d94944fe11b1bf2ead63753b0ad2bfd3358073755150b3a6c900b6179e51`;
all other ELF bytes are identical.

The resulting recovery image is 29,335,552 bytes with SHA-256
`34bed1046ecef38b13ca8eda20f97f1a0610af0c4fb4a3e3769fc6aaa73d8d4a`.
Its 12,103,722-byte gzip ramdisk has SHA-256
`5e97bb668101cf85037ac276e25ed76d6d40a99cc08e73150183fa1b98ef4ca4`.
Relative to the first ADB-only image, only `sbin/recovery` data changes; all
489 cpio paths, order and metadata are identical. The existing oneshot init
and ADB-only configuration remain present, so TWRP can return without asking
init to reboot and `/tmp/recovery.log` can remain reachable.

The handset nevertheless repeated the same visible sequence and recovery ADB
did not remain reachable. A full 33,554,432-byte recovery-partition dump taken
from Flyme afterward has the exact v2 artifact as its first 29,335,552 bytes,
proving that Flyme did not replace the diagnostic. The remaining bytes are
pre-existing partition-tail data outside the declared boot-image payload.

The post-test reset record is `poweroff reboot`, command `reboot charge`, at
15:23:58 rather than another software reboot. That record does not classify
the recovery exit: the 419,400-byte pstore console contains the preceding
Flyme session and ends while entering the fastboot/test sequence. Both
`/cache/recovery/last_log` and `/cache/recovery/log` remain the 1,757,331-byte
files last modified at 14:24:07. V2 therefore proves exact image retention but
still loses the volatile log.

Persistent log-capture v3 is built directly from that exact v2 image. Its
recovery SHA-256 is
`61c7e16e706ab04cddc9801b6fa30f6f23683108591e9446dbf66e69e2594ea7`;
it remains 29,335,552 bytes, with a 12,105,342-byte gzip ramdisk whose SHA-256
is `f6d840c8fa929180bdffb77743e644bbc2317ec665ed053c23f3704317518699`.
The v2 kernel, recovery ELF, dependencies, resources, corrected fstab and boot
geometry are byte-identical. Only two cpio data payloads change:

- `init.rc` launches `/sbin/recovery` as a child of the wrapper and assigns the
  service the recovery SELinux domain;
- the existing executable `sbin/permissive.sh` entry carries the wrapper,
  while its mode, ownership, timestamp, inode and all other cpio metadata stay
  unchanged.

Automated comparison proves all 489 paths and their order are unchanged, no
path is added or removed, and no metadata or archive tail changes. Two
independent gzip rewrites have SHA-256
`f6d840c8fa929180bdffb77743e644bbc2317ec665ed053c23f3704317518699`;
both recovery repacks have SHA-256
`61c7e16e706ab04cddc9801b6fa30f6f23683108591e9446dbf66e69e2594ea7`.

The wrapper waits for the existing cache block device, verifies a read-write
mount, creates unique `pro5-twrp-diag-v3-*` files under `/cache/recovery`, and
links `/tmp/recovery.log` to the persistent log before TWRP starts. It retains
its own output and an initial dmesg, syncs every two seconds, and records the
TWRP exit status plus a final dmesg if the child returns. It then remains alive
for ADB. If cache cannot be mounted or written, it deliberately does not start
TWRP and holds the diagnostic environment. This is a deliberate persistent
cache write, not a normal read-only boot test.

The handset test of v3 repeated the Meizu-logo, black-screen, vibration and
automatic Flyme boot sequence. This time the diagnostic files survived. The
wrapper started at 16:31:50 local time, mounted the cache block device, created
its recovery and wrapper logs, and saved a 124,566-byte dmesg ending at kernel
uptime 2.927737 seconds. The dmesg records init starting the wrapper at
2.881801 seconds and cache mounting at 2.912842 seconds. It contains no panic,
oops or reset after that point because the snapshot was taken before TWRP.

The recovery log contains the v3 header but no TWRP output. The wrapper log
contains its start line but not `persistent_log_ready`, and there is no exit
dmesg or recovery exit status. In v3 that marker is written immediately after
an explicit `sync`, while the periodic loop sleeps for two seconds before its
first sync. The result therefore proves the wrapper and cache path, but it
does not distinguish a reset inside the explicit sync from a reset or hard
lock immediately after TWRP launch: every write after the completed snapshot
could still have remained in page cache.

The post-test reset record does not add another software reboot. Its most
recent entry is the 16:30:57 Flyme reboot used to enter recovery. The retained
419,400-byte pstore console is the same preceding Flyme session and ends with
that orderly reboot; the recovery dmesg does not register a pstore or ramoops
backend with the stock DTB. Consequently this test no longer supports the
earlier theory that TWRP returned normally and requested a system reboot.

The recovery-partition acquisition contains the expected 33,554,432 device
bytes followed by a 95-byte `dd` status message that ADB merged into stdout.
Despite that acquisition trailer, its first 29,335,552 bytes have exact v3
SHA-256
`61c7e16e706ab04cddc9801b6fa30f6f23683108591e9446dbf66e69e2594ea7`,
so the tested image is proven. Evidence is retained unchanged at
`artifacts/twrp-device-test-20260807-164003-persistent-log-v3` in the parent
Android workspace.

Synchronous log-capture v4 is built from that exact handset-tested v3 image.
Only the data payload of the existing `sbin/permissive.sh` entry changes. All
489 cpio paths, order and metadata, the kernel, init, patched TWRP ELF,
dependencies, resources, fstab and header geometry remain identical. Two
independent gzip rewrites have SHA-256
`54d9071c1720f7460b5518179e0a95b09c4d36ad20d14e0a9443692eb08ba010`;
both repacked recovery images are 29,335,552 bytes with SHA-256
`929308abf56395ab6ec74d5f53734d5b90f7ce6a45086680e207002e3f6f6029`.

V4 requires cache to report both `rw` and `sync` mount flags before it creates
any diagnostic file. It flushes explicit `cache_sync_ready`,
`recovery_log_linked`, `dmesg_start_saved` and `launching_recovery` stages,
then runs the unchanged TWRP. TWRP opens `/tmp/recovery.log` unbuffered, and
the symlink resolves to the synchronously mounted cache file. A one-second
sync loop remains as a secondary guard. A mount that cannot be made
synchronous prevents TWRP from starting and holds the diagnostic environment.
V4 still is an evidence collector, not a functional recovery candidate.

The handset test of v4 again showed the Meizu logo, a black screen, vibration
and an automatic return to Flyme, but the synchronous log survived through
TWRP's graphics startup. It records TWRP 3.7.0_9 entering `gui_init()`, normal
DRM fallback, a 1080x1920 32-bit BGRA fbdev framebuffer and selection of
double buffering. Its final durable TWRP line is `Using fbdev graphics.`.
There is no following `=> Linking mtab`, so `gui_init()` never returned and
TWRP did not begin either fstab pass, resource loading, encryption, MTP or the
main GUI loop.

The wrapper's human-readable mount-header command uses a BusyBox-incompatible
one-line awk expression and consequently left `cache_mount=` empty while
logging an awk diagnostic. This does not affect the separate multi-line mount
predicate: every durable stage through `launching_recovery` is present, and
the unbuffered recovery log itself contains the graphics output. The v4 mount
and log path therefore worked as intended for this isolation.

The reset record is unchanged from the preceding test: its latest software
reboot remains the 16:30:57 Flyme command used to enter recovery, all panic,
oops, watchdog and hardware-reset counters are zero, and pstore contains a
preceding Flyme session. It cannot classify the later reset. A clean
33,554,432-byte partition acquisition has the exact v4 image as its first
29,335,552 bytes, proving that the intended image produced the log. The full
immutable evidence set is retained at
`artifacts/twrp-device-test-20260807-170103-sync-log-v4` in the parent Android
workspace.

At pinned TeamWin recovery revision
`90e5d9559065cfa8b2b9a5dbb1c5cb7a88f034fa`, the last line comes from
`minuitwrp/graphics.cpp:419`. The remaining initialization sets up
pixelflinger and calls `gr_flip()` twice. In the selected double-buffer fbdev
path, the first flip copies into framebuffer page 1 and invokes
`FBIOPUT_VSCREENINFO` with `yoffset=1920`. The failure boundary is confirmed;
whether that page switch is the cause remains a one-variable hypothesis until
the single-buffer image is tested.

The device tree now sets
`RECOVERY_GRAPHICS_FORCE_SINGLE_BUFFER := true`. Two clean source builds in
the same absolute output path produced identical recovery images with
SHA-256
`370064ffa114783119fed8eea52ca6505a47954f62a1db309d7f268462b9c704`,
identical generated DTBs with SHA-256
`0b537be248ed155a925d58c9a6b927ec1c4cdfaa0624ea714e848abddfba7d84`,
and identical kernel configs. That full source image changes many variables
and its generated DTB remains rejected for device use, so it is retained only
as the audited donor of `sbin/libminuitwrp.so`.

Single-buffer repair v5 is built from the exact handset-tested v4 image and
changes only the data payload of `sbin/libminuitwrp.so`. The old library has
SHA-256
`35698bff0cead8468880ac09a581b2ea0a5614daef889bb1e751a53bfd7b3cc0`;
the twice-built replacement has SHA-256
`ecd2d3dedced81b9122c9fedcb32f278e9d914e2a923dc4bf85cd571ab4cc8f1`.
Their 839 exported dynamic symbols are identical. The replacement contains
the single-buffer build and runtime markers and no `double buffered` branch.
All 489 cpio paths, path order and metadata, the kernel, init, patched recovery
ELF, fstab, resources, synchronous wrapper and boot geometry are unchanged.
Two independent v5 ramdisk and image repacks are byte-identical.

The resulting 29,335,552-byte v5 image has SHA-256
`23db8d86e7b6523b2a4ad1c8ed2b2bbd319d490d05d57381f3670dbad42f5fe1`.
Its 12,105,466-byte gzip ramdisk has SHA-256
`32603758753db481881eb1f7b1527e469f0641aa64a732cb31bb7aac7792238d`.
It retains v4's synchronous logger and therefore still creates files named
`pro5-twrp-diag-v4-*`. V5 is an isolated device-test candidate, not an
accepted recovery.

The v5 handset test did not repeat the v4 failure. The Meizu logo flashed and
the panel became bright; after the screen timeout it went black, and Home or
Power woke it back to the retained Meizu image. Two synchronous recovery logs
started 14 seconds apart. Both contain the single-buffer markers, return from
`gui_init()`, load the splash and complete TWRP themes, process both fstab
passes, scan partitions and enter the `main`/`main2` GUI pages. The second
session records repeated brightness transitions `255 -> 5 -> 0 -> 255`,
matching the observed timeout and key wake. V5 therefore proves that removing
the page-1 flip fixes the startup hang and that TWRP's main loop and input
handling are alive.

The exact source explains why the GUI remained invisible. Under
`RECOVERY_GRAPHICS_FORCE_SINGLE_BUFFER`, `double_buffered` is false and every
flip copies into framebuffer page 0, but `set_displayed_framebuffer(0)` also
returns immediately on that same false value. No initialization ioctl selects
page 0, so DECON can continue scanning the bootloader logo page while TWRP
renders normally elsewhere. V4 already passed this init-time
`FBIOPUT_VSCREENINFO` request with `yoffset=0`; its first later request for
`yoffset=1920` was the operation removed by v5.

The v5 reset record contains two `system wreset` events and retains zero
panic, oops and watchdog counters. The owner's long Power press accounts for
the final warm reset, but the evidence does not identify the earlier restart.
Pstore contains a Flyme session rather than either recovery session. Recovery
reported `init.svc.adbd=running`, but USB ADB did not enumerate at the host;
it remains a separate acceptance item after visible scanout is restored. The
clean 33,554,432-byte partition acquisition has the exact v5 image as its
first 29,335,552 bytes. Immutable evidence is retained at
`artifacts/twrp-device-test-20260807-173254-single-buffer-v5` in the parent
Android workspace.

The reviewed minuitwrp patch permits only the init-time page-zero selection
when forced single buffering is compiled. Later flips remain memcpy-only and
cannot request page 1. The patch SHA-256 is
`db20e6c53fce5a2c50556bbae2f59dd9dab398fc0c2c7c61e4e23278b724cf1c`.
Two clean source builds produced identical 27,308,032-byte recovery images
with SHA-256
`7cbef6a30c2a380b479266b5399c6a6647c897950519e96f8473ff50e64f886c`,
identical generated DTBs and identical kernel configs. The full source image
and generated DTB remain donor evidence only and must not be flashed for this
isolation.

Page-zero repair v6 is built from the exact handset-tested v5 image and again
changes only `sbin/libminuitwrp.so`. The twice-built replacement is 398,968
bytes with SHA-256
`e051032762c474654192460e85c94144b368d9a1d441435a603088955a032978`.
It contains the single-buffer and page-zero runtime markers, contains no
`double buffered` branch, and has the same 839 dynamic symbol names and types
as the v5 library. All 489 cpio paths, order and metadata, the kernel, init,
patched recovery ELF, fstab, resources, synchronous wrapper and boot geometry
remain identical. Two v6 repacks are byte-identical.

The resulting 29,335,552-byte v6 recovery has SHA-256
`398dc69d5af4b9210b09c27d8a50e16edeaebbbf7f4844d3efefaa402c6934c8`.
Its 12,105,582-byte gzip ramdisk has SHA-256
`27a43742f3245a9b92c7054d225cbd76159873114c01df49b74b3324409e2690`.
V6 retains the v4 synchronous logger and remains a one-variable device-test
candidate rather than an accepted recovery.

The v6 handset test showed a fully black panel, but its retained synchronous
log proves the recovery stayed alive. It contains the forced-single-buffer and
page-zero markers, returns from graphics initialization, processes fstab and
partitions, loads the complete theme, enters `main`/`main2`, and records
brightness `255 -> 0 -> 255`. There is no recovery crash, panic, oops or
watchdog reset. The clean partition acquisition has the canonical v6 image as
its exact prefix. Immutable evidence is retained at
`artifacts/twrp-device-test-20260807-180116-page-zero-v6` in the parent
Android workspace.

That result proves that selecting page 0 displays the buffer minuitwrp cleared,
but later userspace copies do not refresh this MIPI command-mode panel. The
reviewed follow-up makes forced-single-buffer flips issue
`FBIOPAN_DISPLAY` with `yoffset=0`. It retains page zero and can never select
the rejected `yoffset=1920` page.

Command-refresh v7 starts from the exact handset-tested v6 image and changes
only `sbin/libminuitwrp.so`. All 489 cpio paths, order and metadata, the proven
kernel, diagnostic init and wrapper, patched recovery ELF, fstab, resources
and boot geometry remain identical. Its replacement library came from two
byte-identical clean source builds, and two image repacks are byte-identical.
The resulting 29,335,552-byte recovery has SHA-256
`26c98728539ab21d723a67906e8250a78be633cdb481cdaa93f2ecdee2e7d43e`;
its 12,105,636-byte gzip ramdisk has SHA-256
`7c46b84170ccd2c108816b936105a961ba2907969d892fae2c65b69b6b04d725`.

V7 reached and displayed the complete TWRP interface. After approximately one
minute, the configured timeout made the panel black. Touch, Home and Power
continued to operate the UI and repeatedly restored brightness from 0 to 255,
but display output did not resume. Both retained logs load the theme and enter
the main/install pages; the longer session records repeated `255 -> 5 -> 0 ->
255` transitions. Reset evidence contains no panic, oops, watchdog or hardware
reset. The first 29,335,552 bytes of the partition acquisition match v7
exactly. Immutable evidence is retained at
`artifacts/twrp-device-test-20260807-182653-command-refresh-v7`.

TWRP's timeout path first sets brightness to zero and then calls
`gr_fb_blank(true)`; wake calls `gr_fb_blank(false)` before restoring
brightness. The m86 DECON implementation uses that FBIOBLANK request to stop
and restart the command-mode DSI controller. V7 proves the controller does not
reliably return even though the TWRP main loop, touch input and backlight remain
alive. The maintained tree therefore sets `TW_NO_SCREEN_BLANK`: timeout still
turns off only the AMOLED backlight, while wake no longer depends on a full
DECON/DSI power cycle.

The v7 `MTP Crashed, not starting MTP on boot.` text is deliberately injected
by its diagnostic init setting `mtp.crash_check=1`; it is not evidence of an
MTP process crash. That legacy init also creates but never mounts
`/dev/usb-ffs/adb`, so its missing host ADB cannot validate the maintained
source path. The source candidate restores upstream's FunctionFS mount and new
minadbd. A read-only check of the connected Flyme system established its
working ADB-only gadget as `18d1:4ee7`; recovery now uses that exact PID,
forces one post-mount `none -> adb` transition, reserves `18d1:4ee2` for
MTP+ADB, and explicitly uses `/dev/mtp_usb` for the Exynos MTP function.

The resulting full-source v8 candidate is retained at
`artifacts/twrp-20260807-185235-recoveryimage` in the parent Android workspace.
Its 27,303,936-byte recovery image has SHA-256
`9c4d5038e80de335792977690ea963e3b9d5e66463ac58f602d124fa2fd06102`;
both fully clean build passes produced that exact image. It retains kernel
SHA-256
`f628266ac0c23770c81e27e553de0b58f9c51df55d50c54bc88cf0196b796da7`,
uses a 10,059,600-byte LZMA ramdisk with SHA-256
`93386aaea2b037b2ed4b62438d24644bb297dc11eb46eacfa67808a6e8cc7794`,
and has no embedded DTB. The generated kernel config and build-only DTB are
also byte-identical between passes.

Post-fetch extraction confirms the FunctionFS mount, `f_ffs` alias, new
minadbd, ADB/MTP product properties and ordered ADB transition are present in
the sealed image. The `adbd` binary has SHA-256
`d3c07396b138d08ca1822ced2986d5c3a3364e09134fe67e47b75dd5fc118d06`.
No forced MTP-crash property or persistent diagnostic wrapper remains. The
final build commands contain `TW_NO_SCREEN_BLANK` for the GUI/fbdev objects and
`USB_MTP_DEVICE=\"/dev/mtp_usb\"` for the MTP library. The old branch's
optional `host_init_verifier` could not link because its own static
`libselinux` omits `selinux_status_getenforce`; this did not alter the sealed
artifact. Source validation, shell syntax, extracted rc review, boot-header
inspection, the checksum manifest, partition-size gate and two-pass
reproducibility checks all pass.

The handset test rejects v8. It showed the Meizu logo, never reached the TWRP
GUI, and returned to Flyme. A complete recovery-partition acquisition has the
canonical 27,303,936-byte v8 image as its byte-identical prefix, so this was
not a stale or partial flash. `/proc/reset_reason` records an ordinary
software `reboot` at 19:29:15; panic, oops, watchdog and hardware-reset
counters remain zero. The 43-byte ramoops file contains only the NAND ECC
summary, and `/cache/recovery` contains nothing from this attempt. Immutable
evidence and its verified checksum manifest are retained at
`artifacts/twrp-device-test-20260807-193330-full-source-v8` in the parent
Android workspace. V8 must not be tested again.

The next diagnostic therefore returns to the exact v7 image that displayed
the complete TWRP GUI and changes only `init.rc` and `sbin/recovery`. The
recovery ELF is extracted from the reproducible pre-v8 source build made after
`TW_NO_SCREEN_BLANK` was enabled, then receives the same exact
`sys.powerctl`-to-`twrp.loghold` diagnostic patch as v7. Its needed-library set
is identical to v7 and the only removed undefined symbol is `gr_fb_blank`,
which directly proves that timeout can no longer invoke FBIOBLANK.

The v7 boot log also identifies the legacy ADB failure: init starts adbd before
properties exist, fails to expand the absent `ro.serialno`, and then the
`ro.debuggable` and `service.adb.root` actions kill it twice. V9 removes those
competing actions, leaves FunctionFS unmounted so the retained 598,600-byte
adbd uses `/dev/android_adb`, disables MTP, and configures one post-property
ADB gadget as `18d1:4ee7` with serial `PRO5TWRPV9`. This follows the legacy
`android_usb` arrangement used by the TeamWin Exynos 7420 zeroflte/noblelte
trees while accounting for the PRO 5 recovery's empty serial property.

Two clean v9 ramdisk and image repacks are byte-identical. The resulting
29,335,552-byte image is retained at
`artifacts/twrp-bootdiag-20260807-195753-legacy-adb-v9/recovery.img` with
SHA-256
`342c788c2bccc12d6af7717a90cbcf48ee9bda11494cdc37c318e7031ba0a760`.
The kernel, command-refresh display library, old adbd, wrapper, all other
payloads, all 489 cpio paths, metadata, order, archive tail and boot geometry
remain v7.

The handset test rejects v9. The TWRP UI remained touch-responsive but still
went black, and the host saw no USB device or ADB serial. The owner clarified
that blackouts also occur while touch interaction is continuous, so the normal
idle timeout is not the root cause. `TW_NO_SCREEN_BLANK` still removes only the
`gr_fb_blank()` calls, but the remaining timer behavior cannot explain an
interaction-time failure. V9 must not be tested again.

The maintained tree now also sets `TW_NO_SCREEN_TIMEOUT`, which compiles out
the complete dim/brightness-zero/blank/unblank timeout state machine. A new
fully clean source build produced the same 27,303,936-byte recovery image in
both passes, SHA-256
`faff297b31eab8aa1a6b85b31e801d72d0bc512cdee6850bd6d0451749013d31`.
Its extracted 935,160-byte recovery ELF has SHA-256
`fb86468df29070d51ec2ce63466cfb49249fac94d4c5a1e59b84fff127968678`
and contains neither `/sbin/postscreenblank.sh` nor
`/sbin/postscreenunblank.sh`. This is the v10 recovery donor only; the full
source image and generated DTB are not handset candidates.

V10 again starts from the exact handset-proven v7 image and changes only
`init.rc` and `sbin/recovery`. The donor recovery receives the exact
`sys.powerctl`-to-`twrp.loghold` patch and has SHA-256
`ee950be58363bd499c43af37464453ed6af8d3a50cf102855cc1b8ca5b63f079`.
The old static adbd and `/dev/android_adb` transport are retained. Init now
configures `18d1:4ee7`, serial `PRO5TWRPV10`, and starts adbd directly from the
boot action; there are no `sys.usb.config` actions, FunctionFS mounts or adbd
restart races. MTP remains disabled for this isolation.

Two v10 ramdisk and image repacks are byte-identical. The resulting
29,335,552-byte test image is retained at
`artifacts/twrp-bootdiag-20260807-233936-direct-adb-v10/recovery.img` with
SHA-256
`6d1455bd633e439158df6b13602cc26344eeea0bdcc56ac7614ceaef35fc5690`.
All 489 cpio paths, order and metadata, the v7 kernel, command-refresh display
library, old adbd, diagnostic wrapper, fstab and boot geometry are unchanged.
The continuous-touch clarification arrived before this image was handset-
tested. V10 is therefore superseded and must not be flashed.

## Pre-copy VSYNC pacing v11

V7's forced-single-buffer path calls `FBIOPAN_DISPLAY` after every changed
frame. The m86 kernel implements that request through the full
`decon_set_par()` path: it rewrites live window state, toggles the command-mode
hardware trigger, and waits for VSYNC. Continuous touch increases the redraw
and PAN rate, matching the observed interaction-time blackouts better than an
idle timer does.

Disassembly of the old working TWRP's `libminuitwrp.so` provides a concrete
ordering reference. Its single-buffer flip executes `FBIO_WAITFORVSYNC`, then
copies the draw surface into the active framebuffer page, then issues
`FBIOPAN_DISPLAY`. V7 omitted the pre-copy wait. Patch
`0005-fbdev-wait-for-vsync-before-single-buffer-copy.patch` restores that
ordering under `RECOVERY_GRAPHICS_FORCE_SINGLE_BUFFER`; a failed wait is logged
and the kernel's bounded VSYNC timeout prevents an unlimited userspace wait.

Two fully clean source builds produced the same 27,308,032-byte donor recovery,
SHA-256
`bdfc2aa9ac4401614572d92c48eb72a2151dacf569ee95b09032e062376e4697`.
Its 398,968-byte `libminuitwrp.so` has SHA-256
`14efd5195e0379669656d0866adcedaa6030a645b7071056ff08437386e682c0`
and contains the page-zero, PAN-refresh, and pre-copy-VSYNC markers. The v10
and v11 libraries have identical sets of 839 dynamic symbol names and the same
ten needed libraries.

V11 starts from the exact untested v10 image and changes only the data payload
of `sbin/libminuitwrp.so`. It intentionally keeps the timeout-disabled recovery
ELF and direct legacy ADB init unchanged, so the sole v11 variable is display
flip pacing. The ADB identity remains `18d1:4ee7` / `PRO5TWRPV10`, the
598,600-byte old adbd remains on `/dev/android_adb`, and MTP remains disabled.
All 489 cpio paths, order and metadata, kernel, init, recovery ELF, wrapper,
fstab and boot geometry remain unchanged. Two ramdisk and image repacks are
byte-identical.

The resulting 29,335,552-byte test image is retained at
`artifacts/twrp-bootdiag-20260808-000625-precopy-vsync-v11-final/recovery.img`
with SHA-256
`8e88e946ce04efe2ccc006147c7da654ad14d9c6c3cb0eb2c610067a72e327d8`.
Independent inspection confirms the stock-derived kernel SHA-256
`5df2fd06a58635c0299f10686c715a35fbc7ba0169bf9ffccdb292bba42c7d04`,
zero embedded DTB, valid conditional-DTB image ID, no trailing bytes, and a
4,218,880-byte margin below the recovery partition size. This is still a
device-test candidate, not final acceptance.

The handset test rejects v11. The exact 29,335,552-byte v11 artifact is the
prefix of the recovery-partition acquisition, so the result is not a stale or
partial flash. The TWRP UI still turned black during continuous interaction
and touch remained active, while the host never enumerated a recovery USB
device or ADB serial. The owner returned to Flyme. Reset storage contains no
panic, oops or watchdog event. `/cache/recovery` contains only older TWRP 3.0
logs rather than a current v11 diagnostic, and pstore belongs to the following
Flyme boot; neither may be represented as a v11 runtime log.

## Legacy framebuffer initialization v12

The initial disassembly reading suggested that the known-working TWRP 3.0
`libminuitwrp.so` kept kernel geometry without an initialization-time
`FBIOPUT_VSCREENINFO`. Patch
`0006-fbdev-match-legacy-single-buffer-pan-contract.patch` therefore
suppresses the late synthesized mode request while retaining page-zero PAN
refresh and pre-copy VSYNC. A later instruction-level audit corrected that
first conclusion: the old library performs a separate early forced mode replay
immediately after `FBIOGET_VSCREENINFO`; this is addressed by v16 below.

Two clean source builds produced the same 27,303,936-byte donor recovery,
SHA-256
`331087361e2bd02f7628793d7361117df52ba0184329961b509ad82a25db6471`.
Its 398,976-byte `libminuitwrp.so` has SHA-256
`84ce54a1df62e76ef58838edb3b94a200f0eb3f4ce05aeaad68265783826b0ed`.
V12 applies only that library to the exact partition-proven v11 image. Its two
repacks are byte-identical; the resulting 29,335,552-byte image has SHA-256
`4e4320b297c3ca086a697f488f0ddaca5017f62e40512fb1b980eb2f2b642463`
and ramdisk SHA-256
`a5644b67e806609aec4dcb3c5f46e1cbe0658312eec981bdcdc9271d0cbad5e1`.
The handset test rejects v12. The top of the panel showed a white line, while
changing to a new TWRP page could restore a complete frame only temporarily.
The exact v12 image remains the audited v13 base and the v16 single-variable
base, but must not be reflashed as a candidate.

## Note5-style lightweight PAN and ready-first ADB v13

The contemporary Galaxy Note 5 recovery implementation is applicable at the
DECON transaction level because both devices use Exynos 7420 command-mode
display hardware. Its `decon_pan_display()` returns while the controller is
off, updates the scanout address, triggers the transfer and waits for VSYNC;
it does not call `decon_set_par()` for every frame. The PRO 5 path did call
the full mode-setting function for every TWRP PAN. The maintained kernel now
uses the Note5-style lightweight PAN transaction. The Note5 BoardConfig and
panel description are not copied: its resolution, pixel format, brightness
path and recovery buffering policy are device-specific.

The new kernel was produced by two fully clean source builds. Both generated
the same 27,303,936-byte donor recovery with SHA-256
`dba0bf646c2e82a480c02fca94bb430cd7b2f6f902a5b00899224f2f73dc6a48`
and the same 17,239,832-byte kernel with SHA-256
`aac6338d2b64f49e2988215fff186a2f229fc7d6e2545f7d9178ff307835a5e5`.
This is a complete maintained-kernel replacement relative to v12, including
the earlier pstore/ramoops corrections as well as the PAN change; it is not
claimed to be a binary one-instruction kernel substitution.

V13 also changes the exact v12 `init.rc` and `sbin/permissive.sh` data while
preserving all 489 cpio paths, order, metadata and archive tail. Old minadbd
continues to use `/dev/android_adb`. Init starts it with the gadget disabled;
the wrapper waits up to ten seconds for the kernel `adb_open` marker before it
publishes ADB-only `2a45:0c01`, serial `PRO5TWRPV13`. If the first state stays
`DISCONNECTED`, it performs one disabled-to-enabled reconnect edge without
restarting adbd. Gadget attributes, device nodes and the adbd process are
recorded every five seconds in synchronously mounted cache evidence, even when
host enumeration never succeeds.

Two v13 ramdisk and recovery repacks are byte-identical. The final test image
is 29,351,936 bytes with SHA-256
`96c066af2d1c03f82c868c9e4eb77b63dce66f6c0f770a79423821db3ee964ad`;
its 12,104,815-byte gzip ramdisk has SHA-256
`ceace4e0d220f94f63417f88349fe602fcf2468ab7898d6264729e8296a8de35`.
It has no embedded DTB, uses the conditional-DTB image ID, has no trailing
bytes and leaves 4,202,496 bytes below the physical recovery-partition size.
V13 is a controlled combined device-test candidate, not final acceptance.

The handset test rejects v13. It stayed on the Meizu logo and never exposed a
recovery USB device before returning to Flyme. The 33,554,432-byte recovery
partition acquisition has the exact v13 artifact as its first 29,351,936
bytes, proving that the result is not a stale or partial flash.

No `pro5-twrp-diag-v13-*` file exists. The retained `last_log` predates the
test and the newly touched `last_log.gz` is empty, so the ready-first ADB
wrapper did not reach its first persistent stage. Pstore contains only the
43-byte NAND ECC summary from the following Flyme boot. Reset storage reports
`system wreset` count 4 with zero panic, oops and dedicated watchdog counters.
The evidence is retained at
`artifacts/twrp-device-test-20260808-0055-note5-pan-ready-adb-v13`.

V8 and v13 both used the later maintained kernel containing pstore/ramoops
changes and both stopped at the Meizu logo before useful userspace evidence.
The Note5 PAN hypothesis is therefore not yet rejected: v13 changed the entire
kernel rather than only that path. The next display candidate restores the
four pstore/ramoops files and defconfig from revision
`52bb509cf2ba6a8a21107080bfdedb5219ead70d`, which produced the v11 kernel
baseline already proven to reach TWRP, while retaining only the current
Note5-style PAN change. Its ramdisk must remain byte-identical to v11 so ADB
changes are deferred until this kernel boots.

## V11-baseline lightweight PAN v14

The isolated source build completed twice from empty output directories. The
four pre-pstore files match fixed hashes from revision
`52bb509cf2ba6a8a21107080bfdedb5219ead70d`; after excluding those restored
files, the only kernel source path changed from the v11 baseline is
`drivers/video/exynos/decon/decon-int_drv.c`. Both clean builds produced the
same 27,287,552-byte donor recovery with SHA-256
`02856bae0eb1e8ca4718b480e0adc8909852cdb410811ff5e331eeb90b2979cc`
and the same 17,222,424-byte kernel with SHA-256
`7cb5b99f6ec849b4ab7b5508964ddb4641fede416cd8ab8611643f0bc6e454ff`.
The generated config and DTB are also byte-identical across both passes.

V14 starts from the exact partition-proven v11 image and changes only its
kernel component. Its complete 12,104,105-byte gzip ramdisk remains
byte-identical, SHA-256
`7364783467cc5011d48ea9314acd8217223b05ebe3d2784e3e145d4467a590e4`.
Consequently v11's pre-copy VSYNC display library, timeout-disabled recovery
ELF, direct legacy ADB init, old adbd, v4 synchronous wrapper, fstab and every
other userspace byte remain unchanged. V14 deliberately does not include the
v12 initialization or v13 USB changes.

Two kernel-only repacks are byte-identical. The resulting 29,335,552-byte v14
image has SHA-256
`ddc37377309011ad5954afb85c8ab1f58d0ec958adacb9c7fce0ef6fd721b9bc`,
uses the conditional-DTB image ID, embeds no DTB, contains no trailing bytes
and leaves 4,218,880 bytes below the physical recovery partition. It is a
display-only device-test candidate, not final acceptance.

The handset test also rejects v14: it reached the complete UI but still turned
black, then lost touch feedback and returned to Flyme. Removing
`decon_set_par()` from PAN is therefore not sufficient.

## Legacy forced-mode initialization v16

Fresh disassembly of the known-working TWRP 3.0 library proves its exact
single-buffer initialization order. Immediately after
`FBIOGET_VSCREENINFO`, it clears `vi.vmode`, sets
`vi.activate = FB_ACTIVATE_FORCE`, and submits the otherwise kernel-provided
structure with `FBIOPUT_VSCREENINFO`. Only then does it query
`FBIOGET_FSCREENINFO`, mmap and clear framebuffer memory. Its changed-frame
path remains `FBIO_WAITFORVSYNC`, copy, then `FBIOPAN_DISPLAY`.

Patch `0007-fbdev-replay-legacy-force-mode-init.patch` reproduces that early
one-time transaction. It deliberately retains v12's suppression of the later
synthesized mode request, its single page and its paced PAN loop. Two clean
source builds produced an identical 27,303,936-byte donor image. The extracted
398,976-byte `libminuitwrp.so` has SHA-256
`9f77e4ef45c36d85b20e4e502e9f4a3e5de5f2467d0a27ad97ef36ec54eca18b`.

V16 applies only that library to the exact v12 image. Its original kernel,
init, recovery executable, ADB setup, wrapper, fstab, ramdisk path order and
boot geometry remain unchanged. Two ramdisk and recovery repacks are
byte-identical. The 29,335,552-byte result has SHA-256
`7c92a6268b0c4d57dc94b3382ea9cbae7c9c1e6ee74866d6ce611d026e9691d4`,
embeds no DTB and leaves 4,218,880 bytes below the recovery partition size.

## Flyme USB identity v17

The running Flyme system enumerates on the host as `2a45:0c02`, manufacturer
`Meizu`, product `M86`, with USB and ADB serial `860BDNA2225S`. At the owner's
request, v17 publishes those exact descriptors while retaining the direct
legacy ADB-only function. This intentionally uses Flyme's MTP+ADB PID with an
ADB-only recovery function as a descriptor-matching diagnostic; it does not
enable MTP.

V17 starts from the exact v16 image and changes only the `init.rc` data
payload. Its kernel, `libminuitwrp.so`, recovery executable, old adbd, wrapper,
fstab, remaining ramdisk entries and boot geometry remain unchanged. Both
clean repacks are byte-identical. The 29,335,552-byte image has SHA-256
`e7d17b0dc4bd0136bb9338a2263f1bad602c75d3d0db123a9e6e512b804c6cda`,
embeds no DTB and leaves 4,218,880 bytes below the recovery partition size.

The v17 handset test did not expose any USB device to macOS. Repeated host
samples found neither `2a45:0c02` nor the expected serial and `adb devices -l`
remained empty. This is below the ADB protocol layer: the host never received
even the USB device descriptor.

Recovery-start dmesg from v3 through v7 consistently reports
`fusb302 check status 2`, which is the driver's `Unattached` state. It contains
no `USB_HOST_ATTACH`, `usb host/cdp`, or `Turn on gadget` event. Flyme boot
logs on the same handset and cable do contain the complete sequence from MUIC
host attach through `dwc3 ... Turn on gadget` and successful gadget
configuration. In `drivers/usb/gadget/android.c`, userspace's write of
`android0/enable=1` only called `dwc3_exynos_vbus_event(NULL, 1)` when the
missing MUIC notification had already set `usb_attach`. Recovery therefore
could not enumerate regardless of the selected VID/PID or adbd binary.

## Forced DWC3 gadget session v18

V18 isolates that missing kernel transition. It starts from the revision that
produced the v11/v17 kernel and applies one patch only to
`drivers/usb/gadget/android.c`: when userspace explicitly enables
`android_usb`, the driver now acquires the gadget wake lock and sends the DWC3
VBUS-on event even when MUIC left `usb_attach` false. The existing ADB
`disable_depth` handshake remains unchanged, so the composite configuration
still connects only after old adbd opens `/dev/android_adb`.

The exact baseline display source is retained with SHA-256
`455f1e7f71eafb4f4516c789a28fa3c90f3880a3a484c54d3a8dfd19f44112d0`.
Two clean source builds produced byte-identical recovery images, DTBs and
kernel configs. The donor kernel is 17,222,424 bytes with SHA-256
`959b97010805584b9935ba2004a684b9330b76de82a5ac911ee876d3f38e9b38`.

V18 replaces only the kernel component in the exact v17 image. The complete
12,104,206-byte ramdisk remains byte-identical to v17 with SHA-256
`ffed93c7672f8b56e83610bd7a983e10f27e8394ce1c718293b8844a93100b64`.
Consequently the `2a45:0c02` identity, serial `860BDNA2225S`, ADB-only
function, old adbd, v16 display library, recovery executable, wrapper, fstab
and every other userspace byte are unchanged. Two kernel-only repacks are
byte-identical. The final 29,335,552-byte v18 image has SHA-256
`975710e9214f8c471791748e42029c623ecb6b9a35e6fc6c856c4a6c77d0943f`,
embeds no DTB and leaves 4,218,880 bytes below the recovery partition size.
It is an enumeration-first diagnostic, not final recovery acceptance.

The handset test accepts the v18 USB change. macOS enumerated `2a45:0c02`
with serial `860BDNA2225S`, and `adb devices -l` reported the recovery as
`device`, product `PRO5`, device `m86`. Both `/sbin/adbd` and
`/sbin/recovery` remained alive during an extended live capture. This proves
that the previous failure was below the ADB protocol layer and that forcing
the DWC3 gadget VBUS session repairs it.

ADB made the blackout measurable without relying on retained logs. During a
black frame, fb0 remained 1080x1920 at 32 bpp, the PWM backlight reported
brightness and actual brightness 255 with `bl_power=0`, and recovery remained
touch-responsive. At the same time
`/sys/devices/13930000.decon_fb/decon_state` reported `lpd` and the DSIM
runtime state was `suspended`. Writing the unchanged page-zero PAN coordinates
to fb0 immediately changed DECON to `on` and advanced the VSYNC timestamp. It
then re-entered LPD and suspended DSIM about 70 milliseconds later. Dmesg
records the matching `decon_runtime_resume`, framebuffer parameter replay and
`decon_runtime_suspend` sequence. This is a direct causal probe: the current
blackout is DECON low-power entry, not TWRP timeout, a blanked backlight, lost
framebuffer contents, touch failure, MTP failure or recovery-process death.
The live evidence is retained in
`artifacts/twrp-device-live-20260808-v18-screen-debug`.

## Recovery kernel with DECON LPD disabled v19

V19 preserves the now-proven v18 USB path and changes one kernel configuration
bit only: `CONFIG_DECON_LPD_DISPLAY` is disabled. This uses the kernel's own
compile-time boundary around the DECON LPD worker and entry/exit machinery;
panel timing, framebuffer geometry, PAN, backlight and DSIM source code remain
unchanged. This is a recovery-specific mitigation based on the live causal
probe, not a claim that the old working recovery kernel never contained LPD
support.

The no-LPD donor was built twice from clean output using profile
`pre-pstore-usb-vbus-no-lpd`. Both 27,287,552-byte recovery images have
SHA-256
`7ce879901169990f8aea6fa48ca436e16bd15345e6634b4384cd4a6237fb4614`;
their 17,222,424-byte kernels have SHA-256
`45474fdcdd7f354b81e18d4aa13704d9d990838ff562f1625c6ba11f7c036d21`.
The DTB and generated kernel config are also byte-identical across both
passes. The generated config has SHA-256
`d8a081e100d581447fba72990cc3f2d738c0a18a3e6bba6f4fef51730ba5f909`
and explicitly records `# CONFIG_DECON_LPD_DISPLAY is not set`.

V19 replaces only the kernel component in the exact v18 image. Its complete
12,104,206-byte ramdisk remains byte-identical with SHA-256
`ffed93c7672f8b56e83610bd7a983e10f27e8394ce1c718293b8844a93100b64`.
Thus the forced-DWC3 USB fix, `2a45:0c02`, serial `860BDNA2225S`, old adbd,
v16 minui library, recovery executable, wrapper, fstab and all remaining
userspace bytes are unchanged. Two kernel-only repacks are byte-identical.
The resulting 29,335,552-byte image has SHA-256
`aa366fe911ccb31a71bf4ee3213a644b1973bb90229e243d4c9eaa76bb99902e`,
embeds no DTB and leaves 4,218,880 bytes below the recovery partition size.
It is a focused display test candidate, not final recovery acceptance.

The first v19 live test confirms that the intended kernel is running:
`/proc/config.gz` reports `# CONFIG_DECON_LPD_DISPLAY is not set`, while ADB
enumerates as the retained `860BDNA2225S` serial. From kernel uptime 66.01 to
288.73 seconds, 180 consecutive samples all report DECON state `on`, DECON
runtime `active`, DSIM runtime `active`, brightness and actual brightness 255,
`bl_power=0`, and both recovery and adbd alive. Every sampled VSYNC timestamp
increases. The complete dmesg through uptime 312 seconds contains no LPD
entry, `decon_runtime_suspend`, panic, oops, watchdog bite, I/O error or
timeout. At the end, DECON and DSIM remain active and the recovery log records
continued harmless navigation among main, advanced, reboot, install, mount
and wipe pages. This accepts the kernel-side LPD isolation and retained ADB
path; final visual acceptance still requires the owner to confirm that the
physical panel did not black out. Evidence is retained in
`artifacts/twrp-device-live-20260808-v19-no-lpd-screen-debug`.

## Functional MTP and reboot cleanup v20

The v19 runtime audit identifies both reported functional failures as retained
diagnostic overrides rather than new kernel faults. Its `init.rc` explicitly
sets `mtp.crash_check=1`, so TWRP prints that MTP crashed and deliberately does
not create its MTP server even though `/dev/mtp_usb`, the kernel MTP function
and both TWRP MTP libraries are present. Its recovery ELF also contains
`twrp.loghold` in place of the original `sys.powerctl` literal. That exact
12-byte diagnostic substitution prevented early tests from leaving Recovery,
but it also makes ordinary system, recovery, bootloader and power-off menu
requests inert. The synchronous cache wrapper remains the recovery service,
accounting for its wrapper and periodic-sync shell processes.

A reversible live v19 probe disabled the gadget, selected `mtp,adb`, waited
12 seconds and restored `adb`. The kernel logged `mtp_bind_config`, bound
`mtp[0]` and `adb[1]`, reached `USB_STATE=CONFIGURED`, macOS re-enumerated the
same `2a45:0c02` / `860BDNA2225S` device and ADB reconnected in composite mode.
The automatic rollback then restored ADB-only and ADB reconnected again. This
accepts the kernel, DWC3-session fix, descriptor and legacy transport portions
of the MTP path before changing userspace.

V20 starts from the exact v19 image and changes only two existing ramdisk data
payloads. `init.rc` no longer sets the MTP crash flag, implements reversible
`none`, `adb` and `mtp,adb` actions around the proven Meizu identity, launches
`/sbin/recovery` directly and restores the old working m86 recovery's wildcard
`on property:sys.powerctl=*` contract. `sbin/recovery` is restored to the exact
unmodified, timeout-disabled ELF from the clean v10 donor, SHA-256
`fb86468df29070d51ec2ce63466cfb49249fac94d4c5a1e59b84fff127968678`.
It differs from v19's ELF only in the 12-byte `twrp.loghold` to
`sys.powerctl` literal and keeps the same dependencies and behavior otherwise.

All 489 cpio entries, entry order, metadata and archive tail remain identical;
only `init.rc` and `sbin/recovery` data change. Two gzip ramdisk rewrites are
byte-identical with SHA-256
`93ab8d2e3278779b19b20f584ffc3da76fdc8c7e8c9ad9a7af6ffb49534933cb`,
and two recovery repacks are byte-identical. The final 29,335,552-byte v20
image has SHA-256
`8bccf65784167228398ae96b372d67232948e2333f96e0407eb25faad52c4d13`.
Its v19 kernel, disabled DECON LPD, forced-DWC3 session, minui, old adbd, fstab,
stock-DTB boundary and remaining ramdisk data are unchanged.

The audit also classifies the remaining visible log lines. Failure to mount
`/external_sd` or `/usb-otg` is expected when no removable card or OTG block
device is connected. `indeterminate013` is the animation loader's terminating
probe after the twelve packaged frames, not a missing displayed asset. The
optional Audience audio-codec firmware is irrelevant to recovery storage,
display, touch and USB. These do not justify adding firmware, fabricating
storage presence or changing the now-proven kernel.

## Flashing boundary

Keep the stock Flyme 8 DTB in place. V6 through v19 are rejected, superseded,
or historical evidence and must not be flashed again; v19's display and USB
repairs are retained unchanged in v20. Write only the exact v20 `recovery.img` to the
`recovery` partition; do not write `dtb`, `bootimg`,
`/dev/block/sdb`, `ldfw`, or an identity/parameter partition. Do not mount,
wipe, format, install or restore during the first test. Keep USB attached and
first verify MTP plus ADB without rebooting. Test one reboot target at a time,
starting with system, and return to Recovery before testing recovery or
bootloader so each result remains attributable.
