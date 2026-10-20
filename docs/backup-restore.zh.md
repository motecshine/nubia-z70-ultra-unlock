# 备份与恢复

## 分区布局（Z70 Ultra / SM8750 UFS）

| LUN | 内容 | 关键分区 |
|-----|------|---------|
| LUN0 | 系统/数据 | super(16GB)、persist、frp、keystore |
| LUN1 | A槽引导链 | xbl_a、xbl_config_a、apdp |
| LUN2 | B槽引导链 | xbl_b、xbl_config_b、apdpb |
| LUN3 | 配置 | cdt、ddr、ALIGN_TO_128K_1 |
| LUN4 | 固件/引导 | modem_a/b(350MB×2)、boot_a/b、abl_a/b、uefi_a/b 等 83 分区 |
| LUN5 | 设备专属(隐藏) | modemst1/2(IMEI)、fsg、fsc、ztecfg |

> LUN5 不通过 GPT 寻址（firehose 读超时），但 ROM 包也不会刷写它们（`filename=""`），
> 所以 IMEI 天然安全。

## 备份命令

```bash
adb reboot edl && sleep 15
qdl-rs --backend usb -l devprg -s ufs backup -o ~/edl-backup/<时间>
```

备份 58 个分区 + 5 个 LUN 的原始 GPT，约 1.2GB。

## 恢复命令

### 恢复单个分区

```bash
# 需要知道分区名和 LUN
qdl-rs --backend usb -l devprg -s ufs -L 4 write boot_a ~/edl-backup/<时间>/L4__boot_a.img
```

### 恢复 GPT（整表）

```bash
qdl-rs --backend usb -l devprg -s ufs -L 4 overwrite-storage ~/edl-backup/<时间>/gpt_raw_lun4.bin
```

### 恢复基带（信号问题时）

```bash
qdl-rs --backend usb -l devprg -s ufs -L 4 write modem_a ~/edl-backup/<时间>/L4__modem_a.img
```

## 救砖流程

1. 关机 → 按住「音量上+音量下」→ 插 USB 进 9008
2. 用备份恢复损坏的分区
3. 重启

> 9008 跑在 BootROM 层，不依赖系统/GPT/bootloader，所以任何软件损坏都能救。
> 唯一救不了的是物理损坏和"熔断"更新烧的 fuse。
