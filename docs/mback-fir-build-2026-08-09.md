# mBack and Flyme 5 FIR build record — 2026-08-09

This record covers the complete `lineage_m86-userdebug bacon` build containing
the configurable mBack path and the local Flyme OS 5.1.2.0A FIR data. It closes
the source, build, packaging, and static-audit gates for those changes. Runtime
acceptance still requires a PRO 5 handset test.

## Source state

- workspace revision: `911b1493a4d2af2617091df3691876af9f0e6d7f`
- device tree revision: `00eaccd3500c40d4a3afbe149c36b3332ce2673d`
- kernel revision: `75b4f04d9ad32ec9b6ed2b8a4671d00ac6e378cd`
- build target: `lineage_m86-userdebug bacon`
- build jobs: 8
- completed: `2026-08-09T16:34:58+08:00`
- retained locally: `../artifacts/pro5-lineage-20260809-162612-bacon`

## Retained artifacts

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `lineage-17.1-20260809-UNOFFICIAL-m86.zip` | 642,233,428 | `35bbe493d313f6a2ceb665e6ecdf3aab3a414252976ae15049a1d91702e99e75` |
| `lineage_m86-target_files-pro5-a10-20260806.zip` | 1,551,209,589 | `b91b0e9d1956907fca8c2353c99714c72f5cd52aad93cf8009290c895a0a313b` |
| `boot.img` | 18,292,736 | `0f861f005152abdcd6aed62e26f6c4ef842577575c500cc00a6d9447dd8ef550` |
| `recovery.img` | 27,295,744 | `797c060db8b50ef82c09457227d99d78f4cfeffcdbcd71291300ac217ece8c8b` |
| `system.img` | 1,591,767,548 | `15f4334885fca152271b23f697fbfe1667e921f13e7901efcf6c6d305e87abe4` |
| `dtb.img` | 143,996 | `267e74680086f97808b4e15108b889fe9883ef431cc677c1f5370567383e0451` |

The fetch workflow verified every entry in `SHA256SUMS` and tested both ZIP
files before moving the download out of its `.partial` directory.

## Feature payload evidence

The installed product tree and retained target-files ZIP contain identical FIR
files under `SYSTEM/vendor/firmware`:

| File | SHA-256 |
| --- | --- |
| `stage1.txt` | `4706f3622459cd55d0f881f3fe1eea73fd465c28a266039efb6b6edc31b4ec2c` |
| `stage2.txt` | `2950bfd8c78d6f84acf3fa883e5901adae68c1bf10d216b0495648c8caa96772` |

The target-files ZIP also contains the distinct F9-F12 `fpc1020.kl` gesture
mapping, `ro.meizu.hardware.mback=true`, the rebuilt `framework.jar`, and the
rebuilt `LineageParts.apk`. This proves the source changes reached the packaged
system rather than remaining only in the checked-in trees.

The standard build audits passed for the full block OTA, hybrid DTB, boot and
recovery headers, partition sizes, exFAT objects, 219 locked proprietary
inputs, source-built graphics/ION outputs, camera ABI closure, and fingerprint
HIDL output. The OTA audit found only `bootimg`, `dtb`, and `system` block
targets and reported `ota-required-cache=0`.

## Builder memory handling

The builder grants the job cgroup 64,424,796,160 bytes while host `sysconf`
reports 128 configured CPUs. `ART_BOOT_IMAGE_EXTRA_ARGS=-j8` correctly limited
each `dex2oatd` instance to eight compiler workers, but Ninja initially ran the
ARM and ARM64 boot-image rules together. Their combined file-cache and mmap
peak reached the cgroup limit and failed with `ENOMEM`; there was no OOM kill
and no source/compiler error.

The accepted build used the already-generated combined Ninja graph to build
the missing ARM boot-image target alone, with the same `-j8` dex2oat command.
ARM64 had already completed successfully. A read-only `POSIX_FADV_DONTNEED`
pass released build-output page cache before the serial target; it changed no
file contents. The subsequent `bacon -j8` treated both boot-image targets as
up to date and completed normally. A direct `mka <output-path>` is not a valid
substitute: Android 10 may regenerate the graph and expand the request into
thousands of dependencies when its environment signature differs.

## Builder housekeeping

To retain enough space for the new immutable evidence, two old remote artifact
copies were removed only after their remote and local `SHA256SUMS` matched and
both copies passed a full `sha256sum -c` check:

- remote `20260809-122233-bacon`; retained locally as
  `../artifacts/pro5-lineage-20260809-122233-bacon`
- remote `20260807-101323-bacon`; retained locally as
  `../artifacts/pro5-lineage-20260807-101323-bacon`

Both remain recoverable by rsync from their verified local copies. The
recreatable remote ccache was also cleared; no source, current output, stock
evidence, or current artifact was removed.

## Remaining runtime gate

After flashing, use the checks in `docs/mback-fir-implementation.md`. Confirm
all four mBack preferences act immediately and persist, external F9-F12 keys
remain ordinary keys, the navigation-bar fallback remains usable, and HiFi
loads the packaged FIR or the byte-identical compiled fallback without parser
errors.
