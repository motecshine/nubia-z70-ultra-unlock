# nubia Z70 Ultra (NX733J) — Bootloader Unlock & Global ROM Toolkit

Complete toolkit for the **nubia Z70 Ultra (NX733J, Snapdragon 8 Elite / SM8750)**:
EDL flashing, bootloader unlock, CN → Global ROM conversion, full backup/restore.

> ⚠️ **WARNING**: This process wipes data, unlocks the bootloader and modifies system
> partitions. Back up everything first. The author is not responsible for any bricks
> or data loss.
>
> 📖 **中文文档**: [README_zh.md](README_zh.md)

---

## Table of Contents

- [Highlights](#highlights)
- [Core discovery: Oem="ZTE"](#core-discovery-oemzte)
- [Quick start](#quick-start)
- [How it works](#how-it-works)
- [Step-by-step](#step-by-step)
- [Recovery / unbrick](#recovery--unbrick)
- [FAQ](#faq)
- [Repository layout](#repository-layout)

---

## Highlights

| Item | Result |
|------|--------|
| Bootloader | ✅ Unlocked (`fastboot flashing unlock`) |
| System | ✅ Global `PQ84A01-UN` (Google services included) |
| OTA | ✅ Frozen (blocks "fusing" updates) |
| Root | Optional (unlocked bootloader, root anytime) |

---

## Core discovery: Oem="ZTE"

The SM8750 ZTE firehose (`xbl_s_devprg_ns.melf` / `devprg`) authenticates the **host tool**:

```
LOG: ERROR: Tool doesn't come from ZTE.
```

Without ZTE's official tool credentials, every storage read/write is NAKed.

**The bypass**: the firehose's `configure` command needs one extra attribute:

```xml
<configure MemoryName="ufs" ... SkipStorageInit="0" Oem="ZTE"/>
                                            └───────┘
```

With `Oem="ZTE"`, the firehose logs `zte download tool: 1` and grants full storage access.

This is the key step — without it, no community tool (qdl-rs/QFIL/edl) can flash SM8750 ZTE devices.

See [docs/firehose-secret.md](docs/firehose-secret.md) (Chinese) for the full investigation.

---

## Quick start

```bash
git clone https://github.com/motecshine/nubia-z70-ultra-unlock.git
cd nubia-z70-ultra-unlock

./z70.sh init        # Install deps + build qdl-rs (auto-detects your OS)
./z70.sh doctor      # Check environment
./z70.sh auto        # ⭐ Full unlock pipeline (backup → unlock → restore)
./z70.sh flash       # Flash global ROM
./z70.sh freeze-ota  # Freeze OTA updates
```

### `auto` pipeline

| Step | Action | Automated |
|------|--------|-----------|
| 1/6 | Full partition backup | ✅ |
| 2/6 | Flash unlock (modified GPT + patched UEFI) | ✅ |
| 3/6 | `fastboot flashing unlock` + on-screen confirm | ⚠️ manual |
| 4/6 | Hardware-enter EDL (volume keys + USB) | ⚠️ manual |
| 5/6 | Restore original GPT + boot | ✅ |
| 6/6 | Verify unlock state | ✅ |

The two manual steps are physical limitations (phone screen + hardware EDL entry);
the script pauses and waits for you.

---

## How it works

### Bootloader unlock (AVB exploit)

The Z70 Ultra's stock bootloader has **no** unlock command (`flashing unlock` / `oem unlock`
both return `unknown command`). The exploit:

```
1. Remove vbmeta_a + pvmfw_a from GPT  → disables AVB verification
2. Flash patched UEFI to boot_a       → boots into a "standard" Fastboot
3. Reboot → standard Fastboot mode
4. fastboot flashing unlock           → sets persistent unlock flag
5. Restore original GPT + boot
6. Reboot → unlocked
```

### Global ROM flash

1. Get the global ROM (`Z70Ultra_NebulaOS1.0.7MR3_NX733J_GB_15`, GB = Global)
2. Filter `rawprogram*.xml` (drop GPT entries + empty-filename device-specific partitions)
3. Flash with `qdl-rs flasher`

The ROM package already excludes dangerous partitions (`modemst1/2` = IMEI, `fsg/fsc`
= radio calibration, `devinfo` = unlock state, `persist` = sensor calibration) — their
`filename=""` means they're defined but never written.

---

## Step-by-step

### 0. Prerequisites

- macOS or Linux (verified on macOS)
- nubia Z70 Ultra (NX733J) with working ADB
- Global ROM (optional, 8.5GB): https://www.needrom.com/download/zte-nubia-z70-ultra/
  (version `Z70Ultra_NebulaOS1.0.7MR3_NX733J_GB_15`)

### 1. Initialize environment

```bash
./z70.sh init
```

This installs dependencies (Homebrew, sevenzip, aria2, android-platform-tools, rust,
libusb), clones + patches + builds qdl-rs, copies the bundled firehose and patched UEFI
from `tools/`, and starts aria2 RPC.

### 2. Full backup

```bash
./z70.sh auto   # does backup first, then unlock
# or backup only:
adb reboot edl && sleep 15
./z70.sh backup
```

Backs up 58 partitions across LUN0/1/2/3/4 (~1.2GB) including modem (baseband), boot
chain, calibration data and all GPT tables.

### 3. Unlock bootloader

`./z70.sh auto` walks you through the full unlock flow (backup → flash → unlock → restore).

### 4. Flash global ROM

```bash
# Download + extract the ROM first, then:
python3 scripts/filter_rawprogram.py ~/edl-rom/ROM/images
adb reboot edl && sleep 15
./z70.sh flash
```

~10-15 min (17GB super partition). First boot takes 5-10 minutes.

### 5. Freeze OTA (critical!)

```bash
./z70.sh freeze-ota
```

ZTE pushes "fusing" OTAs that permanently burn SoC fuses and re-lock the bootloader.
Freezing the updater keeps your unlock forever.

---

## Recovery / unbrick

Any software damage is recoverable via EDL + backups:

```bash
# Hardware EDL entry: power off → hold Vol+ AND Vol- → plug USB
# Restore a single partition:
qdl-rs --backend usb -l devprg -s ufs write <partition> <backup.img> -L <LUN>
# Restore GPT:
qdl-rs --backend usb -l devprg -s ufs -L 4 overwrite-storage gpt_raw_lun4.bin
```

EDL runs in the BootROM (below system/GPT/bootloader), so it works no matter what
software state the device is in. The only unrecoverable scenarios are physical damage
and blown fuses from "fusing" OTAs.

---

## FAQ

**Q: Fingerprint stopped working?**
A: Unlock can break fingerprint calibration. Toolbox v1.2.1+ has a fix (needs Windows).

**Q: Will OTA work?**
A: No, and don't use it. OTA is frozen; "fusing" updates would permanently re-lock.
Update the system manually via EDL instead.

**Q: Can I root?**
A: Bootloader is unlocked — patch boot.img with Magisk and flash it.

**Q: Cellular/IMEI issues?**
A: The backup contains the CN `modem_a.img`; flash it back to restore.

---

## Repository layout

```
nubia-z70-ultra-unlock/
├── README.md                  # This document (English)
├── README_zh.md               # Chinese version
├── LICENSE                    # Non-commercial license
├── z70.sh                     # One-shot script (init/auto/backup/flash/...)
├── docs/                      # Technical docs (Chinese)
│   ├── firehose-secret.md     # Oem="ZTE" discovery
│   ├── unlock-bootloader.md   # Unlock internals
│   └── backup-restore.md      # Backup & restore
├── scripts/
│   ├── gpt_edit.py            # GPT partition editor
│   ├── filter_rawprogram.py   # rawprogram filter
│   └── aria2.conf             # aria2 config (2 connections, avoids ban)
├── patches/
│   ├── qdlrs-oem-zte.patch    # Core patch (Oem="ZTE" + backup/unlock cmds)
│   └── fh_reset.rs            # Rescue tool source
└── tools/                     # Device files (cross-platform)
    ├── firehose/NX789J.elf    # SM8750 ZTE-signed firehose
    └── uefi/uefi_unlock_8e.img # Patched UEFI (required for unlock)
```

> Note: qdl-rs is built from source by `./z70.sh init` — binaries are platform-specific.

---

## Credits

- [qualcomm/qdlrs](https://github.com/qualcomm/qdlrs) — official Qualcomm EDL tool
- [Iqinix/Qualcomm-firehoses](https://github.com/Iqinix/Qualcomm-firehoses) — firehose collection
- ZTE Family Toolbox author "某贼" (CoolAPK) — the unlock exploit
- XDA community @danielxik @dev-reverse — English toolbox port

## License

**Non-commercial use only.** See [LICENSE](LICENSE). Commercial use requires written permission.
