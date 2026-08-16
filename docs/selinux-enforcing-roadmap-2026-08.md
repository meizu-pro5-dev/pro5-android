# SELinux Enforcing 差距评估 — m86 Android 10（2026-08-14 实测）

## 结论

当前 ROM 距离 Enforcing 主要是“标签债 + 少量最小 allow 规则”，不是内核能力
缺口。冷启动 permissive 抓取到 **316 条去重 denial 事件、161 个唯一
(scontext,tcontext,tclass,perms) 元组、85 行聚合 allow 草案**；其中
**71%（224/316）的 tcontext 是通用 `device`/`sysfs`/`debugfs`**，说明问题
首先在文件/节点标签，不在策略规则数量。内核 SELinux 已启用且不可关闭，
policy v30 正常加载，编译后策略只有 `su`、`backuptool` 两个 permissive 域。

只要完成下面三层工作，就可以进入 enforcing 冷启动迭代：

1. 移除内核内置 `androidboot.selinux=permissive`，得到可 enforcing 启动的内核；
2. 为 m86 硬件节点/sysfs/debugfs 补齐标签（覆盖约七成 denial）；
3. 按服务域补 30–50 条最小 allow 规则，然后冷启动/功能回归收敛。

---

## 1. 当前状态（已固化为证据）

证据目录：`evidence/selinux-enforcing-gap-20260814/`

| 项目 | 实测值 |
| --- | --- |
| `getenforce` | `Permissive` |
| effective cmdline | 内核 defconfig 内置 `androidboot.hardware=m86 androidboot.selinux=permissive`，`CONFIG_CMDLINE_EXTEND=y` |
| 涉及 defconfig | `cm_pro5_defconfig`、`cm_pro5_fingerprint_experiment_defconfig`（均为第 461–462 行） |
| 内核能力 | `CONFIG_SECURITY_SELINUX=y`，`SECURITY_SELINUX_BOOTPARAM`/`DISABLE` 未开，`DEFAULT_SECURITY_SELINUX=y`，`DEVELOP=y` |
| policy 版本 | 30；编译产物 459,789 字节，与设备 `/sepolicy` sha256 一致 |
| 编译策略规模 | 1,375 types / 22,811 rules（`checkpolicy -M -b` 索引输出） |
| 编译策略 permissive 域 | 仅 `su`、`backuptool` |
| 设备 `sepolicy` | `/sepolicy` = builder `precompiled_sepolicy`，sha256 `99016e9a…dd656` |
| 本产品 | `lineage_m86_fingerprint_experiment-userdebug 10`（当前实机） |

### 为什么是 permissive

不是 `BOARD_KERNEL_CMDLINE`（它为空，boot.img v0 header cmdline 也为空），
而是 kernel 自己的内置 cmdline。`system/core/init/selinux.cpp` 的
`StatusFromCmdline()` 只要看到 `androidboot.selinux=permissive` 就置
permissive，所以后续 Enforcing 门槛的第一步是改 defconfig 而不是改 build
system：

```text
# 现状
CONFIG_CMDLINE="androidboot.hardware=m86 androidboot.selinux=permissive"
CONFIG_CMDLINE_EXTEND=y

# Enforcing 实验候选
CONFIG_CMDLINE="androidboot.hardware=m86"
CONFIG_CMDLINE_EXTEND=y
```

`CONFIG_CMDLINE_EXTEND` 必须保留：当前 DTB 的 `/chosen/bootargs` 非空，否则
`androidboot.hardware=m86` 会丢失（见 `docs/kernel-port.md`）。移除
permissive 后需实测确认 bootloader/DTB 没有额外注入 `androidboot.selinux=
permissive`；若存在，再在 m86 init patch 或 bootargs 覆盖层处理。

---

## 2. Denial 基线

采集方式：冷启动 Lineage 10，permissive；`dmesg` + `logcat -b all -d`，
按 audit serial 去重，再用路径聚合。解析产物：

- `denial-raw-lines.txt` — 316 条去重事件原文
- `denial-unique.tsv` — 161 个唯一规则元组及次数
- `denial-path-counts.tsv` — 141 个 path 级键及权限并集
- `allow-draft.txt` — 85 行聚合 allow 草案（含明显不可行的通用规则）

### 2.1 按 tcontext 分类

| tcontext | 事件 | 占比 | 含义 |
| --- | ---: | ---: | --- |
| `device` | 141 | 44% | `/dev` 节点没有 device 类型标签 |
| `sysfs` | 68 | 21% | sysfs 路径没有细分 genfs 标签 |
| `debugfs` | 14 | 4% | Mali debugfs 没有标签 |
| 其他具体类型 | 92 | 29% | 真正需要新增/补全的规则 |
| `unlabeled` | 1 | <1% | 待定位 `.version` unlink |

也就是说：**先把标签补对，denial 基数就降到约 92 条事件（29%）**。

### 2.2 按子系统分桶（事件数）

| 子系统 | 事件 | 主要对象 |
| --- | ---: | --- |
| graphics/GPU | 93 | `/dev/mali0`、decon vsync、debugfs mali |
| 其他（见 2.4） | 57 | module_request、binder、属性、exec、app 噪声 |
| power/sensors/light | 45 | bq2753x、hotplug/boostpulse、iio/als、背光/LED |
| TEE/fingerprint | 37 | `/dev/mobicore*`、s5p-smem、uinput、fpdata |
| cgroup | 22 | `/dev/stune/*/tasks` |
| init/mount | 17 | socket/netlink、efs mount、cbd/shell exec |
| GNSS/GPS | 15 | `/data/system/gps/*` FIFO、vndbinder |
| radio/cbd | 13 | `/dev/umts_ipc*`、operatortable.db |
| audio | 11 | `/dev/i2c-7`、HiFi/audience 属性 |
| fsck | 4 | `/dev/block/sda43` |
| wifi | 2 | `/data/calibration/mac_addr` |

快速开关 wifi/蓝牙追加的 denial 很少（12 条，集中在 `hal_wifi` 读 mac_addr、
rild ioctl、shell 属性文件），未改变上述结构。

### 2.3 前 20 条 path 级缺口（摘录）

| 次数 | 对象 | 源域 | 建议修复 |
| ---: | --- | --- | --- |
| 23 | `/dev/mali0` | surfaceflinger | 标 `gpu_device`；AOSP 已有 surfaceflinger→gpu 规则 |
| 15 | `/dev/mali0` | bootanim | 标 `gpu_device`；AOSP 已有 bootanim→gpu 规则 |
| 15 | `/dev/mali0` | platform_app | 标 `gpu_device`；AOSP appdomain→gpu 已覆盖 |
| 14 | bq2753x `present` | healthd | genfs 标 `sysfs_batteryinfo`；healthd 规则已存在 |
| 10 | `/dev/mobicore` | init | 标 `tee_device` + `allow init tee_device:chr_file rw_file_perms` |
| 9+8 | `/dev/stune/*/tasks` | zygote | 标 `cgroup`；AOSP zygote→cgroup 规则已覆盖大部分 |
| 9 | FPC `clk_enable` | hal_fingerprint_default | 细粒度 `fpc_sysfs` 类型 + 最小写规则 |
| 7 | CPU `boostpulse` | hal_power_default | 窄 genfs 类型（如 `m86_cpufreq_sysfs`）+ write |
| 6 | MFC `video6/name` | mediacodec | genfs 标 MFC sysfs 类型 + r_file_perms |
| 5 | debugfs `/mali/mem*` | system_server | genfs 标 `debugfs_gpu` + r_dir_file |
| 5 | `/dev/i2c-7` | audioserver | 标 `i2c_device`/audio 专用类型 + rw_file_perms |
| 4 | `operatortable.db` | rild | 补 `rild → radio_data_file` 文件规则 |
| 3+3 | `/dev/umts_ipc0/1` | rild | 标 `radio_device` + rild rw 规则 |
| 3 | `/dev/mobicore-user` | hal_fingerprint_default | `tee_device` + HAL rw 规则 |
| 2 | `fpdata/user.db` | hal_fingerprint_default | 补 HAL→`fingerprintd_data_file` 读规则 |
| 2 | `/dev/vndbinder` | hal_gnss_default | `vndbinder_use(hal_gnss)` |
| 2 | `/dev/uinput` | hal_fingerprint_default | 补 HAL→`uhid_device` rw 规则 |
| 2 | `/dev/s5p-smem` | hal_fingerprint_default | 标 `ion_device` + HAL rw 规则 |

### 2.4 “其他”桶里的固定动作

- **module_request `personality-8`**：10 个服务域。内核 3.10 不支持
  personality-8 模块请求，属于无害噪声；按域 `dontaudit`，不放开
  `module_request`。
- **`init → system_file:file execute_no_trans`**：`cbd`、`mcDriverDaemon`、
  `m86_usb_serial` 直接在 init 域执行。正确做法是为三者建立 exec type 和
  domain transition；不能给 init 开 execute_no_trans 通配。
- **属性 denial**：`audioserver` 写 `primary.pa.ready`、
  `persist.sys.audience.ustrhal`、`persist.vendor.m86.hifi.enabled`，
  `rild` 写 `radio.ril.reset_count`。给这些属性建 device property type，
  并把 persist 属性移入对应 property_contexts。
- **app 噪声**：untrusted_app 读 `/proc/<pid>/net/tcp` 与 `apexd_prop`。
  enforcing 下应保持拒绝；确认具体 app 来源后 `dontaudit` 或修 app 行为，
  不开放 appdomain→property/proc_net。
- **init↔system_suspend、init↔hwservicemanager binder**：补最小
  `binder_call` 对。
- **`fsck → block_device(sda43)`、`init → efs_file:dir mounton`**：为
  `/dev/block/sda43`（custom 分区）建类型并授权 fsck；给 init 补 efs mount。

---

## 3. 还差多远：工作分解

### P0 — enforcing 启动开关（1 个内核构建 + 1 次刷机）

改两个 m86 defconfig 的 `CONFIG_CMDLINE`，构建 boot.img，冷启动确认
`getenforce=Enforcing` 且 adb/串口仍可用。这一步会立刻暴露 P1/P2 未覆盖的
硬失败；失败时通过回刷 permissive boot.img 恢复，不碰 system/data。

### P1 — 标签层（预计 1 个 sepolicy 批次，消掉约 70% denial）

新增/扩展：

- `file_contexts`：`/dev/mali0`、`/dev/i2c-7`、`/dev/adnc0..5`、
  `/dev/video16`、`/dev/umts_ipc*`、`/dev/umts_dm0`、`/dev/umts_router`、
  `/dev/umts_boot0`、`/dev/umts_rfs0`、`/dev/mobicore*`、`/dev/s5p-smem`、
  `/dev/spi_boot_link`、`/dev/fpc1020`、`/dev/stune`、`/data/system/gps`、
  `/data/calibration/mac_addr` 等；
- `genfs_contexts`：bq2753x/usb power_supply、MFC `video6`、decon vsync、
  iio/als、背光/m86_led、FPC `clk_enable/irq`、debugfs `/mali` 等；
- 新类型走 m86 设备树 sepolicy，不继承 Galaxy 标签。

### P2 — 规则层（预计 30–50 行、按服务分 8–10 个 `.te` 文件）

按现有 `docs/device-tree-refactor-plan.md` 的十组服务切分：

| 服务组 | 主要新增规则 |
| --- | --- |
| boot/init/mount | cbd/mcDriverDaemon/usb_serial 域转换、socket/netlink、efs/custom mount |
| graphics | 只补 vsync sysfs + debugfs_gpu；mali 标签后基本被 AOSP 规则覆盖 |
| audio | `audioserver → i2c/audio device`、三个 persist 属性 |
| radio | `rild → radio_device/radio_data_file`、reset_count 属性 |
| sensors/GNSS | gps FIFO 类型、`vndbinder_use(hal_gnss)`、传感器 sysfs 窄规则 |
| power/light | boostpulse、hotplug profile、背光/LED 窄规则 |
| TEE/fingerprint | tee/fpc/ion/uhid 设备规则、fpdata DB、FPC sysfs、mcDaemon 域 |
| wifi/bt | mac_addr 标定文件、bcmdhd sysfs（已有 genfs 三条保留） |
| 其他 | module_request dontaudit、app 噪声 dontaudit、binder 对 |

### P3 — enforcing 收敛（预计 2–4 次构建-刷机迭代）

- 冷启动 ×5 无 crash loop，关键服务全部 `running`；
- 功能矩阵：显示/亮度、声音、RIL 双卡、Wi-Fi/BT、GPS、相机、传感器、
  指纹（实验产品）、NFC（NFC 产品另行验证）；
- AVC 日志只允许三类：白名单噪声、明确 `dontaudit`、已归因未实现项；
- 每轮只新增最小规则，不改通配 allow、不设 `SELINUX_IGNORE_NEVERALLOWS`。

---

## 4. 关键约束

- **不能给 `device:chr_file` 加通配 allow**：AOSP neverallow
  `neverallow domain device:chr_file { open read write }` 会直接卡死编译；
  这是标签层必须先行、而不是 audit2allow 直灌的原因。
- **`hal_fingerprint_default → fingerprintd_data_file` 是设备特有**（Flyme
  HAL 直读 `/data/system/users/0/fpdata/user.db`）；现策略没有对应规则，
  需要显式最小授权。NFC/指纹可按计划留在实验分支，不阻塞默认产品 enforcing。
- **早期 kernel/ueventd denial**（block 节点 create/setattr、sys_rawio、
  mknod、recovery 域读 media_rw）要在 enforcing 冷启动重新采集；它们只在
  开环早期出现，permissive 系统日志会因 ring buffer 覆盖而丢失。
- **TWRP recovery 是独立域**：主系统 enforcing 不要求 TWRP 域同时收敛；
  发布时再单独评审 recovery 策略。

---

## 5. 建议的下一步（不刷 data）

1. 先做一个 **enforcing boot.img 探针**：只改 `CONFIG_CMDLINE`，构建并
   仅刷 boot 分区；冷启动抓 `getenforce`、`dmesg avc`、服务状态。
2. 若出现 crash loop，用同一 boot.img 加串口/adb 捕获首轮 enforcing denial，
   按 P1/P2 分批修。
3. 默认产品先行（不含指纹 TEE 的 37 条），实验产品跟随。
