#!/usr/bin/env bash
# ===================================================================
#  Cài đặt Niri + Noctalia v5 trên CachyOS
#  Tham khảo: docs.noctalia.dev/v5, wiki.cachyos.org/.../niri
#  Chạy với user thường (KHÔNG dùng sudo khi gọi script này).
# ===================================================================
set -euo pipefail

CONFIG_DIR="$HOME/.config/niri"
CONFIG_FILE="$CONFIG_DIR/config.kdl"
BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"

log()  { echo -e "\e[1;32m[setup]\e[0m $*"; }
warn() { echo -e "\e[1;33m[setup]\e[0m $*"; }
err()  { echo -e "\e[1;31m[setup]\e[0m $*" >&2; }

if [[ $EUID -eq 0 ]]; then
  err "Đừng chạy bằng root/sudo. Chạy bằng user thường, script tự sudo khi cần."
  exit 1
fi

if ! grep -qi cachyos /etc/os-release 2>/dev/null; then
  warn "Không thấy CachyOS trong /etc/os-release. Vẫn chạy được trên Arch-based khác, nhưng hãy kiểm tra lại."
  read -rp "Tiếp tục? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || exit 1
fi

log "Cập nhật hệ thống..."
sudo pacman -Syu --noconfirm

# -------------------------------------------------------------------
# 1. Niri + các thành phần Wayland cần thiết
# -------------------------------------------------------------------
log "Cài Niri và các gói nền tảng (portal, audio, font, terminal...)"
sudo pacman -S --needed --noconfirm \
  niri \
  xwayland-satellite \
  xdg-desktop-portal-gnome \
  xdg-desktop-portal-gtk \
  alacritty \
  polkit-gnome \
  gnome-keyring \
  qt5-wayland qt6-wayland \
  pipewire wireplumber \
  ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji

# -------------------------------------------------------------------
# 2. AUR helper (paru) — CachyOS thường có sẵn, nhưng phòng trường hợp chưa có
# -------------------------------------------------------------------
if ! command -v paru &>/dev/null; then
  log "Chưa có paru, đang cài từ AUR..."
  sudo pacman -S --needed --noconfirm base-devel git
  tmpdir=$(mktemp -d)
  git clone https://aur.archlinux.org/paru.git "$tmpdir/paru"
  (cd "$tmpdir/paru" && makepkg -si --noconfirm)
  rm -rf "$tmpdir"
else
  log "paru đã có sẵn, bỏ qua bước cài AUR helper."
fi

# -------------------------------------------------------------------
# 3. Noctalia v5 (gói noctalia-git trên AUR)
# -------------------------------------------------------------------
log "Cài Noctalia v5 (noctalia-git) từ AUR..."
paru -S --needed --noconfirm noctalia-git

# -------------------------------------------------------------------
# 4. Cấu hình Niri cho Noctalia
# -------------------------------------------------------------------
mkdir -p "$CONFIG_DIR"

if [[ -f "$CONFIG_FILE" ]]; then
  mkdir -p "$BACKUP_DIR"
  cp "$CONFIG_FILE" "$BACKUP_DIR/config.kdl.bak"
  log "Đã sao lưu config Niri cũ vào $BACKUP_DIR"
else
  # Lấy config mặc định của Niri làm điểm khởi đầu nếu user chưa từng chạy Niri
  if [[ -f /etc/niri/config.kdl ]]; then
    cp /etc/niri/config.kdl "$CONFIG_FILE"
  else
    touch "$CONFIG_FILE"
  fi
fi

# Xoá block cũ nếu script này từng chạy trước đó (để chạy lại không bị lặp)
MARK_START="// >>> noctalia-autoconfig start"
MARK_END="// <<< noctalia-autoconfig end"
if grep -qF "$MARK_START" "$CONFIG_FILE"; then
  sed -i "\#${MARK_START}#,\#${MARK_END}#d" "$CONFIG_FILE"
fi

log "Ghi cấu hình Noctalia vào $CONFIG_FILE"
cat >> "$CONFIG_FILE" <<'EOF'

// >>> noctalia-autoconfig start
// Tự khởi động Noctalia cùng Niri
spawn-at-startup "noctalia"

// Bo góc cửa sổ + clip theo góc bo
window-rule {
    geometry-corner-radius 20
    clip-to-geometry true
}

// Cửa sổ Settings của Noctalia luôn ở dạng nổi (floating)
window-rule {
    match app-id="dev.noctalia.Noctalia.Settings"
    open-floating true
    default-column-width { fixed 1080; }
    default-window-height { fixed 920; }
}

debug {
    honor-xdg-activation-with-invalid-serial
}

// Phím tắt điều khiển Noctalia
binds {
    Mod+Space { spawn-sh "noctalia msg panel-toggle launcher"; }
    Mod+S     { spawn-sh "noctalia msg panel-toggle control-center"; }
    Mod+Comma { spawn-sh "noctalia msg settings-toggle"; }

    XF86AudioRaiseVolume   { spawn-sh "noctalia msg volume-up"; }
    XF86AudioLowerVolume   { spawn-sh "noctalia msg volume-down"; }
    XF86AudioMute          { spawn-sh "noctalia msg volume-mute"; }
    XF86MonBrightnessUp    { spawn-sh "noctalia msg brightness-up"; }
    XF86MonBrightnessDown  { spawn-sh "noctalia msg brightness-down"; }
}
// <<< noctalia-autoconfig end
EOF

# -------------------------------------------------------------------
# 5. Noctalia Greeter (màn hình đăng nhập, dùng greetd) — tuỳ chọn
# -------------------------------------------------------------------
INSTALL_GREETER="n"
read -rp "Cài thêm Noctalia Greeter (màn hình đăng nhập đồng bộ giao diện)? [y/N] " INSTALL_GREETER
if [[ "$INSTALL_GREETER" =~ ^[Yy]$ ]]; then

  log "Cài greetd + phụ thuộc cho Noctalia Greeter..."
  sudo pacman -S --needed --noconfirm \
    greetd cage wlr-randr dbus polkit

  log "Cài Noctalia Greeter (noctalia-greeter-git) từ AUR..."
  paru -S --needed --noconfirm noctalia-greeter-git

  log "Chạy script thiết lập hệ thống cho Noctalia Greeter (tạo user/thư mục greetd)..."
  tmp_greeter_src=$(mktemp -d)
  git clone --depth=1 https://github.com/noctalia-dev/noctalia-greeter "$tmp_greeter_src"
  if [[ -f "$tmp_greeter_src/scripts/setup_greeter_system.sh" ]]; then
    sudo bash "$tmp_greeter_src/scripts/setup_greeter_system.sh"
  else
    warn "Không tìm thấy setup_greeter_system.sh, bỏ qua bước này (có thể AUR package đã tự chạy)."
  fi
  rm -rf "$tmp_greeter_src"

  GREETER_SESSION_BIN="$(command -v noctalia-greeter-session || true)"
  if [[ -z "$GREETER_SESSION_BIN" ]]; then
    err "Không tìm thấy noctalia-greeter-session sau khi cài. Kiểm tra lại gói noctalia-greeter-git."
  else
    log "Cấu hình /etc/greetd/config.toml (trỏ phiên mặc định là niri)..."
    if [[ -f /etc/greetd/config.toml ]]; then
      sudo cp /etc/greetd/config.toml "/etc/greetd/config.toml.bak-$(date +%Y%m%d-%H%M%S)"
      log "Đã sao lưu /etc/greetd/config.toml cũ."
    fi
    sudo mkdir -p /etc/greetd
    cat <<EOF | sudo tee /etc/greetd/config.toml > /dev/null
[terminal]
vt = 1

[default_session]
command = "$GREETER_SESSION_BIN -- --session niri"
user = "greeter"
EOF

    warn "greetd sẽ thay thế display manager hiện tại của bạn (nếu có, vd: GDM/SDDM/LightDM)."
    read -rp "Vô hiệu hoá display manager khác và bật greetd ngay bây giờ? [y/N] " ENABLE_GREETD
    if [[ "$ENABLE_GREETD" =~ ^[Yy]$ ]]; then
      for dm in gdm gdm3 sddm lightdm lxdm; do
        if systemctl is-enabled "$dm" &>/dev/null; then
          log "Tắt $dm..."
          sudo systemctl disable "$dm"
        fi
      done
      sudo systemctl enable greetd
      log "Đã bật greetd. Khởi động lại để vào màn hình đăng nhập mới."
    else
      log "Đã cấu hình xong nhưng CHƯA bật greetd. Bật thủ công sau bằng: sudo systemctl enable --now greetd"
    fi

    echo
    echo "Ghi chú Noctalia Greeter:"
    echo "  • Sau khi cài Noctalia v5 (đã làm ở bước 3), vào Settings → Security →"
    echo "    Noctalia Greeter → Sync Now để đồng bộ wallpaper/màu sắc ra màn hình đăng nhập."
    echo "  • Đổi phiên mặc định: sửa '--session niri' trong /etc/greetd/config.toml"
    echo "    (xem tên phiên hợp lệ bằng lệnh: noctalia-greeter sessions)."
    echo "  • Log lỗi: /var/log/noctalia-greeter.log và /var/lib/noctalia-greeter/greeter.log"
  fi
else
  log "Bỏ qua Noctalia Greeter."
fi

log "✅ Hoàn tất cài đặt!"
echo
echo "Bước tiếp theo:"
echo "  • Có display manager (SDDM/GDM...): đăng xuất, chọn phiên 'Niri' khi đăng nhập lại."
echo "  • Không có display manager: gõ 'niri-session' (hoặc 'niri --session') từ TTY."
echo "  • Mở Settings của Noctalia bằng Mod+, để chọn theme/wallpaper lần đầu."
echo
echo "⚠ Lưu ý: nếu config.kdl gốc của bạn vốn đã có sẵn 'spawn-at-startup waybar/fuzzel'"
echo "  hoặc block 'binds { ... }' khác, hãy mở $CONFIG_FILE kiểm tra để tránh"
echo "  trùng thanh bar/launcher hoặc trùng phím tắt với Noctalia."
echo
echo "File cấu hình: $CONFIG_FILE"
[[ -d "$BACKUP_DIR" ]] && echo "Backup config cũ:  $BACKUP_DIR/config.kdl.bak"
