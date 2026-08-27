# Meizu PRO 5 (`m86`) — LineageOS 19.1 / Android 12

UNOFFICIAL. This project is not affiliated with or endorsed by Meizu,
LineageOS or Samsung.

This branch is the reproducible integration workspace for the Meizu PRO 5
Android 12 port. It contains device-owned hardware sources, ordered changes to
upstream Android projects, pinned manifests, revision locks and build tooling.

The Android 10 workspace remains available on the `main` branch.

## Repository layout

- `hardware/meizu/m86/`: source-owned audio, Bluetooth, Camera3, gatekeeper,
  graphics, media and radio compatibility modules.
- `manifests/lineage-19.1-m86.xml`: pinned device and Exynos dependencies.
- `patches/lineage-19.1/`: ordered patches for upstream platform projects.
- `locks/lineage-19.1-revisions.tsv`: validated base, result and tree IDs.
- `tools/install-lineage-19.1-hardware.sh`: installs the device hardware tree.
- `tools/apply-lineage-19.1-patches.sh`: validates and applies the patch queue.
- `docs/lineage-19.1-native3.md`: publication and source preparation notes.

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

Initialize LineageOS 19.1:

```sh
repo init -u https://github.com/LineageOS/android.git -b lineage-19.1
mkdir -p .repo/local_manifests
cp /path/to/pro5-android/manifests/lineage-19.1-m86.xml \
  .repo/local_manifests/m86.xml
repo sync
```

Install device-owned hardware and apply the platform queue:

```sh
/path/to/pro5-android/tools/install-lineage-19.1-hardware.sh "$PWD"
/path/to/pro5-android/tools/apply-lineage-19.1-patches.sh "$PWD"
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

The development snapshot includes native Exynos7420 Camera3 preview, front and
rear still capture, multi-output request handling, legacy Camera API support,
MFC/OMX recording compatibility, mBack input policy and the Android 12 legacy
kernel compatibility layer. It remains a development port and should not be
treated as a production release.

## Publication policy

No proprietary library, stock firmware, device evidence, build output or
flashable artifact is committed here. In particular,
`hardware/meizu/m86/camera/libexynoscamera_stock/libexynoscamera.so` is a local
input only and is explicitly ignored.

See `LICENSING.md`, `NOTICE`, `CONTRIBUTING.md` and `SECURITY.md` before
redistributing or contributing changes.
