# PRO5 Android 10 仓库维护记录

## 当前结构

2026-08-09 起，原先由顶层仓库直接跟踪的 PRO5 Android 10 设备源码已拆分为三个独立 Git 仓库。目录位置保持不变，Android 构建脚本无需改路径；顶层仓库仅记录子模块指针。

| 组件 | 本地路径 | 分支 | 拆分后首个维护提交 |
| --- | --- | --- | --- |
| device tree | `device/meizu/m86` | `lineage-17.1` | `1e87081cad7f7a7e0ac94732ff710236e771d6ba` |
| kernel tree | `kernel/meizu/m86` | `lineage-17.1` | `60400e3babdf2813b383992a14dd0ce1d5db094a` |
| vendor tree | `vendor/meizu/m86` | `lineage-17.1` | `371a549ca1d09c8c1616b015a052a99b22211a98` |

三个仓库均由顶层仓库 `d18c46f8` 时的已提交历史通过 `git subtree split` 派生，因此组件相关的旧提交历史仍可查询。当前未配置远端；`.gitmodules` 预设同一 Git 组织中的相对仓库名：

- `android_device_meizu_m86.git`
- `android_kernel_meizu_m86.git`
- `android_vendor_meizu_m86.git`

若实际远端命名不同，应在首次发布前同时修改 `.gitmodules` 和各子仓库的 `origin`。

## 首次发布

分别为三个子仓库配置远端并推送维护分支：

```bash
git -C device/meizu/m86 remote add origin <device-repository-url>
git -C device/meizu/m86 push -u origin lineage-17.1

git -C kernel/meizu/m86 remote add origin <kernel-repository-url>
git -C kernel/meizu/m86 push -u origin lineage-17.1

git -C vendor/meizu/m86 remote add origin <vendor-repository-url>
git -C vendor/meizu/m86 push -u origin lineage-17.1
```

确认子仓库可访问后，再发布顶层仓库。新工作副本使用：

```bash
git clone --recurse-submodules <workspace-repository-url>
```

已有工作副本使用：

```bash
git submodule sync --recursive
git submodule update --init --recursive
```

## 日常维护

修改应先在对应子仓库提交，再由顶层仓库更新 gitlink。例如：

```bash
git -C device/meizu/m86 add -A
git -C device/meizu/m86 commit -m 'm86: describe the device change'
git add device/meizu/m86
git commit -m 'device: update m86 tree'
```

kernel 和 vendor 使用同一流程。发布时应先推送子仓库提交，再推送引用这些提交的顶层仓库，避免其他工作副本无法初始化子模块。

顶层 `remote/push-local.sh` 仍以 rsync 将可维护源码同步到构建机。脚本排除任意层级的 `.git`，所以拆分不会污染远端 Android 源码树，也不会改变既有构建路径。

## 不进入 Git 的内容

- `vendor/meizu/m86/proprietary/`：受再分发限制的提取 blob；仅提交映射、生成规则和说明。
- `outputs/`、`artifacts/`：构建产物及归档。
- `backups/`、`work/`、`out/`、`ccache/`：本机备份、临时数据和生成目录。
- `evidence/`：设备证据默认仅保存在本机，只有 `evidence/README.md` 可跟踪。

拆分不等于备份。在配置并验证远端之前，四个仓库（顶层加三个子仓库）的 `.git` 数据均只存在于当前工作机。

## 检查清单

提交或发布前执行：

```bash
git status --short
git submodule status
git -C device/meizu/m86 status --short
git -C kernel/meizu/m86 status --short
git -C vendor/meizu/m86 status --short
bash -n remote/*.sh
```

涉及构建逻辑的改动仍须按影响范围完成模块构建；最终发布包须记录 SHA-256、构建日志和设备验证结果。
