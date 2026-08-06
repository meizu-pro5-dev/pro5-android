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
5. A source-built Android 10 library always wins over copying an Android 7
   platform library. A shim must name the exact missing symbols and calling
   blob; broad compatibility libraries are rejected.

`tools/audit-elf-deps.sh` reproduces the class and SONAME counts on the Linux
builder. After the first system build, its output is combined with
`readelf --dyn-syms` checks against the actual product libraries to produce the
symbol-level closure.
