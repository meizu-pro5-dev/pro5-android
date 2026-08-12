# m86 LineageOS 17.1 设备树重构计划

> 状态：计划已确认；当前采用第 17 节“A10 清理后逐功能 bring-up A11”执行模式
>
> 适用范围：Meizu PRO 5（`m86`）LineageOS 17.1 / Android 10
>
> 目标：在不改变已验证硬件行为的前提下，把现有 17.1 整理为可审计、可复现、
> 可向 LineageOS 18.1 迁移的 m86-first 实现。

## 1. 决策摘要

现有 17.1 不需要从 CM14 或 Flyme 重新建树。启动链、分区、ramdisk、m86
HAL、固件和多数硬件配置继续作为实现基础。重构只解决以下结构问题：

1. Samsung common 目前仍包含 Galaxy 默认值，m86 依赖“先继承、再清空”；
2. mBack UI 和动作定义侵入 `frameworks/base`、`lineage-sdk` 和 LineageParts；
3. Hi-Fi UI 直接修改 AOSP Settings；
4. HAL、VINTF、feature XML 和实际运行状态之间缺少严格的单一所有者；
5. Android 7 blobs、source HAL 和 shim 的边界虽然已有审计，但还没有形成便于
   Android 11 逐模块迁移的产品结构；
6. 当前最终构建来自 dirty 工作区，源码提交和最终产物之间还没有封口。

重构采用以下原则：

- common 只拥有 Exynos 7420 平台能力；
- `device/meizu/m86` 主动增加 m86 功能，不通过清空 Galaxy 功能来得到 m86；
- 普通硬件键走 keylayout 和 Lineage 通用能力；
- mBack 非标准手势走 `DeviceKeyHandler`；
- mBack 和 Hi-Fi UI 走 `M86Parts`；
- framework/platform 补丁必须只解决无法在设备层表达的 ABI 或系统策略缺口；
- 未通过真机验证的 NFC 和指纹不进入默认能力声明；
- 本轮不更换内核、不更新 blobs、不改变 DTB、不扩大功能范围。

## 2. 基线和非目标

### 2.1 输入基线

- 最终 17.1 刷机 ZIP、boot、DTB、system、target-files 和哈希备份；
- 当前 m86 Linux 3.10.61 可启动内核；
- 哈希锁定的 Flyme 8.0.5.0A proprietary 集合；
- 当前 `device/meizu/m86`、`vendor/meizu/m86` 和 Samsung universal7420 common；
- 已验证的启动、显示、触摸、存储、USB、音频、无线、基带、电源等行为；
- 已知未完成：NFC、指纹完整功能。

### 2.2 明确非目标

- 不升级到 Android 11；
- 不进行 Linux 3.10.108 stable 更新；
- 不改 boot geometry、分区大小或刷写集合；
- 不用生成 DTB 替换当前锁定 DTB；
- 不格式化、迁移或备份 userdata；
- 不开发在线 OTA 或增量 OTA；
- 不修完 NFC 或指纹；
- 不在重构过程中加入新调校、新内核特性或新 proprietary 文件。

## 3. 目标所有权模型

| 层 | 允许拥有 | 禁止拥有 |
| --- | --- | --- |
| `device/samsung/universal7420-common` | Exynos 架构、ION、MFC/OpenMAX、Samsung SLSI graphics、通用 HIDL wrapper、平台 seccomp | Galaxy boot、分区、panel、RIL、audio route、sensor、NFC、fingerprint、Wi-Fi 校准、产品身份 |
| `device/meizu/m86` | boot geometry、DTB 分区、fstab/init/ueventd、m86 HAL、overlay、M86Parts、m86 sepolicy、releasetools | Galaxy 产品配置、Android 7 平台库副本 |
| `vendor/meizu/m86` | 哈希锁定的 Flyme blobs、固件、校准、生成的 vendor makefile | Samsung/Galaxy blobs、手写功能策略、framework 代码 |
| `kernel/meizu/m86` | m86 DTS、驱动、sysfs/proc/input ABI | UI、Android 设置策略 |
| Android platform patches | 无设备层替代方案的 ABI/系统缺口 | Settings 页面、设备资源、可由 HAL/overlay/DeviceKeyHandler 表达的功能 |

依赖方向固定为：

```text
LineageOS 17.1 platform
        ↑
universal7420 common platform
        ↑
device/meizu/m86
        ↑
vendor/meizu/m86 + kernel/meizu/m86
```

不允许 common 反向引用 `device/meizu/m86` 的文件，也不允许平台仓库直接读取
m86 私有配置文件。

## 4. 目标目录

```text
device/meizu/m86/
├── Android.bp
├── AndroidProducts.mk
├── BoardConfig.mk
├── device.mk
├── lineage_m86.mk
├── manifest.xml
├── compatibility_matrix.xml
├── parts/
│   ├── Android.bp
│   ├── AndroidManifest.xml
│   ├── res/xml/hifi_settings.xml
│   ├── res/xml/mback_settings.xml
│   └── src/org/lineageos/settings/
│       ├── hifi/
│       └── mback/
├── audio/
├── bluetooth/
├── camera/
├── gps/
├── keylayout/
├── lights/
├── media/
├── nfc/
├── overlay/
│   ├── frameworks/
│   └── lineage-sdk/
├── power/
├── releasetools/
├── rootdir/
├── sepolicy/
├── sensors/
├── touch/
├── usb/
└── wifi/
```

`parts/` 只服务 m86，模块名使用 `M86Parts`。如果未来出现第二台共享同一功能的
Meizu 设备，再把共享代码迁移到独立 `hardware/meizu` 或 `packages/apps/MeizuParts`；
本轮不提前泛化。

## 5. Samsung common 重构

### 5.1 BoardConfig

把 common 的内容分为两类：

**保留在 common：**

- arm64/arm 双架构和 Exynos 7420 CPU 基线；
- Samsung SLSI 编译集成；
- ION、DMA-BUF、MFC、OpenMAX、graphics 所需平台变量；
- Android 10 旧内核兼容构建开关；
- 所有 universal7420 设备都需要的 seccomp/platform include。

**移回 m86：**

- `BOARD_VENDOR := meizu`；
- boot base、offset、page size、Image 类型；
- kernel source/config；
- 独立 DTB 分区和 releasetools；
- 全部分区大小、fstab 和 recovery 配置；
- panel/backlight、电池和 charger 节点；
- Broadcom firmware 路径、Bluetooth 地址策略；
- SITRIL、SIM 数量和 modem 配置；
- m86 linker shims 和 process SDK override；
- m86 sepolicy 路径、vendor security patch；
- feature 和产品身份。

完成后，m86 `BoardConfig.mk` 不再包含一长串 `:=` 空值来撤销 Galaxy 配置。
common 新增一项变量时，不得自动改变 m86 产品行为。

### 5.2 product makefile

common product 层只打包经过 m86 审核的 Exynos 平台模块：

- graphics allocator/mapper/composer wrapper；
- source-built gralloc/HWC/memtrack 及其同族库；
- MFC/OpenMAX 平台模块；
- 通用 netutils/seccomp 兼容组件。

以下内容只允许在 m86 `device.mk`：

- audio、camera、GNSS、sensor、radio、NFC、fingerprint service；
- firmware 和 calibration；
- feature XML；
- overlay、M86Parts；
- init、keylayout、USB、power、lights；
- proprietary vendor makefile。

因为 common fork 只服务 m86，本轮删除无意义的
`ifeq ($(TARGET_DEVICE),m86)`，直接表达唯一产品需要的 Exynos 平台组合。

## 6. 硬件按键和 mBack

### 6.1 普通按键

- Power、Volume 等标准键继续由 kernel input 和 `.kl` 映射；物理 Home 的
  `gpio-keys` scan 102 在 mBack handler 中按导航模式消费；
- `config_deviceHardwareKeys` 只声明真正存在的标准硬件键；
- 不在 framework 中增加普通硬件键识别代码；
- 外接键盘的 F9–F12 不能被当成 mBack。

### 6.2 mBack 事件路径

保留四种可区分事件：

| 手势 | Android key |
| --- | --- |
| Tap | F9 |
| Double tap | F10 |
| Swipe left | F11 |
| Swipe right | F12 |

`M86Parts` 提供 `org.lineageos.settings.mback.KeyHandler`，实现 Lineage
`DeviceKeyHandler`。通过 m86 lineage-sdk overlay 配置：

- `config_deviceKeyHandlerLibs`；
- `config_deviceKeyHandlerClasses`。

KeyHandler 必须：

1. 手势只处理输入设备名 `uinput-fpc` 或 `fpc1020`；物理 Home 只处理
   `gpio-keys` + `KEYCODE_HOME` + scan 102；
2. 同时检查 key code 和 scan code，拒绝来源不匹配事件；
3. 在未取消的 key-up 上执行一次动作；
4. 返回 `null` 消费原始 F9–F12；
5. 支持 Back、Home、Recents、Menu、Sleep、Camera、Last app、Split screen
   等经审计动作；
6. 在三键导航启用时只消费、不执行 mBack 手势，物理 Home 也不得回退为
   HOME；mBack 启用时物理按压保持 HOME 语义；
7. 不影响指纹认证生命周期；
8. 不使用 Accessibility 或常驻前台服务模拟系统按键。

默认 A10 产品使用内核 raw FPC AP-navigation backend，不安装或声明任何
fingerprint userspace、feature 或 VINTF。发布 DTB 以 hash 锁定的 Flyme DTB
为输入，只把 SPI4 的零长度 `secure-mode` property 改为 FDT_NOP；compatible、
GPIO、phandle 和其余节点保持逐字节不变。M8 fingerprint experiment 使用独立
TEE defconfig 和未修改 secure DTB，两个 backend 不得同时启用。

动作配置使用 m86 私有 `Settings.Secure` 键，按 Android 用户保存。不要向
`LineageSettings` 公共 API 添加 `MBACK_*` 常量。

### 6.3 mBack UI

`M86Parts` 提供 mBack 页面：

- 四种手势动作；
- 使用 mBack 导航/使用屏幕导航栏；
- 可选触摸音和振动强度；
- Lineage Settings 外部入口和搜索 metadata。

新安装默认显示屏幕导航栏，确保 mBack 或指纹异常时仍可操作。升级迁移由
`M86Parts` 的一次性版本迁移完成，不在 `PhoneWindowManager` 中写入私有初始化
标记。

### 6.4 退出的补丁

完成 M86Parts/DeviceKeyHandler 后删除：

- `patches/frameworks-base/0004-input-handle-configurable-meizu-mback-gestures.patch`；
- `patches/lineage-sdk/0001-input-add-meizu-mback-actions-and-settings.patch`；
- `patches/packages-apps-lineageparts/0001-buttons-add-meizu-mback-controls.patch`；
- 对应 `migrations/` 补丁。

## 7. Hi-Fi UI 和后端

### 7.1 UI

`M86Parts` 提供 ES9018 页面：

- Hi-Fi enable；
- Automatic、Low、High、Line-out gain；
- Line-out 高音量确认；
- 当前耳机/后端可用状态；
- Settings 声音分类入口。

Hi-Fi 是整机全局硬件状态，M86Parts 持久化到 `Settings.Global` 并直接通知
m86 audio wrapper；wrapper 自己保存最后状态/增益并负责硬件恢复。不得继续使用
会随 Android 用户切换而改变 DAC 状态的每用户配置。

删除：

- `patches/packages-apps-settings/0001-system-add-meizu-hifi-sound.patch`（已迁移到 M86Parts）。

### 7.2 后端分两阶段

**阶段一：m86-owned policy（当前目标）。**

- M86Parts writes `Settings.Global` and calls `AudioManager.setParameters()`;
- the wrapper persists state/gain and restores them on output open, wired-route
  changes, and audioserver restart;
- the wrapper reapplies the legacy headphone-volume callback at output open and
  route changes to avoid the known low-volume regression;
- AudioService, AudioFlinger, and the global Settings HiFi patches are removed
  from the active queue.

The remaining gate is behavioral: verify normal audio first, then ES9018 modes,
headset insertion/removal, output reopen, audioserver restart, and volume-level
regression without reintroducing a framework special case.

第二阶段不阻塞 17.1 重构封口，也不阻塞 18.1 首次迁移。

## 8. HAL、VINTF 和 feature 声明

### 8.1 单一所有者

建立 `docs/module-ownership.tsv`，每行至少包含：

```text
subsystem  module  implementation  bitness  install-path  vintf-owner  init-owner  source/blob  runtime-status
```

规则：

- 一个 install path 只能有一个 owner；
- 一个 HIDL instance 只能由主 manifest 或 module fragment 中的一处声明；
- service 自带 `init_rc` 时，设备树不得再手写同名 service；
- source-built module 优先，除非锁定 blob 被明确选为 owner；
- 不能依赖重复 make rule 的覆盖顺序选择 ABI 家族。

### 8.2 module-owned fragment

对本地源码 service，优先在 `Android.bp` 中绑定：

```bp
init_rc: ["service.m86.rc"],
vintf_fragments: ["service.m86.xml"],
```

主 `manifest.xml` 只保留没有 module fragment 的外部/旧式服务。构建后必须运行
分支对应的 `checkvintf`，并检查最终安装目录中的全部 fragments。

### 8.3 未完成功能

默认 17.1 产品在重构期间：

- 不复制 NFC 和 fingerprint feature XML；
- 不在主 manifest 声明未通过的 instance；
- 不在设置中显示可用能力；
- 保留源码、配置和 proprietary 文件，供独立实验构建使用。

恢复声明的前提是完成各自的真机矩阵，而不是“服务进程存在”或“模块成功打包”。

## 9. Proprietary 和 shim 整理

### 9.1 不改变输入 bytes

本轮使用现有锁定 Flyme 集合，不增删 blob。先把生成 makefile 按功能分段并生成
所有权报表：

- boot-independent firmware；
- graphics；
- media/OMX；
- audio；
- radio；
- Wi-Fi/Bluetooth；
- camera；
- sensors/GNSS；
- NFC；
- fingerprint/Trustonic。

### 9.2 shim 规则

每个 shim 必须记录：

- 精确调用者和 ABI 位数；
- 缺失 symbol；
- 输出安装路径；
- 加载机制；
- Android 10 验证结果；
- Android 11 重新审计要求。

禁止：

- 导入 Android 7 `libbinder`、`libutils`、`libcutils` 等平台库；
- 用一个宽泛 shim 为无关子系统提供大量旧 symbol；
- 让 Flyme 和 Samsung source 的同名图形库在同一 namespace 依赖搜索顺序碰运气。

## 10. 平台补丁处置矩阵

| 补丁组 | 17.1 重构处置 | 退出条件 |
| --- | --- | --- |
| mBack：framework/base、lineage-sdk、LineageParts | 删除 | M86Parts + DeviceKeyHandler 通过真机测试 |
| Hi-Fi：Settings | 删除 | M86Parts Hi-Fi 页面可用 |
| Hi-Fi：AudioService/AudioFlinger | 删除 | M86Parts→wrapper Global contract and route/restart matrix |
| headphone volume / Hi-Fi audio hook | 暂留、重新记录 ABI | audio wrapper 或 HAL 原生实现等价能力 |
| hardware/interfaces legacy audio guards | 暂留 | Flyme HAL wrapper 不再触发缺失 callback |
| camera provider binder compatibility | 暂留 | camera wrapper/provider 不再需要旧 binder 路径 |
| gralloc fbdev hardening | 移入 common 平台补丁层 | 上游 source module 包含等价修复 |
| system/core legacy adbd transport | 暂留、与设备 rc 联合验证 | 不打补丁的 adbd 连续冷启动和大文件传输稳定 |
| storage isolated-storage override | 单独复核，不与重构混合 | 能由产品属性/overlay 表达或确认仍必需 |
| build/make releasetools | 保留刷机 ZIP 所需最小部分 | 不再需要对应 cache/full-package 例外 |
| common m86 target、BT fallback、rild patch | 重写为明确平台接口 | common 不再含 Galaxy 产品分支或运行时型号特判 |
| external/glib legacy build | 暂留 | 最后调用它的 vendor 组件被替换 |

`patches/series.tsv` 的每一行必须增加或关联：原因、m86 调用者、验证门槛和计划
退出版本。不能仅凭“构建需要”永久保留平台补丁。

## 11. SELinux

当前 permissive 不能作为重构完成条件。策略按服务分组：

- boot/init/mount；
- graphics/media；
- radio/cbd；
- audio/Hi-Fi；
- Wi-Fi/Bluetooth；
- camera；
- sensors/GNSS；
- Trustonic/fingerprint；
- NFC；
- M86Parts/DeviceKeyHandler。

规则：

- common policy 只描述 Exynos 平台类型；
- m86 设备节点、属性、文件和 daemon policy 放设备树；
- 不把 Galaxy `file_contexts` 整体继承进 m86；
- 不用通配 allow、`dontaudit` 或 `SELINUX_IGNORE_NEVERALLOWS` 掩盖未知拒绝；
- 先在 permissive 收集、归因，再以 enforcing 冷启动和功能回归封口。

M2 基线已经捕获 SurfaceFlinger 对 `/dev/mali0` 和
`/sys/devices/13930000.decon_fb/vsync` 的 denial。它们不阻塞 permissive 下的
图形 bring-up，但属于 graphics policy 的明确未偿债务；M8 必须使用 m86-owned
设备类型和最小 allow 规则收敛，不能以 ueventd 的宽权限替代标签和策略。

NFC/指纹 policy 可以留在实验分支，不阻塞默认产品 enforcing。

## 12. 实施阶段和门槛

R0–R6 描述的是一次性完成并发布整套重构版 17.1 的阶段模型。当前按第 17 节
逐功能执行：每个功能域从这里选取相应的源码、构建和设备门槛，在 A10 通过后
才进入 A11。无需等待全部 R0–R6 完成，但任何被选中的 A10 门槛都不能省略。

### R0：源码封口

工作：

- 保存当前三个子仓库 SHA 和完整 dirty diff；
- 把最终产物对应的必要修改整理为聚焦提交；
- 记录所有 untracked 文件；
- 生成新的 manifest lock、blob lock 和 patch inventory；
- 保留现有最终 ZIP/boot/DTB/system/target-files 作为行为 oracle。

门槛：干净 checkout 能安装同一组本地树和补丁，且没有 builder-only 手改。

### R1：common 边界重构

工作：

- common 删除 Galaxy boot/product/HAL 默认值；
- m86 BoardConfig 主动声明板级配置；
- common product 仅保留 Exynos 平台模块；
- 不改 kernel、DTB、vendor bytes 和 platform patches。

构建门槛：

- patch script 连续执行两次保持幂等；
- `bootimage` 和 `systemimage` 构建通过；
- boot header、kernel 和 DTB 输入不变；
- installed-files、module owner、VINTF 和 proprietary hash audit 通过。

设备门槛：启动、ADB、显示、触摸、存储、USB，随后做一次全功能回归。

### R2：M86Parts 与 mBack

工作：

- 新建 M86Parts；
- 迁移 mBack UI 和设置；
- 现代化旧 m86 `DeviceKeyHandler`；
- 添加 Lineage key handler overlay；
- 删除 mBack 三组平台补丁。

设备门槛：

- 四种手势动作立即生效并跨重启保存；
- 屏幕导航与 mBack 导航可安全互换；
- 外接 F9–F12 不触发 mBack；
- keyguard、横屏、熄屏、快速重复操作正常；
- 指纹认证即使尚未完整适配，也不能因导航 handler 崩溃或被抢占。

### R3：M86Parts 与 Hi-Fi

工作：

- 迁移 Hi-Fi UI；
- 删除 Settings 补丁；
- 暂保窄化后的 audio framework compatibility；
- 明确全局设置迁移和默认值。

设备门槛：普通 codec/ES9018 切换、四种 gain、耳机插拔、Line-out 警告、
audioserver restart、通话、蓝牙音频、休眠恢复均不回归。

### R4：HAL/VINTF/feature 清理

工作：

- 完成 module ownership 表；
- 消除重复 service、manifest 和 install rule；
- NFC/指纹从默认 feature 声明移除；
- 每个功能域独立执行 ELF、namespace 和 VINTF audit。

设备门槛：除明确隐藏的 NFC/指纹外，17.1 已验证功能无回归。

### R5：平台补丁收敛与 enforcing

工作：

- 按处置矩阵逐个证明剩余 patch 必需；
- 完成 m86 sepolicy；
- 移除 permissive 和忽略 neverallow 的设置；
- 生成最终 clean source lock。

门槛：enforcing 冷启动、完整功能矩阵、连续 suspend/resume、压力和重启测试通过。

### R6：17.1 重构基线封存

生成：

- TWRP 完整刷机 ZIP；
- boot.img、system.img、target-files；
- manifest lock、kernel config、patch inventory；
- module ownership、blob/shim ABI 报表；
- 完整 build log、installed-files 和 SHA-256；
- 设备回归记录；
- 回退到重构前最终 17.1 的说明。

不生成在线 OTA，不包含 userdata/data/cache 格式化。

## 13. 真机回归矩阵

每阶段至少记录：

| 功能域 | 最小证据 |
| --- | --- |
| Boot | 冷启动、连续 5 次重启、pstore/reset reason |
| ADB/USB | adb、MTP、500 MiB 双向传输、插拔 20 次 |
| Display/input | bootanimation/UI、亮度、触摸、旋转、按键、mBack |
| Storage | system/data/internal storage/microSD、重启后挂载 |
| Audio | speaker、receiver、mic、wired、BT、call、Hi-Fi |
| Radio | 双卡、短信、通话、移动数据、飞行模式恢复 |
| Wi-Fi/BT | 扫描、连接、热点、配对、音频、重启恢复 |
| Camera/media | 前后摄预览、拍照、录像、flash、硬解 |
| Sensors/GNSS | 已声明 sensor、定位、休眠恢复 |
| Power | 充电、电量、温度、suspend/resume、待机 |
| NFC/fingerprint | 标记未完成，不得伪装通过 |
| SELinux | enforcing、无持续关键 denial、服务无 crash loop |

“模块存在”“服务已注册”或“设置页面出现”都不是功能通过证据。

## 14. 变更隔离和回退

- 每个阶段只改变一个所有权边界；
- common 重构时不改 UI，M86Parts 迁移时不改 kernel，SELinux 收敛时不换 blob；
- 每阶段先构建受影响模块，再 `bootimage/systemimage`，最后 `bacon`；
- 每个真机候选记录 ZIP、boot、DTB SHA-256 和实际分区读回哈希；
- 写 boot/system/DTB 继续遵守逐次授权；
- 不写 userdata、bootloader、ldfw、private、proinfo 或其他敏感分区；
- 任一核心功能回归时回退当前阶段，不在失败状态叠加下一阶段。

## 15. 每个功能域向 LineageOS 18.1 的交付物

一个 17.1 功能域完成清理和回归后，18.1 才接收该功能域的以下输入：

1. 干净提交的 m86 BoardConfig、ramdisk、partition 和 releasetools；
2. m86-owned HAL、M86Parts 和 DeviceKeyHandler；
3. 明确所有权的 m86 platform 模块，或锁定且未修改的 Exynos 上游模块；
4. 哈希锁定的 vendor 输入及功能分组；
5. 每个 shim 的调用者和 Android 11 重审清单；
6. 最小剩余 platform patch 列表；
7. 17.1 真机行为矩阵和最终产物 oracle；
8. NFC/指纹的明确未完成状态。

18.1 不直接复制 17.1 的 monolithic manifest、Settings/LineageParts patch、
“继承 common 后清空”的 BoardConfig 结构或其他尚未通过 A10 cleanup 的实现，
也不把适配落入三星 A11 仓库。

## 16. 完成定义

只有同时满足以下条件，17.1 设备树重构才算完成：

- 本地及远端源码工作区干净且 revision 可锁定；
- common/device/vendor/kernel/platform patch 的所有权清楚；
- mBack 和 Hi-Fi UI 均由 M86Parts 提供；
- mBack 使用 DeviceKeyHandler，无 mBack 专属 framework/Lineage SDK/LineageParts 补丁；
- AOSP Settings 不包含 m86 Hi-Fi 页面；
- 没有重复 HAL、VINTF instance 或 install owner；
- 默认产品不宣称未完成的 NFC/指纹；
- SELinux enforcing；
- 已验证功能相对重构前无回归；
- 完整刷机 ZIP、target-files、锁、日志、哈希和设备证据已归档；
- 可以从干净 checkout 在构建机上重复生成同一来源集合，无手工远端修改。

以上是独立发布重构版 17.1 的完成定义。在第 17 节逐功能迁移模式下，不要求先
完成整套 R0–R6 再开始 Android 11；但一个功能域只有在 A10 清理构建和真机回归
通过后，才允许进入对应的 A11 port。已归档的旧 A10 产物始终保留为回退 oracle，
新的 A10 清理候选使用新名称和新哈希，绝不覆盖旧产物。

## 17. 从 A10 清理开始逐功能 bring-up LineageOS 18.1

### 17.1 路线决策

Android 11 不再以修改三星 `lineage-18.1` device/common/hardware 源码为主线。
当前执行方式是：

- A10/LineageOS 17.1 保持为可构建、可修改、可实机回归的清理基线，而不是只读
  frozen oracle；
- 每次只选择一个功能域，先在 A10 消除脏实现并证明行为无回归，再把清理后的
  m86 实现移植到 A11；
- 不要求先发布一套全部清理完成的 A10，也不允许绕过该功能域的 A10 清理门槛
  直接在 A11 堆兼容补丁；
- A11 只接收 m86-owned 的 device、vendor、HAL/wrapper、M86Parts、sepolicy 和
  必需的最小 platform compatibility；
- 三星 A11 仓库只能作为只读参考或未修改的构建依赖，禁止承载 m86 patch、条件
  分支、RUNPATH、产品配置或服务所有权；
- 现有基于三星 A11 common/HWC/RUNPATH 的候选只保留为诊断证据，不再作为后续
  构建或刷机基线；
- NFC 和指纹继续作为明确未完成项，不阻塞其他功能域。

### 17.2 三条工作轨

#### 轨道 C：A10 cleanup baseline

对当前 A10 实现逐域执行清理：

- 保留已验证的旧 ZIP、boot、DTB、system、target-files 和 SHA-256 作为回退；
- 保存当前 dirty diff、untracked 文件、manifest、kernel config 和 blob lock；
- 把“继承 Samsung common 后清空”、重复 HAL/VINTF/init owner、全局 m86 平台补丁
  和宽泛 shim 改造成明确的 m86 owner；
- 每个功能域生成新的 A10 构建和真机回归证据；
- 不在清理时换内核、DTB 或 proprietary bytes，也不顺带开发下一个功能。

轨道 C 是活跃实现轨，不接收 A11 service、HIDL/VINTF 版本或 branch-specific
策略。A10 清理失败时，A11 对应功能保持未迁移。

#### 轨道 P：portable m86 layer

维护已经通过 A10 清理门槛、可以跨 Android 版本迁移的内容：

- boot geometry、partition map、独立 DTB、fstab、init 和 ueventd 硬件事实；
- keylayout、input identity、mBack gesture contract 和 M86Parts 业务逻辑；
- m86 lights、power、USB serial、audio/camera/media compatibility 等源码实现；
- mixer、firmware、calibration、GNSS/NFC 配置和 proprietary inventory；
- module ownership、blob/shim ABI、sysfs/ioctl/property 契约和运行时证据。

轨道 P 不包含 Android 版本号、HIDL/VINTF 版本、A11 linker namespace 规则或
平台构建开关。A10/A11 文件不能共用时，必须共享同一硬件事实并在 migration map
记录两边实现。

#### 轨道 T：A11 m86 target

负责把轨道 P 的单个已清理功能域接入 LineageOS 18.1：

- 产品入口、BoardConfig、partition、ramdisk 和功能声明由 `device/meizu/m86`
  主动拥有；
- Android 11 service wrapper、module-owned VINTF fragment、init、sepolicy、
  property context 和 compatibility matrix 放在 m86-owned 仓库；
- 需要新增共享代码时优先使用 `hardware/meizu/m86` 或等价的 m86-owned 目录；
- 官方 LineageOS 和三星 A11 仓库保持干净；确需平台补丁时只修改官方 LineageOS
  平台仓库，并记录唯一调用者、失败日志、无设备层替代的理由和退出条件；
- 每个功能域独立构建、刷机、回归和封存，不从失败状态继续叠加功能。

### 17.3 提交分层

每个功能域使用四类提交，禁止混合：

1. `facts:` 锁定 A10 当前硬件事实、ABI、owner 和行为证据；
2. `a10-clean:` 清理 A10 实现并删除被替代的脏补丁；
3. `a11-port:` 把通过 A10 门槛的 m86 实现接入 A11；
4. `a11-platform:` 只处理 A11 无设备/HAL/overlay 替代方案的最小兼容缺口。

示例：

```text
facts: lock m86 mBack input-device and gesture contract
a10-clean: move mBack actions into M86Parts DeviceKeyHandler
a10-clean: drop m86 framework and LineageParts input patches
a11-port: add the validated m86 key handler and overlay
a11-platform: <不存在；使用 Lineage DeviceKeyHandler 扩展点>
```

图形功能域也必须从 A10 owner 开始，而不是从三星 A11 源码开始：

```text
facts: record the A10 graphics owner set and Flyme camera/OMX consumers
a10-clean: make the m86 graphics family and dependency closure explicit
a11-port: select the validated m86 graphics implementation on Android 11
a11-platform: <仅在失败日志证明设备层无法解决时存在>
```

禁止新增针对三星 A11 device/common/hardware 仓库的提交。每个
`a11-platform:` 提交必须记录调用者、失败日志、验证命令和退出条件。

### 17.4 迁移矩阵

`pro5-android11/docs/lineage17-migration-map.tsv` 对每个功能域记录：

```text
subsystem  a10-source  a10-dirty-impl  a10-clean-commit  a10-validation
           portable-output  a11-target  a11-port-commit  status
```

允许的 A11 处理结论为：

- `copy-fact`：硬件事实原样迁移；
- `port-source`：只移植已经通过 A10 清理门槛的源码；
- `use-unmodified`：使用未修改的官方或三星 A11 模块；
- `m86-wrapper`：由 m86-owned wrapper 隔离旧 blob/API；
- `defer`：NFC/指纹等未完成项；
- `drop`：Galaxy 实现、被清理的 A10 脏补丁或无实际调用者的内容。

任何 A11 输入都必须能追溯到 A10 清理提交、锁定硬件事实或未修改的上游模块。
禁止为了通过编译而复制无来源 common、blob 或平台库。

### 17.5 当前执行顺序

#### M0：双基线封口

- 固化最后可用 A10 产物，同时保存当前 A10 dirty source 全量证据；
- 重新建立可重复的 A10 clean checkout、patch queue 和构建入口；
- 将现有三星 A11 common/HWC/RUNPATH ZIP、日志和补丁标记为 historical；
- 建立新的 A11-from-A10 分支和 artifact 命名空间，不复用旧 S0 候选名称。

门槛：旧 A10 回退包可校验；当前 dirty 实现全部有来源；A10 可从本地权威源码
重新构建；新 A11 分支不含针对三星 A11 仓库的 m86 修改。

#### M1：boot、partition、DTB、ramdisk 与基础 ADB

- 在 A10 清理 BoardConfig、boot geometry、独立 DTB、fstab、init、ueventd、
  USB gadget 最小启动路径和 releasetools owner；
- 删除通过继承/清空 Galaxy 配置形成的启动链；
- A10 重新构建并验证 boot、存储基础和 ADB；
- 将同一套 m86 硬件事实移植到最小 A11 target，先达到 kernel/init/ADB，暂不
  宣称 UI 或其他硬件功能。

#### M2：显示与图形

- 在 A10 锁定唯一 graphics owner、32/64 位依赖闭包及 camera/OMX 消费者；
- 清除重复安装、同 SONAME 搜索顺序和 donor 覆盖行为；
- A10 UI、亮度、旋转及只覆盖 graphics-buffer 路径的视频 smoke 通过后，再在 A11
  接入同一 owner 模型；完整硬件编解码矩阵属于 M7；
- A11 不修改三星 graphics 源码；需要兼容时使用 m86-owned wrapper 或未修改模块。

#### M3：存储、USB/MTP 与输入/mBack

依次处理 storage → USB/MTP → standard keys → mBack：每个子域都必须先完成 A10
清理和实机回归。mBack 迁入 M86Parts/DeviceKeyHandler，并从 A10 开始删除
frameworks/base、lineage-sdk 和 LineageParts 的 m86 专属补丁。

#### M4：Wi-Fi、Bluetooth 与 radio

按 Wi-Fi → Bluetooth → dual-SIM/radio 顺序逐域执行。每域一次性清理并迁移
package、init、VINTF、sepolicy、firmware/calibration 和 proprietary owner；
不得继续使用 Samsung common 中的 m86 Bluetooth/rild 条件分支。M4 radio 门槛只
封注册、短信、数据、切卡、call setup/state；完整通话音频属于 M5 联合门槛，避免
M4 与 M5 形成循环依赖。

#### M5：普通音频与 Hi-Fi

- 先清理并验证 A10 playback、record、call、wired 和 BT audio；
- 优先用 m86-owned audio wrapper 收敛 Flyme HAL ABI，逐步退出全局
  AudioService、AudioFlinger、`hardware/interfaces` 和 `libhardware` 特判；
- 普通音频在 A11 通过后，再迁移 M86Parts Hi-Fi UI、gain 和恢复策略。

#### M6：lights、vibrator、power、sensors 与 GNSS

每个子系统独立完成 A10 cleanup → A10 test → A11 port → A11 test，保留独立
回退点，不把多项低层服务打成一个不可二分的候选。lights、vibrator、power、
sensors 可并行做只读 facts/ABI 审计和独立源码草案；进入同一集成分支、生成候选和
真机矩阵时仍严格一次一个。GNSS 的 AGPS 真机门槛等待 M4 radio。

#### M7：media/OMX 与 camera

- 先在 A10 明确 Flyme OMX/camera blob、shim 和 graphics buffer ABI 的唯一 owner；
- 先迁移 media/codec，再迁移 camera enumerate、preview、capture、record/flash；
- A11 compatibility 放在 m86-owned wrapper，不能通过修改三星 A11 graphics 或
  camera donor 解决。

#### M8：NFC、fingerprint、enforcing 与发布封口

- NFC/fingerprint 默认隐藏，在核心功能稳定后使用独立实验分支；
- 每个功能只有完整 A10/A11 运行时矩阵通过后才恢复 feature/VINTF/设置入口；
- 最后在 A11 完成 enforcing、FDE、功耗温控、完整 ZIP 和回退验证；
- 归档 A10 cleanup history、migration map、ownership、patch inventory、manifest、
  artifacts 和设备证据。

### 17.6 每个功能域的双闭环模板

每次迁移必须依次完成：

1. **Observe A10**：记录服务、模块、日志、节点、属性、ABI 和真机行为；
2. **Assign A10**：指定 device/vendor/HAL/platform 唯一 owner；
3. **Clean A10**：删除 Galaxy 默认、重复声明、全局设备特判和宽泛 shim；
4. **Build A10**：受影响模块 → boot/system → `bacon`；
5. **Test A10**：执行该功能矩阵及 boot/display/storage/USB 核心回归；
6. **Port A11**：只移植已验证的硬件事实和 m86-owned 实现；
7. **Build/Audit A11**：检查 ELF、namespace、VINTF、installed-files、blob hashes；
8. **Test A11**：执行同一功能矩阵和核心回归；
9. **Seal**：保存两边提交、manifest、日志、哈希、回退包并更新 migration map。

A10 清理和 A11 port 是同一功能域的两个顺序门槛，但必须是不同提交。A10 未通过
时不得开始 A11；A11 未通过时不得进入下一个功能域。

用户可以明确接受某一未完成真机项的风险并要求主线继续，但必须在
`domain-gate-waivers.tsv` 记录日期、未完成项、授权范围和证据。豁免不会把
`pending` 改写成 `passed`，也不自动满足 release seal；除非记录明确授权，豁免只
允许进入紧邻的下一 A10 功能域，不能据此开始 A11 port。

可并行范围只包括只读 facts/ABI/owner 审计、互不重叠的源码草案和静态工具开发。
同一主线 candidate、A10→A11 门槛、刷机和设备验证始终串行；SELinux、vendor
分组与 validator 随每个域一起收敛，不能拖到 M8 一次修复。

### 17.7 同步规则

- A10 facts 或 clean 实现变化后，必须在同一工作包更新 migration map；
- 每个 portable source 先在 A10 编译和真机验证，再进入 A11；
- 不为保持文本相同而共享 BoardConfig、HIDL/VINTF 或 branch-specific 文件；
- 不把 A11 service/policy 反向塞入 A10，也不把 A10 platform hack 原样复制到 A11；
- 三星 A11 仓库必须保持干净，`git status --porcelain` 非空即阻止候选封存；
- A10 和 A11 artifacts 使用不同目录与版本名，任何旧产物都不可被覆盖。

### 17.8 完成定义

满足以下条件后，才可认为 A10 清理与 A11 bring-up 完成：

- A10 每个有效功能域都有清理提交、A10 构建和真机回归证据；
- A10 的 Samsung common 条件分支、mBack/Hi-Fi 全局 UI 补丁、重复 owner 和宽泛
  compatibility hack 均已迁出或有明确保留理由；
- A11 每项功能都能追溯到通过验证的 A10 实现或未修改的上游模块；
- 三星 A11 device/common/hardware 仓库没有 m86 patch 或脏工作区；
- A11 device/vendor/HAL/M86Parts/platform patch 有唯一所有权；
- 每个保留 shim/platform patch 都有调用者、验证证据和退出条件；
- NFC/指纹状态如实隐藏或标记；
- A11 enforcing、完整刷机 ZIP 和核心功能矩阵通过；
- A10 原始 oracle、A10 clean artifacts、A11 最终 artifacts 及迁移证据全部归档。
