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
second failure left no recovery log in ramoops; the retained pstore record was
the preceding Flyme kernel's orderly reboot into recovery. Image/ramdisk size
and the new init/userspace remain the two live hypotheses.

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
