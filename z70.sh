#!/usr/bin/env bash
# nubia Z70 Ultra toolkit - environment setup + common operations
# Usage: ./z70.sh <command>
#   init       Set up environment (deps + build qdl-rs + copy firehose/UEFI)
#   edl        Enter 9008 (EDL) mode
#   backup     Full partition backup (requires EDL first)
#   unlock     Flash unlock (modified GPT + patched UEFI)
#   restore    Restore after unlock (GPT + boot)
#   auto       Full unlock pipeline: backup → unlock → restore (with manual pauses)
#   flash      Flash global ROM (requires extracted + filtered ROM)
#   verify     Verify unlock/version state
#   freeze-ota Freeze OTA updates
#   doctor     Check environment status

set -e

# ============ Paths ============
EDL_TOOLS="$HOME/edl-tools"
QDL="$EDL_TOOLS/qdl-rs"
FIREHOSE="$EDL_TOOLS/devprg_z70u"
UEFI_UNLOCK="$EDL_TOOLS/uefi_unlock_8e.img"
BACKUP_DIR="$HOME/edl-backup"
VENV="$HOME/.venvs/edl"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ============ Colors ============
G='\033[32m'; Y='\033[33m'; R='\033[31m'; B='\033[34m'; N='\033[0m'
ok()   { echo -e "${G}✅ $*${N}"; }
info() { echo -e "${B}ℹ️  $*${N}"; }
warn() { echo -e "${Y}⚠️  $*${N}"; }
err()  { echo -e "${R}❌ $*${N}"; }
step() { echo -e "\n${B}==== $* ====${N}"; }

cmd="${1:-help}"
shift || true

# ============ init: environment setup ============
do_init() {
  step "Check system"
  [[ "$(uname)" == "Darwin" ]] || { err "macOS only (current: $(uname))"; exit 1; }
  ok "macOS detected"

  step "Check Homebrew"
  if ! command -v brew >/dev/null; then
    warn "Homebrew not found, installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  ok "Homebrew: $(brew --version | head -1)"

  step "Install dependencies (sevenzip/aria2/android-platform-tools/rust/git/libusb)"
  for pkg in sevenzip aria2 android-platform-tools rust git libusb; do
    if command -v "$pkg" >/dev/null 2>&1 || brew list "$pkg" >/dev/null 2>&1; then
      ok "$pkg installed"
    else
      info "Installing $pkg ..."
      brew install "$pkg" || warn "$pkg install failed, skipping"
    fi
  done

  step "Set up Python venv + pyusb (for EDL detection)"
  if [[ ! -d "$VENV" ]]; then
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet --upgrade pip
    "$VENV/bin/pip" install --quiet pyusb
  fi
  ok "Python venv: $VENV"

  step "Clone and build qdl-rs"
  QDLRS_DIR="${QDLRS_DIR:-/tmp/qdlrs}"
  if [[ ! -d "$QDLRS_DIR/.git" ]]; then
    info "Cloning qualcomm/qdlrs ..."
    rm -rf "$QDLRS_DIR"
    git clone --depth 1 https://github.com/qualcomm/qdlrs.git "$QDLRS_DIR"
  fi
  cd "$QDLRS_DIR"
  info "Applying Oem=ZTE patch ..."
  git apply --check "$PROJECT_DIR/patches/qdlrs-oem-zte.patch" 2>/dev/null && \
    git apply "$PROJECT_DIR/patches/qdlrs-oem-zte.patch" && ok "Patch applied" || \
    warn "Patch already applied or conflict, skipping"
  info "Building (cargo build) ..."
  cargo build --release --bin qdl-rs --bin fh_reset 2>/dev/null || cargo build --release --bin qdl-rs
  mkdir -p "$EDL_TOOLS"
  cp target/release/qdl-rs "$QDL" 2>/dev/null || true
  cp target/release/fh_reset "$EDL_TOOLS/fh_reset" 2>/dev/null || true
  if [[ ! -f "$QDLRS_DIR/cli/src/bin/fh_reset.rs" ]]; then
    mkdir -p "$QDLRS_DIR/cli/src/bin"
    cp "$PROJECT_DIR/patches/fh_reset.rs" "$QDLRS_DIR/cli/src/bin/fh_reset.rs"
    cargo build --release --bin fh_reset
    cp target/release/fh_reset "$EDL_TOOLS/fh_reset"
  fi
  ok "qdl-rs built: $QDL"

  step "Prepare firehose (NX789J.elf, SM8750 ZTE-signed)"
  if [[ -f "$PROJECT_DIR/tools/firehose/NX789J.elf" ]]; then
    cp "$PROJECT_DIR/tools/firehose/NX789J.elf" "$FIREHOSE"
    ok "Using bundled firehose"
  elif [[ ! -f "$FIREHOSE" ]]; then
    info "Downloading from Iqinix/Qualcomm-firehoses..."
    curl -sL --max-time 120 -o "$FIREHOSE" \
      "https://raw.githubusercontent.com/Iqinix/Qualcomm-firehoses/main/ZTE/NX789J.elf"
    [[ -s "$FIREHOSE" ]] && ok "firehose downloaded ($(stat -f%z "$FIREHOSE") bytes)" || \
      { err "firehose download failed"; rm -f "$FIREHOSE"; }
  else
    ok "firehose already present"
  fi

  step "Prepare patched UEFI (uefi_unlock_8e.img)"
  if [[ -f "$PROJECT_DIR/tools/uefi/uefi_unlock_8e.img" ]]; then
    cp "$PROJECT_DIR/tools/uefi/uefi_unlock_8e.img" "$UEFI_UNLOCK"
    ok "Using bundled patched UEFI"
  else
    warn "No bundled uefi_unlock_8e.img, place it manually at $UEFI_UNLOCK"
  fi

  step "Set up aria2 (2 connections, avoids Needrom ban)"
  mkdir -p "$HOME/.aria2"
  cp "$PROJECT_DIR/scripts/aria2.conf" "$HOME/.aria2/aria2.conf"
  sed -i '' "s|^dir=.*|dir=$HOME/Downloads|" "$HOME/.aria2/aria2.conf"
  pkill -f aria2c 2>/dev/null || true
  nohup aria2c --conf-path="$HOME/.aria2/aria2.conf" > "$HOME/.aria2/aria2.log" 2>&1 &
  sleep 2
  ok "aria2 RPC started (localhost:6800)"

  step "Create directories"
  mkdir -p "$EDL_TOOLS" "$BACKUP_DIR"
  ok "edl-tools: $EDL_TOOLS"
  ok "edl-backup: $BACKUP_DIR"

  step "Initialization complete! Only the ROM needs manual download:"
  echo ""
  echo "  ROM (needed only for global ROM flashing):"
  echo "    Page: https://www.needrom.com/download/zte-nubia-z70-ultra/"
  echo "    Version: Z70Ultra_NebulaOS1.0.7MR3_NX733J_GB_15 (8.5GB, GB=Global)"
  echo "    Extract to: ~/edl-rom/ROM/images/"
  echo ""
  echo "  Everything else (tools/firehose/UEFI) ships with this repo."
  echo ""
  echo "  Check environment: ./z70.sh doctor"
}

# ============ doctor: environment check ============
do_doctor() {
  echo "=== Environment ==="
  check() { command -v "$1" >/dev/null 2>&1 && ok "$1" || err "$1 not installed"; }
  check brew; check adb; check fastboot; check 7zz; check aria2c; check cargo; check git

  echo "=== Key files ==="
  [[ -f "$QDL" ]] && ok "qdl-rs" || err "qdl-rs not built (run init)"
  [[ -f "$FIREHOSE" ]] && ok "firehose" || err "firehose missing (run init)"
  [[ -f "$UEFI_UNLOCK" ]] && ok "uefi_unlock_8e.img" || warn "uefi_unlock_8e.img missing (needed for unlock)"

  echo "=== Device ==="
  adb devices 2>/dev/null | tail -n +2 | grep -q "device" && ok "ADB device connected" || warn "No ADB device"
}

# ============ Other commands ============
do_edl() {
  info "Entering 9008 (EDL) ..."
  adb reboot edl
  sleep 15
  "$VENV/bin/python" -c "
import usb.core, usb.backend.libusb1
be = usb.backend.libusb1.get_backend(find_library=lambda x: '/opt/homebrew/lib/libusb-1.0.dylib')
d = usb.core.find(idVendor=0x05c6, idProduct=0x9008, backend=be)
print('✅ EDL OK' if d else '❌ Not in EDL')
"
}

do_backup() {
  d="$BACKUP_DIR/$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$d"
  info "Backing up to $d"
  "$QDL" --backend usb -l "$FIREHOSE" -s ufs backup -o "$d"
  ok "Backup complete: $d"
}

do_unlock() {
  bak="${1:-$(ls -td $BACKUP_DIR/*/ 2>/dev/null | head -1)}"
  [[ -z "$bak" ]] && { err "No backup found, run backup first"; exit 1; }
  [[ -f "$UEFI_UNLOCK" ]] || { err "Missing $UEFI_UNLOCK"; exit 1; }
  info "Using backup: $bak"
  python3 -c "open('/tmp/gpt_orig_6s.bin','wb').write(open('$bak/gpt_raw_lun4.bin','rb').read()[:6*4096])"
  python3 "$PROJECT_DIR/scripts/gpt_edit.py" "$bak/gpt_raw_lun4.bin" /tmp/gpt_modified.bin vbmeta_a pvmfw_a
  python3 -c "open('/tmp/gpt_mod_6s.bin','wb').write(open('/tmp/gpt_modified.bin','rb').read()[:6*4096])"
  info "Flashing unlock (modified GPT + patched UEFI)..."
  "$QDL" --backend usb -l "$FIREHOSE" -s ufs --reset-mode system \
    unlock-flash --gpt-file /tmp/gpt_mod_6s.bin --uefi-file "$UEFI_UNLOCK"
  info "Device will reboot into standard Fastboot. Then run: fastboot flashing unlock"
  info "After unlock, hardware-enter EDL and run: ./z70.sh restore $bak"
}

do_restore() {
  bak="${1:-$(ls -td $BACKUP_DIR/*/ 2>/dev/null | head -1)}"
  python3 -c "open('/tmp/gpt_orig_6s.bin','wb').write(open('$bak/gpt_raw_lun4.bin','rb').read()[:6*4096])"
  info "Restoring GPT + boot_a ..."
  "$QDL" --backend usb -l "$FIREHOSE" -s ufs --reset-mode system \
    unlock-restore --gpt-file /tmp/gpt_orig_6s.bin --boot-file "$bak/L4__boot_a.img"
}

do_flash() {
  cd ~/edl-rom/ROM/images
  info "Flashing global ROM ..."
  "$QDL" --backend usb -l "$FIREHOSE" -s ufs --reset-mode system \
    flasher -p rawprogram0.xml rawprogram1.xml rawprogram2.xml rawprogram4.xml
}

do_verify() {
  echo "=== Unlock state ==="
  adb shell getprop ro.boot.flash.locked
  adb shell getprop ro.boot.vbmeta.device_state
  echo "=== System version ==="
  adb shell getprop ro.product.name
  adb shell getprop ro.build.version.release
  echo "=== Google services ==="
  adb shell pm list packages 2>/dev/null | grep -c google
}

do_freeze_ota() {
  for pkg in com.zte.zdm com.zte.zdmdaemon com.zte.zdmdaemon.install com.zte.zdm.omacp com.google.android.configupdater; do
    info "Freezing $pkg"
    adb shell pm disable-user --user 0 "$pkg" || warn "$pkg failed"
  done
  ok "OTA freeze complete"
}

# ============ auto: full unlock pipeline ============
do_auto() {
  step "Auto unlock pipeline started"
  echo "Flow: backup → flash unlock → [manual: fastboot confirm] → [manual: enter EDL] → restore → verify"
  echo ""

  # --- 1. Backup ---
  step "1/6 Full backup"
  do_edl
  do_backup
  BAK="$(ls -td $BACKUP_DIR/*/ | head -1)"
  ok "Backup complete: $BAK"

  # --- 2. Flash unlock ---
  step "2/6 Flash unlock (modified GPT + patched UEFI)"
  do_unlock "$BAK"

  # --- 3. Manual: fastboot confirm ---
  step "3/6 MANUAL: fastboot unlock confirmation"
  echo ""
  echo "  Device is rebooting into standard Fastboot (serial becomes af6c26cd)..."
  echo "  Waiting 20s..."
  sleep 20
  fastboot devices 2>/dev/null || true
  echo ""
  echo "  ⚠️  Run on your computer: fastboot flashing unlock"
  echo "  Then [look at the phone screen], select UNLOCK THE BOOTLOADER"
  echo "  with volume keys and press power to confirm."
  echo ""
  read -r -p "  Press Enter after completing the unlock confirmation..." _

  # --- 4. Manual: hardware EDL entry ---
  step "4/6 MANUAL: hardware-enter 9008 (EDL)"
  echo ""
  echo "  ⚠️  Manually enter EDL:"
  echo "    1. Unplug the USB cable"
  echo "    2. Hold power for 15s to force shutdown"
  echo "    3. Hold Vol+ AND Vol-"
  echo "    4. While holding, plug the USB cable back in"
  echo ""
  read -r -p "  Press Enter after plugging the cable..." _
  sleep 5

  # --- 5. Restore ---
  step "5/6 Restore original GPT + boot"
  do_restore "$BAK"

  # --- 6. Verify ---
  step "6/6 Verify unlock state"
  sleep 30
  do_verify
  echo ""
  ok "Unlock pipeline complete! To flash the global ROM, run: ./z70.sh flash"
}

# ============ Command dispatch ============
case "$cmd" in
  init)       do_init ;;
  doctor)     do_doctor ;;
  edl)        do_edl ;;
  backup)     do_backup ;;
  unlock)     do_unlock "$@" ;;
  restore)    do_restore "$@" ;;
  auto)       do_auto ;;
  flash)      do_flash ;;
  verify)     do_verify ;;
  freeze-ota) do_freeze_ota ;;
  *) echo "Usage: $0 {init|doctor|edl|backup|unlock|restore|auto|flash|verify|freeze-ota}" ;;
esac
