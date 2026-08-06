# Verified stock base

The compatibility base is the locally retained Flyme 8.0.5.0A full OTA:

- source: `/Users/kophapro/Projects/Android/work/pro5-flyme-8.0.5.0A/update.zip`
- archive size: 1,596,746,506 bytes
- archive SHA-256: `7d1585b86aaf8fd1ab6a5e12f8a3a50f9ed6a759d8f91d51ca1b1d4c13a77a28`
- stock Android: 7.0 / API 24
- display ID: Flyme 8.0.5.0A
- fingerprint: `Meizu/meizu_PRO5/PRO5:7.0/NRD90M/m86.Flyme_8.0.1594148303:user/release-keys`
- product model/device: PRO 5 / PRO5
- platform property: `exynos5`

All member and reconstructed-image hashes used by the port are recorded in
`locks/stock-flyme-8.0.5.0A.sha256`.

## Boot and partition facts

The stock `boot.img` is 17,010,960 bytes. The host identifies an Android boot
image with kernel address `0x40080000`, ramdisk address `0x42000000`, and 4096
byte pages. The device uses a separate `dtb` partition; the OTA does not append
that DTB to `boot.img`.

Read-only extraction confirms a 15,522,064-byte uncompressed ARM64 `Image`, a
1,481,903-byte gzip ramdisk, and empty second-stage and DT sections. The stock
ramdisk imports `init.m86.rc` through `ro.hardware`, contains `fstab.m86`, and
defines the UFS `misc` partition. Its data entry is both `formattable` and
`encryptable=/cache/metadata`; the Android 10 baseline preserves those facts.
Hashes for the extracted kernel, compressed/uncompressed ramdisk, fstab, and
device-specific rc files are recorded in the stock lock.

The verified updater script addresses UFS partitions below
`/dev/block/platform/15570000.ufs/by-name/`:

- `system`
- `bootimg`
- `bootlogo`
- `ldfw`
- `dtb`
- `recovery`
- `custom`

It also writes the stock `bootloader` payload directly to `/dev/block/sdb`.
Custom recovery/ROM packaging must never reproduce that write. Initial
bring-up artifacts are limited to explicitly reviewed `bootimg`, `dtb`, and
`recovery` images, with size and hash checks before any flashing is resumed.

The reconstructed ext4 system image is 2,484,350,976 bytes. It is the source
for proprietary-file inventory and ABI inspection; it is not copied into the
source repository.

The seed blob list can be checked without mounting or modifying the image:

```bash
PYTHONPATH=../work/pro5-flyme-8.0.5.0A/python-deps \
  ./tools/audit-proprietary-files.py \
  ../work/pro5-flyme-8.0.5.0A/extracted/system.img \
  vendor/meizu/m86/proprietary-files.txt
```

The script exits nonzero while any seed entry is absent, so the audit can be
used as a bring-up gate once the inventory is reconciled.

The imported CM 14.1 seed contained 226 unique paths. The Flyme 8 audit found
202 at the same paths, four Mobicore libraries relocated under `vendor/lib`
and `vendor/lib64`, and 20 legacy files no longer shipped by Meizu. The
path-reconciled inventory contained 206 unique entries and all 206 resolved in
the verified image. ELF analysis then added 13 direct private/legacy
dependencies used by the stock camera, display-effect, and audio-effect
binaries, producing 219 verified source paths. Removed entries are not
silently sourced from an older OTA; any future need for one must be
demonstrated by runtime evidence and recorded as an explicit compatibility
exception.
