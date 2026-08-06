# TWRP frameworks/base compatibility patch

The pinned OmniROM `android_frameworks_base_old` branch references the host
module `stats-log-api-gen` from two Soong genrules but omits the module's
source directory. Soong therefore cannot generate `build.ninja`, even for a
recovery-only product.

`0001-restore-aosp-p-stats-log-api-gen.patch` restores the complete directory
from the authoritative AOSP `platform/frameworks/base` tag
`android-9.0.0_r47`, which is also the platform tag selected by the pinned
minimal TWRP manifest. The downloaded Gitiles archive was:

```text
URL=https://android.googlesource.com/platform/frameworks/base/+archive/android-9.0.0_r47/tools/stats_log_api_gen.tar.gz
SHA256=ed2e8eacedf554419dcc45e5ecca2a6395b740f4de53b7bb610463fe2184081c
```

The patch is applied to `frameworks/base` by `install-twrp-trees.sh` and is
archived beside each accepted recovery image.
