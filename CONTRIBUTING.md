# Contributing

Thanks for helping with the Meizu PRO 5 (`m86`) LineageOS 17.1 port. Please
follow the repository rules below so changes stay reviewable and reproducible.

## Scope

- `device/meizu/m86`, `hardware/meizu/m86`, `twrp/device/meizu/m86`,
  `patches/`, `remote/`, `tools/`, `docs/`, manifests and locks are the active
  product path.
- `legacy/device-meizu-m86-cm14` is imported provenance only. Do not modify it
  in this repository; port a component into the active path instead.
- Do not commit proprietary binaries, stock firmware, device evidence,
  `out/`, artifacts, or credentials. The `.gitignore` boundary is deliberate.

## Change rules

1. Keep each commit focused and use an imperative, scoped subject, for example
   `camera: keep the legacy HAL on /dev/binder`.
2. Validate shell edits locally:
   ```bash
   bash -n remote/*.sh tools/*.sh
   ```
3. Before applying a patch, run:
   ```bash
   git -C <target-repo> apply --check <path-to.patch>
   ```
4. Run the relevant patch/build script twice to prove migration and
   idempotency, then build the affected target before `bacon`.
5. Name patches by ownership and purpose, for example
   `kernel-m86-watchdog-hotplug-serialization.patch`. Keep unrelated fixes in
   separate patches.
6. Keep provenance: record the upstream repository, branch, commit, and why a
   change is needed. Never edit generated `out/` files.
7. Update `docs/domain-gates.tsv`, `docs/module-ownership.tsv`,
   `docs/platform-debt.tsv` / `docs/retired-platform-debt.tsv`, and
   `patches/series.tsv` when ownership changes.
   The retired ledger keeps historical patch paths for provenance, but retired
   patch artifacts are removed. Resync an old builder checkout instead of
   relying on the workspace to reverse retired changes.
8. Every runtime-sensitive change needs build evidence and, where the gate
   demands it, device evidence with a recorded hash.

## Pull requests

Include:

- the original error or gap;
- root cause;
- modified repository and files;
- upstream commit or link when one exists;
- exact validation commands and results;
- artifact hashes and build log references;
- any flashing risk.

Pull requests that add unreviewed partition dumps, credentials, private keys,
or vendor binaries will be closed.

## 中文贡献规则（摘要）

提交保持单一主题、祈使句 scoped subject；shell 修改先跑 `bash -n`；补丁先
`git apply --check` 并双跑验证幂等；更新 domain/module/debt ledger 与
`patches/series.tsv`；运行时敏感改动必须附构建/设备证据与哈希。禁止提交
厂商二进制、凭证、私钥、未审查分区镜像。
