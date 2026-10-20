# 核心发现：Oem="ZTE" 绕过 SecTools 工具认证

## 背景

ZTE/努比亚的骁龙 8 Elite (SM8750) 设备，其 firehose programmer（`xbl_s_devprg_ns.melf`，
在工具箱中叫 `devprg`）带有一个**主机工具身份校验**机制。

## 现象

用社区工具（qdl-rs / QFIL / bkerler edl）加载 firehose 后，`nop` 等基础命令正常，
但所有存储读写（read/program/erase）被 NAK：

```
LOG: INFO:  Calling handler for configure
LOG: INFO:  Storage type set to value UFS
LOG: ERROR: Tool doesn't come from ZTE.
LOG: ERROR: Failed to run the last command -1
RECV: response value="NAK"
```

## 原理

firehose 内置了 X.509 证书 `SecTools1`（Qualcomm 签发，San Diego/California），
用于验证主机工具是否 ZTE 官方工具。验证失败的标志就是日志里的
`Tool doesn't come from ZTE`。

## 突破

对比 ZTE Family Toolbox 的 configure 命令发现，它比社区工具多传了一个属性：

```xml
<!-- 社区工具 (失败) -->
<configure MemoryName="ufs" ... SkipStorageInit="0" />

<!-- ZTE 工具箱 (成功) -->
<configure MemoryName="ufs" ... SkipStorageInit="0" Oem="ZTE" />
```

加上 `Oem="ZTE"` 后：

```
LOG: INFO: zte download tool: 1     ← 识别为 ZTE 工具
Found protocol version 1            ← configure 被接受
LOG: INFO: Calling handler for read ← 存储命令放行
```

## 补丁位置

qdl-rs 的 `qdl/src/lib.rs` → `firehose_configure()` 函数，在 configure XML 里加：

```rust
("Oem", "ZTE"),
```

完整补丁见 `patches/qdlrs-oem-zte.patch`。

## 影响

- 这是整个 SM8750 ZTE 设备刷机的**关键一步**
- 没有它，任何社区工具都无法读写存储
- 补丁后，EDL 读写完全开放（备份、刷机、救砖都依赖这个）
