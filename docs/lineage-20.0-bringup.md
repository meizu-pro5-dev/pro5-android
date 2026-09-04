# LineageOS 20.0 / Android 13 bring-up

This branch records the initial Android 13 source state for the Meizu PRO 5
(`m86`). It is an unofficial development port, not a runtime-qualified release.

## Camera migration boundary

Only the completed Exynos74xx native Camera3 work is carried into the
LineageOS 20 SLSI tree. `libcamera/34xx` is kept byte-for-byte at the
`samsung7420/lineage-20.0-unify` base; no m86 Camera3 changes may be placed
there. The m86 kernel-facing metadata remains the four-node Exynos7420 ABI.

The Android 13 build adaptations are split between:

- `hardware/samsung_slsi-linaro/exynos/libcamera/74xx` and `common_v2`;
- the device-owned `hardware/meizu/m86/camera/libexynoscamera3_m86` target;
- the graphics, OpenMAX, framework and Camera2 compatibility queue.

## Platform queue boundary

The maintained LineageOS 20 queue contains eleven hardware compatibility
patches. Ten are Android 13 adaptations of the final LineageOS 19.1 fixes:
two `frameworks/av` patches, one `hardware/interfaces` patch, one SLSI graphics
patch, four SLSI OpenMAX patches, one Camera2 patch and one NFC patch. The
eleventh is the LineageOS 20-specific legacy Wi-Fi RTT enum compatibility patch
under `hardware/lineage/interfaces`.

Two fixes added to LineageOS 19.1 after this branch was opened are carried
directly rather than as platform patches:

- `tools/extract-stock-files.py` accepts both integer and enum-like inode mode
  values;
- the m86 `ExynosCamera3FrameFactoryPreviewM86.cpp` records the first stop
  error while continuing the complete FLITE/3AA/GSC software cleanup.

The broader Android 12 stock-extraction and native-only camera-route cleanup
is not copied wholesale: LineageOS 20 retains its version-specific camera
rollback and stock-DTB topology boundaries.

## Device-common independence

The m86 product does not sync, inherit or parse
`device/samsung/universal7420-common`. The two MFC sandbox syscall additions
are device-owned under `device/meizu/m86/seccomp`; the obsolete common header
path and Soong namespace have been removed. Exynos7420 support is consumed
directly from the pinned Samsung SLSI repositories.

## Network status

The temporary Android 12 `system/bpf` checkpoint and the property-gated
no-BPF platform queue have been retired. `frameworks/native`,
`packages/modules/Connectivity`, `packages/modules/NetworkStack`, `system/bpf`,
`system/core` and `system/netd` therefore remain byte-for-byte at their
manifest-pinned LineageOS 20 bases.

The Android 13 source state requires device-owned cgroup-v2 configuration and
a coherent native kernel eBPF backport. Per-UID traffic accounting, Data
Saver/firewall enforcement, tethering/offload and GPU BPF accounting remain
runtime qualification gates until that path is validated on hardware.

The reference Exynos7420 LineageOS 20 kernel uses a coherent eBPF/cgroup
backport, enables `CONFIG_BPF`, `CONFIG_BPF_SYSCALL`, `CONFIG_CGROUP_BPF`,
`CONFIG_NET_CLS_BPF`, `CONFIG_NET_ACT_BPF` and `CONFIG_BPF_JIT`, and reports a
newer kernel version to `bpfloader`. The m86 port now follows that subsystem
model instead of carrying platform bypasses. Device and kernel revision locks
must be advanced only after the native source state passes build and runtime
validation.

Reference branch:
`samsungexynos7420/android_kernel_samsung_universal7420`,
`lineage-20.0-unify-clang-2`.

The comparison was made at reference head
`1de3d6e11448b14de2a6cd7dcc6f2ec94887d833`. Representative changes include
the arm64 eBPF JIT (`f8138d2e86a`), arm64 `bpf()` syscall wiring
(`14f448d9ec4`), cgroup program support (`e47c736426f` and `697d0cdd523`),
defconfig enablement (`6713ec6c150` and `65a045face4`) and the kernel-version
compatibility workaround (`122a5d0b7a4`). These changes form a subsystem
backport, not an independently safe list of cherry-picks. The reference and
m86 kernel histories have no common Git merge base, so the stack should be
ported and tested by subsystem; the version workaround must not be applied by
itself.

## Reproducing the source state

1. Initialize LineageOS 20.0 and copy `manifests/lineage-20.0-m86.xml` to
   `.repo/local_manifests/m86.xml`.
2. Sync after the listed m86/SLSI branches have been published.
3. Run `tools/install-lineage-20.0-hardware.sh` with the Android source root.
4. Run `tools/apply-lineage-20.0-patches.sh` with the same root.
5. Populate proprietary files from a legally obtained stock Flyme image.
6. Ensure the arm64 Chromium WebView Git LFS object is checked out; a pointer
   file is not a valid input APK.
7. Stage the stock Flyme DTB at `device/meizu/m86/prebuilt/dtb.img` and verify
   it with the device repository's hash-locked prebuilt checks.
8. Select `lineage_m86-userdebug` and build.

Exact repository and tree IDs are recorded in
`locks/lineage-20.0-revisions.tsv`.

## Build checkpoint

The previous source checkpoint successfully completed a full `m bacon` build,
including `libexynoscamera3_m86`, `camera.m86`, the m86 power service, the
legacy Wi-Fi HAL service, boot/recovery/system images, target-files and the
non-A/B OTA package. That result predates retirement of the no-BPF queue and
does not validate the native eBPF transition. The build was produced after
populating the arm64 WebView
LFS object and staging the deliberately untracked, hash-locked stock Flyme DTB.

The packaged `dtb.img`, target-files `RADIO/dtb.img` and source input all match
the locked Flyme SHA-256, and the generated updater script installs it to the
dedicated m86 `dtb` partition. Do not replace it with a kernel-generated DTB:
the device tree currently specifies the stock Flyme DTB ABI. Disabling the
apparently unpopulated FIMC-IS sensor2 and sensor3 nodes caused an immediate
Meizu-logo reboot loop; flashing the byte-identical stock DTB with the same
build restored Android boot. Keep both nodes enabled until the Exynos7420
camera topology dependency is removed in source. On-device validation remains
pending for RIL, Wi-Fi, mobile data, traffic accounting/policy, camera capture
and recording.

## First runtime evidence

The first Android 13 device log and tombstone bundle reached zygote,
SurfaceFlinger and `system_server`, then blocked in `StartAudioService` waiting
for `media.audio_policy`. The generic Android 13 audio service aborted before
HAL registration with `Binder threadpool cannot be shrunk after starting`:
it started the legacy vndbinder pool and then attempted to reduce the same
libbinder process pool through libbinder_ndk. The m86 product now owns the
proven Exynos7420 HIDL-only audio service boundary and does not link
libbinder_ndk.

The same evidence showed gpuservice aborting in the pinned `GpuWork` map
constructor after the 3.10 kernel returned `ENOSYS` for syscall 280 (`bpf`).
That failure must now be resolved by the native kernel eBPF implementation;
the platform queue no longer suppresses either GPU accounting collector.
