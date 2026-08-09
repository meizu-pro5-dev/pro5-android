# Meizu PRO 5 TWRP device tree

This is the source-built recovery tree for the `m86` acceptance target. It is
intended for the maintained local m86 kernel and the official minimal TWRP
`twrp-9.0` manifest, whose recovery component reports TWRP `3.7.0_9`.

The partition names, FDE key location, boot-image geometry, display path, and
removable-storage sysfs paths come from the verified Flyme 8.0.5.0A base and
the previously booting PRO 5 recovery evidence. The build injects only the
hash-locked Flyme 8 `st_fts.bin` required by the STM touch driver's automatic
firmware check; the same bytes were present in the old working TWRP ramdisk.
No old SuperSU payload, TWRP app, prebuilt recovery kernel, HAL, or Android 7
platform library is included.

V4 and v5 device logs together show that Exynos DECON hangs when fbdev's first
double-buffer flip switches from page 0 to `yoffset=1920`. Forced single
buffering avoids that hang and boots through the main TWRP page. V5 retained
the bootloader logo because upstream fbdev skipped its initial page-zero
selection whenever `double_buffered` was false. V6 selected the already
cleared page 0 and consequently produced a pure black panel while TWRP still
loaded the full theme, entered the main GUI, timed out and handled key wake.

The runtime kernel identifies DECON as MIPI command mode. Its mapped
framebuffer does not transmit a new panel frame merely because userspace copied
new pixels into page 0; `FBIOPAN_DISPLAY` runs the DECON page programming,
hardware-trigger and VSYNC path. The reviewed minuitwrp patches therefore
permit the initial `yoffset=0` selection and issue a page-zero PAN after every
forced-single-buffer copy. They never select page 1 or `yoffset=1920`.

V7 device logs then show the main GUI remains alive when the display goes dark
after the configured timeout: brightness changes from 255 to 0, touch events
continue changing pages and waking brightness to 255, and no panic, oops or
watchdog reset occurs. V9 then proved that compiling out only DECON/DSI
`FBIOBLANK` is insufficient: the UI stayed touch-responsive but the panel still
went black. The owner observed the same failure during continuous touch, which
rejects idle timeout as the primary cause. `TW_NO_SCREEN_BLANK` and
`TW_NO_SCREEN_TIMEOUT` remain defensive isolation settings.

The v7 refresh workaround calls `FBIOPAN_DISPLAY` after every changed frame.
On this kernel, each call runs the full `decon_set_par()` path, rewrites window
state, toggles the hardware trigger and waits for VSYNC. Touch-driven redraw
bursts therefore repeatedly reprogram live command-mode DECON. The original
working TWRP binary waited for `FBIO_WAITFORVSYNC` before overwriting its
single scanout page; the maintained fbdev path now restores that ordering so
each refresh is paced to the panel before the page-zero copy and PAN.

The maintained kernel's `android_usb` gadget compiles `f_fs.c` directly, just
like the Exynos 7420/8890 recovery implementations used for comparison. The
standalone `CONFIG_USB_FUNCTIONFS` gadget remains disabled to avoid registering
a second FunctionFS implementation. Upstream recovery mounts
`/dev/usb-ffs/adb`; the device rc selects its v1/synchronous compatibility path
and then performs one ordered ADB-only transition after `post-fs`.

The connected Flyme system was read back before this change and proved its
working ADB gadget uses `18d1:4ee7`, `functions=adb`, and a configured state.
Recovery now uses that exact VID/PID for ADB-only mode instead of advertising
the `4ee2` MTP+ADB PID with no MTP interface. TWRP may still switch to
`18d1:4ee2`; MTP is explicitly bound to the Exynos legacy `/dev/mtp_usb`
character device. USB mass-storage mode is disabled because m86 uses
data/media and the class LUN path is not part of its recovery gadget layout.

The v10 isolation keeps the proven old `/dev/android_adb` transport and
configures `18d1:4ee7` directly from init's boot action. It intentionally has
no USB property action, FunctionFS mount, MTP mode or adbd restart sequence.
This diagnostic path is separate from the maintained full-source FunctionFS
configuration above. V11 retains that direct ADB path byte-for-byte and changes
only `libminuitwrp.so`, adding the old working backend's pre-copy VSYNC pacing
before each page-zero copy and PAN. The retained diagnostic serial therefore
remains `PRO5TWRPV10` even though the display candidate is v11.

V11 still blacked out during continuous interaction and its direct gadget
never enumerated. V12 suppressed the late synthesized framebuffer-mode
request while preserving the kernel geometry; its handset test showed a top
white line and intermittent complete frames after page changes. A fresh
instruction-level audit corrected the earlier initialization reading: the
working TWRP 3.0 library replays the kernel-provided mode immediately after
`FBIOGET_VSCREENINFO`, with `vmode=0` and `FB_ACTIVATE_FORCE`, before it reads
fixed geometry or maps framebuffer memory. The maintained backend now
reproduces this early one-time transaction while retaining the v12 single-page
VSYNC/copy/PAN loop.

The contemporary Galaxy Note5 Exynos 7420 DECON driver is applicable more
directly to the remaining refresh failure: its PAN callback updates the
scanout address, triggers the command-mode transfer and waits for VSYNC without
calling `decon_set_par()` on every frame. The m86 callback now follows that
lightweight transaction. Note5-specific panel resolution, pixel format,
brightness and BoardConfig settings are deliberately not copied.

The v13 combined diagnostic retains the v12 fbdev library and uses that kernel
path. Its legacy minadbd opens `/dev/android_adb` while the gadget is disabled;
the synchronous wrapper waits for the kernel `adb_open` marker before enabling
`2a45:0c01` / `PRO5TWRPV13`, then records periodic USB state to cache. This is
test instrumentation, not the final maintained FunctionFS/MTP configuration.

V13 stopped at the Meizu logo before that wrapper created any persistent file.
The exact recovery-partition prefix and repeated v8 result reject using the
whole later pstore/ramoops kernel for this isolation, but do not reject the PAN
change itself. V14 therefore restores the SHA-locked source baseline that
produced v11's booting kernel. Relative to that baseline, only
`decon-int_drv.c` changes. V14 also restores the complete v11 ramdisk
byte-for-byte, so it is the controlled display-only test of lightweight PAN;
ready-first ADB is deferred until this kernel reaches TWRP.

The source intentionally does not expose `/dev/block/sdb`, `ldfw`, `param`,
`proinfo`, `private`, or `rstinfo`. These targets are unnecessary for normal
recovery operation and an accidental write can destroy the bootloader,
firmware, calibration, or unique device data.
