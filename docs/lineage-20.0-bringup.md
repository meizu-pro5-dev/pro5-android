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

## Device-common independence

The m86 product does not sync, inherit or parse
`device/samsung/universal7420-common`. The two MFC sandbox syscall additions
are device-owned under `device/meizu/m86/seccomp`; the obsolete common header
path and Soong namespace have been removed. Exynos7420 support is consumed
directly from the pinned Samsung SLSI repositories.

## Network status

The Android 12 `system/bpf` compatibility patch is retained only as a build
checkpoint. It does not make the 3.10 kernel satisfy Android 13 networking.

For the first Android 13 boot, the patch queue now provides an explicit
temporary no-BPF mode selected by the device property
`ro.kernel.ebpf.supported=false`. The mode:

- lets init continue when the 3.10 cgroup layout cannot create an Android 13
  process group;
- lets netd continue without a cgroup v2 root, BPF handler initialization or
  bandwidth-controller initialization;
- makes NetworkStats tolerate missing pinned BPF maps and retain its legacy
  `xt_qtaguid` fallback;
- keeps IpClient on netd callbacks instead of the Android 13 direct-netlink
  parser.

The changes are narrowly property-gated: devices that do not explicitly set
the property to false retain the upstream fail-closed paths. They were adapted
from the `8890q/patches` LineageOS 20 no-BPF pattern, with the map-result checks
corrected and the m86-specific missing-cgroup-v2 failure covered. This is a
boot-enablement path, not a networking qualification. Per-UID traffic
accounting, Data Saver/firewall enforcement and tethering/offload may be
incomplete until they are tested on hardware.

The reference Exynos7420 LineageOS 20 kernel uses a coherent eBPF/cgroup
backport, enables `CONFIG_BPF`, `CONFIG_BPF_SYSCALL`, `CONFIG_CGROUP_BPF`,
`CONFIG_NET_CLS_BPF`, `CONFIG_NET_ACT_BPF` and `CONFIG_BPF_JIT`, and reports a
newer kernel version to `bpfloader`. The m86 kernel does not yet contain that
stack. Runtime networking therefore remains an explicit bring-up blocker. Once
the kernel backport is implemented, remove the false property and retire this
temporary no-BPF queue; it must not become the final networking architecture.

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

The current source checkpoint successfully builds `libexynoscamera3_m86`,
`camera.m86`, `bootimage`, the temporary no-BPF `init`/`netd`/Connectivity/
NetworkStack targets, the m86 power service, the legacy Wi-Fi HAL service and
`systemimage`. The resulting system image was produced from a clean Android 13
dependency build after the arm64 WebView LFS object was populated.

The first blocker in a full `bacon` build is the deliberately untracked,
hash-locked stock input `device/meizu/m86/prebuilt/dtb.img`. Do not replace it
with a kernel-generated DTB: the device tree currently specifies the stock
Flyme DTB ABI. The build may expose further issues after that input is staged.
On-device validation remains pending, including boot, RIL, Wi-Fi, mobile data,
traffic accounting/policy, camera capture and recording.
