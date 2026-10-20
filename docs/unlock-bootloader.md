# Bootloader Unlock — How It Works

> 中文版: [unlock-bootloader.zh.md](unlock-bootloader.zh.md)

## Why the normal way fails

The Z70 Ultra's stock bootloader is crippled:
- `fastboot flashing unlock` → `unknown command`
- `fastboot oem unlock` → `unknown command`
- No official unlock tool provided

## The AVB Exploit (ZTE Family Toolbox approach)

### Core idea

Use full EDL read/write to bypass the bootloader's signature enforcement:

```
1. Remove vbmeta_a + pvmfw_a from the GPT
   → disables AVB (Android Verified Boot) verification
2. Flash the patched UEFI to boot_a
   → the patched UEFI is a "standard Fastboot" that supports flashing unlock
3. Reboot → boot into the patched UEFI's Fastboot mode
4. fastboot flashing unlock → set persistent unlock flag
5. Restore original GPT + original boot_a
6. Reboot → unlocked
```

### Why it works

- **Missing vbmeta** → ABL cannot perform AVB verification → allows booting
  "unofficial" boot images
- **Patched UEFI** (`uefi_unlock_8e.img`, 2.7MB) is an Android bootimg whose kernel
  is actually a modified bootloader providing a standard fastboot interface
- **Unlock flag** is persisted in a bootloader-private region (not GPT-addressable),
  so it survives restoring the original boot

### Verification after unlock

```
ro.boot.flash.locked = 0            (1 = locked)
ro.boot.vbmeta.device_state = unlocked
ro.boot.verifiedbootstate = orange  (verification disabled)
```

## Key files

| File | Purpose | Source |
|------|---------|--------|
| `devprg` | SM8750 firehose | toolbox res/NX789J/ or Iqinix repo |
| `uefi_unlock_8e.img` | patched UEFI | toolbox avbexploit/anonymous1/ |
| `gpt_edit.py` | GPT partition editor | this repo scripts/ |

## Notes

1. **Wipes data** (standard behavior of `fastboot flashing unlock`)
2. **Fingerprint may break** (fixable with toolbox v1.2.1+)
3. **Freeze OTA after unlock** to block "fusing" updates
4. Hardware EDL entry: power off → hold Vol+ AND Vol- → plug USB
