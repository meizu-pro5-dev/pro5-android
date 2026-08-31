# Flyme blob ABI ledger

## Current inventory

The verified Flyme 8.0.5.0A extraction set contains 219 files totaling
154,423,203 bytes. It is retained outside Git and transferred explicitly to
the builder with a 219-line SHA-256 manifest.

Linux `readelf` identifies 178 ELF objects:

- 96 ELF32 objects;
- 82 ELF64 objects;
- 78 unique `DT_NEEDED` SONAMEs;
- 37 SONAMEs supplied by another file in the extraction set;
- 41 SONAMEs expected from the Android 10 platform or open-source device
  stack.

The private dependency closure was expanded beyond the old CM 14.1 list for
the Meizu camera helpers, display-effect core, legacy STLport runtime, and
audio-effect helper. No Android 7 copy of libc, libbinder, libutils, libui, or
another platform library is admitted merely to make a basename resolve.

## High-risk platform boundaries

The basename closure does not prove ABI compatibility. The largest fragile
boundaries are:

| SONAME | Current blob callers | Treatment |
| --- | ---: | --- |
| `libutils.so` | 130 | compare imported/exported symbols; donor compatibility first |
| `libcutils.so` | 100 | donor source or narrow shim; never replace Android 10 libcutils |
| `libstagefright_foundation.so` | 71 | defer optional Flyme codec/extractor blobs until media bring-up |
| `libbinder.so` | 54 | use Android 10 libbinder with targeted legacy ABI fixes only |
| `libmedia.so` | 29 | high-risk camera/audio/media boundary; symbol audit required |
| `libstagefright.so` | 29 | use donor stagefright shim pattern where applicable |
| `libui.so` | 27 | validate camera/display blobs against universal7420 adaptations |
| `libhardware.so` | 26 | HAL ABI is comparatively stable but still symbol-checked |
| `libhardware_legacy.so` | 23 | prefer Android 10 implementation and donor command wrappers |
| `libstagefright_omx.so` | 18 | reuse universal7420 OpenMAX source/shim pattern |

The universal7420 common BoardConfig already supplies loader mappings for
`libexynoscamera_shim.so` and `libstagefright_shim.so`. The m86 product must
package those shims only when the corresponding stock libraries enter a
system-image milestone; inheriting the entire Samsung product file would also
copy Samsung sensors, radio, camera, NFC, and feature declarations and is not
acceptable.

### SITRIL boundary

The final Flyme 8 `libsitril.so` is present in matching 32-bit and 64-bit
forms; the Android 10 radio daemon uses the 64-bit copy. Its only RIL entry
point is `RIL_Init`. Disassembly of that function resolves its returned
`RIL_RadioFunctions` table at `0xf9fd0`; the first word is `0x0000000c`, so
the final production blob reports RIL v12. It directly names
`/dev/umts_ipc0`, `/dev/umts_ipc1`, and
`/dev/umts_boot0`. Its direct private dependency chain includes
`libril_sitril.so`, `librilutils_sitril.so`, and `libsitril-jniif.so` from the
same verified build.

Android 10's source-built `rild` and `libril` provide the HIDL radio service;
the Flyme `rild_exynos` must not run. A full output-side symbol audit remains a
hard gate because the private Flyme libraries reference Android 7 binder and
utils SONAMEs. If those imports do not resolve against the built Android 10
objects, replace only the failing private dependency with a narrow source shim
after recording its precise imported-symbol set. Never satisfy it by copying
old platform libraries.

### Mali loader boundary

Flyme 8.0.5.0A contains the legacy `/system/lib/egl/egl.cfg` entry `0 1 mali`,
but Android 10's EGL loader does not consume that file. Its compatibility
search finds the verified 32-bit and 64-bit
`/system/vendor/lib*/egl/libGLES_mali.so` objects by the `libGLES_*.so`
pattern. The old configuration file is therefore deliberately excluded from
the proprietary inventory.

The Android 10 Vulkan loader instead derives `vulkan.exynos5.so` from
`ro.board.platform=exynos5`. The verified Flyme image contains both 32-bit and
64-bit names as links to the corresponding combined Mali GLES library, and
the universal7420 LineageOS 17.1 vendor tree uses the same layout. The m86
device makefile reproduces those links without duplicating the large blobs.
Vulkan feature XML remains deferred until the driver passes an on-device
enumeration test; presence of entry points alone is not treated as functional
evidence.

### GNSS and sensors boundaries

The verified 64-bit `gps.default.so` is exposed through the same-SoC
`android.hardware.gnss@1.0-impl.zero` wrapper and talks to `gpsd` through
`/dev/socket/gps`. The daemon consumes the final Flyme configuration at
`/system/etc/gps.xml`; the local copies are locked to SHA-256
`eab2ec1b4b2c2855e0fc38f27a59e84522570020192925f63b11fd7ab7f75e5d`
for `gps.xml` and
`44a960aec8d8322cba8386779fa54355e10d976c19871c45fe44547c4ccb11d0`
for `gps.conf`. Because the Android 7 daemon imports old C++ sensor, binder,
GUI and crypto interfaces, `/system/bin/gpsd=27` is the only process SDK
override. The first full output must still prove every imported symbol
against the built Android 10 libraries before GNSS is called functional.

The verified `sensors.m86.so` depends only on the stable legacy HAL,
libcutils/log and C library boundary, so Android 10's generic sensors 1.0
bridge is used rather than Samsung's device-specific implementation. String
and sysfs inspection identifies the Meizu CyWee hub plus separate ALS and
proximity paths. Feature declarations are limited to the sensor types the
blob actually reports; Galaxy barometer and heart-rate declarations are
explicitly excluded.

### Camera boundary

The product has one camera implementation: the source-built 32-bit
`camera.m86` module linked to `libexynoscamera3_m86`. The Flyme HAL1 engine,
the universal7420 donor stack, their ABI bridges and their conditional vendor
copy rules are not part of the product. Stock camera firmware, sensor setfiles
and audited Meizu image-processing dependencies remain proprietary inputs.

The output audit requires both installed modules to be ELF32, verifies that
`camera.m86` exports `HMI` and links `libexynoscamera3_m86.so`, rejects retired
HAL1/donor/shim dependencies, and compares installed files with their
source-built intermediates. Runtime acceptance still requires provider
enumeration, preview, both sensors, still capture, recording, autofocus,
flash/torch, rotation, suspend/resume and repeated open.

## Milestone policy

1. Kernel and the first boot image do not require the Flyme system blob set.
   Recovery consumes only the hash-locked `st_fts.bin` needed by the STM touch
   driver's automatic firmware check; it does not inherit the Android 7 HAL
   or platform-library set.
2. Display/UI adds only Mali, allocator/composer dependencies, and Meizu panel
   support after source-vs-blob selection.
3. Radio, connectivity, audio, sensors/GPS, and camera each receive a separate
   extraction section and dependency/symbol report.
4. Flyme codec and extractor extensions are optional. They remain deferred if
   they require old internal Stagefright ABI or conflict with Android 10
   modules.
5. A source-built Android 10 library wins unless the destination is explicitly
   owned by the reviewed 219-file Flyme lock. A shim must name the exact
   missing symbols and calling blob; broad compatibility libraries are
   rejected.

Before every full `bacon` build, the remote worker requires the 219-line hash
lock produced by extraction and verifies every staged proprietary input in
place. The lock is copied into the artifact directory, alongside the pinned
source manifest and stock-image lock. After `bacon`, the worker applies the
same lock to the installed system tree, so duplicate make rules cannot replace
an explicitly selected Flyme file with different bytes. Output-side ELF and
symbol compatibility remains a separate post-build ABI gate.

`tools/audit-elf-deps.sh` reproduces the class and SONAME counts on the Linux
builder. After the first system build, its output is combined with
`readelf --dyn-syms` checks against the actual product libraries to produce the
symbol-level closure.
