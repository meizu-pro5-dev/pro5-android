# Meizu PRO 5 (`m86`) — LineageOS 20.0 / Android 13

UNOFFICIAL. This project is not affiliated with or endorsed by Meizu,
LineageOS or Samsung.

This branch is the reproducible integration workspace for the Meizu PRO 5
Android 13 port. It contains device-owned hardware sources, ordered changes to
upstream Android projects, pinned manifests, revision locks and build tooling.

The Android 12 workspace remains available on the `lineage-19.1` branch, and
the Android 10 workspace on `main`.

## Repository layout

- `hardware/meizu/m86/`: source-owned audio, Bluetooth, Camera3, gatekeeper,
  graphics, media and radio compatibility modules.
- `manifests/lineage-20.0-m86.xml`: m86 and Exynos7420 dependencies.
- `patches/lineage-20.0/`: ordered patches for upstream platform projects.
- `locks/lineage-20.0-revisions.tsv`: validated base, result and tree IDs.
- `tools/install-lineage-20.0-hardware.sh`: installs the device hardware tree.
- `tools/apply-lineage-20.0-patches.sh`: validates and applies the patch queue.
- `docs/lineage-20.0-bringup.md`: Android 13 scope and known blockers.

## Source repositories

The following full repositories are maintained by the
[`meizu-pro5-dev`](https://github.com/meizu-pro5-dev) organization:

- `android_device_meizu_m86`
- `android_kernel_meizu_m86`
- `android_vendor_meizu_m86`
- `android_hardware_samsung_slsi-linaro_exynos`

They are complemented by the device-owned source and upstream patch queue in
this repository.

## Preparing a source tree

Initialize LineageOS 20.0:

```sh
repo init -u https://github.com/LineageOS/android.git -b lineage-20.0
mkdir -p .repo/local_manifests
cp /path/to/pro5-android/manifests/lineage-20.0-m86.xml \
  .repo/local_manifests/m86.xml
repo sync
```

Install device-owned hardware and apply the platform queue:

```sh
/path/to/pro5-android/tools/install-lineage-20.0-hardware.sh "$PWD"
/path/to/pro5-android/tools/apply-lineage-20.0-patches.sh "$PWD"
```

Populate `vendor/meizu/m86/proprietary/` from a legally obtained stock Flyme
image using the extraction tooling in the device repository. Proprietary files
are deliberately absent from all public repositories.

Build:

```sh
source build/envsetup.sh
lunch lineage_m86-userdebug
m bacon
```

## Current scope

The Android 13 checkpoint completes a full `bacon` build, including the native
Exynos7420 Camera3 modules, boot/recovery/system images and the non-A/B OTA.
Camera migration is deliberately limited to the completed 74xx implementation;
the SLSI 34xx camera tree is unchanged from its Android 13 Exynos7420 base. The
OTA packages the locally staged, hash-locked stock Flyme DTB for the dedicated
`dtb` partition. Device runtime validation remains pending.
A property-gated no-BPF patch queue is included to unblock the first boot on
the 3.10 kernel, but networking remains unqualified and may lack accounting or
policy enforcement. GPU memory/work BPF accounting is also disabled in that
mode so gpuservice remains available. The coherent eBPF/cgroup backport used by the other
Exynos7420 LineageOS 20 devices remains the required final implementation.

## Publication policy

No proprietary library, stock firmware, device evidence, build output or
flashable artifact is committed here. In particular,
`hardware/meizu/m86/camera/libexynoscamera_stock/libexynoscamera.so` is a local
input only and is explicitly ignored.

See `LICENSING.md`, `NOTICE`, `CONTRIBUTING.md` and `SECURITY.md` before
redistributing or contributing changes.
