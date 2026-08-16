# License map for pro5-android10

This repository is a mixed-license workspace. The root `LICENSE` (Apache-2.0)
applies to files the m86 project authors unless a more specific notice in a
subdirectory says otherwise. The kernel and kernel-derived material remain
under the Linux kernel license, GPL-2.0-only.

| Path | License | Notes |
| --- | --- | --- |
| `device/meizu/m86/` | Apache-2.0 | Submodule; see its own `LICENSE` |
| `vendor/meizu/m86/` | Apache-2.0 | Submodule; build definitions only, no binaries |
| `hardware/meizu/m86/` | Apache-2.0 | Local HAL wrappers; one derived file noted in `NOTICE` |
| `twrp/device/meizu/m86/` | Apache-2.0 | Local TWRP device tree |
| `patches/twrp-kernel-m86/` | GPL-2.0-only | Kernel patches; see its `COPYING` |
| `overlays/kernel-meizu-m86-case-sensitive/` | GPL-2.0-only | Byte-identical kernel source copies; see its `COPYING` |
| `kernel/meizu/m86/` | GPL-2.0-only | Submodule; see its `COPYING` |
| `legacy/device-meizu-m86-cm14/` | No license asserted | Imported unchanged; see its `UPSTREAM.md` and `LEGAL-NOTE.md` |
| `docs/` | CC-BY-SA-4.0 | See `docs/LICENSE.CC-BY-SA-4.0.txt` |
| everything else at repository root | Apache-2.0 | Scripts, manifests, locks, TSV metadata |

Third-party attribution lives in `NOTICE`. Do not copy files between
directories with different licenses without updating this map.

## 许可证地图（中文）

本仓库为混合许可证工作区。根目录 `LICENSE`（Apache-2.0）适用于 m86 项目
作者原创文件，除非子目录内有更具体的声明。kernel 及衍生材料保持 Linux
kernel 许可证 GPL-2.0-only。

| 路径 | 许可证 | 说明 |
| --- | --- | --- |
| `device/meizu/m86/` | Apache-2.0 | 子模块，见其自身 `LICENSE` |
| `vendor/meizu/m86/` | Apache-2.0 | 子模块，仅构建定义，不含二进制 |
| `hardware/meizu/m86/` | Apache-2.0 | 本地 HAL 包装；一处派生文件见 `NOTICE` |
| `twrp/device/meizu/m86/` | Apache-2.0 | 本地 TWRP 设备树 |
| `patches/twrp-kernel-m86/` | GPL-2.0-only | kernel 补丁，见其 `COPYING` |
| `overlays/kernel-meizu-m86-case-sensitive/` | GPL-2.0-only | kernel 源码逐字节副本，见其 `COPYING` |
| `kernel/meizu/m86/` | GPL-2.0-only | 子模块，见其 `COPYING` |
| `legacy/device-meizu-m86-cm14/` | 不重新许可 | 原样导入，见 `UPSTREAM.md` 与 `LEGAL-NOTE.md` |
| `docs/` | CC-BY-SA-4.0 | 见 `docs/LICENSE.CC-BY-SA-4.0.txt` |
| 仓库根目录其余内容 | Apache-2.0 | 脚本、manifest、locks、TSV 元数据 |

第三方归属记录在 `NOTICE`。请勿在许可证不同的目录之间复制文件而不更新
本映射表。
