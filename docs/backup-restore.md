# Backup & Restore

> 中文版: [backup-restore.zh.md](backup-restore.zh.md)

## Partition layout (Z70 Ultra / SM8750 UFS)

| LUN | Contents | Key partitions |
|-----|----------|----------------|
| LUN0 | system/data | super (16GB), persist, frp, keystore |
| LUN1 | slot A boot chain | xbl_a, xbl_config_a, apdp |
| LUN2 | slot B boot chain | xbl_b, xbl_config_b, apdpb |
| LUN3 | config | cdt, ddr, ALIGN_TO_128K_1 |
| LUN4 | firmware/boot | modem_a/b (350MB×2), boot_a/b, abl_a/b, uefi_a/b — 83 partitions |
| LUN5 | device-specific (hidden) | modemst1/2 (IMEI), fsg, fsc, ztecfg |

> LUN5 is not GPT-addressable (firehose read times out), but ROM packages never
> write to it (`filename=""`), so the IMEI is naturally safe.

## Backup command

```bash
adb reboot edl && sleep 15
qdl-rs --backend usb -l devprg -s ufs backup -o ~/edl-backup/<timestamp>
```

Backs up 58 partitions + raw GPT for 5 LUNs, ~1.2GB total.

## Restore commands

### Restore a single partition

```bash
# Need to know the partition name and LUN
qdl-rs --backend usb -l devprg -s ufs -L 4 write boot_a ~/edl-backup/<ts>/L4__boot_a.img
```

### Restore the GPT (full table)

```bash
qdl-rs --backend usb -l devprg -s ufs -L 4 overwrite-storage ~/edl-backup/<ts>/gpt_raw_lun4.bin
```

### Restore baseband (cellular issues)

```bash
qdl-rs --backend usb -l devprg -s ufs -L 4 write modem_a ~/edl-backup/<ts>/L4__modem_a.img
```

## Unbrick procedure

1. Power off → hold Vol+ AND Vol- → plug USB to enter 9008 (EDL)
2. Restore the damaged partitions from backup
3. Reboot

> EDL runs in the BootROM (below system/GPT/bootloader), so it works regardless of
> the software state. The only unrecoverable scenarios are physical damage and
> blown fuses from "fusing" OTAs.
