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

Manifest URLs stay canonical. Git rewrites LineageOS fetches to TUNA and AOSP
fetches to USTC without editing the manifest. An individual failed LineageOS
fetch retries against GitHub directly; failed AOSP fetches rotate through
BFSU, TUNA, and finally the accelerated upstream. Each manifest project runs
in a bounded `repo sync` process because an aggregate repo 2.65 worker pool
stalled after a mirror timeout on this builder.

## Recovery rule

A fresh builder must be recoverable by running the checked-in bootstrap and
sync scripts, checking out the locked LineageOS manifest and reference SHAs,
installing the local trees, applying the checked-in patches, and rebuilding.
No manual-only edit on the builder is considered part of the port.
