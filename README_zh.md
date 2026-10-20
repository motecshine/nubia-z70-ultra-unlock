# nubia Z70 Ultra (NX733J) 解锁 + 刷国际版 完整工具包

针对 **努比亚 Z70 Ultra (NX733J, 骁龙8 Elite/SM8750)** 的完整解锁与刷机流程。
包含：EDL 刷机、Bootloader 解锁、国行→国际版转换、完整备份/恢复。

> ⚠️ **警告**：本流程会清空数据、解锁 bootloader、修改系统分区。操作前务必完整备份。作者对任何砖机/数据丢失不负责。

---

## 目录

- [成果速览](#成果速览)
- [核心发现：Oem="ZTE"](#核心发现oemzte)
- [准备工作](#准备工作)
- [Step 1: 编译工具](#step-1-编译工具)
- [Step 2: 完整备份](#step-2-完整备份)
- [Step 3: 解锁 Bootloader](#step-3-解锁-bootloader)
- [Step 4: 刷国际版 ROM](#step-4-刷国际版-rom)
- [Step 5: 冻结 OTA](#step-5-冻结-ota)
- [恢复/救砖](#恢复救砖)
- [FAQ](#faq)

---

## 成果速览

| 项目 | 结果 |
|------|------|
| Bootloader | ✅ 解锁（`fastboot flashing unlock`） |
| 系统 | ✅ 国际版 `PQ84A01-UN`（含 Google 服务） |
| OTA | ✅ 冻结（防熔断更新） |
| Root | 可选（未 root，bootloader 已解锁可随时 root） |

---

## 核心发现：Oem="ZTE"

ZTE 的 SM8750 firehose（`xbl_s_devprg_ns.melf` / `devprg`）会对**主机工具做身份校验**：

```
LOG: ERROR: Tool doesn't come from ZTE.
```

没有 ZTE 官方工具的签名凭证，所有存储读写都会被 NAK 拒绝。

**突破点**：firehose 的 configure 命令需要一个特殊属性：

```xml
<configure MemoryName="ufs" ... SkipStorageInit="0" Oem="ZTE"/>
                                            └───────┘
```

加上 `Oem="ZTE"` 后，firehose 日志变为 `zte download tool: 1`，存储读写全部放行。

这是整个流程的关键 —— 没有这一步，qdl-rs/QFIL 等社区工具都无法刷写 SM8750 的 ZTE 设备。

---

## 准备工作

### 硬件/软件需求

- **Mac 或 Linux**（本流程在 macOS 上验证）
- 手机：nubia Z70 Ultra (NX733J)，能进系统（ADB 可用）
- 已下载的**国际版 ROM**（Needrom 上的 `ZTE-Nubia-Z70-Ultra.7z`，8.53GB）
- 补丁 UEFI 文件 `uefi_unlock_8e.img`（来自 ZTE Family Toolbox）

### 一键初始化环境（推荐）

```bash
cd ~/z70-ultra-unlock
./z70.sh init       # 装依赖 + 编译 qdl-rs + 下载 firehose + 配置 aria2
./z70.sh doctor     # 检查环境是否就绪
```

`init` 会自动完成：
- 安装 Homebrew + sevenzip + aria2 + android-platform-tools + rust + libusb
- 设置 Python venv (pyusb)
- 克隆 qualcomm/qdlrs 并打 `Oem="ZTE"` 补丁
- 编译 qdl-rs + fh_reset
- 从仓库 tools/ 复制 firehose + 补丁 UEFI
- 配置并启动 aria2 RPC

### 一键脚本全部命令

```bash
cd ~/z70-ultra-unlock
./z70.sh init        # 初始化环境
./z70.sh doctor      # 检查环境
./z70.sh auto        # ⭐ 全自动解锁流水线 (备份→解锁→恢复)
./z70.sh backup      # 单独完整备份
./z70.sh flash       # 刷国际版 ROM
./z70.sh verify      # 验证解锁/版本
./z70.sh freeze-ota  # 冻结 OTA
```

#### `auto` 流水线说明

`./z70.sh auto` 按序执行：

| 步骤 | 内容 | 是否自动 |
|------|------|---------|
| 1/6 | 完整备份分区 | ✅ 自动 |
| 2/6 | 刷解锁 (改GPT+补丁UEFI) | ✅ 自动 |
| 3/6 | `fastboot flashing unlock` + 屏幕确认 | ⚠️ 人工 |
| 4/6 | 按键进 9008 | ⚠️ 人工 |
| 5/6 | 恢复原 GPT + boot | ✅ 自动 |
| 6/6 | 验证解锁状态 | ✅ 自动 |

两个人工步骤是物理限制（手机屏幕按键 + 硬件进 EDL），脚本会暂停等你回车。

### 手动安装依赖（可选，不用 init 时）

```bash
brew install sevenzip aria2 android-platform-tools rust
```

### 克隆 qdl-rs 并打补丁

```bash
git clone --depth 1 https://github.com/qualcomm/qdlrs.git /tmp/qdlrs
cd /tmp/qdlrs
# 应用 Oem="ZTE" 补丁（见 patches/ 目录）
git apply ~/z70-ultra-unlock/patches/qdlrs-oem-zte.patch
cargo build --release --bin qdl-rs
```

---

## Step 1: 编译工具

编译好的 `qdl-rs` 就是刷机主工具，配合 firehose（`devprg`）使用。

```bash
cd /tmp/qdlrs
cargo build --release --bin qdl-rs
cp target/release/qdl-rs ~/edl-tools/qdl-rs
```

firehose 文件来源：工具箱 `bin/res/NX789J/devprg`（与 Z70 Ultra 通用），
或 GitHub `Iqinix/Qualcomm-firehoses` 仓库的 `ZTE/NX789J.elf`。

---

## Step 2: 完整备份

**刷机前必须备份！** 备份通过 EDL 只读完成，零风险。

```bash
# 进 9008 模式
adb reboot edl
sleep 15

# 备份所有关键分区（LUN0/1/2/3/4）
mkdir -p ~/edl-backup
~/edl-tools/qdl-rs --backend usb -l ~/edl-tools/devprg_z70u -s ufs \
  backup -o ~/edl-backup/$(date +%Y%m%d)
```

备份内容（58 个分区，~1.2GB）：
- **LUN0**：persist/frp/keystore/misc/parameter/ssd（校准+FRP）
- **LUN1**：xbl_a/xbl_config_a/apdp（A槽引导链）
- **LUN2**：xbl_b/xbl_config_b/apdpb（B槽引导链）
- **LUN3**：cdt/ddr（配置）
- **LUN4**：全部83分区（含 modem_a/b 基带、boot、abl、uefi 等）

---

## Step 3: 解锁 Bootloader

### 原理

工具箱的 AVB exploit 方案：
1. 删除 GPT 中的 `vbmeta_a` 和 `pvmfw_a` 分区（关闭 AVB 校验）
2. 把补丁 UEFI（`uefi_unlock_8e.img`）刷到 `boot_a`
3. 重启后设备进入**标准 Fastboot 模式**（支持 `flashing unlock`）
4. 执行解锁，再恢复原 GPT + boot

### 执行

```bash
# 1. 生成修改版 GPT（删除 vbmeta_a + pvmfw_a）
python3 scripts/gpt_edit.py \
  ~/edl-backup/<时间>/gpt_raw_lun4.bin \
  /tmp/gpt_modified.bin vbmeta_a pvmfw_a

# 2. 截取 GPT 部分（前 6 扇区）
python3 -c "open('/tmp/gpt_mod_6s.bin','wb').write(open('/tmp/gpt_modified.bin','rb').read()[:6*4096])"
python3 -c "open('/tmp/gpt_orig_6s.bin','wb').write(open('~/edl-backup/<时间>/gpt_raw_lun4.bin','rb').read()[:6*4096])"

# 3. 进 EDL 刷入（改 GPT + 补丁 UEFI 到 boot_a）
adb reboot edl
sleep 15
~/edl-tools/qdl-rs --backend usb -l ~/edl-tools/devprg_z70u -s ufs --reset-mode system \
  unlock-flash --gpt-file /tmp/gpt_mod_6s.bin --uefi-file ~/edl-tools/uefi_unlock_8e.img

# 4. 设备重启后进入标准 Fastboot（序列号会变成 af6c26cd）
fastboot devices

# 5. 执行解锁（手机会弹确认屏，音量键选 UNLOCK，电源键确认）
fastboot flashing unlock

# 6. 解锁后重新进 EDL 恢复（需要硬件按键：关机→按住两个音量键→插USB）
#    然后恢复原 GPT + boot_a
~/edl-tools/qdl-rs --backend usb -l ~/edl-tools/devprg_z70u -s ufs --reset-mode system \
  unlock-restore --gpt-file /tmp/gpt_orig_6s.bin --boot-file ~/edl-backup/<时间>/L4__boot_a.img

# 7. 验证解锁
adb shell getprop ro.boot.flash.locked   # 输出 0 = 已解锁
```

---

## Step 4: 刷国际版 ROM

### 4.1 下载 ROM

- **预览/下载页**：https://www.needrom.com/download/zte-nubia-z70-ultra/
- 来源：Needrom（需注册登录）
- 版本：`Z70Ultra_NebulaOS1.0.7MR3_NX733J_GB_15`（GB=国际版）
- 大小：8.53GB（.7z）
- 下载建议：开 Cloudflare WARP 绕过 TLS 限制，aria2 最多 2 连接（Needrom 限制，超了会 ban）

### 4.2 解压

```bash
mkdir -p ~/edl-rom && cd ~/edl-rom
7zz x ~/Downloads/ZTE-Nubia-Z70-Ultra.7z
```

### 4.3 过滤 rawprogram（剔除危险分区）

ROM 包的 rawprogram 里 `filename=""` 的分区（modemst1/2=IMEI、fsg/fsc=基带校准、
devinfo=解锁状态、persist=传感器校准）**不会被刷写**，这是安全的。

但 GPT 条目（PrimaryGPT/BackupGPT）含 QFIL 占位符，qdl-rs 不识别，需剔除：

```bash
python3 scripts/filter_rawprogram.py ~/edl-rom/ROM/images
```

### 4.4 刷入

```bash
adb reboot edl
sleep 15
cd ~/edl-rom/ROM/images
~/edl-tools/qdl-rs --backend usb -l ~/edl-tools/devprg_z70u -s ufs --reset-mode system \
  flasher -p rawprogram0.xml rawprogram1.xml rawprogram2.xml rawprogram4.xml
```

> 约 10-15 分钟（super 分区 17GB）。刷完设备自动重启，首次开机 5-10 分钟。

### 4.5 验证

```bash
adb shell getprop ro.product.name    # 应为 PQ84A01-UN（国际版）
adb shell getprop ro.boot.flash.locked  # 0 = 仍解锁
```

---

## Step 5: 冻结 OTA

**必须做！** ZTE 的"熔断"OTA 会烧 SoC fuse 永久锁死 bootloader。

```bash
for pkg in com.zte.zdm com.zte.zdmdaemon com.zte.zdmdaemon.install com.zte.zdm.omacp com.google.android.configupdater; do
  adb shell pm disable-user --user 0 $pkg
done
```

---

## 恢复/救砖

任何软件层面的损坏都能通过 EDL + 备份恢复：

```bash
# 硬件进 9008：关机 → 按住「音量上+音量下」→ 插 USB
# 恢复单个分区
~/edl-tools/qdl-rs --backend usb -l ~/edl-tools/devprg_z70u -s ufs \
  write <分区名> <备份镜像> -L <LUN号>

# 恢复 GPT（LUN4）
~/edl-tools/qdl-rs --backend usb -l ~/edl-tools/devprg_z70u -s ufs -L 4 \
  overwrite-storage ~/edl-backup/<时间>/gpt_raw_lun4.bin
```

---

## FAQ

**Q: 指纹失效了？**
A: 解锁可能破坏指纹校准。工具箱 v1.2.1+ 有修复功能（需要 Windows）。

**Q: 能正常 OTA 吗？**
A: 不能也不要用。OTA 被冻结了，且"熔断"更新会永久锁死。系统更新走手动 EDL 刷。

**Q: 想 root？**
A: bootloader 已解锁，用 Magisk patch boot.img 再刷入即可。

**Q: 基带/信号出问题？**
A: 备份里有国行 modem_a.img，刷回即可。

---

## 目录结构

```
z70-ultra-unlock/
├── README.md                  # 本文档
├── LICENSE                    # 非商业使用许可
├── z70.sh                     # 一键脚本 (init/backup/unlock/flash/...)
├── docs/
│   ├── firehose-secret.md     # Oem="ZTE" 发现过程
│   ├── unlock-bootloader.md   # 解锁原理详解
│   └── backup-restore.md      # 备份恢复详解
├── scripts/
│   ├── gpt_edit.py            # GPT 分区编辑（删分区）
│   ├── filter_rawprogram.py   # rawprogram 过滤
│   └── aria2.conf             # aria2 配置（2连接，防ban）
├── patches/
│   ├── qdlrs-oem-zte.patch    # qdl-rs 补丁（Oem=ZTE + backup/unlock命令）
│   └── fh_reset.rs            # 卡 firehose 时救回的工具源码
└── tools/                     # 随仓库提供的设备文件 (跨平台)
    ├── firehose/
    │   └── NX789J.elf         # SM8750 ZTE 签名 firehose
    └── uefi/
        └── uefi_unlock_8e.img # 补丁 UEFI (解锁必需)

> 注: 刷机工具 qdl-rs 需自行编译 (`./z70.sh init` 自动完成)，
> 因为编译产物是平台相关的 (macOS/Linux/Windows 各不相同)。
```

---

## 致谢

- [qualcomm/qdlrs](https://github.com/qualcomm/qdlrs) - 高通官方 EDL 工具
- [Iqinix/Qualcomm-firehoses](https://github.com/Iqinix/Qualcomm-firehoses) - firehose 收集
- ZTE Family Toolbox 作者「某贼」(酷安) - 解锁 exploit
- XDA 社区 @danielxik @dev-reverse - 工具箱英文版
