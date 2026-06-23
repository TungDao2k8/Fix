#!/bin/bash

# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Lỗi: Vui lòng chạy script này với quyền root (dùng sudo)."
  exit 1
fi

echo "=== CÔNG CỤ FIX SDDM BLACK SCREEN CHO NVIDIA & LIMINE ==="

# ---------------------------------------------------------
# 1. CẤU HÌNH MKINITCPIO (EARLY KMS)
# ---------------------------------------------------------
MKINIT_CONF="/etc/mkinitcpio.conf"
echo "[1/4] Xử lý Early KMS trong $MKINIT_CONF..."
cp "$MKINIT_CONF" "${MKINIT_CONF}.bak"

if grep -q "nvidia_drm" "$MKINIT_CONF"; then
    echo "  -> Các module NVIDIA đã tồn tại. Bỏ qua."
else
    echo "  -> Thêm module: nvidia, nvidia_modeset, nvidia_uvm, nvidia_drm"
    sed -i 's/^MODULES=(/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm /' "$MKINIT_CONF"
    sed -i 's/^MODULES="/MODULES="nvidia nvidia_modeset nvidia_uvm nvidia_drm /' "$MKINIT_CONF"
fi

if grep -q "^HOOKS=.*kms.*" "$MKINIT_CONF"; then
    echo "  -> Xóa hook 'kms' khỏi HOOKS theo chuẩn NVIDIA."
    sed -i 's/ kms / /g' "$MKINIT_CONF"
fi

# ---------------------------------------------------------
# 2. CẤU HÌNH MODPROBE (DRM MODESET)
# ---------------------------------------------------------
MODPROBE_CONF="/etc/modprobe.d/nvidia.conf"
echo "[2/4] Xử lý Modprobe tại $MODPROBE_CONF..."
mkdir -p /etc/modprobe.d
echo "options nvidia-drm modeset=1" > "$MODPROBE_CONF"
echo "options nvidia-drm fbdev=1" >> "$MODPROBE_CONF"
echo "  -> Đã ghi cấu hình modeset=1 và fbdev=1."

# ---------------------------------------------------------
# 3. TỰ ĐỘNG CẤU HÌNH LIMINE BOOTLOADER
# ---------------------------------------------------------
echo "[3/4] Dò tìm và cập nhật cấu hình Limine..."
LIMINE_CONF=""
# Danh sách các đường dẫn phổ biến của file cấu hình Limine
POSSIBLE_PATHS=(
    "/boot/limine.conf"
    "/boot/limine.cfg"
    "/boot/limine/limine.conf"
    "/boot/limine/limine.cfg"
    "/boot/efi/EFI/limine/limine.conf"
    "/boot/efi/EFI/limine/limine.cfg"
    "/efi/EFI/limine/limine.conf"
    "/efi/EFI/limine/limine.cfg"
    "/boot/efi/limine.conf"
    "/efi/limine.conf"
)

for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -f "$path" ]; then
        LIMINE_CONF="$path"
        break
    fi
done

if [ -n "$LIMINE_CONF" ]; then
    echo "  -> Tìm thấy file cấu hình tại: $LIMINE_CONF"
    cp "$LIMINE_CONF" "${LIMINE_CONF}.bak"
    
    # Kiểm tra xem tham số đã có sẵn chưa
    if grep -q "nvidia-drm.modeset=1" "$LIMINE_CONF"; then
        echo "  -> Tham số nvidia-drm.modeset=1 đã tồn tại. Bỏ qua."
    else
        echo "  -> Đang chèn tham số NVIDIA vào kernel_cmdline..."
        # Tìm các dòng chứa 'kernel_cmdline:' (có thể có khoảng trắng thụt lề) và chèn tham số vào cuối dòng
        sed -i '/^[[:space:]]*kernel_cmdline:/ s/$/ nvidia-drm.modeset=1 nvidia-drm.fbdev=1/' "$LIMINE_CONF"
        echo "  -> Cập nhật Limine thành công (Đã sao lưu file cũ thành .bak)."
    fi
else
    echo "  -> ⚠️ KHÔNG TÌM THẤY file cấu hình Limine tự động!"
    echo "  -> Bạn hãy tự mở file cấu hình Limine của mình và thêm: nvidia-drm.modeset=1 nvidia-drm.fbdev=1 vào dòng kernel_cmdline."
fi

# ---------------------------------------------------------
# 4. PACMAN HOOK & REBUILD INITRAMFS
# ---------------------------------------------------------
PACMAN_HOOK_DIR="/etc/pacman.d/hooks"
PACMAN_HOOK_FILE="$PACMAN_HOOK_DIR/nvidia.hook"
echo "[4/4] Tạo Pacman hook và chạy mkinitcpio..."
mkdir -p "$PACMAN_HOOK_DIR"
cat <<EOF > "$PACMAN_HOOK_FILE"
[Trigger]
Operation=Install
Operation=Upgrade
Operation=Remove
Type=Package
Target=nvidia
Target=linux

[Action]
Description=Cập nhật NVIDIA module trong initcpio
Depends=mkinitcpio
When=PostTransaction
NeedsTargets
Exec=/bin/sh -c 'while read -r trg; do case \$trg in linux) exit 0; esac; done; /usr/bin/mkinitcpio -P'
EOF

echo "  -> Đang chạy mkinitcpio -P (Vui lòng đợi)..."
mkinitcpio -P > /dev/null

echo "=== HOÀN TẤT! ==="
echo "✅ Script đã thực thi xong toàn bộ. Vui lòng gõ lệnh 'reboot' để khởi động lại máy."
