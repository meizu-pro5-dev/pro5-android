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

The next diagnostic narrows that boundary further. Recovery SHA-256
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

If this image reaches the UI, the recovery executable stack is viable and the
failure lies in other complete-new-rootfs or Android 9 early-startup content.
If it stalls, the next discriminator is a small Android 9 dynamic-linker probe
that falls through to the known-working recovery, separating the linker/libc
ABI from the new recovery executable itself.

## Flashing boundary

Keep the stock Flyme 8 DTB in place. After explicit approval, flash only the
reviewed minimal-runtime `recovery.img` with SHA-256
`c391de4d77392a6c8f2f2012d44746d0b46d18e4585faf953587222a36a3766d`
to the `recovery` partition. Do not flash `dtb`, `bootimg`, `/dev/block/sdb`,
`ldfw`, or any identity/parameter partition.

After a successful start, collect read-only evidence before any mount or
write test:

```sh
adb shell getprop ro.twrp.version
adb shell getprop ro.product.device
adb shell dmesg > twrp-dmesg.txt
adb pull /tmp/recovery.log
```

If the image stalls, return to fastboot and restore the known-working recovery
image. Leave the stock DTB untouched in either outcome.
