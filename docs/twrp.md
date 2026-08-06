# TWRP acceptance plan

## Source decision

The recovery target is a separate source-built TWRP checkout based on the
official minimal Omni manifest's `twrp-9.0` branch. At the design lock used to
author this tree:

- minimal manifest HEAD: `f3f57994a2aa2c92303df24bb01caff6850f7463`;
- TeamWin recovery HEAD: `90e5d9559065cfa8b2b9a5dbb1c5cb7a88f034fa`;
- reported recovery version: `3.7.0_9`.

The final build is governed by the generated `twrp-9.0-manifest.xml`, not by
these descriptive branch heads. The upstream sources are the
[minimal TWRP Omni manifest](https://github.com/minimal-manifest-twrp/platform_manifest_twrp_omni/tree/twrp-9.0)
and [TeamWin recovery](https://github.com/TeamWin/android_bootable_recovery/tree/android-9.0).

Each synchronized project is accepted only when its pinned `HEAD` tree, Git
index, and clean worktree contain the same complete file set. This caught a
previously interrupted `frameworks/base` checkout whose empty index had left
more than eleven thousand tracked files absent while `repo sync` still
reported success. The sync worker can rebuild only this precisely identified
empty-index state from the already-pinned commit; all other incomplete or
dirty states are rejected and retried through `repo`. Upstream's intentional
empty placeholder repositories remain valid when both the commit tree and
index contain zero paths.

The manifest's 32-bit AOSP Python 2.7.5 prebuilt does not ship a `zlib`
extension, although Pie host tools import compressed Python modules. Before
building, the worker compiles only this extension from the same manifest's
pinned `external/python/cpython2` source and exports it through `PYTHONPATH`.
The 32-bit compiler and zlib development ABI are explicit builder bootstrap
dependencies, and a compress/decompress round trip must pass before Soong is
started.

The official build FAQ normally maps a device that launched on Android 5.1 to
the Android 6.0 TWRP branch. For m86 that branch would also freeze recovery at
the 2016 TWRP 3.0 generation already represented by the old working image.
Using `twrp-9.0` is a deliberate compatibility exception: it retains the
legacy non-A/B, separate-recovery layout while providing the maintained
3.7.0_9 recovery code. Every function therefore remains a device-test gate;
branch selection alone is not evidence that a function works.

## Stock and blob boundary

The latest verified production base available to this port is Flyme
8.0.5.0A, Android 7 / API 24, archive SHA-256
`7d1585b86aaf8fd1ab6a5e12f8a3a50f9ed6a759d8f91d51ca1b1d4c13a77a28`.
All 219 current proprietary-file entries resolve byte-for-byte from that
image. Its partition names, FDE metadata location, boot header, display
driver, and removable-storage topology define this recovery tree.

Framebuffer, UFS, USB, microSD, dm-crypt and filesystems are provided by the
maintained kernel and open TWRP userspace. Recovery has one necessary Flyme
runtime blob: `vendor/firmware/st_fts.bin`, because the STM touch driver starts
an automatic firmware check after probe and requests `st_fts.bin`. The
65,568-byte Flyme 8 copy has SHA-256
`6362b3058217451a29638c6538ec2dc0f8910702679363bf0a4a96e11c63896d`;
it is byte-identical to the file in the previously booting TWRP 3.0 ramdisk.
The build injects this file from the verified off-Git stock dump and then
checks the copy embedded in `recovery.img`. It does not carry the old
recovery's Android 6 libraries, SuperSU payload, or prebuilt kernel.

Flyme stores legacy full-disk-encryption metadata in `/cache/metadata`. Its
Android 7 `vold` contains the cipher name `aes-xts-fmp`. TWRP 9 reads
`crypto_type_name` from that metadata and, on the normal dm-crypt path used by
m86, passes the name unchanged to the kernel. The maintained kernel's
`dm-crypt.c` recognizes `aes-xts-fmp` as the Exynos hardware-FMP path and the
defconfig enables `CONFIG_DM_CRYPT`, `CONFIG_FMP`, and
`CONFIG_UFS_FMP_DM_CRYPT`. `TARGET_HW_DISK_ENCRYPTION` is intentionally not
enabled: that TWRP switch selects the unrelated QCOM `cryptfs_hw` interface
and `req-crypt` target. This establishes a coherent static path, but the
actual handset metadata KDF and password/PIN decryption remain runtime gates
after backup access resumes.

Android 9 adbd first tries FunctionFS v2 descriptors and AIO, while this
Samsung 3.10 gadget accepts v1 descriptors and has no FunctionFS AIO support.
Both AOSP adbd and TWRP's MTP implementation contain v1/synchronous fallbacks;
the device rc selects them with `sys.usb.ffs.aio_compat=1`. It otherwise leaves
the FunctionFS mount and `sys.usb.config` state machine to upstream TWRP, so
there are no duplicate mounts or competing property actions. On m86, TWRP MTP
uses its `/dev/mtp_usb` fallback supplied by `CONFIG_USB_G_ANDROID`; ADB uses
the same gadget's FunctionFS function.

## Boot and partition contract

The recovery image must satisfy all of these static checks:

| Field | Required value |
| --- | --- |
| boot header | classic Android v0, empty name and command line |
| kernel | uncompressed ARM64 `Image`, address `0x40080000` |
| ramdisk | gzip, address `0x42000000` |
| second stage | size 0, address `0x40f00000` |
| tags | `0x40000100` |
| page size | 4096 bytes |
| embedded DT | size 0 |
| recovery image limit | at most 33,550,336 bytes |
| device tree | separate raw FDT containing `Meizu, M86` |

The one-page recovery reserve is conservative until the paused GPT backup is
resumed. A 32 MiB partition dump exists, but no artifact may consume the last
page merely on that historical evidence.

The normal recovery UI exposes `system`, `data`, `cache`, `custom`, `boot`,
`recovery`, `dtb`, `dtb_backup`, `bootlogo`, `efs`, `mnv`, `misc`, microSD and
USB OTG. EFS and MNV are mounted read-only and offered for backup, not wipe.
Only boot, recovery, DTB and system image are image-flash targets. The tree
does not expose `/dev/block/sdb`, bootloader, `ldfw`, `param`, `proinfo`,
`private`, or `rstinfo`.

## Functional acceptance

Static build acceptance requires:

1. two independently cleaned `omni_m86-eng recoveryimage` builds from the
   pinned manifest with fixed Android and kernel build identities/timestamps;
2. a generated `recovery.img` and matching raw m86 DTB;
3. passing boot-header, ramdisk, embedded STM firmware, FMP config, DTB and
   partition-size validators;
4. byte-identical recovery, DTB, and generated kernel-config hashes across two
   clean builds in the same absolute output path, recorded in
   `REPRODUCIBILITY.txt`;
5. retained manifest, local revision, generated kernel config, full log,
   stock lock and SHA-256 list.

The absolute output path is intentionally identical for both passes. Android's
ELF link inputs record intermediate paths, so using differently named pass
directories changes build IDs even when sources, environment, and timestamps
are identical. Pass 1 is copied to a small comparison snapshot, the stable
output directory is deleted and rebuilt, and only then are the three accepted
outputs compared byte for byte.

Two remaining ramdisk generators are normalized by reviewed patches. The
recovery make rule sorts both embedded `ramdisk-files` inventories with the C
locale because parallel installation otherwise changes their traversal order.
The SELinux rule invokes `sefcontext_compile -r`: PCRE2's serialized host
bytecode contains process-specific data, is not portable from the x86-64 host
to the ARM64 target, and changes between clean runs. Omitting that optional
payload is supported by the pinned loader, which compiles the retained regex
strings on first use. The exact patch series and patch payloads are retained
with every accepted artifact.

Full recovery acceptance additionally requires explicit authorization and
device evidence for:

1. boot, OLED display, touch coordinates, Home/Power keys, brightness and
   screen blank/unblank;
2. root ADB, shell, log retrieval and ADB sideload;
3. MTP on an unlocked internal store and reliable USB reconnect;
4. cache/system/custom mounts and read-only EFS/MNV backup;
5. Flyme legacy FDE password/PIN decryption through
   `/cache/metadata`, followed by internal `/data/media/0` access;
6. microSD and USB OTG discovery with FAT, exFAT and NTFS media;
7. backup and restore of data/system plus reviewed raw image partitions;
8. installation of the final LineageOS 17.1 ZIP, ZIP signature/digest paths,
   reboot to system/recovery/bootloader, battery percentage, temperature and
   correct clock;
9. rollback using the previously retained recovery and DTB images.

No phone write is part of the build workflow. Static acceptance will be
completed first; flashing and the functional matrix begin only after the user
approves the exact artifacts and commands.
