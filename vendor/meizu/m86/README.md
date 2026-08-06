# m86 proprietary interface

This tree contains extraction metadata and generated build definitions, not
stock binaries. `proprietary/` is intentionally ignored by the local Git
repository and by host-to-builder synchronization.

The initial list is inherited from the final community cm-14.1 device tree.
The verified extraction source for Android 10 is Flyme 8.0.5.0A, whose archive
and image hashes are recorded under `locks/`. Entries must be checked for
existence, ELF class, dependencies, partition destination, and Android 10
namespace/shim requirements before they are promoted into a boot milestone.

Run `extract-files.sh PATH_TO_EXPANDED_ROM` only from an installed LineageOS
17.1 checkout so the branch-matched `extract_utils.sh` generates the makefiles.
