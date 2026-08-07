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

## Flashing boundary

Keep the stock Flyme 8 DTB in place. After explicit approval, flash only the
second ADB log-capture `recovery.img` with SHA-256
`34bed1046ecef38b13ca8eda20f97f1a0610af0c4fb4a3e3769fc6aaa73d8d4a`
to the `recovery` partition. Do not flash `dtb`, `bootimg`, `/dev/block/sdb`,
`ldfw`, or any identity/parameter partition. The expected visible result may
remain a black screen, but the handset should stay in the recovery init
environment instead of returning to Flyme.

After a successful start, collect read-only evidence before any mount or
write test:

```sh
adb wait-for-device
adb pull /tmp/recovery.log
adb shell dmesg > twrp-dmesg.txt
adb shell getprop > twrp-properties.txt
```

After the files are retained, use `adb reboot bootloader`; the diagnostic keeps
that exact power-control route enabled. Restore the known-working recovery if
needed. If ADB never enumerates, use the physical long-press/bootloader recovery
route. Leave the stock DTB untouched in every outcome.
