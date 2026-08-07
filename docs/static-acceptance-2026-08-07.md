# Static acceptance record — 2026-08-07

This record closes the build-only gate for the first Meizu PRO 5 Android 10
bring-up artifacts. It does not close any handset runtime or release gate.
Phone backup and flashing remain paused.

## LineageOS 17.1

The accepted `lineage_m86-userdebug bacon` build was produced from local
revision `4edc8954da03f9e2fa950838d5e7670a4c12f5d0` and retained locally at
`../artifacts/pro5-lineage-20260807-101323-bacon` relative to this repository.
The artifact metadata records Flyme 8.0.5.0A as the stock base and 219
hash-locked proprietary inputs.

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `lineage-17.1-20260807-UNOFFICIAL-m86.zip` | 640,976,020 | `f18f666f4279341ff33847d967ac5f1841f42acd2ba78ae71ed47eea40d8ecb8` |
| `lineage_m86-target_files-pro5-a10-20260806.zip` | 1,546,315,665 | `b6a98b9c30ca8a11b79342832faa12fbc9942a457e1870f198574a32a3471524` |
| `boot.img` | 18,022,400 | `d7c21806c56c9f24fdab389baa71455b4d145744a33de0af3d43b6bfe79b97b4` |
| `recovery.img` | 27,021,312 | `e16ea92a3deb6d36d007538c9a374e710583e4d3efd6cb080a571e46d5f3c31d` |
| `system.img` | 1,584,288,252 | `da90337523eb3a688fc1d15ee8714be088e4c4b688eb52cf457c79f0bdfda81a` |
| `dtb.img` | 146,172 | `0b537be248ed155a925d58c9a6b927ec1c4cdfaa0624ea714e848abddfba7d84` |

Static checks passed:

- the complete build, framework VINTF check, SELinux policy compilation,
  target-files generation, full block OTA generation and test-key signing;
- filesystem creation and read-only `e2fsck` checks for system and userdata;
- v0 boot/recovery headers, empty header command line, gzip ramdisks, verified
  addresses, partition limits and a separate raw m86 DTB;
- the generated kernel config and restored exFAT objects;
- camera HAL/core symbol closure and the Android 10 fingerprint HIDL output;
- all 219 locked Flyme files present in the final installed system tree and
  byte-identical to their staged inputs;
- OTA ZIP and target-files ZIP integrity plus every retained SHA-256 entry;
- OTA writes limited to the reviewed `system`, `bootimg`, and `dtb` targets,
  with no bootloader, `ldfw`, boot-logo, backup-DTB, or identity payload.

The cache/GPT geometry is still unavailable because device backup is paused.
The accepted package is therefore a full OTA only. Its metadata says
`ota-required-cache=0`; the system transfer list contains only `new`, `zero`,
and `erase` operations, with no source diff, move, or stash operation. The
checked-in releasetools guard rejects incremental block OTA generation until
the actual PRO 5 cache size is recorded.

## TWRP 3.7.0_9

The accepted `omni_m86-eng recoveryimage` artifact is retained locally at
`../artifacts/twrp-20260807-083954-recoveryimage` relative to this repository.
It was built from local revision
`f360d79c9e4ffb765027e903bec0b4dc499fe8ce` twice after independently cleaning
the same absolute output directory.

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `recovery.img` | 33,325,056 | `15512623bd62ddf7fee3517267cb56338a1e47ef4f8c76dfe87bc2c1be5490dc` |
| `exynos7420-m86-codegen.dtb` | 146,172 | `0b537be248ed155a925d58c9a6b927ec1c4cdfaa0624ea714e848abddfba7d84` |
| generated kernel config | 99,953 | `33b578b5be3fd51f6048ab6305d65e37bf2a2dfa31d980bdc5f782aca4f647d2` |

Both clean passes produced byte-identical recovery, DTB, and generated kernel
config. The image inspector found the configured ADB/sideload, MTP, legacy FDE
and e4crypt paths, `exfat-fuse`, `fsck.exfat`, NTFS support, recovery fstab,
init services, pigz-owned gzip links, and the embedded STM touch firmware. The
only proprietary TWRP runtime input is `etc/firmware/st_fts.bin`, SHA-256
`6362b3058217451a29638c6538ec2dc0f8910702679363bf0a4a96e11c63896d`.

## Remaining gates

Neither artifact is a release or daily-driver claim. The Android kernel still
uses the named permissive bring-up command-line gate, the packages use test
keys, LineageOS 17.1 has a February 2023 security patch level, and the handset
has not supplied runtime logs. Explicit authorization and device evidence are
still required for:

1. TWRP display, touch, keys, brightness, ADB/sideload, MTP, mounts,
   encryption, removable storage, backup/restore, install and reboot paths;
2. kernel/init boot, Android UI, graphics, storage and suspend/resume;
3. radio/data, Wi-Fi, Bluetooth, audio, sensors, GPS, NFC, fingerprint and
   camera;
4. SELinux enforcing, verified cache geometry, incremental upgrade, thermal
   and battery soak, and rollback.

Only those runtime results can turn the current flashable, statically audited
images into a full-function acceptance claim.
