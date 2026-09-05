# m86 codec2 source checkpoint — 2026-09-05

This checkpoint publishes the source state used for `m86.20260905.codec2`,
including the earlier local device, kernel, Bluetooth and platform changes.
The Android target-files build and full/incremental OTA packaging passed.
This is a build and host-validation checkpoint; it does not certify sustained
1080p hardware decoding or all device runtime gates.

## Source ownership and changes

- The device repository registers the Bluetooth Audio 2.0 provider, establishes
  sensor permissions before HAL startup, reports existing Exynos temperatures
  through the standard Thermal HAL, restores OMX component names, and selects
  the m86-compatible output format.
- The kernel repository includes the native eBPF/JIT work, extended IPv4/IPv6
  address flags, station Wi-Fi power save, per-UID CPU/I/O statistics, and stable
  cpufreq policy links. Runtime networking/accounting validation remains required.
- This repository owns the Bluetooth initialization state machine. Firmware,
  SCO and low-power completion remain serialized through vendor command completion;
  early success callbacks cannot hide failures or publish initialization twice.
- Android platform changes remain in `patches/lineage-20.0/series.tsv`, pinned
  to upstream bases. They are published as source patches here rather than by
  changing the upstream LineageOS/Samsung repositories.
- Six platform trees (frameworks/av, hardware/interfaces, hardware/lineage/interfaces,
  SLSI graphics, Camera2, and system/nfc) are byte-identical to the previously
  published queue. Their previously applied local edits now have local commits.
- Retired Android 10 patch artifacts and their automatic reversal path are removed;
  the historical retirement ledger is retained.

## Codec defect and repair

The gralloc0 OMX configuration chose private multi-plane NV12 (`0x121`). The m86
allocator can allocate that format, but its YCbCr lock implementation rejects it.
The OMX adapter checked only HIDL transport success and discarded mapper callback
errors, allowing empty plane addresses to reach the HEVC output enqueue path,
which returns `OMX_ErrorBadParameter` for a null output address.

The m86 board now selects ordinary NV12M (`0x105`), retains private input recognition,
and leaves other boards' default mapping unchanged. Mapper callback failures are
checked and output-import failures produce an error event during playback, excluding
flush/reconfiguration/shutdown. An unsupported optional 10-bit query keeps the 8-bit
format reported by G_FMT; unexpected driver errors propagate.

The uploaded playback log does not cover the first fatal OMX event completely.
The code defect and function-level failure behavior are confirmed, but the precise
runtime chain for that historical fallback is not closed by logs. An unsupported
10-bit query is not evidence that the stream was 10-bit or that this query caused
fallback. Hardware playback and resource release still need device testing.

## Host tool repairs and patch replay

- `build/make`: hash zero blocks as bytes so Python 3 can generate the extra
  incremental OTA post-install verification script.
- `bootable/recovery`: the host simulator honors an explicit source fingerprint
  before deriving one, matching Android init. The source system and Recovery
  provide the same Flyme compatibility fingerprint. OTA assertions are retained.
- `tools/apply-lineage-20.0-patches.sh`: preflight each complete ordered project
  queue against its locked tree, recognize already-applied trees, reject unknown
  local changes, and keep the caller's staging area untouched. This fixes a second
  invocation failing after the first invocation left patches applied at base HEAD.

## Validation

- AVC, HEVC, MPEG4/H263, VP8 and VP9 decoder modules built for 32/64-bit.
- `m target-files-package -j8` completed in 6m17s; all ten installed decoder
  libraries contain the new diagnostics and both architectures use the board flag.
- `python3 tools/test-m86-codec-contracts.py /path/to/android-source` passed six
  production-function tests: board/default formats, mapper errors, geometry queries,
  actual gralloc NV12 mapping, and output-import error events.
- All nine platform queues replayed from their upstream base twice in isolated
  clones. Every result matched `locks/lineage-20.0-revisions.tsv`; original indexes
  were unchanged and an extra untracked file was rejected.
- Public hardware installation ran twice and matched the built source files.
- All 74 shell scripts passed `bash -n`; changed device XML and JSON parsed.
- Both OTA ZIP CRC/content checks and whole-package testkey signatures passed.
- Full and incremental host install simulations passed the post-install system
  block hashes. Incremental boot and full boot/DTB bytes match target-files.
- The full package carries target Recovery but does not flash it directly from
  updater-script. Boot-time recovery installation and external shell programs,
  as well as real boot and playback, are outside the host simulation.

No new device runtime source edits were made while preparing this publication.
Local build and validation records are retained under
`/root/work/pro5-codec2-20260905` and `/root/work/pro5-publish-all-20260905`.
Raw logs, firmware, proprietary binaries, and flashable artifacts are not in Git.

## Locally retained OTA artifacts

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `lineage-20.0-m86-codec2-full.zip` | 738432613 | `59ec3a7f89d809156254987bd45ebf743e84b883f460042a8a80b864999d5d48` |
| `lineage-20.0-m86-codec1-to-codec2-incremental.zip` | 1486200 | `4b403ec339a2db7d42f5b2157f86b911b29c733827fe75d620f4aa0999ef277c` |

The incremental package requires the original codec1 baseline and matching source
partition hashes. Both packages target codec2, carry no userdata wipe instruction,
and use the existing project testkey. The rebuilt kernel banner is
`Linux 3.10.61-user #9`; the DTB is byte-identical to codec1.

## Recorded source revisions

Full base/result/tree IDs are in the version lock. The owned source repositories
and new platform repair results are:

- `device/meizu/m86`: `923dc96205ca1ae1061e7c631ab27bf8054bf9c5`.
- `kernel/meizu/m86`: `81a497d3ac77b454000fe8d8454636b15cbf5671`.
- `hardware/samsung_slsi-linaro/openmax`: `a9696c016e359feb4d29a2d8a737d8719d4ab089`.
- `build/make`: `cfa4c7e21ac1718d0890a9dec6576909f2ad8854`.
- `bootable/recovery`: `192589acc7cbc112d1bf332b5a310e67171a82fa`.
