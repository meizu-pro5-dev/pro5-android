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
device-specific setting. It is a strong correction, not proof of a boot,
until the resulting image is tested on the handset.

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
byte-identical outputs. The corrected image is a new, untested device
candidate rather than an accepted recovery:

| Artifact | Size | SHA-256 | Partition margin |
| --- | ---: | --- | ---: |
| `twrp-20260807-124903-recoveryimage/recovery.img` | 27,308,032 | `8c20eaa5301a9c70ad363cd765d5ba4cf33be69a37fc3f6a88d9b8cca5b07ca9` | 6,242,304 |

It must be tested with the verified stock Flyme 8 DTB. If it starts, collect
display, touch, ADB, `/tmp/recovery.log`, `dmesg` and `/sys/fs/pstore`
evidence before any writable mount. If it still stalls, restore and boot the
known-working recovery before starting Flyme, then copy any new
`console-ramoops*` file. A kernel panic, a userspace log, and an absent pstore
record lead to different next steps and must not be collapsed into the same
"Meizu logo" result.

## Old-content load-envelope control

The next diagnostic uses only the reconfirmed working recovery's kernel,
header and gzip userspace. Zero bytes follow its valid gzip stream inside the
header-declared ramdisk. Linux 3.10's `unpack_to_rootfs` explicitly skips NUL
bytes after a compressed archive, and the decompressed cpio remains
byte-identical to the working ramdisk.

The control is at least as demanding as the failed LZMA candidate on every
bootloader load dimension: its kernel is 17,512,240 bytes versus 17,222,424,
its ramdisk is exactly the same 10,058,368 bytes, and its complete image is
27,578,368 bytes versus 27,287,552. Its recovery SHA-256 is
`09fd948512af17275fed9e8167a66e8e66da15349960ba78d5a66c68960ca942`.

- If it boots, image size and bootloader component-load size are excluded;
  isolate the maintained kernel next.
- If it stalls, bracket the image/component boundary before changing init or
  userspace.

This control remains retained but is no longer the first test after the exact
display-handoff omission was found. If the corrected source candidate still
stalls without useful pstore evidence, run this all-old-content control next;
its result still cleanly accepts or rejects the bootloader load-envelope
hypothesis.

## Flashing boundary

Keep the stock Flyme 8 DTB in place. Flash only the reviewed diagnostic file
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
