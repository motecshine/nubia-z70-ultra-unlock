#!/usr/bin/env bash
# Z70 Ultra 刷机助手 - 环境初始化 + 常用操作
# 用法: ./z70.sh <命令>
#   init      初始化环境 (装依赖+编译工具+下载firehose)
#   edl       进 9008 模式
#   backup    完整备份 (需先 edl)
#   unlock    解锁流程刷写 (改GPT+补丁UEFI)
#   restore   解锁后恢复 (恢复GPT+boot)
#   auto      全自动流水线: 备份→解锁→恢复 (有人工暂停点)
#   flash     刷国际版 ROM (需已解压+过滤)
#   verify    验证解锁/版本状态
#   freeze-ota 冻结 OTA 更新
#   doctor    检查环境状态

set -e

# ============ 路径配置 ============
EDL_TOOLS="$HOME/edl-tools"
QDL="$EDL_TOOLS/qdl-rs"
FIREHOSE="$EDL_TOOLS/devprg_z70u"
UEFI_UNLOCK="$EDL_TOOLS/uefi_unlock_8e.img"
BACKUP_DIR="$HOME/edl-backup"
VENV="$HOME/.venvs/edl"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ============ 颜色 ============
G='\033[32m'; Y='\033[33m'; R='\033[31m'; B='\033[34m'; N='\033[0m'
ok()   { echo -e "${G}✅ $*${N}"; }
info() { echo -e "${B}ℹ️  $*${N}"; }
warn() { echo -e "${Y}⚠️  $*${N}"; }
err()  { echo -e "${R}❌ $*${N}"; }
step() { echo -e "\n${B}==== $* ====${N}"; }

cmd="${1:-help}"
shift || true

# ============ init: 环境初始化 ============
do_init() {
  step "检查系统"
  [[ "$(uname)" == "Darwin" ]] || { err "仅支持 macOS (当前: $(uname))"; exit 1; }
  ok "macOS 检测通过"

  step "检查 Homebrew"
  if ! command -v brew >/dev/null; then
    warn "未安装 Homebrew, 正在安装..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  ok "Homebrew: $(brew --version | head -1)"

  step "安装依赖 (sevenzip/aria2/android-platform-tools/rust/git/libusb)"
  for pkg in sevenzip aria2 android-platform-tools rust git libusb; do
    if command -v "$pkg" >/dev/null 2>&1 || brew list "$pkg" >/dev/null 2>&1; then
      ok "$pkg 已安装"
    else
      info "安装 $pkg ..."
      brew install "$pkg" || warn "$pkg 安装失败, 跳过"
    fi
  done

  # 7zz 的路径可能不同
  SEVENZIP="$(command -v 7zz || command -v 7z || echo /opt/homebrew/bin/7zz)"

  step "设置 Python venv + pyusb (EDL 检测用)"
  if [[ ! -d "$VENV" ]]; then
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet --upgrade pip
    "$VENV/bin/pip" install --quiet pyusb
  fi
  ok "Python venv: $VENV"

  step "克隆并编译 qdl-rs"
  QDLRS_DIR="${QDLRS_DIR:-/tmp/qdlrs}"
  if [[ ! -d "$QDLRS_DIR/.git" ]]; then
    info "克隆 qualcomm/qdlrs ..."
    rm -rf "$QDLRS_DIR"
    git clone --depth 1 https://github.com/qualcomm/qdlrs.git "$QDLRS_DIR"
  fi
  cd "$QDLRS_DIR"
  info "应用 Oem=ZTE 补丁 ..."
  git apply --check "$PROJECT_DIR/patches/qdlrs-oem-zte.patch" 2>/dev/null && \
    git apply "$PROJECT_DIR/patches/qdlrs-oem-zte.patch" && ok "补丁已应用" || \
    warn "补丁已应用过或冲突, 跳过"
  info "编译 (cargo build) ..."
  cargo build --release --bin qdl-rs --bin fh_reset 2>/dev/null || cargo build --release --bin qdl-rs
  mkdir -p "$EDL_TOOLS"
  cp target/release/qdl-rs "$QDL" 2>/dev/null || true
  cp target/release/fh_reset "$EDL_TOOLS/fh_reset" 2>/dev/null || true
  # 复制 fh_reset 源码(如果 cargo build 没编它)
  if [[ ! -f "$QDLRS_DIR/cli/src/bin/fh_reset.rs" ]]; then
    mkdir -p "$QDLRS_DIR/cli/src/bin"
    cp "$PROJECT_DIR/patches/fh_reset.rs" "$QDLRS_DIR/cli/src/bin/fh_reset.rs"
    cargo build --release --bin fh_reset
    cp target/release/fh_reset "$EDL_TOOLS/fh_reset"
  fi
  ok "qdl-rs 编译完成: $QDL"

  step "准备 firehose (NX789J.elf, SM8750 ZTE 签名)"
  # 优先用仓库自带的
  if [[ -f "$PROJECT_DIR/tools/firehose/NX789J.elf" ]]; then
    cp "$PROJECT_DIR/tools/firehose/NX789J.elf" "$FIREHOSE"
    ok "使用仓库自带的 firehose"
  elif [[ ! -f "$FIREHOSE" ]]; then
    info "从 Iqinix/Qualcomm-firehoses 下载..."
    curl -sL --max-time 120 -o "$FIREHOSE" \
      "https://raw.githubusercontent.com/Iqinix/Qualcomm-firehoses/main/ZTE/NX789J.elf"
    [[ -s "$FIREHOSE" ]] && ok "firehose 下载完成 ($(stat -f%z "$FIREHOSE") bytes)" || \
      { err "firehose 下载失败"; rm -f "$FIREHOSE"; }
  else
    ok "firehose 已存在"
  fi

  step "准备补丁 UEFI (uefi_unlock_8e.img)"
  if [[ -f "$PROJECT_DIR/tools/uefi/uefi_unlock_8e.img" ]]; then
    cp "$PROJECT_DIR/tools/uefi/uefi_unlock_8e.img" "$UEFI_UNLOCK"
    ok "使用仓库自带的补丁 UEFI"
  else
    warn "仓库无 uefi_unlock_8e.img, 需手动放到 $UEFI_UNLOCK"
  fi

  step "设置 aria2 (2连接, 防 Needrom ban)"
  mkdir -p "$HOME/.aria2"
  cp "$PROJECT_DIR/scripts/aria2.conf" "$HOME/.aria2/aria2.conf"
  sed -i '' "s|^dir=.*|dir=$HOME/Downloads|" "$HOME/.aria2/aria2.conf"
  pkill -f aria2c 2>/dev/null || true
  nohup aria2c --conf-path="$HOME/.aria2/aria2.conf" > "$HOME/.aria2/aria2.log" 2>&1 &
  sleep 2
  ok "aria2 RPC 已启动 (localhost:6800)"

  step "创建目录"
  mkdir -p "$EDL_TOOLS" "$BACKUP_DIR"
  ok "edl-tools: $EDL_TOOLS"
  ok "edl-backup: $BACKUP_DIR"

  step "初始化完成! 还需手动准备:"
  echo ""
  echo "  仅需 ROM (刷国际版才需要):"
  echo "    预览页: https://www.needrom.com/download/zte-nubia-z70-ultra/"
  echo "    版本: Z70Ultra_NebulaOS1.0.7MR3_NX733J_GB_15 (8.5GB, GB=国际版)"
  echo "    解压到: ~/edl-rom/ROM/images/"
  echo ""
  echo "  其余工具/firehose/UEFI 都已随仓库提供, 无需额外下载。"
  echo ""
  echo "  检查环境: ./z70.sh doctor"
}

# ============ doctor: 环境检查 ============
do_doctor() {
  echo "=== 环境检查 ==="
  check() { command -v "$1" >/dev/null 2>&1 && ok "$1" || err "$1 未安装"; }
  check brew; check adb; check fastboot; check 7zz; check aria2c; check cargo; check git

  echo "=== 关键文件 ==="
  [[ -f "$QDL" ]] && ok "qdl-rs" || err "qdl-rs 未编译 (运行 init)"
  [[ -f "$FIREHOSE" ]] && ok "firehose" || err "firehose 缺失 (运行 init)"
  [[ -f "$UEFI_UNLOCK" ]] && ok "uefi_unlock_8e.img" || warn "uefi_unlock_8e.img 缺失 (解锁才需要)"

  echo "=== 设备状态 ==="
  adb devices 2>/dev/null | tail -n +2 | grep -q "device" && ok "ADB 设备已连接" || warn "无 ADB 设备"
}

# ============ 其它命令 ============
do_edl() {
  info "进入 9008 ..."
  adb reboot edl
  sleep 15
  "$VENV/bin/python" -c "
import usb.core, usb.backend.libusb1
be = usb.backend.libusb1.get_backend(find_library=lambda x: '/opt/homebrew/lib/libusb-1.0.dylib')
d = usb.core.find(idVendor=0x05c6, idProduct=0x9008, backend=be)
print('✅ EDL OK' if d else '❌ 未进入 EDL')
"
}

do_backup() {
  d="$BACKUP_DIR/$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$d"
  info "备份到 $d"
  "$QDL" --backend usb -l "$FIREHOSE" -s ufs backup -o "$d"
  ok "备份完成: $d"
}

do_unlock() {
  bak="${1:-$(ls -td $BACKUP_DIR/*/ 2>/dev/null | head -1)}"
  [[ -z "$bak" ]] && { err "没有找到备份目录, 先执行 backup"; exit 1; }
  [[ -f "$UEFI_UNLOCK" ]] || { err "缺少 $UEFI_UNLOCK"; exit 1; }
  info "使用备份: $bak"
  python3 -c "open('/tmp/gpt_orig_6s.bin','wb').write(open('$bak/gpt_raw_lun4.bin','rb').read()[:6*4096])"
  python3 "$PROJECT_DIR/scripts/gpt_edit.py" "$bak/gpt_raw_lun4.bin" /tmp/gpt_modified.bin vbmeta_a pvmfw_a
  python3 -c "open('/tmp/gpt_mod_6s.bin','wb').write(open('/tmp/gpt_modified.bin','rb').read()[:6*4096])"
  info "刷入解锁 (改GPT + 补丁UEFI)..."
  "$QDL" --backend usb -l "$FIREHOSE" -s ufs --reset-mode system \
    unlock-flash --gpt-file /tmp/gpt_mod_6s.bin --uefi-file "$UEFI_UNLOCK"
  info "设备将重启进入标准 Fastboot, 然后执行: fastboot flashing unlock"
  info "解锁后硬件进 9008, 再执行: ./z70.sh restore $bak"
}

do_restore() {
  bak="${1:-$(ls -td $BACKUP_DIR/*/ 2>/dev/null | head -1)}"
  python3 -c "open('/tmp/gpt_orig_6s.bin','wb').write(open('$bak/gpt_raw_lun4.bin','rb').read()[:6*4096])"
  info "恢复 GPT + boot_a ..."
  "$QDL" --backend usb -l "$FIREHOSE" -s ufs --reset-mode system \
    unlock-restore --gpt-file /tmp/gpt_orig_6s.bin --boot-file "$bak/L4__boot_a.img"
}

do_flash() {
  cd ~/edl-rom/ROM/images
  info "刷国际版 ROM ..."
  "$QDL" --backend usb -l "$FIREHOSE" -s ufs --reset-mode system \
    flasher -p rawprogram0.xml rawprogram1.xml rawprogram2.xml rawprogram4.xml
}

do_verify() {
  echo "=== 解锁状态 ==="
  adb shell getprop ro.boot.flash.locked
  adb shell getprop ro.boot.vbmeta.device_state
  echo "=== 系统版本 ==="
  adb shell getprop ro.product.name
  adb shell getprop ro.build.version.release
  echo "=== Google 服务 ==="
  adb shell pm list packages 2>/dev/null | grep -c google
}

do_freeze_ota() {
  for pkg in com.zte.zdm com.zte.zdmdaemon com.zte.zdmdaemon.install com.zte.zdm.omacp com.google.android.configupdater; do
    info "冻结 $pkg"
    adb shell pm disable-user --user 0 "$pkg" || warn "$pkg 失败"
  done
  ok "OTA 冻结完成"
}

# ============ auto: 全自动流水线 (备份→解锁→刷机) ============
do_auto() {
  step "自动流水线启动"
  echo "流程: 备份 → 刷解锁 → [人工: fastboot确认] → [人工: 按键进9008] → 恢复 → 验证"
  echo ""

  # --- 1. 备份 ---
  step "1/6 完整备份"
  do_edl
  do_backup
  BAK="$(ls -td $BACKUP_DIR/*/ | head -1)"
  ok "备份完成: $BAK"

  # --- 2. 刷解锁 ---
  step "2/6 刷解锁 (改GPT + 补丁UEFI)"
  do_unlock "$BAK"

  # --- 3. 人工: fastboot 确认 ---
  step "3/6 人工步骤: fastboot 解锁确认"
  echo ""
  echo "  设备正在重启进入标准 Fastboot (序列号会变成 af6c26cd)..."
  echo "  等待 20 秒后检查..."
  sleep 20
  fastboot devices 2>/dev/null || true
  echo ""
  echo "  ⚠️  请在电脑上执行: fastboot flashing unlock"
  echo "  然后【看手机屏幕】, 用音量键选 UNLOCK THE BOOTLOADER, 电源键确认"
  echo ""
  read -r -p "  确认完成后按回车继续..." _

  # --- 4. 人工: 硬件进 9008 ---
  step "4/6 人工步骤: 硬件进 9008"
  echo ""
  echo "  ⚠️  请手动进 9008: "
  echo "    1. 拔掉 USB 线"
  echo "    2. 长按电源键 15秒 强制关机"
  echo "    3. 按住「音量上 + 音量下」"
  echo "    4. 保持按住, 插上 USB 线"
  echo ""
  read -r -p "  插线后按回车继续..." _
  sleep 5

  # --- 5. 恢复 ---
  step "5/6 恢复原 GPT + boot"
  do_restore "$BAK"

  # --- 6. 验证 ---
  step "6/6 验证解锁状态"
  sleep 30
  do_verify
  echo ""
  ok "解锁流水线完成! 如需刷国际版 ROM 再执行: ./z70.sh flash"
}

# ============ 命令分发 ============
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
  *) echo "用法: $0 {init|doctor|edl|backup|unlock|restore|auto|flash|verify|freeze-ota}" ;;
esac
