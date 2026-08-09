# PRO 5 TWRP flashing boundary

`recovery.img` is a raw Android boot image for the UFS `recovery` partition.
The PRO 5 stores its device tree in the separate UFS `dtb` partition; the
recovery image does not embed a DTB. Neither file is authorized for flashing
merely because a build or repack completed.

The 2026-08-07 source-built recovery and generated
`exynos7420-m86-codegen.dtb` are rejected for device use: recovery boot stalled
at the Meizu logo both with the Flyme 8 DTB and with the generated DTB. The
generated DTB must not be flashed again until the maintained kernel is made
compatible with the stock board contract and a new pair is reviewed.

Before the first device test, retain verified rollback copies of the current
`recovery` and `dtb` partitions, check both artifact SHA-256 values, and obtain
explicit approval for the exact fastboot commands. Never write the recovery
artifact to `bootimg`, `/dev/block/sdb`, `ldfw`, or any parameter/identity
partition.

The first isolation image combined the exact kernel and boot-header contract
from the known-working recovery with the complete new TWRP ramdisk. It also
stalled at the logo and is rejected. Before another experimental image, first
reconfirm that the unmodified known-working recovery still boots with the
stock Flyme 8 DTB. Never flash a DTB from the rejected source build.

Subsequent source builds package only English and Simplified Chinese resources
to create a meaningful margin below the partition and bootloader boundary.
They use a kernel-supported LZMA-Alone recovery ramdisk while retaining the
kernel's gzip decoder for normal Android boot; no recovery feature or Chinese
font coverage is removed for compression.
Each new image still requires static review and explicit test approval; it is
not accepted merely because it is smaller.

The rejected LZMA candidate is 27,287,552 bytes with recovery SHA-256
`a360a6f1a269c9c730f8f288f4783cf9d2054a742718292abed03f2e3823e5aa`.
It passed two byte-identical clean builds but stalled at the Meizu logo after
the old recovery baseline was reconfirmed, so it is rejected. Do not flash it
or its generated DTB again.

The corrected device candidate restored the original booting m86 tree's initial
framebuffer blank/unblank and enabled persistent kernel-console capture for
both the stock-DTB reserved-memory layout and generated-DTB ION layout. Its
`recovery.img` is 27,308,032 bytes with SHA-256
`8c20eaa5301a9c70ad363cd765d5ba4cf33be69a37fc3f6a88d9b8cca5b07ca9`.
It passed two byte-identical clean builds but stalled at the Meizu logo and
returned automatically to Flyme. No recovery ADB, current recovery log or
pstore console payload was recovered, so the candidate is rejected. Keep the
verified stock Flyme 8 DTB and do not flash the generated DTB packaged beside
it.

The all-old-content current-envelope control with SHA-256
`f86fe878513b9df07bdfd7c32f8064564377067622b355a7a5c889f260dcedca`
reached recovery. The owner also confirmed that the maintained-source-kernel /
old-userspace diagnostic booted. A later LZMA hybrid that restored the legacy
startup chain, SHA-256
`14c0056ca835cd1599b70e892071458c6693cbdfaa5071ef0efefcc169fd83bb`,
stalled and is rejected; do not flash it again.

The all-old-content gzip load-envelope control with SHA-256
`22a42a33516da36dcbc9ec3a1807716123430e2f5a256f25b5d5f16b2dee469d`
and size 32,571,392 bytes reached the recovery UI. The matching
proven-source-kernel / new-userspace / legacy-init gzip diagnostic with SHA-256
`0dad8b1710cd8eef39f6b3d632f71bc8cd5f3c857ed16055fbbf4b3224254ed3`
then failed. A minimal new-runtime image and its fstab-corrected successor also
failed with the same black-screen/vibration/automatic-Flyme sequence. The last
test recorded a normal software `reboot`, with no panic or watchdog reset.

The first ADB log-capture recovery with SHA-256
`a2d6c1fd75c33d51af047c2bd94fb344f27a6bd887048854efc79b56bf147375`
and size 29,335,552 bytes was tested. It still returned automatically to Flyme
with a second normal software `reboot`; removing the rc wildcard did not
intercept old init's special handling of `sys.powerctl`.

ADB log-capture v2 with SHA-256
`34bed1046ecef38b13ca8eda20f97f1a0610af0c4fb4a3e3769fc6aaa73d8d4a`
and size 29,335,552 bytes was tested. It repeated the same visible sequence and
recovery ADB did not remain reachable. A post-test partition dump proves the
exact v2 image was still installed, but reset-reason storage records a
`poweroff reboot` with command `reboot charge`; neither that record nor pstore
contains the recovery session. The two standard cache logs still predate the
test. V2 is therefore inconclusive and must not be tested again.

The next test-only image is persistent log-capture v3 with SHA-256
`61c7e16e706ab04cddc9801b6fa30f6f23683108591e9446dbf66e69e2594ea7`
and size 29,335,552 bytes. Two independent ramdisk repacks and recovery-image
repacks are byte-identical. Relative to the exact tested v2 base, only
`init.rc` and the existing executable `sbin/permissive.sh` data change; all
489 cpio paths, path order and metadata, the proven kernel, TWRP ELF, fstab and
boot geometry remain identical.

V3 deliberately mounts cache read-write before starting TWRP and creates
unique `pro5-twrp-diag-v3-*` recovery log, wrapper log and dmesg files under
`/cache/recovery`, syncing them every two seconds. This is a disclosed
persistent device write. Its handset test repeated the visible failure but
retained the wrapper header and pre-launch dmesg, proving that the wrapper and
cache path ran. It did not retain the first marker written after the explicit
sync, TWRP output or an exit marker. The latest reset record and pstore console
belong to the preceding Flyme reboot into recovery, not the recovery exit. V3
must not be tested again.

Synchronous log-capture v4 with SHA-256
`929308abf56395ab6ec74d5f53734d5b90f7ce6a45086680e207002e3f6f6029`
and size 29,335,552 bytes was tested. It is built from the exact tested v3
image and changes only the existing `sbin/permissive.sh` data payload. All 489
paths, their order and metadata, the kernel, init, TWRP ELF, fstab and boot
geometry remain identical. Two independent repacks are byte-identical.

V4 requires cache to be mounted `rw,sync`, flushes named stages before TWRP,
and directs TWRP's unbuffered log to that synchronous filesystem. This is a
disclosed persistent device write. Its handset test retained TWRP output
through fbdev initialization. The final line is `Using fbdev graphics.` after
selection of a 1080x1920 32-bit double-buffered framebuffer; TWRP never
returns from `gui_init()` and does not reach fstab processing. The recovery
partition dump proves the exact v4 image was tested. Reset reason and pstore
do not contain the recovery exit. V4 must not be tested again.

Single-buffer repair v5 with SHA-256
`23db8d86e7b6523b2a4ad1c8ed2b2bbd319d490d05d57381f3670dbad42f5fe1`
and size 29,335,552 bytes was tested. It is built from the exact tested v4 image and
changes only `sbin/libminuitwrp.so`. The replacement came from two
byte-identical clean source builds with
`RECOVERY_GRAPHICS_FORCE_SINGLE_BUFFER := true`; it contains the
single-buffer runtime marker and no double-buffer branch. Every cpio path,
path order and metadata, the kernel, init, patched recovery ELF, fstab,
resources, synchronous wrapper and boot geometry remain unchanged. Two
independent v5 repacks are byte-identical.

V5 retains the disclosed `rw,sync` cache writes and continues to create
`pro5-twrp-diag-v4-*` files. Its two retained logs pass graphics init, process
fstab and partitions, load the full theme, enter the main GUI and handle
screen timeout plus Home/Power wake. The panel still shows the bootloader
Meizu image because forced single buffering draws to page 0 while skipping
the initial page-zero scanout request. The partition dump proves the exact v5
image was tested. V5 must not be tested again.

Page-zero single-buffer v6 with SHA-256
`398dc69d5af4b9210b09c27d8a50e16edeaebbbf7f4844d3efefaa402c6934c8`
was tested and must not be flashed again. The panel stayed black, but the
retained log proves TWRP loaded the full theme, entered the main GUI, timed out
and handled wake. Page zero was correct; command-mode DECON simply did not
transmit later memcpy-only updates.

Command-refresh v7 with SHA-256
`26c98728539ab21d723a67906e8250a78be633cdb481cdaa93f2ecdee2e7d43e`
was also tested and must not be flashed again. Page-zero `FBIOPAN_DISPLAY`
refresh made the TWRP UI visible and interactive. After about one minute,
TWRP's normal timeout made the panel black; touch and keys continued to change
pages, vibrate, and restore brightness, but the command-mode display did not
resume. That initially implicated timeout-time FBIOBLANK, but later continuous-
touch blackouts reject timeout as the primary cause.

V7 is a diagnostic hybrid. Its `MTP Crashed` line was deliberately forced by
the test init, and that init never mounted ADB FunctionFS. Neither symptom is
a valid result for the maintained source recovery.

The source-built v8 device-test image is 27,303,936 bytes with recovery SHA-256
`9c4d5038e80de335792977690ea963e3b9d5e66463ac58f602d124fa2fd06102`.
The retained artifact's `REPRODUCIBILITY.txt` records this same hash for both
clean build passes. V8:

- retains forced single buffering, page-zero selection, and page-zero PAN
  refresh;
- uses `TW_NO_SCREEN_BLANK`, so timeout turns off the AMOLED backlight without
  powering down DECON/DSI;
- restores the full source ramdisk, upstream FunctionFS mount, and new
  minadbd;
- uses the Flyme-proven ADB-only identity `18d1:4ee7`, then permits TWRP to
  switch to `18d1:4ee2` for MTP+ADB;
- selects FunctionFS v1/synchronous compatibility and the Exynos
  `/dev/mtp_usb` MTP device;
- disables unrelated USB mass-storage mode; and
- removes the v4 synchronous diagnostic wrapper and its forced cache logging.

The sealed image retains kernel SHA-256
`f628266ac0c23770c81e27e553de0b58f9c51df55d50c54bc88cf0196b796da7`
and contains a 10,059,600-byte LZMA ramdisk with SHA-256
`93386aaea2b037b2ed4b62438d24644bb297dc11eb46eacfa67808a6e8cc7794`.
Independent extraction confirms the FunctionFS mount, new minadbd, USB
properties and absence of the diagnostic MTP-crash property. The handset test
stalled at the Meizu logo and returned to Flyme through a normal software
reboot. A partition acquisition proved the exact v8 image was installed. V8 is
rejected and must not be flashed again.

Legacy-ADB v9, SHA-256
`342c788c2bccc12d6af7717a90cbcf48ee9bda11494cdc37c318e7031ba0a760`,
returned to the exact v7 base and removed `gr_fb_blank()` from the recovery
ELF. The UI remained touch-responsive but still went black, and no USB device
enumerated at the host. V9 is rejected and must not be flashed again.

Direct-ADB/no-screen-timeout v10 is 29,335,552 bytes with SHA-256
`6d1455bd633e439158df6b13602cc26344eeea0bdcc56ac7614ceaef35fc5690`.
It starts from the exact v7 image and changes only `init.rc` and
`sbin/recovery`. The recovery ELF has the complete TWRP timeout state machine
compiled out. Init directly enables legacy ADB-only `18d1:4ee7`, serial
`PRO5TWRPV10`, with no USB property action, FunctionFS mount or restart race.
Two independent repacks are byte-identical. V10 was not handset-tested and is
superseded by v11; do not flash v10.

Pre-copy-VSYNC v11 is 29,335,552 bytes with SHA-256
`8e88e946ce04efe2ccc006147c7da654ad14d9c6c3cb0eb2c610067a72e327d8`.
It starts from the exact v10 image and changes only
`sbin/libminuitwrp.so`. The owner reported blackouts during continuous touch,
so the timeout-disabled settings are retained only as defensive isolation.
The actual display change restores the ordering found in the old working
TWRP: `FBIO_WAITFORVSYNC`, then copy into active page zero, then
`FBIOPAN_DISPLAY`. This paces touch-driven redraws and avoids overwriting the
scanout page while the previous command-mode transfer is in flight. The v10
direct legacy ADB configuration remains byte-identical, including serial
`PRO5TWRPV10`; MTP remains disabled.

The replacement library came from two fully clean, byte-identical source
builds. Two v11 ramdisk repacks and recovery-image repacks are also
byte-identical. All 489 cpio paths, path order and metadata, the proven kernel,
init, recovery ELF, old adbd, fstab, synchronous logger and boot geometry are
unchanged. The handset nevertheless blacked out during continuous interaction
while touch remained active, and recovery USB/ADB never enumerated. A complete
partition acquisition proved the exact v11 image was installed. No current
cache or pstore log survived, and reset storage reports no panic, oops or
watchdog event. V11 is rejected and must not be flashed again.

V12, SHA-256
`4e4320b297c3ca086a697f488f0ddaca5017f62e40512fb1b980eb2f2b642463`,
was tested and is rejected. It changes only `libminuitwrp.so` and suppresses
the late synthesized `FBIOPUT_VSCREENINFO` while retaining kernel framebuffer
geometry. The panel showed a top white line; changing TWRP pages could
temporarily restore a complete frame. Fresh disassembly shows that the working
TWRP 3.0 backend did perform an earlier one-time mode replay with `vmode=0`
and `FB_ACTIVATE_FORCE`, before fixed-geometry discovery and mmap.

Note5-style PAN/ready-first-ADB v13 is 29,351,936 bytes with SHA-256
`96c066af2d1c03f82c868c9e4eb77b63dce66f6c0f770a79423821db3ee964ad`.
It starts from the audited v12 ramdisk and:

- replaces the kernel with a twice-built candidate whose Exynos 7420 DECON
  PAN path updates the scanout address, triggers and waits for VSYNC without
  running full `decon_set_par()` for every redraw;
- retains v12 page-zero single buffering, pre-copy VSYNC, post-copy PAN and
  legacy framebuffer initialization;
- starts old minadbd on `/dev/android_adb` while the gadget is disabled, waits
  for the kernel `adb_open` marker, and only then publishes ADB-only
  `2a45:0c01` / `PRO5TWRPV13`; and
- writes periodic USB gadget, device-node and adbd-process evidence to
  synchronously mounted cache under `pro5-twrp-diag-v13-*`.

The kernel source builds and both hybrid repacks are byte-identical. All 489
ramdisk paths, order and metadata are preserved; only `init.rc` and
`sbin/permissive.sh` data change from v12. V13 has no embedded DTB and leaves
4,202,496 bytes below the physical recovery-partition size. It is a controlled
combined test, not accepted recovery. Its handset test stopped at the Meizu
logo and never exposed USB. The exact partition prefix proves v13 was flashed;
no v13 cache diagnostic exists, so its wrapper and ADB path did not run. V13
is rejected and must not be flashed again.

V11-baseline lightweight-PAN v14 is 29,335,552 bytes with SHA-256
`ddc37377309011ad5954afb85c8ab1f58d0ec958adacb9c7fce0ef6fd721b9bc`.
It starts from the exact partition-proven v11 image and changes only the
kernel component. Four pstore/ramoops files and the defconfig are restored to
the fixed revision that produced v11's booting kernel; the sole remaining
kernel source delta is the Note5-style lightweight PAN implementation in
`decon-int_drv.c`.

The 12,104,105-byte v11 ramdisk remains byte-identical, including the existing
pre-copy-VSYNC display library, direct legacy ADB init, old adbd and synchronous
cache logger. Two clean kernel builds and two hybrid repacks are byte-identical.
The handset reached the complete UI but still blacked out, subsequently lost
touch feedback and returned to Flyme. V14 is rejected and must not be flashed
again.

Legacy forced-mode initialization v16 is 29,335,552 bytes with SHA-256
`7c92a6268b0c4d57dc94b3382ea9cbae7c9c1e6ee74866d6ce611d026e9691d4`.
It starts from the exact v12 image and changes only `sbin/libminuitwrp.so`.
Immediately after `FBIOGET_VSCREENINFO`, the backend now clears `vmode`, sets
`FB_ACTIVATE_FORCE`, and replays the unchanged kernel-provided structure with
`FBIOPUT_VSCREENINFO`, before querying fixed geometry and mmap. This matches
the working TWRP 3.0 instruction order. The existing one-time blank/unblank,
single page, pre-copy VSYNC and post-copy page-zero PAN remain unchanged.

Two clean source builds and two recovery repacks are byte-identical. V16 keeps
the v12 kernel, init, recovery executable, old adbd, cache logger, fstab and
boot geometry byte-for-byte, embeds no DTB and leaves 4,218,880 bytes below the
recovery partition.

Keep the verified Flyme 8 DTB unchanged. Write only the exact v16 image to
`recovery`; do not write `bootimg`, `dtb`, `/dev/block/sdb`, firmware,
parameter, calibration, or identity partitions. Do not wipe, format, install,
restore or perform any other recovery write test. Continuously navigate only
harmless pages and report whether the white line, blackout, touch loss or
automatic reboot occurs.

Flyme-USB-identity v17 is 29,335,552 bytes with SHA-256
`e7d17b0dc4bd0136bb9338a2263f1bad602c75d3d0db123a9e6e512b804c6cda`.
It starts from the exact v16 image and changes only `init.rc`. It publishes
`2a45:0c02`, manufacturer `Meizu`, product `M86` and serial
`860BDNA2225S`, matching the descriptors observed while the running Flyme
system exposed MTP+ADB. Recovery continues to request only the legacy `adb`
function; MTP is deliberately not enabled.

Two independent repacks are byte-identical. The v16 kernel, forced-mode
display library, recovery executable, old adbd, synchronous logger, fstab,
remaining ramdisk paths and boot geometry are unchanged. For this USB test,
v17 supersedes v16. Keep the verified Flyme 8 DTB unchanged and write only the
exact v17 image to `recovery`.

Forced-DWC3-session v18 is 29,335,552 bytes with SHA-256
`975710e9214f8c471791748e42029c623ecb6b9a35e6fc6c856c4a6c77d0943f`.
It starts from the exact v17 image and changes only the kernel component. The
kernel is built twice from the same v11 baseline used by v17, with one
`android_usb` change: writing `android0/enable=1` now sends the DWC3 gadget
VBUS-on event even if Recovery's MUIC path misclassified the connected host
and never set `usb_attach`.

V18 retains the complete v17 ramdisk byte-for-byte, including `2a45:0c02`,
serial `860BDNA2225S`, ADB-only mode, old adbd, v16 display library, recovery
executable, logger and fstab. The baseline DECON source is unchanged. Two
clean kernel builds and two hybrid repacks are byte-identical.

For the next USB test, v18 supersedes v17. Keep the verified Flyme 8 DTB
unchanged and write only the exact v18 `recovery.img` to `recovery`. First
check whether the host enumerates `2a45:0c02`; only after enumeration, restart
the host ADB server and check for serial `860BDNA2225S`. Do not use blackout
behavior as this build's first acceptance criterion and do not write any other
partition.

The handset test accepts v18's USB repair: the host enumerated `2a45:0c02`,
and ADB connected as serial `860BDNA2225S`, product `PRO5`, device `m86`.
Live ADB sampling then identified the display failure. During a black frame,
recovery and adbd remained alive, touch remained responsive, fb0 geometry was
unchanged, and backlight brightness remained 255 with `bl_power=0`. DECON was
instead in `lpd` while DSIM was runtime-suspended. A page-zero PAN immediately
woke DECON and advanced VSYNC, but the driver returned to LPD about 70ms
later. V18 is therefore superseded as a display candidate, while its USB
kernel change is retained.

No-DECON-LPD v19 is 29,335,552 bytes with SHA-256
`aa366fe911ccb31a71bf4ee3213a644b1973bb90229e243d4c9eaa76bb99902e`.
It starts from the exact v18 image and changes only the kernel component. The
new kernel keeps v18's forced-DWC3 gadget session but builds the v11-baseline
DECON with `# CONFIG_DECON_LPD_DISPLAY is not set`. Its SHA-256 is
`45474fdcdd7f354b81e18d4aa13704d9d990838ff562f1625c6ba11f7c036d21`.
Two clean donor builds, their DTBs and kernel configs are byte-identical, as
are two final kernel-only repacks.

The complete v18 ramdisk remains byte-for-byte identical, SHA-256
`ffed93c7672f8b56e83610bd7a983e10f27e8394ce1c718293b8844a93100b64`.
This preserves `2a45:0c02`, serial `860BDNA2225S`, old adbd, the v16 minui
library, recovery executable, logger and fstab. Keep the verified Flyme 8 DTB
unchanged and flash only the exact v19 `recovery.img` to `recovery`. Do not
write any other partition or perform a wipe, format, install or restore.
Keep USB attached, exercise harmless TWRP pages, then leave the device in
Recovery so DECON/DSIM state and kernel logs can be sampled over ADB.

The v19 live test accepts the display and ADB changes. `/proc/config.gz`
confirms DECON LPD is disabled. Across 180 samples from uptime 66 to 289
seconds, DECON stayed `on`, DECON and DSIM stayed active, every VSYNC timestamp
advanced, brightness stayed 255, and recovery plus adbd remained alive. No
LPD transition, runtime suspend, panic, oops or watchdog event occurred.

Functional-cleanup v20 is 29,335,552 bytes with SHA-256
`8bccf65784167228398ae96b372d67232948e2333f96e0407eb25faad52c4d13`.
It starts from the exact v19 image and changes only `init.rc` and
`sbin/recovery` data. The v19 kernel, display library, old adbd, fstab and all
other userspace bytes remain unchanged.

V19's init deliberately set `mtp.crash_check=1`, while its recovery ELF had
the diagnostic `twrp.loghold` string in place of `sys.powerctl`. V20 removes
the forced MTP suppression, adds proven `adb`/`mtp,adb` gadget actions, runs
recovery without the synchronous diagnostic wrapper and restores the exact
unmodified recovery power property. A reversible v19 live probe already
confirmed that the kernel binds MTP and ADB together, macOS enumerates the
composite device and ADB reconnects before and after the transition.

Two ramdisk rewrites and two recovery repacks are byte-identical. All 489 cpio
paths, path order and metadata are retained; only the two declared data
payloads change. Keep the verified Flyme 8 DTB unchanged and flash only the
exact v20 `recovery.img` to `recovery`. First test that MTP and ADB coexist.
Then test one reboot target at a time, beginning with system; do not write any
other partition or perform a wipe, format, install or restore during this
acceptance pass.
