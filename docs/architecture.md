# Build and source architecture

## Authority boundary

The local `pro5-android10` Git repository is authoritative for every authored
porting change. AutoDL is an execution environment and cache, not the only copy
of any adaptation code.

Historical m86 sources are stored below `legacy/`, outside the directories
installed into the Android checkout. This prevents Android 10 from discovering
obsolete Android.mk modules while retaining the complete reviewable baseline.

| Data | Authoritative location | Remote location |
| --- | --- | --- |
| Device tree | `device/meizu/m86` | `src/lineage-17.1/device/meizu/m86` |
| Kernel fork | `kernel/meizu/m86` | `src/lineage-17.1/kernel/meizu/m86` |
| Vendor metadata | `vendor/meizu/m86` | `src/lineage-17.1/vendor/meizu/m86` |
| Android patches | `patches` | applied to `src/lineage-17.1` |
| Manifest/source locks | `manifests`, `locks` | generated first under `logs` |
| Full LineageOS source | not mirrored | `src/lineage-17.1` |
| Reference repositories | revision locks only | `reference` |
| `out`, ccache, images | evidence/hashes only | persistent builder disk |

The remote root is restricted to `/root/autodl-tmp/pro5-android10`. The
builder's approximately 30 GiB root overlay is not suitable for an Android
checkout. The 300 GiB persistent volume is sufficient only with a bounded
25 GiB ccache and periodic build-output accounting.

Manifest URLs stay canonical. LineageOS fetches use GitHub through
`/etc/network_turbo` first, then the CERNET MirrorZ selector, TUNA, and the
accelerated upstream. AOSP fetches use USTC, then BFSU, TUNA, and finally the
accelerated upstream. Each manifest project runs in a bounded `repo sync`
process because an aggregate repo 2.65 worker pool stalled after a mirror
timeout on this builder. A manifest hash keys the progress checkpoint,
allowing an interrupted run to retain completed projects without reusing that
state after an intentional source refresh.

MirrorZ is a selector rather than a third source corpus. On 2026-08-07 its
LineageOS route redirected this builder to BFSU. The `lineage-17.1` refs for
the manifest, `frameworks/base`, and `external/sonivox` repositories matched
GitHub, TUNA, and BFSU exactly; the selector therefore participates as a
bounded fallback without changing manifest provenance. The workers already
disable clone bundles, as recommended by the MirrorZ help page for repositories
whose mirrored bundles fail.

## Recovery rule

A fresh builder must be recoverable by running the checked-in bootstrap and
sync scripts, checking out the locked LineageOS manifest and reference SHAs,
installing the local trees, applying the checked-in patches, and rebuilding.
No manual-only edit on the builder is considered part of the port.
