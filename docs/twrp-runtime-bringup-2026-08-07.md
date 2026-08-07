# PRO 5 TWRP runtime bring-up, 2026-08-07

## Observed results

The reproducible TWRP 3.7.0_9 source build did not reach the recovery UI, and
no recovery ADB evidence was collected. It stalled at the Meizu logo in both
combinations that were tested:

1. source-built `recovery.img` with the existing Flyme 8 DTB;
2. source-built `recovery.img` with the generated maintained-kernel DTB.

The handset owner then manually restored the Flyme 8.0.5.0A DTB. Flyme booted
normally. There was no automatic DTB rollback.

These observations reject the source-built recovery/DTB pair, but they do not
identify a single crashing instruction because no early console or recovery
ADB log was available. Static inspection also rules out the two most obvious
header theories:

- the Flyme 8 `bootimg` and source-built recovery both use
  `second_addr=0x40f00000`;
- the Flyme 8 boot header has a nonzero OS-version word, so a nonzero word is
  not by itself incompatible with the bootloader.

The strongest remaining boundary is the maintained recovery kernel and its
board/DTB contract. The new TWRP ramdisk still requires an independent runtime
test.

## Isolation image

The next test image is deliberately hybrid and test-only:

- kernel: byte-identical to the known-working TWRP kernel;
- header geometry and image-ID scheme: inherited from the known-working TWRP;
- ramdisk: byte-identical after decompression to the accepted TWRP 3.7.0_9
  ramdisk, recompressed with deterministic `gzip -9` so it fits;
- embedded DTB: none;
- required external DTB: stock Flyme 8.0.5.0A DTB;
- maximum recovery image size: 33,550,336 bytes, leaving one 4 KiB page below
  the confirmed 33,554,432-byte recovery partition.

This test has one decision boundary:

- if it boots, the new TWRP userspace/ramdisk can start on known-good kernel
  hardware support, and work should move to the maintained kernel/DTB path;
- if it stalls, investigate ramdisk/init compatibility or the much larger
  compressed/decompressed ramdisk before changing the DTB again.

It cannot satisfy final acceptance because its kernel is a provenance-locked
prebuilt from the known-working recovery rather than the maintained source
build.

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
