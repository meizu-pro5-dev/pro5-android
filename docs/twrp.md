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

The archived defconfig claimed a vendor `CONFIG_EXFAT_FS` implementation, but
the released m86 tree omitted its Kconfig and source. The missing GPL driver is
restored from a locked Linux 3.10 Exynos 7420 donor whose three functional
Kconfig symbols match the retained m86 selections, plus the RCU cache-teardown
fix already used by m86 FAT. The donor-only storage-log selection depended on
an unavailable `PROC_STLOG` implementation and is explicitly rejected as
stale. Android vold uses that kernel filesystem. Recovery deliberately also
builds TWRP's open-source `exfat-fuse` binary, while NTFS remains on `ntfs-3g`;
the build requires the linked kernel objects and the artifact inspector
requires both userspace paths as real ARM64 ELF files before accepting the
image.

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
uses an explicit `/dev/mtp_usb` path supplied by `CONFIG_USB_G_ANDROID`; ADB
uses the same gadget's embedded FunctionFS function. `f_fs.c` is compiled
directly by the vendor `android.c`, so enabling the separate
`CONFIG_USB_FUNCTIONFS` gadget would duplicate registration rather than fix
ADB.

This split is consistent with TeamWin's Exynos 7420 Galaxy S6 and Note 5
trees, which use the legacy `android_usb` sysfs gadget and `/dev/mtp_usb`, and
with the Android 9 Exynos 8890 recovery tree, which mounts ADB FunctionFS,
sets `f_ffs/aliases=adb`, selects `sys.usb.ffs.aio_compat=1`, and builds the new
minadbd. The connected Flyme system was also read back directly: its working
ADB-only state is `18d1:4ee7`, `functions=adb`, `enable=1`, and
`state=CONFIGURED`. The recovery tree now uses that exact ADB PID, reserves
`18d1:4ee2` for MTP+ADB, disables unrelated USB mass-storage mode, and forces
one `none -> adb` transition after upstream has mounted FunctionFS. TWRP may
later switch to MTP+ADB through its unchanged upstream property state machine.

## Boot and partition contract

The recovery image must satisfy all of these static checks:

| Field | Required value |
| --- | --- |
| boot header | classic Android v0, empty name and command line |
| kernel | uncompressed ARM64 `Image`, address `0x40080000` |
| ramdisk | LZMA-Alone, address `0x42000000` |
| second stage | size 0, address `0x40f00000` |
| tags | `0x40000100` |
| page size | 4096 bytes |
| embedded DT | size 0 |
| recovery image limit | at most 33,550,336 bytes |
| device tree | separate raw FDT containing `Meizu, M86` |
| GUI languages | exactly `en` and `zh_CN` |
| first display handoff | framebuffer blank/unblank before the TWRP splash |
| persistent console | pstore/ramoops with stock-DTB and generated-DTB lookup paths |

The selective-language recovery patch retains the common English fonts and
`DroidSansFallback.ttf`, which `zh_CN.xml` explicitly references. Other
translation XML files and the Japanese-specific CJK font are excluded. The
artifact inspector verifies both directory inventories exactly so a stale or
incremental output cannot silently restore the full language set.

The recovery ramdisk uses the Android 9 build system's native
`LZMA_RAMDISK_TARGETS=recovery` path. `cm_pro5_defconfig` enables both gzip and
LZMA initramfs decoding: normal Android boot remains gzip-compatible, while
the standalone recovery image is substantially smaller without removing ADB,
FDE, MTP, exFAT, NTFS, or the full Simplified Chinese fallback font. Artifact
inspection decompresses the LZMA stream and applies the same exact file,
hash, ELF, language, and font gates used for gzip.

The original booting m86 recovery tree set `TW_SCREEN_BLANK_ON_BOOT`; the new
tree initially omitted it. Because the stock bootloader leaves its logo in the
scanout buffer, the maintained tree restores the initial blank/unblank cycle
and statically gates the setting. This makes early UI visibility a controlled
part of the device contract rather than an inference from a retained boot
logo.

The maintained kernel also enables pstore console capture. Its Exynos ramoops
driver first resolves the stock Flyme DTB's generic reserved-memory phandle
and then falls back to the Exynos ION heap used by the generated DTB. Every
kernel-bearing build requires the pstore configuration and both linked driver
objects. Runtime creation of a new console record remains a handset gate.

The one-page recovery reserve is conservative until the paused GPT backup is
resumed. A 32 MiB partition dump exists, but no artifact may consume the last
page merely on that historical evidence.

The normal recovery UI exposes `system`, `data`, `cache`, `custom`, `boot`,
`recovery`, `dtb`, `dtb_backup`, `bootlogo`, `efs`, `mnv`, `misc`, microSD and
USB OTG. EFS and MNV are mounted read-only and offered for backup, not wipe.
Only boot, recovery, DTB and system image are image-flash targets. The tree
does not expose `/dev/block/sdb`, bootloader, `ldfw`, `param`, `proinfo`,
`private`, or `rstinfo`.

## Rejected corrected candidate

Commit `7e2a4136` restores the m86 early framebuffer blank/unblank and adds the
complete persistent-console kernel path. Two clean builds produced the same
candidate:

| Artifact | Size | SHA-256 | Partition margin |
| --- | ---: | --- | ---: |
| `recovery.img` | 27,308,032 | `8c20eaa5301a9c70ad363cd765d5ba4cf33be69a37fc3f6a88d9b8cca5b07ca9` | 6,242,304 |

The candidate was tested with the verified stock Flyme 8 DTB. It remained at
the Meizu logo and then returned automatically to Flyme without recovery ADB
or a current `/cache/recovery/last_log`, so it is rejected. The only pstore
file after the warm reset was a 43-byte ECC notice with no console payload.
The generated DTB remains a review artifact and must not be flashed.

The all-old-content current-envelope control with SHA-256
`f86fe878513b9df07bdfd7c32f8064564377067622b355a7a5c889f260dcedca`
subsequently reached recovery. The owner also confirmed that the earlier
maintained-source-kernel / old-userspace image with SHA-256
`7a126febd9e3d12b221fd870effb4a835b9604265cf33ad556da60f0dbfa54e1`
had booted. Since the old-kernel / new-ramdisk image failed, the new ramdisk is
a sufficient failure boundary.

The first legacy-init hybrid with SHA-256
`14c0056ca835cd1599b70e892071458c6693cbdfaa5071ef0efefcc169fd83bb`
also stalled, but it combined the later pstore kernel with LZMA and is not a
clean discriminator. It is rejected. The exact gzip load-envelope control
with SHA-256
`22a42a33516da36dcbc9ec3a1807716123430e2f5a256f25b5d5f16b2dee469d`
then reached the recovery UI, while the matching proven-source-kernel /
new-userspace / legacy-init gzip image with SHA-256
`0dad8b1710cd8eef39f6b3d632f71bc8cd5f3c857ed16055fbbf4b3224254ed3`
stalled at the logo. This excludes the image-load envelope and legacy startup
chain and isolates new executable/runtime or rootfs content.

The next minimal-runtime diagnostic has SHA-256
`c391de4d77392a6c8f2f2012d44746d0b46d18e4585faf953587222a36a3766d`.
It retains the proven source kernel and byte-identical old init, ueventd,
SELinux, healthd, toolbox and adbd, replacing only the TWRP 3.7 recovery
runtime, the tools it names, resources and device configuration. Its
12,104,107-byte gzip ramdisk is smaller than the passed 15,051,754-byte
control. The 69-entry recursive runtime closure has no missing dependency and
matches the corrected new ramdisk byte for byte.

On the handset it reached a black screen after the Meizu logo, vibrated, and
then automatically rebooted into Flyme. No current recovery log or retained
recovery console was available. Static inspection excludes a dynamic-linker
failure of the legacy critical services because init, ueventd, healthd and
adbd are statically linked. It also exposed an old-only `/etc/twrp.fstab`
inside the hybrid; TWRP 3.7 prefers that path, so it shadowed the reviewed
new `/etc/recovery.fstab`.

The next one-variable diagnostic removes only that shadowing file. Its
recovery SHA-256 is
`7a648ed1a5bc86db96741931104bab8443a728bd1f2b90d8abac7182156f691b`;
all 488 surviving ramdisk entries and the proven kernel are byte-identical,
and the boot-header geometry is unchanged from the preceding image. The
handset nevertheless repeated the same Meizu-logo, black-screen, vibration
and automatic Flyme boot sequence.

The post-test reset record identifies a normal software reboot at 14:47:56
with command `reboot`; every panic, oops, watchdog and hardware-reset counter
is zero. Cache recovery logs predate the test and pstore contains the following
Flyme boot. This excludes both the stale fstab and a kernel crash. It strongly
indicates that TWRP returned from its GUI path and requested the default system
reboot, although the in-memory recovery log is required to identify why.

The ADB-only log-capture diagnostic has recovery SHA-256
`a2d6c1fd75c33d51af047c2bd94fb344f27a6bd887048854efc79b56bf147375`.
It retains the corrected fstab image and changes only legacy `init.rc` data:
MTP is skipped, the known-working static adbd is exposed as `18d1:4ee7`, an
ordinary system reboot rc action is removed, and bootloader/recovery reboot
requests remain enabled. The recovery service is `oneshot`, intended to
preserve the tmpfs log if TWRP exits. All other cpio data and metadata, the
proven kernel and boot geometry are byte-identical. It is a temporary evidence
collector, not a candidate for functional acceptance.

That image also returned automatically to Flyme. The reset record increments
the software-reboot counter and records command `reboot` at 15:03:57, with all
crash and watchdog counters still zero. The pinned TWRP source writes
`sys.powerctl=reboot,` after its GUI returns, and this result shows the old
init's special power-property processing bypasses the removed rc wildcard.

The second log-capture diagnostic has recovery SHA-256
`34bed1046ecef38b13ca8eda20f97f1a0610af0c4fb4a3e3769fc6aaa73d8d4a`.
It changes exactly 12 bytes in the 935,176-byte `sbin/recovery`: the sole
same-length `sys.powerctl` literal becomes the inert `twrp.loghold`. Every
other recovery ELF byte, all cpio metadata and data, the ADB-only oneshot init,
proven kernel and boot geometry remain identical. This prevents TWRP's default
GUI-return path from invoking init's power control while preserving the
volatile log-capture environment.

V2 was tested and repeated the same visible failure. The full recovery
partition collected afterward contains the exact v2 image as its
byte-identical prefix, so Flyme did not replace it. Recovery ADB did not remain
reachable, the standard cache recovery logs still predate the test, and the
retained pstore record contains the preceding Flyme session rather than the
recovery boot. The new reset record is `poweroff reboot` with command
`reboot charge`, which does not classify the TWRP exit. V2 is therefore
inconclusive rather than evidence of another kernel or init failure.

Persistent log-capture v3 has recovery SHA-256
`61c7e16e706ab04cddc9801b6fa30f6f23683108591e9446dbf66e69e2594ea7`.
It is built from the exact tested v2 image and changes only the `init.rc` and
existing executable `sbin/permissive.sh` data payloads. The first change runs
TWRP as a child of the wrapper in the recovery SELinux domain; the second
installs the wrapper while retaining the entry's original executable cpio
metadata. All 489 cpio paths, path order and metadata, the v2 TWRP ELF, proven
kernel, fstab, resources and header geometry remain identical. Two independent
gzip ramdisk and recovery-image repacks are byte-identical.

Before TWRP starts, the wrapper verifies that the existing cache filesystem is
mounted read-write, creates unique `pro5-twrp-diag-v3-*` files under
`/cache/recovery`, redirects `/tmp/recovery.log` to the persistent log,
captures dmesg and syncs every two seconds. On a TWRP return it records the exit
status and a second dmesg, then remains alive. A cache mount or write failure
prevents TWRP from starting and holds init/ADB instead. This intentional cache
write requires explicit device-test approval; v3 is an evidence collector,
not a functional recovery candidate.

V3 was tested and repeated the same visible failure, but it proved that the
wrapper reached userspace, mounted cache and saved its initial dmesg. The
surviving log stops immediately before the first post-sync stage marker. The
latest reset record and pstore console both belong to the preceding Flyme
reboot into recovery, so this attempt does not record a normal TWRP-requested
reboot. Because v3's periodic loop slept before its first sync, the missing
post-launch data may have remained in page cache during an early reset or hard
lock.

Synchronous log-capture v4 has recovery SHA-256
`929308abf56395ab6ec74d5f53734d5b90f7ce6a45086680e207002e3f6f6029`.
It is built from the exact tested v3 image and changes only the
`sbin/permissive.sh` data payload. Cache must be mounted with both `rw` and
`sync` flags before any diagnostic file is created. Explicit stages are
flushed before the unchanged TWRP starts, and TWRP's unbuffered log resolves
directly to that synchronous filesystem. All 489 cpio paths, order and
metadata and every other recovery component remain identical; two independent
ramdisk and image repacks are byte-identical. V4 remains a diagnostic and
requires explicit approval because it writes synchronously to cache.

The v4 handset test retained the complete startup boundary. TWRP enters
`gui_init()`, falls back normally from DRM to fbdev, reads a 1080x1920 32-bit
BGRA framebuffer and selects double buffering. The final durable line is
`Using fbdev graphics.`; the later `=> Linking mtab` marker is absent. Fstab
processing, resource loading, encryption, MTP and the main GUI loop therefore
never start. The exact v4 image is also present at the front of the clean
post-test recovery-partition acquisition. Reset-reason storage is unchanged
from the preceding Flyme reboot and pstore contains the preceding Flyme
session, so neither classifies the recovery exit.

At the pinned TeamWin source revision, the remaining graphics initialization
performs pixelflinger setup and two flips. The double-buffer fbdev backend's
first flip copies to framebuffer page 1 and switches to `yoffset=1920` through
`FBIOPUT_VSCREENINFO`. This is the narrowest untested operation after the last
log line, but remains a hypothesis rather than a confirmed cause.

The device tree now enables
`RECOVERY_GRAPHICS_FORCE_SINGLE_BUFFER := true`. Two clean source builds are
byte-identical; the full source recovery has SHA-256
`370064ffa114783119fed8eea52ca6505a47954f62a1db309d7f268462b9c704`.
That image is donor evidence only because it changes multiple variables, and
its generated DTB must not be flashed.

Single-buffer v5 has recovery SHA-256
`23db8d86e7b6523b2a4ad1c8ed2b2bbd319d490d05d57381f3670dbad42f5fe1`.
It starts from the exact tested v4 image and changes only
`sbin/libminuitwrp.so`; all 489 cpio paths, order and metadata, the proven
kernel, init, patched recovery ELF, fstab, resources, v4 synchronous wrapper
and boot geometry remain identical. The replacement library contains the
single-buffer marker and no double-buffer branch, while its dynamic symbol
surface is identical to the v4 library. Two independent ramdisk and recovery
repacks are byte-identical. V5 still writes `pro5-twrp-diag-v4-*` files under
cache and requires an isolated device test before acceptance.

The v5 device logs prove that single buffering passes `gui_init()`, processes
both fstab passes, loads the full theme and enters the main TWRP GUI. Repeated
brightness transitions also match the observed screen timeout and Home/Power
wake. The remaining Meizu image is not a TWRP crash: forced single buffering
renders into page 0 but upstream fbdev skips its initial page-zero selection
because `double_buffered` is false, leaving DECON on the bootloader scanout
page.

The reviewed fbdev patch permits exactly the initial `yoffset=0` request under
`RECOVERY_GRAPHICS_FORCE_SINGLE_BUFFER`; all later flips remain memcpy-only.
Two clean patched source builds are byte-identical, with recovery SHA-256
`7cbef6a30c2a380b479266b5399c6a6647c897950519e96f8473ff50e64f886c`.
The full source image and its generated DTB remain donor evidence only.

Page-zero v6 has recovery SHA-256
`398dc69d5af4b9210b09c27d8a50e16edeaebbbf7f4844d3efefaa402c6934c8`.
It starts from the exact tested v5 image and changes only
`sbin/libminuitwrp.so`. All 489 paths, order and metadata and every other
component remain identical. The library contains the page-zero marker and no
double-buffer branch, with the same 839 dynamic symbol names and types as v5.
Two ramdisk and recovery repacks are byte-identical. V6 retains the disclosed
v4 synchronous cache logger and requires a visible-UI device test before
acceptance.

The v6 device evidence proves that page zero was selected and TWRP reached its
main GUI, but the panel remained black because command-mode DECON did not
transmit later memcpy-only framebuffer updates. Command-refresh v7 therefore
keeps forced single buffering and page zero while issuing a page-zero
`FBIOPAN_DISPLAY` after each copy. It changes only `sbin/libminuitwrp.so` in
the exact tested v6 diagnostic and has recovery SHA-256
`26c98728539ab21d723a67906e8250a78be633cdb481cdaa93f2ecdee2e7d43e`.

V7 displayed the TWRP UI and remained touch-responsive. After the configured
timeout the screen went black; Home, Power and touch repeatedly restored
brightness but not panel output. The logs continue changing GUI pages and
contain no crash, panic, oops or watchdog event. This initially implicated
timeout-time FBIOBLANK of the command-mode DECON/DSI controller. V9 later
compiled out that FBIOBLANK call, but the UI still went black even during
continuous touch interaction. This rejects idle timeout as the root cause.
The source tree keeps both `TW_NO_SCREEN_BLANK` and `TW_NO_SCREEN_TIMEOUT` as
defensive isolation settings.

V7's MTP warning was forced by its diagnostic init and is not an observed MTP
crash. The same legacy init omitted the FunctionFS mount, so its unavailable
ADB is also not a test of the full source recovery.

The full-source v8 device-test image is retained at
`artifacts/twrp-20260807-185235-recoveryimage` in the parent Android workspace.
Its 27,303,936-byte `recovery.img` has SHA-256
`9c4d5038e80de335792977690ea963e3b9d5e66463ac58f602d124fa2fd06102`.
Both clean build passes produced that exact hash; the generated kernel config
and build-only DTB are also byte-identical across the two passes. The image
retains the proven kernel SHA-256
`f628266ac0c23770c81e27e553de0b58f9c51df55d50c54bc88cf0196b796da7`,
uses a 10,059,600-byte LZMA ramdisk with SHA-256
`93386aaea2b037b2ed4b62438d24644bb297dc11eb46eacfa67808a6e8cc7794`,
and embeds no DTB.

Independent post-fetch inspection verifies that v8 contains the upstream
FunctionFS mount, the `f_ffs` ADB alias, new minadbd, the Flyme-proven ADB-only
identity `18d1:4ee7`, an ordered post-mount `none -> adb` transition, and the
explicit Exynos MTP device `/dev/mtp_usb`. It contains neither the forced
`mtp.crash_check=1` property nor the cache-logging diagnostic wrapper. The
`TW_NO_SCREEN_BLANK` and `/dev/mtp_usb` compiler definitions are present in
the final build graph. V8 passes the source validator, shell syntax checks,
boot-image/ramdisk inspection, checksum manifest, size gate, and reproducible
build gate. Its handset test nevertheless stopped at the Meizu logo and
returned to Flyme through an ordinary software reboot. A complete partition
acquisition proved the exact image was installed; no panic, oops, watchdog,
current cache log or recovery ADB evidence was recovered. V8 is rejected.

V9 returned to the exact v7 base and added only a recovery ELF built with
`TW_NO_SCREEN_BLANK` plus a legacy ADB-only init. Its UI remained alive and
touch-responsive but still went black, while no USB device enumerated at the
host. The later clarification that it also blacks out during continuous touch
rejects the idle timer as the primary failure mechanism.

The tree therefore also sets `TW_NO_SCREEN_TIMEOUT`. The fully clean v10 donor
build is byte-identical across two passes and its recovery ELF contains neither
post-screen-blank hook path. V10 applies that ELF to the exact v7 image and
uses a direct boot-action legacy gadget, `18d1:4ee7` / `PRO5TWRPV10`, with no
USB property action, FunctionFS mount or adbd restart. Its two repacks are
byte-identical. The 29,335,552-byte image has SHA-256
`6d1455bd633e439158df6b13602cc26344eeea0bdcc56ac7614ceaef35fc5690`
and is retained at
`artifacts/twrp-bootdiag-20260807-233936-direct-adb-v10/recovery.img`.
It was superseded before handset testing and must not be flashed.

The continuous-touch result points instead to the v7 refresh workaround. Each
changed frame issues `FBIOPAN_DISPLAY`, and m86 handles each request through
the full `decon_set_par()` command-mode path. The old working TWRP binary
orders its single-buffer flip as `FBIO_WAITFORVSYNC`, active-page copy, then
PAN. The maintained fbdev code now restores that pre-copy VSYNC wait, pacing
touch-driven redraw bursts to the panel before overwriting scanout page zero.

Two fully clean source builds produced an identical 27,308,032-byte donor
recovery with SHA-256
`bdfc2aa9ac4401614572d92c48eb72a2151dacf569ee95b09032e062376e4697`.
Its replacement `libminuitwrp.so` has SHA-256
`14efd5195e0379669656d0866adcedaa6030a645b7071056ff08437386e682c0`.
The dynamic symbol-name set and needed-library set are unchanged from v10.

V11 applies only that library to the exact v10 base, keeping the defensive
timeout-disabled recovery ELF and direct ADB configuration unchanged. Two
ramdisk and recovery repacks are byte-identical. The resulting 29,335,552-byte
image has SHA-256
`8e88e946ce04efe2ccc006147c7da654ad14d9c6c3cb0eb2c610067a72e327d8`
and is retained at
`artifacts/twrp-bootdiag-20260808-000625-precopy-vsync-v11-final/recovery.img`.
It has no embedded DTB and requires the unchanged Flyme 8 DTB. V11 remains a
single-variable device-test candidate rather than an accepted recovery.

The handset test rejected v11: the UI still blacked out during continuous
interaction, touch stayed active and no recovery USB device or ADB serial ever
enumerated. A full partition acquisition proved the exact v11 image was
installed. No current recovery cache log or pstore console survived, and reset
storage reports no panic, oops or watchdog event.

V12 starts from the exact v11 image and changes only `libminuitwrp.so`,
suppressing the late synthesized `FBIOPUT_VSCREENINFO` while retaining kernel
geometry. Its 29,335,552-byte recovery SHA-256 is
`4e4320b297c3ca086a697f488f0ddaca5017f62e40512fb1b980eb2f2b642463`.
The handset test showed a top white line and intermittent complete frames when
changing pages, so v12 is rejected. Fresh disassembly corrects the earlier
contract reading: the working TWRP 3.0 library performs an early one-time
`FBIOPUT_VSCREENINFO` with `vmode=0` and `FB_ACTIVATE_FORCE` before
`FBIOGET_FSCREENINFO` and mmap; it merely avoids the later synthesized mode
request.

The contemporary Note5 Exynos 7420 kernel provides the more direct display
reference: PAN updates the scanout address, triggers the command-mode transfer
and waits for VSYNC without calling the complete `decon_set_par()` path on
every frame. The maintained m86 kernel now follows that transaction pattern.
The Note5 panel resolution, pixel format, brightness path and whole recovery
BoardConfig are not transplanted.

V13 combines the v12 framebuffer library with that lightweight PAN kernel and
a native ready-first ADB diagnostic. Old minadbd opens `/dev/android_adb` while
the gadget is disabled; only after the kernel logs `adb_open` does the wrapper
publish `2a45:0c01` / `PRO5TWRPV13`. It records USB state every five seconds to
synchronously mounted cache, so failed host enumeration should still leave
device-side evidence.

The kernel donor and hybrid image each pass two byte-identical builds or
repacks. V13 is 29,351,936 bytes with SHA-256
`96c066af2d1c03f82c868c9e4eb77b63dce66f6c0f770a79423821db3ee964ad`,
has no embedded DTB, preserves the Flyme 8 DTB requirement and remains a
controlled combined device-test candidate rather than accepted recovery.

The handset test rejected v13 at the Meizu logo before its persistent wrapper
or ADB setup left any evidence. A complete partition acquisition matches v13
exactly. Cache contains no v13 diagnostic, pstore contains only the following
Flyme boot's NAND ECC summary, and reset storage has zero panic, oops or
watchdog counts. Because both v8 and v13 used the later pstore/ramoops kernel,
the next candidate restores the v11-proven pre-pstore kernel baseline and
retains only the Note5 PAN source change. Its ramdisk and old ADB path remain
byte-identical to v11 for a display-only isolation.

That v14 isolation is now complete. Four pstore-related source files are
SHA-locked to the revision that produced the v11-proven kernel; the only
remaining kernel source delta is the Note5-style change in
`decon-int_drv.c`. Two clean builds produced identical kernels with SHA-256
`7cb5b99f6ec849b4ab7b5508964ddb4641fede416cd8ab8611643f0bc6e454ff`.

V14 replaces only the kernel component of exact v11. Its ramdisk remains
byte-identical with SHA-256
`7364783467cc5011d48ea9314acd8217223b05ebe3d2784e3e145d4467a590e4`;
two hybrid repacks are also byte-identical. The final 29,335,552-byte recovery
has SHA-256
`ddc37377309011ad5954afb85c8ab1f58d0ec958adacb9c7fce0ef6fd721b9bc`,
embeds no DTB and is a display-only device-test candidate. ADB remains the
known-failing v11 path so that USB does not add another variable.

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

The builder container has a roughly 60 GiB cgroup limit even though host tools
report much more RAM. Clean Android builds can fill most of that allowance
with file cache and stall late packaging steps, so recovery and ROM builds
default to eight jobs. `PRO5_TWRP_BUILD_JOBS` remains an explicit override for
a builder with a separately verified memory limit.

Two remaining ramdisk generators are normalized by reviewed patches. The
recovery make rule sorts both embedded `ramdisk-files` inventories with the C
locale because parallel installation otherwise changes their traversal order.
The SELinux rule invokes `sefcontext_compile -r`: PCRE2's serialized host
bytecode contains process-specific data, is not portable from the x86-64 host
to the ARM64 target, and changes between clean runs. Omitting that optional
payload is supported by the pinned loader, which compiles the retained regex
strings on first use. The exact patch series and patch payloads are retained
with every accepted artifact.

The recovery tree also had two parallel post-install owners for `/sbin/gzip`
and `/sbin/gunzip`: toybox linked them to itself while pigz linked the same
paths to `pigz`. A reviewed recovery patch removes those two names only from
toybox's symlink set. The image inspector then requires the cpio link payloads
to hash exactly as `pigz`, so a scheduling-dependent winner cannot reappear.

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
