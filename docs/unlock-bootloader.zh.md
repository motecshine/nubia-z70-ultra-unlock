# Bootloader 解锁原理详解

## 为什么普通方法不行

Z70 Ultra 的 bootloader 是阉割版：
- `fastboot flashing unlock` → `unknown command`
- `fastboot oem unlock` → `unknown command`
- 官方不提供解锁工具

## AVB Exploit 方案（ZTE Family Toolbox 的原理）

### 核心思路

利用 EDL 的完整读写能力，绕过 bootloader 的签名校验：

```
1. 删除 GPT 里的 vbmeta_a + pvmfw_a 分区定义
   → 关闭 AVB (Android Verified Boot) 校验
2. 把补丁 UEFI 刷到 boot_a
   → 补丁 UEFI 是一个"标准 Fastboot"，支持 flashing unlock
3. 重启 → 进入补丁 UEFI 的 Fastboot 模式
4. fastboot flashing unlock → 解锁（写持久化标志）
5. 恢复原 GPT + 原 boot_a
6. 重启 → 解锁完成
```

### 为什么可行

- **vbmeta 缺失** → ABL 无法做 AVB 校验 → 允许启动"非官方"的 boot
- **补丁 UEFI**（`uefi_unlock_8e.img`，2.7MB）是一个 Android bootimg，
  内核实为修改过的 bootloader，进入后提供标准 fastboot 接口
- **解锁标志持久化**在 bootloader 私有区域（非 GPT 寻址），恢复 boot 后依然有效

### 验证结果

解锁后：
```
ro.boot.flash.locked = 0        (1=锁定)
ro.boot.vbmeta.device_state = unlocked
ro.boot.verifiedbootstate = orange   (校验关闭)
```

## 关键文件

| 文件 | 说明 | 来源 |
|------|------|------|
| `devprg` | SM8750 firehose | 工具箱 res/NX789J/ 或 Iqinix 仓库 |
| `uefi_unlock_8e.img` | 补丁 UEFI | 工具箱 avbexploit/anonymous1/ |
| `gpt_edit.py` | GPT 分区编辑 | 本项目 scripts/ |

## 注意事项

1. **会清空数据**（fastboot flashing unlock 的标准行为）
2. **指纹可能失效**（工具箱 v1.2.1+ 可修复）
3. 解锁后**冻结 OTA**，防止"熔断"更新永久锁死
4. 进 9008 的硬件方法：关机 → 按住「音量上+音量下」→ 插 USB
