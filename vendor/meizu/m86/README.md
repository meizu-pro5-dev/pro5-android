# m86 proprietary interface

This tree contains extraction metadata and generated build definitions, not
stock binaries. `proprietary/` is intentionally ignored by the local Git
repository. Stock bytes are transferred to the builder only through the
explicit proprietary-blob workflow.

The list was seeded from the final community cm-14.1 device tree and reconciled
against Flyme 8.0.5.0A. Its archive and image hashes are recorded under
`locks/`; every current source path resolves in that image. ELF class,
dependencies, partition destination, and Android 10 namespace/shim behavior
still require milestone-specific validation.

Create a minimal expanded-ROM tree from the verified image with:

```bash
PYTHONPATH=../work/pro5-flyme-8.0.5.0A/python-deps \
  ./tools/extract-stock-files.py \
  ../work/pro5-flyme-8.0.5.0A/extracted/system.img \
  vendor/meizu/m86/proprietary-files.txt \
  ../work/pro5-flyme-8.0.5.0A/blob-dump
```

Run `extract-files.sh PATH_TO_EXPANDED_ROM` only from an installed LineageOS
17.1 checkout so the branch-matched `extract_utils.sh` generates the makefiles.
