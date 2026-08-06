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
