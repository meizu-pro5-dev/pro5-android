# Meizu PRO 5 Android 10 porting strategy

## Decision

Build LineageOS 17.1 as a legacy, non-Treble Android 10 target on the stock
Meizu boot chain and partition layout. Keep the last hardware-booting m86
kernel as the initial kernel base, then port Android 10 compatibility changes
from the maintained universal7420 kernel. Reuse the universal7420 userspace
only at the Exynos platform boundary; retain Meizu-specific DT, display,
radio, audio, camera, sensors, fingerprint, NFC, and storage definitions.

This is intentionally not a GSI-only plan. PRO 5 launched before Treble and
its Android 7 vendor binaries require a device-specific compatibility layer.

## Evidence layers

| Layer | Role | Local authority |
| --- | --- | --- |
| Flyme 8.0.5.0A | firmware ABI, boot geometry, partitions, production blobs | `locks/stock-flyme-8.0.5.0A.sha256`, `docs/stock-base.md` |
| m86 cm-14.1-latest | last community hardware implementation and blob inventory | `legacy/device-meizu-m86-cm14` at commit `26c4527...` |
| m86 kernel cm-14.1 | first-boot kernel and Meizu drivers/DT | imported into `kernel/meizu/m86` at the locked reference SHA |
| universal7420 17.1 | Android 10 Exynos 7420 build, kernel, graphics/media and common HAL reference | `manifests/pro5.xml`, generated source locks |
| LineageOS 17.1 | Android 10 framework and build system | remote full checkout plus pinned manifest XML |

No generated image is considered reproducible unless its Lineage manifest,
reference revisions, local Git commit, build command, log, size, and SHA-256
are retained locally.

The current proprietary-file and platform-ABI boundary is tracked in
`docs/blob-abi.md`; a matching SONAME alone is never treated as compatibility
proof.

## Boot-chain boundary

The Samsung donor cannot supply boot-image settings. PRO 5 requires:

- bootloader board name `PRO5`;
- boot image base `0x40078000`;
- effective kernel address `0x40080000`;
- ramdisk offset `0x01f88000`, producing address `0x42000000`;
- 4096-byte boot pages;
- uncompressed arm64 `Image`;
- a raw DTB in the separate `dtb` partition;
- `bootimg` rather than Samsung's `BOOT` partition name.

Samsung's custom boot-image makefile, 2048-byte pages, base `0x10000000`,
dtbhtool container, and appended/separated-DT boot packaging are explicitly
disabled. The custom ROM never writes `/dev/block/sdb`, `bootloader`, `ldfw`,
or `bootlogo`.

## Kernel approach

The first kernel branch is the hardware-proven m86 3.10 tree. The repository's
`staging/lineage-15.1` branch is behind `cm-14.1`, not ahead, so it is not a
better base. The universal7420 LineageOS 17.1 kernel is a patch donor and
behavioral reference.

Kernel work is split into reviewable groups:

1. reproduce the historical `cm_pro5_defconfig` build with LineageOS 17.1's
   GCC toolchain and no functional changes;
2. fix modern host/compiler breakage and rename the final config only after
   the unchanged baseline hash is recorded;
3. compare Android binder/ashmem/ION, namespaces, seccomp, cgroups, SELinux,
   filesystem, networking, and power interfaces against universal7420 17.1;
4. port only required Android 10 changes while preserving Meizu board files,
   UFS definitions, panel/touch, clocks, regulators, thermal policy, modem,
   audio, sensor-hub, NFC, and camera drivers;
5. build the raw DTB separately and compare its nodes, size, and bootloader
   expectations with the verified Flyme DTB;
6. enable stricter security and power options only after recovery and Android
   boot evidence exists.

A wholesale switch to Samsung's device kernel is rejected for the first boot:
the SoC is shared, but the board wiring and peripheral driver set are not.

## Same-SoC reuse boundary

The universal7420 project is authoritative for Android 10 integration of:

- Exynos 7420 build-system exceptions and its `build/soong` fork;
- 64/32-bit architecture and Binder configuration;
- Exynos5/7420 graphics allocation, composition, MFC/media and OpenMAX source;
- Android 10 HIDL service patterns and legacy HAL shims;
- relevant 3.10 Android kernel backports;
- general Exynos UFS, ION, DMA-buf, Renderscript and codec integration.

It is only a reference for the following and must not be copied blindly:

- boot image, partition names/sizes, recovery fstab and OTA releasetools;
- panel/backlight, touch keys, fingerprint and vibrator sysfs paths;
- camera sensors, calibration, flash and ISP firmware;
- modem provisioning, RIL libraries and EFS/MNV semantics;
- audio codec, Audience/TFA tuning and the Hi-Fi DAC path;
- Wi-Fi calibration, Bluetooth address storage and firmware selection;
- thermal tables, charging policy and CPU/GPU voltage/frequency tuning.

The checked-in patch teaches universal7420 common code that `m86` is a valid
target without classifying it as a Galaxy S6 (`zero`) or Note 5 (`noble/zen`).

## Userspace subsystem plan

### Graphics and media

Start with the Flyme 8 32/64-bit Mali, gralloc, HWC, Exynos MFC/OMX and support
libraries. Compare exported symbols and DT/kernel ioctls with the Android 10
universal7420 Exynos HALs. Prefer open universal7420 wrapper code; use narrowly
scoped linker namespace or symbol shims only when the stock ABI requires it.
The first UI milestone may temporarily use HWC1-to-HWC2 adaptation, but every
workaround must be captured as source and tied to a log.

### Radio

PRO 5 exposes the Exynos/Shannon `ss333` family but uses Meizu SITRIL blobs and
its own modem provisioning. Preserve `efs` and `mnv` read/write behavior and
never substitute Galaxy modem firmware. Bring up the radio daemon and SIM
state before data/IMS. Keep Android's RIL compatibility layer isolated from
the framework; do not carry the old forked full `libril` unless symbol evidence
proves a smaller shim cannot work.

### Audio

Treat the Flyme 8 `audio.primary.m86` interfaces, TFA9890 speaker tuning,
Audience ES705 firmware and PRO 5 Hi-Fi path as one device-specific stack.
Universal7420 audio policy structure can be reused, but Samsung codec routes
cannot. Validate normal playback/capture first, then calls, Bluetooth, speaker
protection, headset, and Hi-Fi DAC modes.

### Wi-Fi and Bluetooth

Use the m86 Broadcom `bcmdhd` kernel driver and verified Flyme firmware and
calibration. Audit BCM43455/BCM4349 firmware selection rather than assuming a
Galaxy file. Reuse Android 10 legacy Wi-Fi service patterns and Broadcom vendor
HAL interfaces where ABI-compatible. Preserve the actual Meizu Bluetooth MAC
storage path after it is confirmed from stock runtime evidence.

### Camera

The stock inventory identifies an IMX230 rear path and multiple front-sensor
setfiles. Keep Meizu calibration and flash control. First make the provider
enumerate cameras without opening them, then preview, still capture, recording
and flash. Port universal7420 camera wrappers selectively; never advertise
FULL/RAW capability until runtime tests support it.

### Sensors, GPS, NFC and fingerprint

- Sensors: preserve the Meizu sensor-hub driver, firmware and calibration
  sysfs ABI; wrap the stock HAL behind Android 10's sensors service.
- GPS: inspect and shim the verified Flyme `gps.default`/gps daemon ABI before
  declaring a GNSS HIDL version.
- NFC: use the actual NXP PN547/P61 device nodes and Flyme firmware/config,
  not Samsung S.LSI NFC configuration.
- Fingerprint: retain FPC device/input behavior; port to the Android 10
  biometrics service only after enrollment/authentication storage paths and
  TrustZone dependencies are understood.

## Proprietary-file rules

The inherited cm-14.1 list is an inventory seed, not a final vendor tree.
Every file must be reconciled with the verified Flyme 8 system image:

1. confirm existence and SHA-256;
2. record ELF class, SONAME, needed libraries and undefined symbols;
3. place it in the Android 10 legacy `system/vendor` layout;
4. identify firmware that belongs outside the system image;
5. generate makefiles using LineageOS 17.1 `extract_utils.sh`;
6. add a shim only for a concrete missing symbol or namespace error;
7. keep proprietary bytes out of the local Git history while retaining the
   extraction list, generated build definitions and hashes locally.

## Milestones and gates

| Milestone | Build gate | Device gate |
| --- | --- | --- |
| K0 source lock | all remote and stock revisions recorded | none |
| K1 kernel | `Image` and raw DTB build twice identically | none |
| R1 recovery | recovery image fits 33,550,336 bytes; boot header matches stock | recovery display, keys and adb; no data mount required |
| B1 boot ramdisk | boot image fits 25,161,728 bytes; init rc validates | kernel/init logs and adb, even if UI is absent |
| U1 Android UI | system image fits 2,684,350,464 bytes | SurfaceFlinger/UI, storage and stable suspend/resume |
| C1 connectivity | Wi-Fi/BT/radio/audio modules build with audited blobs | calls/data, Wi-Fi, BT and normal audio tests |
| M1 multimedia | camera/media/sensors/GPS/NFC/fingerprint services build | subsystem test matrix with logs |
| S1 release | SELinux policy compiles enforcing; reproducible ZIP and hashes | encryption/upgrade/thermal/battery soak and rollback test |

Phone backup and all flashing gates remain paused until explicitly resumed.
Build-only work may continue independently on AutoDL.

## Current high-risk items

- Android 10 compatibility of the m86 3.10 kernel and its binder/SELinux
  interfaces;
- stock Android 7 graphics and media blobs under Android 10 linker namespaces;
- Meizu SITRIL and TrustZone dependencies;
- absent or incomplete source for sensor-hub, fingerprint and camera glue;
- exact cache/GPT sizes not yet refreshed from the current handset because the
  backup phase is paused;
- final SELinux policy for legacy vendor daemons.

These risks are addressed in dependency order. Camera, fingerprint and Hi-Fi
do not block the first kernel/recovery/adb milestone.
