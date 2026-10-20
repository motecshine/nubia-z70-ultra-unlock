# Core Discovery: Oem="ZTE" Bypasses SecTools Tool Auth

> 中文版: [firehose-secret.zh.md](firehose-secret.zh.md)

## Background

The firehose programmer (`xbl_s_devprg_ns.melf`, named `devprg` in the toolbox) for
ZTE/nubia Snapdragon 8 Elite (SM8750) devices includes a **host-tool authentication**
mechanism.

## Symptom

After loading the firehose with community tools (qdl-rs / QFIL / bkerler edl), basic
commands like `nop` work, but every storage read/write (read/program/erase) is NAKed:

```
LOG: INFO:  Calling handler for configure
LOG: INFO:  Storage type set to value UFS
LOG: ERROR: Tool doesn't come from ZTE.
LOG: ERROR: Failed to run the last command -1
RECV: response value="NAK"
```

## Mechanism

The firehose embeds an X.509 certificate `SecTools1` (Qualcomm-issued, San
Diego/California) used to verify the host tool is ZTE's official tool. Failed
verification produces the `Tool doesn't come from ZTE` log line.

## The Bypass

Comparing against ZTE Family Toolbox's configure command revealed one extra attribute:

```xml
<!-- Community tools (fail) -->
<configure MemoryName="ufs" ... SkipStorageInit="0" />

<!-- ZTE Family Toolbox (works) -->
<configure MemoryName="ufs" ... SkipStorageInit="0" Oem="ZTE" />
```

With `Oem="ZTE"` added:

```
LOG: INFO: zte download tool: 1     ← recognized as ZTE tool
Found protocol version 1            ← configure accepted
LOG: INFO: Calling handler for read ← storage commands allowed
```

## Patch location

qdl-rs `qdl/src/lib.rs` → `firehose_configure()`, add to the configure XML:

```rust
("Oem", "ZTE"),
```

Full patch: `patches/qdlrs-oem-zte.patch`.

## Impact

- This is the **critical step** for flashing any SM8750 ZTE device.
- Without it, no community tool can read/write storage.
- With it, full EDL access is unlocked (backup, flash, unbrick all depend on this).
