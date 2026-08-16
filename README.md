# Meizu PRO 5 (`m86`) — LineageOS 17.1 / Android 10 bring-up

**UNOFFICIAL**. This project is not affiliated with or endorsed by Meizu,
LineageOS, or TeamWin.

This repository is the reproducible, host-side source of truth for bringing
LineageOS 17.1 (Android 10) to the Meizu PRO 5 (`m86`, Samsung Exynos 7420).
It contains the authored device configuration, maintained kernel source,
vendor build definitions, TWRP device tree, patches, manifests, revision
locks, builder scripts, and bring-up documentation.

No proprietary binaries, stock firmware, device evidence, `out/`, or flashable
artifacts are committed here. The full LineageOS checkout and build output
live on a private Linux builder that you select yourself.

## Status

| Area | Status |
| --- | --- |
| Kernel 3.10.61 | reproducible build, device boot |
| TWRP 3.7.0_9 | source-built recovery with ADB/sideload, MTP, legacy FDE, storage |
| Android 10 bring-up | build/static and device gates tracked in `docs/domain-gates.tsv` |
| SELinux | permissive; enforcing gap assessment in `docs/selinux-enforcing-roadmap-2026-08.md` |
| Proprietary blobs | extracted from Flyme 8.0.5.0A; never committed |

The accepted build-only result and artifact hashes are recorded in
`docs/static-acceptance-2026-08-07.md`. The safety boundary: no script in this
repository is permission to write a device partition; flashing always requires
a separate, explicit confirmation.

## 中文简介

本仓库是 Meizu PRO 5（`m86`，Exynos 7420）移植 LineageOS 17.1 / Android 10
的可复现主机侧源码库，包含原创设备树、维护中的 kernel 源码、vendor 构建
定义、TWRP 设备树、补丁、manifest、修订锁、构建脚本与 bring-up 文档。
仓库不提交任何厂商专有二进制、stock 固件、设备证据或刷机包；完整
LineageOS 源码与构建输出存放在你自行配置的 Linux 构建机上。本项目为
**UNOFFICIAL**，与魅族、LineageOS、TeamWin 无官方关联。

## Repository layout

- `device/meizu/m86/`: Android device configuration authored for this port.
- `kernel/meizu/m86/`: maintained m86 Linux 3.10.61 kernel (GPL-2.0).
- `vendor/meizu/m86/`: generated vendor build definitions; binaries ignored.
- `twrp/device/meizu/m86/`: TWRP 3.7.0_9 device tree.
- `hardware/meizu/m86/`: local audio, Bluetooth and graphics adapters.
- `manifests/`: LineageOS and reference-source declarations.
- `patches/`: reproducible changes to upstream Android repositories.
- `overlays/`: case-sensitive kernel source pairs that cannot coexist on the
  default macOS filesystem.
- `legacy/`: imported cm-14.1 community baseline kept outside Android module
  discovery paths (see its `UPSTREAM.md` and `LEGAL-NOTE.md`).
- `remote/`: builder bootstrap, synchronization and build control scripts.
- `locks/`: immutable upstream revisions and generated manifest snapshots.
- `docs/`: design decisions, hardware findings and bring-up records.
- `evidence/`: locally retained logs and device evidence (ignored by Git).

## Building

### 1. LineageOS source on a Linux builder

```bash
repo init -u https://github.com/LineageOS/android.git -b lineage-17.1
repo sync
```

### 2. Add the m86 trees

Replace `<github-user>` with the GitHub account hosting these repositories.

```xml
<manifest>
  <remote name="meizu-m86" fetch="https://github.com/<github-user>" />
  <project path="device/meizu/m86" name="android_device_meizu_m86"
           remote="meizu-m86" revision="lineage-17.1" />
  <project path="kernel/meizu/m86" name="android_kernel_meizu_m86"
           remote="meizu-m86" revision="lineage-17.1" />
  <project path="vendor/meizu/m86" name="android_vendor_meizu_m86"
           remote="meizu-m86" revision="lineage-17.1" />
</manifest>
```

The proprietary payload is not included: after syncing, populate
`vendor/meizu/m86/proprietary/` from a verified Flyme 8.0.5.0A stock image
using `device/meizu/m86/extract-files.sh`, as described in
`vendor/meizu/m86/README.md`.

### 3. Workspace tooling

Clone this workspace recursively if you want the patch/audit/remote tooling:

```bash
git clone --recurse-submodules \
  https://github.com/<github-user>/pro5-android10.git
```

The `remote/` scripts use the SSH alias `rom-builder` by default. Configure it
in your own `~/.ssh/config`; no cloud endpoint is hard-coded in this public
tree:

```
Host rom-builder
  HostName your-builder.example.com
  User root
  Port 22
  IdentitiesOnly yes
```

Override with `PRO5_BUILDER_HOST`, `PRO5_BUILDER_PORT`, and
`PRO5_REMOTE_ROOT`. The builder keeps persistent state below
`/root/autodl-tmp/pro5-android10` (override the last variable for other
layouts). `/etc/network_turbo` is sourced on the builder when available.

Typical control flow:

```bash
./remote/bootstrap-builder.sh
./remote/push-local.sh
./remote/start-source-sync.sh
./remote/source-sync-status.sh
./remote/start-platform-sync.sh
./remote/platform-sync-status.sh
./remote/prepare-vendor.sh
./remote/start-kernel-build.sh
./remote/kernel-build-status.sh
./remote/start-build.sh bootimage
./remote/build-status.sh
./remote/start-build.sh bacon
./remote/fetch-lineage-artifacts.sh
./remote/start-twrp-source-sync.sh
./remote/twrp-source-sync-status.sh
./remote/start-twrp-build.sh
./remote/twrp-build-status.sh
./remote/fetch-twrp-artifacts.sh
```

`start-build.sh` accepts `kernel`, `bootimage`, `recoveryimage`, or `bacon`.
Override the lower-memory default 8-way build with `PRO5_BUILD_JOBS`; high
parallelism can make `dex2oat` fail with `ENOMEM` under a memory cgroup.

## License

This is a mixed-license workspace; see [`LICENSING.md`](LICENSING.md) and
[`NOTICE`](NOTICE) for the exact map and third-party attribution.

- Kernel and kernel-derived files: GPL-2.0-only
- Device/vendor/hardware/TWRP/scripts: Apache-2.0
- Documentation: CC-BY-SA-4.0
- Imported legacy cm-14.1 tree: no license asserted; see
  `legacy/device-meizu-m86-cm14/LEGAL-NOTE.md`

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the patch, validation and evidence
rules. Report security issues privately as described in
[`SECURITY.md`](SECURITY.md).

## 中文快速开始

1. 在 Linux 构建机上 `repo init -u https://github.com/LineageOS/android.git -b lineage-17.1 && repo sync`；
2. 把上面 `<github-user>` 替换为你的 GitHub 账号，将 XML 放入 `.repo/local_manifests/m86.xml` 后再次 `repo sync`；
3. 用 Flyme 8.0.5.0A stock 镜像运行 `device/meizu/m86/extract-files.sh` 生成厂商二进制；
4. 可选 `git clone --recurse-submodules https://github.com/<github-user>/pro5-android10.git` 获取补丁、审计与远程构建工具；
5. 在 `~/.ssh/config` 配置 `rom-builder`（或设置 `PRO5_BUILDER_HOST/PORT`），按上述控制流构建。
