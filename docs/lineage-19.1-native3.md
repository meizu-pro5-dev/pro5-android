# LineageOS 19.1 native Camera3 publication

This branch publishes the source state used for the Meizu PRO 5 (`m86`)
Android 12 bring-up. It is an unofficial community port.

## Repository boundary

The device tree, kernel, vendor definitions and modified Exynos camera stack
are maintained as full repositories under `meizu-pro5-dev`. Device-owned
hardware sources live in this repository. Changes to the remaining Android
platform projects are kept as ordered patches under `patches/lineage-19.1`.

No stock camera library, proprietary vendor payload, device log, build output
or flashable artifact is published here.

## Source preparation

1. Initialize and sync LineageOS 19.1.
2. Copy `manifests/lineage-19.1-m86.xml` into `.repo/local_manifests/` and sync
   again.
3. Run `tools/install-lineage-19.1-hardware.sh` with the Android source root.
4. Run `tools/apply-lineage-19.1-patches.sh` with the same source root.
5. Extract device proprietary files from an independently obtained stock
   Flyme image using the device tree extraction tooling.
6. Select `lineage_m86-userdebug` and build `bacon`.

The exact source and patch revisions are recorded in
`locks/lineage-19.1-revisions.tsv`.
