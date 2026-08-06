# Meizu PRO 5 Android 10 bring-up

This repository is the reproducible, host-side source of truth for bringing
LineageOS 17.1 (Android 10) to the Meizu PRO 5 (`m86`, Exynos 7420).

The full LineageOS checkout, reference repositories, compiler cache, build
output, and generated images live on the AutoDL builder. All authored porting
work stays here: device configuration, kernel changes, vendor extraction
metadata, manifests, patches, build scripts, source locks, and bring-up notes.

## Layout

- `device/meizu/m86/`: Android device configuration authored for this port.
- `kernel/meizu/m86/`: maintained kernel source used by the port.
- `vendor/meizu/m86/`: extraction scripts and proprietary-file metadata.
- `manifests/`: LineageOS and reference-source declarations.
- `patches/`: reproducible changes to upstream Android repositories.
- `legacy/`: immutable imported community baselines kept outside Android's
  module-discovery paths.
- `remote/`: builder bootstrap, synchronization, and build control scripts.
- `locks/`: immutable upstream revisions and generated manifest snapshots.
- `docs/`: design decisions, hardware findings, and bring-up records.
- `evidence/`: locally retained logs and device/build evidence.

Proprietary binaries, complete Android source mirrors, `out/`, and flashable
artifacts are deliberately not versioned in this repository.

## Builder

The default builder is `REDACTED_BUILDER_ENDPOINT`. Persistent
state is kept below `/root/autodl-tmp/pro5-android10`; the small root overlay is
never used for Android source or build output. `/etc/network_turbo` is sourced
on the builder when available, without printing its contents. Google-hosted
Android traffic uses that acceleration, while GitHub domains bypass it because
direct transfers are measurably faster and more reliable on this builder.
Source synchronization checks out the two GCC 4.9 kernel toolchains first and
then uses separate network and checkout phases to avoid an observed `repo`
interleaved-worker deadlock. Override its conservative four-way concurrency
with `PRO5_SOURCE_SYNC_JOBS` (maximum 16).

Typical control flow:

```bash
./remote/bootstrap-builder.sh
./remote/push-local.sh
./remote/start-source-sync.sh
./remote/source-sync-status.sh
./remote/push-stock-blobs.sh
./remote/start-platform-sync.sh
./remote/platform-sync-status.sh
./remote/start-kernel-build.sh
./remote/kernel-build-status.sh
./remote/start-build.sh bootimage
./remote/build-status.sh
```

`start-build.sh` accepts `kernel`, `bootimage`, `recoveryimage`, or `bacon`.
It applies the checked-in platform patches and installs the local device,
kernel, and vendor trees before launching a logged build in tmux. Override the
default 24-way build with `PRO5_BUILD_JOBS`.

`start-kernel-build.sh` is the earlier standalone gate. It needs only the
LineageOS GCC 4.9 prebuilts, builds the unmodified m86 `Image` and raw
`exynos7420-m86-codegen.dtb` in an external output directory, and records the
local source commit plus both toolchain revisions.

Environment variables can override the non-secret connection defaults:
`PRO5_BUILDER_HOST`, `PRO5_BUILDER_PORT`, and `PRO5_REMOTE_ROOT`.

## Initial target

- OS: LineageOS 17.1 / Android 10
- device codename: `m86`
- SoC: Samsung Exynos 7420
- boot chain: stock Meizu bootloader and partition layout
- first milestone: reproducible kernel plus recovery/boot image
- later milestones: display/adb, storage, radio, Wi-Fi/Bluetooth, audio,
  sensors/GPS, camera, encryption, and SELinux enforcing

The phone backup phase is intentionally paused. No flashing or destructive
device operation is performed by these scripts.
