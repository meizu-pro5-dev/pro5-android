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
- `twrp/`: independent TWRP 3.7.0_9 device tree and flashing boundary.
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
URLs default to GitHub through that acceleration, then retry through the
CERNET MirrorZ selector, TUNA, and the accelerated original endpoint. AOSP
defaults to USTC, then retries through BFSU, TUNA, and the accelerated original
endpoint. Manifest URLs remain unchanged for provenance; Chinese mirrors
bypass the proxy while GitHub uses the acceleration.
Source synchronization checks out the two GCC 4.9 kernel toolchains first and
then processes each full-manifest project in a separately bounded serial
`repo sync`. `repo 2.65` repeatedly deadlocked its worker pool on this builder
after a project fetch failed, even at `-j1`; per-project processes preserve the
existing object cache, isolate timeouts, and record progress under `run/`.
Interrupted runs reuse completed checkouts only when the stored manifest hash
still matches, so a source refresh cannot accidentally consume stale progress.

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
./remote/start-build.sh bacon
./remote/fetch-lineage-artifacts.sh
./remote/start-twrp-source-sync.sh
./remote/twrp-source-sync-status.sh
./remote/start-twrp-build.sh
./remote/twrp-build-status.sh
./remote/fetch-twrp-artifacts.sh
```

`start-build.sh` accepts `kernel`, `bootimage`, `recoveryimage`, or `bacon`.
It applies the checked-in platform patches and installs the local device,
kernel, and vendor trees before launching a logged build in tmux. Override the
memory-safe default 8-way build with `PRO5_BUILD_JOBS`. The builder exposes
more host RAM than the job cgroup permits, so high parallelism can make
`dex2oat` fail an otherwise valid build with `ENOMEM`.

`start-kernel-build.sh` is the earlier standalone gate. It needs only the
LineageOS GCC 4.9 prebuilts, builds the unmodified m86 `Image` and raw
`exynos7420-m86-codegen.dtb` in an external output directory, and records the
local source commit plus both toolchain revisions.

TWRP uses a separate minimal `twrp-9.0` checkout and output directory. The
builder installs the local TWRP device tree and the same maintained m86
kernel, injects the hash-locked Flyme 8 STM touch firmware, builds
`recovery.img` plus its separate raw DTB twice after independently cleaning
the same absolute output root, and rejects differing recovery, DTB, or
kernel-config bytes. The checked-in TWRP patches sort the embedded ramdisk
inventories and omit nondeterministic host PCRE2 bytecode from
`file_contexts.bin`. It
also rejects an image whose embedded firmware, v0 header, gzip ramdisk,
addresses, page size, DT placement, or recovery partition limit differs from
the verified Flyme contract. The resulting artifact directory contains a
pinned upstream manifest, source revision, stock-base lock, generated kernel
config, reproducibility record, hashes, and an explicit flashing boundary. A
successful build does not authorize a phone write.

Environment variables can override the non-secret connection defaults:
`PRO5_BUILDER_HOST`, `PRO5_BUILDER_PORT`, and `PRO5_REMOTE_ROOT`.

## Initial target

- OS: LineageOS 17.1 / Android 10
- device codename: `m86`
- SoC: Samsung Exynos 7420
- boot chain: stock Meizu bootloader and partition layout
- first milestone: reproducible kernel plus recovery/boot image
- recovery acceptance: source-built TWRP 3.7.0_9 with ADB/sideload, MTP,
  legacy FDE, internal storage, microSD/OTG, image backup/flash, and Chinese
- later milestones: display/adb, storage, radio, Wi-Fi/Bluetooth, audio,
  sensors/GPS, camera, encryption, and SELinux enforcing

The phone backup phase is intentionally paused. No flashing or destructive
device operation is performed by these scripts.

The current build-only result, artifact hashes, and unresolved handset gates
are recorded in `docs/static-acceptance-2026-08-07.md`.
