# M0 A10 baseline index

Captured on 2026-08-10 before cleanup. This is a source/build oracle, not a
claim that any device-runtime gate passed.

## Source state

The ignored local evidence package is
`evidence/m0-a10-dirty-oracle-20260810-pre-cleanup`. It contains full-index
binary diffs, porcelain-v2 status, untracked-file hashes and archives, and
patch-queue hashes for these repositories:

| Repository | HEAD |
| --- | --- |
| workspace | `42753e8b79a3bd8c12a8021cd0d5cab61ecde0c9` |
| `device/meizu/m86` | `00eaccd3500c40d4a3afbe149c36b3332ce2673d` |
| `kernel/meizu/m86` | `75b4f04d9ad32ec9b6ed2b8a4671d00ac6e378cd` |
| `vendor/meizu/m86` | `371a549ca1d09c8c1616b015a052a99b22211a98` |

The source package intentionally records dirty and untracked inputs because
the archived build metadata only recorded the top-level repository as dirty.

## Archived build

The immutable backup is
`../backups/pro5-lineage17-final-20260809`. Its 22-entry `SHA256SUMS` was
verified again while sealing the oracle. Key artifacts are:

| Artifact | SHA-256 |
| --- | --- |
| OTA ZIP | `89b238286cb05ad2f7a6eb77dbf80b02abca8296fffed3a63b3a6ec7d8c2190f` |
| boot image | `47eb49afde3efede6e354c3d3b9c87c9938ed63ae9170ed6befe6bcde2e0121c` |
| target-files ZIP | `57f48d5618e3bcbc24e9858c8495958b1c20d2b663cc437affc0a2b673fe60aa` |
| DTB image | `b45054fa87a5ffe114843953172d48d36408e1f93db35a6cbdfb0a8fc58a2165` |

The byte-exact stock DTB input at
`../work/pro5-flyme-8.0.5.0A/dtb-inspect/dtb` has the same DTB hash.

## Validation state

- Build and static artifact evidence: available.
- A10 clean-checkout reproduction: pending.
- M1 three-cold-boot and USB device matrix: pending.
- NFC and fingerprint: known incomplete and not eligible for a passed status.

The authoritative per-domain state and ownership are tracked in
`docs/module-ownership.tsv`.
