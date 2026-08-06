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
- `device/meizu/m86/`: device configuration and proprietary extraction metadata.
- `vendor/meizu/m86/`: generated vendor build definitions; binaries are ignored.
- `manifests/`: LineageOS and reference-source declarations.
- `overlays/`: case-sensitive source fragments that cannot coexist directly
  in the default macOS working tree.
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
on the builder when available, without printing its contents. LineageOS Git
URLs default to TUNA and retry against GitHub directly. AOSP defaults to USTC,
then retries through BFSU, TUNA, and the accelerated original endpoint.
Manifest URLs remain unchanged for provenance; mirrors and unmatched GitHub
traffic bypass the proxy.
Source synchronization checks out the two GCC 4.9 kernel toolchains first and
then processes each full-manifest project in a separately bounded serial
`repo sync`. `repo 2.65` repeatedly deadlocked its worker pool on this builder
after a project fetch failed, even at `-j1`; per-project processes preserve the
existing object cache, isolate timeouts, and record progress under `run/`.

Typical control flow:

```bash
./remote/bootstrap-builder.sh
./remote/push-local.sh
./remote/start-source-sync.sh
./remote/source-sync-status.sh
./remote/start-platform-sync.sh
./remote/platform-sync-status.sh
./remote/prepare-vendor.sh
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
