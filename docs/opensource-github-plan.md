# Meizu PRO 5 (`m86`) 开源到 GitHub 规划

**Open-Source GitHub Release Plan for the Meizu PRO 5 (`m86`) Android 10 port**

- 规划日期：2026-08-16
- 适用范围：仅 `pro5-android10`（LineageOS 17.1 / Android 10，含 TWRP 设备树）
- 目标账号：个人 GitHub 账号（本地检测到的账号：`404698-FDU`，发布前用 `gh auth status` 确认）
- 发布方式：保留完整 Git 历史，直接推送；不重写历史、不 squash
- 许可证组合：按组件合规组合（kernel GPL-2.0；device/vendor/hardware/TWRP/patches Apache-2.0；docs CC-BY-SA-4.0）
- 本文档语言：中文为主，文末附英文项目说明与快速开始（README 按同一标准双语改写）

---

## 1. 已确认的决策

| 决策点 | 结论 |
| --- | --- |
| 范围 | 仅 `pro5-android10`；不含 `pro5-android11`、顶层 `artifacts/outputs/backups/evidence/work` |
| 厂商专有二进制 | 不发布。`vendor/meizu/m86/proprietary/` 已由 `.gitignore` 排除；TWRP 所需的 `st_fts.bin` 也不入库 |
| GitHub 归属 | 个人账号下（检测到 `404698-FDU`） |
| 许可证 | kernel GPL-2.0；device/vendor/hardware/TWRP/patches Apache-2.0；docs CC-BY-SA-4.0 |
| Git 历史 | 保留完整历史直接推送，不 `filter-repo`、不 squash |
| 文档 | 中英双语；README 增加英文入口 |

## 2. 现状盘点（2026-08-16 实测）

### 2.1 仓库与历史

| 仓库 | 提交数 | 跟踪文件 | .git 体积 | 分支 | 作者 |
| --- | ---: | ---: | ---: | --- | --- |
| `pro5-android10`（父仓库） | 169 | 889 | 123 MB | `main` | 单一作者 `404698-FDU <24302010006@m.fudan.edu.cn>` |
| `device/meizu/m86`（子模块） | 43 | — | 3.0 MB | `lineage-17.1` | 同上 |
| `kernel/meizu/m86`（子模块） | 28 | 约 3 万文件 | 117 MB | `lineage-17.1` | 同上 |
| `vendor/meizu/m86`（子模块） | 12 | — | 300 KB | `lineage-17.1` | 同上 |

父仓库 889 个跟踪文件中，`legacy/device-meizu-m86-cm14` 占 657 个，其余 232 个是本次适配的原创/维护代码（docs、patches、tools、remote、hardware、overlays、TWRP 树等）。

### 2.2 安全与敏感内容审计

已执行，结论：**当前跟踪内容与历史未发现可阻断发布的敏感信息**。

- 未发现私钥、`.pem/.p12/.key/.jks`、GitHub PAT、云 AK/SK 等凭据模式。
- 未发现真实 IMEI/序列号/私人 IP 等设备身份信息；命中的只是 RIL 通用代码与 APN 公网参数。
- 历史中新增的二进制/归档文件仅来自 Linux kernel 官方树内的 `drivers/staging/...` 固件/数据文件（`.img/.dat/.fw.ihex`），属于 GPL-2.0 kernel 源码快照的一部分。
- 所有 shell 脚本通过 `bash -n` 检查。
- 厂商 blobs 全部处于 `.gitignore` 排除状态：`vendor/meizu/m86/proprietary/`、`evidence/*`、`artifacts/`、`outputs/`、`backups/`、`work/` 不会进入仓库。
- ⚠️ 两个发布前必须处理的“环境暴露”点：
  1. `remote/common.sh` 与 `README.md` 中硬编码了 AutoDL 构建机地址 `REDACTED_BUILDER_ENDPOINT`。
  2. Git 作者邮箱 `24302010006@m.fudan.edu.cn` 会随完整历史公开。

### 2.3 许可与来源盘点

| 内容 | 来源/性质 | 计划许可证 |
| --- | --- | --- |
| `kernel/meizu/m86` | Meizu m86 `cm-14.1` kernel 基线 `67699d9442...`，Linux 3.10.61，含 GPL `COPYING` | GPL-2.0-only（保持原状） |
| `device/meizu/m86` | 本次适配原创设备树，部分继承 AOSP/LineageOS 模式 | Apache-2.0 |
| `vendor/meizu/m86` | 原创生成式 vendor 定义（仅 `.mk`/列表，无二进制） | Apache-2.0 |
| `hardware/meizu/m86` | 原创 HAL 包装；gralloc 派生自 `hardware/samsung_slsi/exynos` Apache-2.0 代码（文档已记 commit） | Apache-2.0 |
| `twrp/device/meizu/m86` | 原创 TWRP 设备树；上游为 minimal-manifest-twrp `twrp-9.0` 与 TeamWin recovery（`docs/twrp.md` 已锁定 commit） | Apache-2.0（仅限本树；不替上游声明许可） |
| `patches/**` | 对 AOSP/LineageOS 各项目的原创补丁 | 与目标项目一致：平台补丁 Apache-2.0；`patches/twrp-kernel-m86` 为 GPL-2.0 |
| `overlays/kernel-meizu-m86-case-sensitive` | kernel 源文件的大小写拆分副本（commit `67699d9442...`） | GPL-2.0-only |
| `legacy/device-meizu-m86-cm14` | 上游 `meizu-m86/android_device_meizu_m86` `cm-14.1-latest` @ `26c452793...`，**上游仓库未声明 LICENSE** | 不重新许可；保留 `UPSTREAM.md`，只作来源证据分发 |
| `docs/**` | 原创文档与设备证据 | CC-BY-SA-4.0 |
| 顶层 README、脚本、TSV、XML 锁 | 原创配置/工具 | Apache-2.0 |

### 2.4 当前未提交改动（发布前必须处理）

父仓库（`pro5-android10`）：

- `M docs/domain-gates.tsv`
- `M docs/module-ownership.tsv`
- `M docs/platform-debt.tsv`
- `M docs/retired-platform-debt.tsv`
- `M hardware/meizu/m86/audio/audio_primary_m86.cpp`
- `M patches/series.tsv`
- `M remote/worker-build.sh`
- `M tools/validate-lineage-tree.sh`
- `?? docs/selinux-enforcing-roadmap-2026-08.md`
- `?? tools/CodecProbe.java`
- `?? tools/CodecRoundTrip.java`

`device/meizu/m86` 子模块：

- `M BoardConfigPlatform.mk`
- `M camera/Android.bp`
- `M device.mk`
- `?? camera/android.hardware.camera.provider@2.4-service.m86.rc`
- `?? camera/service.cpp`

---

## 3. 目标 GitHub 结构

在个人账号下创建 **4 个公开仓库**。采用这个结构是因为当前 `.gitmodules` 已经使用相对 URL `../android_*.git`，同名仓库按兄弟关系排列后，GitHub 上的 `git clone --recurse-submodules` 无需修改子模块定义即可直接工作。

| GitHub 仓库 | 内容 | 默认分支 | 根许可证 |
| --- | --- | --- | --- |
| `<user>/pro5-android10` | 父仓库：README、docs、patches、tools、remote、manifests、locks、overlays、hardware、twrp、legacy | `main` | Apache-2.0（含 NOTICE 与分目录例外） |
| `<user>/android_device_meizu_m86` | device 子模块 | `lineage-17.1` | Apache-2.0 |
| `<user>/android_kernel_meizu_m86` | kernel 子模块（完整源，满足 GPL 对应源码义务） | `lineage-17.1` | GPL-2.0（已有 `COPYING`） |
| `<user>/android_vendor_meizu_m86` | vendor 子模块（仅构建定义） | `lineage-17.1` | Apache-2.0 |

说明：

- **TWRP 树第一版留在父仓库 `twrp/device/meizu/m86`**。它当前只有 10 个跟踪文件且混在父仓库历史中；在“保留完整历史直接推送”约束下，拆成独立仓库需要 `git subtree` 或 filter，必然产生新历史。待社区开始独立贡献 TWRP 时，再拆为 `<user>/android_device_meizu_m86_twrp`。
- 不发布 `pro5-android11` 及其 Samsung donor 实验树；如需开源 A11 时另立规划。
- 不发布任何 ROM zip / boot.img 等二进制制品为 GitHub Release 初版内容，原因见 §9 风险 R5。

---

## 4. 许可证落地清单

发布前需要新增的文件：

| 路径 | 内容 |
| --- | --- |
| `pro5-android10/LICENSE` | Apache-2.0 全文 |
| `pro5-android10/NOTICE` | 第三方归属：legacy cm-14.1 上游、TWRP/Omni 上游、Samsung gralloc commit、kernel 基线；声明 GPL 目录例外 |
| `pro5-android10/LICENSING.md` | 目录 → 许可证映射表，说明 Apache-2.0 不覆盖 kernel/overlay/GPL patches/legacy |
| `device/meizu/m86/LICENSE` + `NOTICE` | Apache-2.0；记录继承自 AOSP/LineageOS 的接口定义来源 |
| `vendor/meizu/m86/LICENSE` | Apache-2.0 |
| `kernel/meizu/m86/README.md`（如无则补） | 基线 commit、上游 URL、GPL-2.0 说明、与 `COPYING` 的关系 |
| `overlays/kernel-meizu-m86-case-sensitive/COPYING.GPL-2.0`（或 `NOTICE-GPL-2.0.md`） | 声明这些文件是 kernel 源副本，GPL-2.0-only |
| `patches/twrp-kernel-m86/LICENSE.GPL-2.0.md` | kernel 补丁为 GPL-2.0 |
| `docs/LICENSE.md` | CC-BY-SA-4.0 全文或规范链接 + 简短说明 |
| `legacy/device-meizu-m86-cm14/LEGAL-NOTE.md` | 上游仓库无 LICENSE；本项目不重新许可、不加修改地保留；使用者需自行追溯上游许可状态 |
| `device/meizu/m86/audio/firmware/README.md` | `stage1.txt/stage2.txt` 来自 Flyme 8.0.5.0A 调参数据的来源与生成说明 |

需要人工确认的许可决策点：

- **L1 — legacy 树**：上游 `meizu-m86/android_device_meizu_m86` 无 LICENSE。推荐保留并加 `LEGAL-NOTE.md`（不重新许可）；若你倾向零风险，可在发布分支删除 `legacy/` 并用 GitHub Release 之外的方式单独归档。
- **L2 — audio firmware txt**：`stage1.txt`/`stage2.txt` 是 820 B/94 B 的 Flyme 调参数值。社区 device tree 惯例是保留并注明来源；推荐保留 + 来源 README。若担心 Meizu 版权，发布前移除并由 `extract-files.sh` 从 stock dump 重新生成。
- **L3 — 作者邮箱**：保留完整历史意味着 `24302010006@m.fudan.edu.cn` 将公开。可以接受则继续；不愿公开则需要 `git filter-repo --mailmap`（会改写历史，与你选择的“直接推送”冲突）。折中方案：历史不动，后续提交改用 GitHub noreply 邮箱。

---

## 5. 发布前准备（Phase A）

### A1. 提交当前工作

所有提交先在本机完成，保证推送的是“已封版”状态。建议按主题拆分：

```bash
cd /Users/kophapro/Projects/Android/pro5-android10/device/meizu/m86
git add camera/ BoardConfigPlatform.mk device.mk
git commit -m "m86: source-built camera provider service and packaging"

cd /Users/kophapro/Projects/Android/pro5-android10
git add docs/domain-gates.tsv docs/module-ownership.tsv docs/platform-debt.tsv \
        docs/retired-platform-debt.tsv docs/selinux-enforcing-roadmap-2026-08.md
git commit -m "docs: refresh module ownership, platform debt and SELinux roadmap"

git add hardware/meizu/m86/audio/audio_primary_m86.cpp patches/series.tsv \
        remote/worker-build.sh tools/validate-lineage-tree.sh
git commit -m "build: carry reviewed audio, patch-series and validation updates"

git add tools/CodecProbe.java tools/CodecRoundTrip.java
git commit -m "tools: add Exynos codec ABI probes"   # 若决定保留；否则不 add
```

注意：`git status` 中“dirty 子模块指针”必须随子模块提交后，在父仓库一并 `git add device/meizu/m86 && git commit`。

### A2. 脱敏构建机默认地址

`remote/common.sh` 的默认值不要带真实 AutoDL 端点。推荐改为“未配置即拒绝运行”：

```bash
PRO5_BUILDER_HOST="${PRO5_BUILDER_HOST:-}"
PRO5_BUILDER_PORT="${PRO5_BUILDER_PORT:-}"
# 在脚本入口增加：
# [[ -n "$PRO5_BUILDER_HOST" && -n "$PRO5_BUILDER_PORT" ]] ||
#   { echo "set PRO5_BUILDER_HOST/PORT (see README)" >&2; exit 2; }
```

同时把 `README.md` 中的默认 builder 段落改为：

> Builder is selected through `PRO5_BUILDER_HOST` / `PRO5_BUILDER_PORT` (or the SSH alias `rom-builder`). No cloud endpoint is hard-coded in this public tree.

这样既保留工作流，又不公开你的云容器地址。

### A3. 补齐许可证与公开文档

按 §4 清单创建文件，然后：

- 在 README 顶部加双语项目介绍 + `License` 小节，指向 `LICENSING.md`。
- 在 README 明确 `UNOFFICIAL`、不与 Meizu/LineageOS/TWRP 官方关联。
- 增加 `CONTRIBUTING.md`、`SECURITY.md`、`CODE_OF_CONDUCT.md`（可参考 Contributor Covenant）。
- 可选：`.github/ISSUE_TEMPLATE/*.yml` 与 `PULL_REQUEST_TEMPLATE.md`。

### A4. 最终预检（每一句都应在推送前通过）

```bash
cd /Users/kophapro/Projects/Android/pro5-android10

# 1) 语法
bash -n remote/*.sh tools/*.sh

# 2) 敏感信息
git grep -n -I -E '(BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|github_pat_|api[_-]?key[[:space:]]*=)' -- . || true
git grep -n -I 'connect\.westb\.seetacloud\|50658' -- . || true   # 预期无输出

# 3) 确认没有入库的厂商二进制
git ls-files | grep -E '\.(so|apk|img|bin|zip|tar\.gz|mbn|dtb|dex)$' || true
# 允许出现：kernel 官方树内的 .img/.dat/.fw.ihex；不应出现：vendor 专有 blob、stock 固件

# 4) 工作树封版
git status --short --branch
git submodule foreach 'git status --short --branch'

# 5) 历史完整性
git fsck --strict
git submodule foreach 'git fsck --strict'
```

---

## 6. 创建 GitHub 仓库并推送（Phase B）

以下用检测到的账号 `404698-FDU` 举例，执行时以 `gh auth status` 输出为准。

### B0. 认证与账号确认

```bash
gh auth login -h github.com          # 重新登录（当前 token 已失效）
gh auth status
gh api user --jq '.login'            # 确认 <user>
```

### B1. 创建 4 个公开仓库

```bash
USER=404698-FDU   # 改成 gh api user 返回的账号

gh repo create "$USER/android_device_meizu_m86" --public \
  --description "Meizu PRO 5 (m86) device tree for LineageOS 17.1 / Android 10"

gh repo create "$USER/android_kernel_meizu_m86" --public \
  --description "Meizu PRO 5 (m86) Linux 3.10.61 kernel, maintained for LineageOS 17.1"

gh repo create "$USER/android_vendor_meizu_m86" --public \
  --description "Meizu PRO 5 (m86) vendor build definitions (no proprietary binaries)"

gh repo create "$USER/pro5-android10" --public \
  --description "Reproducible Meizu PRO 5 (m86) LineageOS 17.1 bring-up workspace"
```

为每个仓库设置 topics（GitHub 页面操作或）：

```bash
for r in android_device_meizu_m86 android_kernel_meizu_m86 \
         android_vendor_meizu_m86 pro5-android10; do
  gh repo edit "$USER/$r" \
    --add-topic meizu-pro5 --add-topic m86 --add-topic exynos7420 \
    --add-topic lineageos --add-topic android10
done
```

### B2. 推送顺序：先子模块，后父仓库

```bash
cd /Users/kophapro/Projects/Android/pro5-android10

# device
git -C device/meizu/m86 remote add origin "https://github.com/$USER/android_device_meizu_m86.git"
git -C device/meizu/m86 push -u origin lineage-17.1
gh repo edit "$USER/android_device_meizu_m86" --default-branch lineage-17.1

# kernel（体积较大，首次推送可能较慢）
git -C kernel/meizu/m86 remote add origin "https://github.com/$USER/android_kernel_meizu_m86.git"
git -C kernel/meizu/m86 push -u origin lineage-17.1
gh repo edit "$USER/android_kernel_meizu_m86" --default-branch lineage-17.1

# vendor
git -C vendor/meizu/m86 remote add origin "https://github.com/$USER/android_vendor_meizu_m86.git"
git -C vendor/meizu/m86 push -u origin lineage-17.1
gh repo edit "$USER/android_vendor_meizu_m86" --default-branch lineage-17.1

# 父仓库（.gitmodules 已是相对 URL，GitHub 上会自动解析为同账号兄弟仓库）
git remote add origin "https://github.com/$USER/pro5-android10.git"
git push -u origin main
gh repo edit "$USER/pro5-android10" --default-branch main
```

若子模块本地从未配过 `origin`，上面的 `remote add` 即可；不要执行 `git submodule sync` 修改 `origin` 前先确认 `.gitmodules` 保持 `../android_*.git` 相对形式。

### B3. 克隆验证（必须做）

```bash
rm -rf /tmp/pro5-android10-clone-test
git clone --recurse-submodules \
  "https://github.com/$USER/pro5-android10.git" /tmp/pro5-android10-clone-test
cd /tmp/pro5-android10-clone-test
git submodule status          # 期望：三个子模块均为前导空格，指向 lineage-17.1 HEAD
bash -n remote/*.sh tools/*.sh
git status --short --branch   # 期望 clean
```

验证 GitHub 页面：

- 4 个仓库均识别出正确 License（kernel 显示 GPL-2.0，其余显示 Apache-2.0）。
- `pro5-android10` 的 README 首页正常渲染中英文。
- 无任何文件显示为 “Binary file not shown” 中的厂商 blob。

---

## 7. 公开文档与社区配套（Phase C）

### 7.1 README 结构（中英双语）

1. **英文首屏**：项目名、一句话介绍、device codename/SoC、status badge 位、`UNOFFICIAL` 声明。
2. **中文正文**：保留现有 bring-up 记录风格。
3. **Build**：给出基于 public repo 的 `local_manifests` 片段：

```xml
<manifest>
  <remote name="meizu-m86" fetch="https://github.com/404698-FDU" />
  <project path="device/meizu/m86" name="android_device_meizu_m86"
           remote="meizu-m86" revision="lineage-17.1" />
  <project path="kernel/meizu/m86" name="android_kernel_meizu_m86"
           remote="meizu-m86" revision="lineage-17.1" />
  <project path="vendor/meizu/m86" name="android_vendor_meizu_m86"
           remote="meizu-m86" revision="lineage-17.1" />
</manifest>
```

4. **Safety**：明确“本仓库不含刷写/破坏性脚本授权”，device partition 写入必须显式确认。
5. **Provenance & License**：链接 `LICENSING.md`、`docs/twrp.md`、`docs/kernel-port.md`、`legacy/.../UPSTREAM.md`。

### 7.2 社区文件

- `CONTRIBUTING.md`：要求 patch 先 `git apply --check`、`bash -n`、双跑脚本验证幂等、提供构建日志与设备证据。
- `SECURITY.md`：报告路径；声明不接收厂商私有 blobs、镜像、账号凭据。
- Issue/PR 模板：至少包含 device revision、kernel revision、stock base hash、复现命令、日志。
- 发布后维护约定：A10 分支继续 `main` + `lineage-17.1`；破坏性试验分支不推公开仓库或明确标注 `WIP/do-not-flash`。

### 7.3 Release 策略

- **第一版只发布源代码仓库，不发布 ROM zip**。
- 后续可把已通过静态验收的构建发布为 GitHub Release，但仅附：
  - `SHA256SUMS`、`BUILD-METADATA`、`lineage-17.1-m86-lock.xml`、构建日志；
  - 完整 kernel 源码 git commit（GPL 对应源码义务）；
  - 明确的“不要刷入任何未经单独授权的分区”警告。
- 是否附带 `lineage-*.zip` / `boot.img` 需要在 Meizu 专有 blob 与 DTB 再分发风险复核后再决定。

---

## 8. 执行清单（Checklist）

- [ ] 确认 `gh auth status` 的账号名
- [ ] 提交 device 子模块 camera 工作并更新父仓库子模块指针
- [ ] 提交父仓库其余 dirty 文件，工作树 clean
- [ ] 处理 L3：决定作者邮箱是否接受公开
- [ ] 处理 A2：移除 `common.sh`/README 中的 AutoDL 端点
- [ ] 处理 L1/L2：legacy 与 audio firmware txt 的发布决定
- [ ] 新增 §4 全部 LICENSE/NOTICE/LICENSING 文件
- [ ] 重写 README（双语、UNOFFICIAL、Build、License）
- [ ] 新增 CONTRIBUTING/SECURITY/CODE_OF_CONDUCT
- [ ] 通过 §A4 全部预检命令
- [ ] `gh repo create` × 4（public）
- [ ] 推送 device → kernel → vendor → 父仓库
- [ ] 设置 3 个子模块仓库默认分支为 `lineage-17.1`
- [ ] 全新 clone `--recurse-submodules` 验证
- [ ] 检查 GitHub License 识别与 README 渲染
- [ ] 发布公告（XDA / 个人博客 / GitHub Discussion）并声明 UNOFFICIAL

---

## 9. 风险登记表

| ID | 风险 | 影响 | 缓解措施 |
| --- | --- | --- | --- |
| R1 | `legacy/` 上游无 LICENSE | 许可不清，可能被投诉 | 加 `UPSTREAM.md` + `LEGAL-NOTE.md`，不重新许可；或发布前删除 legacy |
| R2 | kernel 内的 ARM Mali/touch/firmware 等厂商头文件/固件源码片段 | 可能涉及厂商许可 | kernel 以 GPL-2.0 完整源发布并附基线 commit；标注“上游 Meizu 发布源，未改许可”；逐项保留出处 |
| R3 | `stage1.txt/stage2.txt` 调参数据来自 Flyme | Meizu 版权风险 | 加来源 README 或改为构建时从 stock dump 生成 |
| R4 | 作者邮箱公开 | 隐私暴露 | 历史保持；后续提交改用 GitHub noreply 邮箱 |
| R5 | ROM zip 含 Meizu 专有 blobs | 再分发侵权风险 | 首版不发二进制 Release；只发源仓库 |
| R6 | 公开构建机端点 | 云容器被扫描/滥用 | 从公开树移除默认 endpoint，改用环境变量/SSH alias |
| R7 | TWRP/Lineage/Meizu 商标 | 被误认为官方 | README/Release 声明 UNOFFICIAL，无官方背书 |
| R8 | 子模块相对 URL 解析失败 | 社区无法一键 clone | 同名兄弟仓库 + `.gitmodules` 保持 `../android_*.git`；B3 克隆验证 |
| R9 | 未提交 dirty 状态漏推/误推 | 发布内容与验证基线不一致 | 先封版、`git status` clean 再 push；每个 repo 记录发布 commit |

---

## 10. English Project Summary

**Meizu PRO 5 (`m86`) — LineageOS 17.1 / Android 10 bring-up (UNOFFICIAL)**

This workspace publishes the reproducible, host-side source of truth for bringing
LineageOS 17.1 (Android 10) to the Meizu PRO 5 (`m86`, Samsung Exynos 7420). It
contains:

- `device/meizu/m86` — device configuration, HALs and feature policies;
- `kernel/meizu/m86` — maintained Linux 3.10.61 kernel with full GPL-2.0 source;
- `vendor/meizu/m86` — build definitions only; no proprietary binaries;
- `hardware/meizu/m86` — audio, Bluetooth and graphics adapters;
- `twrp/device/meizu/m86` — TWRP 3.7.0_9 device tree;
- `patches/`, `manifests/`, `locks/`, `remote/`, `tools/`, `docs/` — reproducible
  patches, revision locks, builder scripts, tooling and bring-up documentation.

No proprietary blobs, stock firmware, device evidence, or flashable images are
committed. Building is done on a private builder selected through
`PRO5_BUILDER_HOST` / `PRO5_BUILDER_PORT`. See `LICENSING.md` for the
component-level license map: the kernel and kernel-derived files are GPL-2.0,
the device/vendor/hardware/TWRP/scripts are Apache-2.0, and the documentation is
CC-BY-SA-4.0. This project is not affiliated with or endorsed by Meizu,
LineageOS, or TeamWin.

---

## 11. English Quick Start (for README)

```bash
# 1. Initialize the LineageOS 17.1 source tree on a Linux builder.
repo init -u https://github.com/LineageOS/android.git -b lineage-17.1
repo sync

# 2. Add the m86 local manifest (adapt the GitHub account name).
mkdir -p .repo/local_manifests
cat > .repo/local_manifests/m86.xml <<'EOF'
<manifest>
  <remote name="meizu-m86" fetch="https://github.com/404698-FDU" />
  <project path="device/meizu/m86" name="android_device_meizu_m86"
           remote="meizu-m86" revision="lineage-17.1" />
  <project path="kernel/meizu/m86" name="android_kernel_meizu_m86"
           remote="meizu-m86" revision="lineage-17.1" />
  <project path="vendor/meizu/m86" name="android_vendor_meizu_m86"
           remote="meizu-m86" revision="lineage-17.1" />
</manifest>
EOF
repo sync

# 3. Reproduce the workspace tooling (optional, from the public workspace repo).
git clone --recurse-submodules \
  https://github.com/404698-FDU/pro5-android10.git

# 4. Build on the configured builder.
#    See the repository README; no script here flashes a device without
#    an explicit, separate confirmation.
```
