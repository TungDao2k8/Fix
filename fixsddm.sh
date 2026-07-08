#!/usr/bin/env bash
# Fix màn hình đen SDDM trên laptop hybrid GPU (AMD iGPU + NVIDIA dGPU)
# Máy: ASUS ROG Zephyrus G16 (GA605WI) - Ryzen AI 9 HX 370 + RTX 4070
# Hệ điều hành: CachyOS
#
# NGUYÊN NHÂN: SDDM greeter (Wayland) mặc định dùng weston làm compositor,
# và weston tự chọn GPU đầu tiên tìm thấy (thường là NVIDIA card1),
# nhưng NVIDIA không có display nối trực tiếp - chỉ AMD (card2) mới có.
# => weston không vẽ được gì -> màn hình đen.
#
# Chạy: chmod +x fix-sddm-black-screen.sh && ./fix-sddm-black-screen.sh

set -e

echo "=== BƯỚC 0: Xác định card AMD / NVIDIA ==="
echo "Kiểm tra bằng lspci để biết chính xác card nào là AMD, card nào là NVIDIA:"
lspci -k | grep -A3 -i "vga\|3d\|display"
echo ""
echo "==> Ghi lại: card nào dùng driver 'amdgpu' và card nào dùng 'nvidia'."
echo "    Mặc định script này giả sử: card2 = AMD, card1 = NVIDIA."
echo "    NẾU KHÁC, sửa lại biến CARD_AMD và CARD_NVIDIA bên dưới trước khi chạy."
echo ""

CARD_AMD="card2"
CARD_NVIDIA="card1"

read -p "Nhấn Enter để tiếp tục với AMD=$CARD_AMD, NVIDIA=$CARD_NVIDIA (Ctrl+C để hủy và sửa script)..."

echo "=== BƯỚC 1: Cài driver NVIDIA (nếu chưa có) ==="
if ! pacman -Qs nvidia-open-dkms > /dev/null 2>&1 && ! pacman -Qs linux-cachyos-nvidia-open > /dev/null 2>&1; then
    echo "Chưa thấy driver NVIDIA, cài đặt..."
    sudo pacman -S --needed nvidia-open-dkms
else
    echo "Driver NVIDIA đã được cài."
fi

echo "=== BƯỚC 2: Bật module NVIDIA sớm trong initramfs (early KMS) ==="
if ! grep -q "nvidia" /etc/mkinitcpio.conf; then
    sudo sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    # Trường hợp MODULES=() rỗng hoàn toàn
    sudo sed -i 's/^MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    echo "Đã thêm module NVIDIA vào /etc/mkinitcpio.conf"
else
    echo "Module NVIDIA đã có trong mkinitcpio.conf"
fi

echo "=== BƯỚC 3: Rebuild initramfs (dùng đúng lệnh cho Limine) ==="
sudo limine-mkinitcpio

echo "=== BƯỚC 4: Thêm kernel parameter cho NVIDIA modeset ==="
LIMINE_CONF="/boot/limine.conf"
if [ -f "$LIMINE_CONF" ]; then
    if ! sudo grep -q "nvidia_drm.modeset=1" "$LIMINE_CONF"; then
        echo "Cần thêm 'nvidia_drm.modeset=1 nvidia_drm.fbdev=1' vào dòng CMDLINE= trong $LIMINE_CONF"
        echo "Mở file để chỉnh tay:"
        echo "    sudo nano $LIMINE_CONF"
        echo "Thêm vào CUỐI mỗi dòng CMDLINE= (mỗi kernel một dòng):"
        echo "    nvidia_drm.modeset=1 nvidia_drm.fbdev=1"
        read -p "Nhấn Enter sau khi đã sửa và lưu file..."
    else
        echo "Kernel parameter đã có sẵn."
    fi
else
    echo "CẢNH BÁO: Không tìm thấy $LIMINE_CONF - kiểm tra tay đường dẫn cấu hình Limine của bạn."
fi

echo "=== BƯỚC 5: Cài weston (bắt buộc để SDDM chạy Wayland greeter) ==="
sudo pacman -S --needed weston

echo "=== BƯỚC 6: Cấu hình SDDM dùng đúng GPU AMD cho weston ==="
sudo mkdir -p /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/20-hybrid-gpu.conf > /dev/null <<EOF
[General]
DisplayServer=wayland

[Wayland]
CompositorCommand=weston --shell=kiosk --drm-device=${CARD_AMD}
EOF
echo "Đã ghi /etc/sddm.conf.d/20-hybrid-gpu.conf"
cat /etc/sddm.conf.d/20-hybrid-gpu.conf

echo ""
echo "=== HOÀN TẤT ==="
echo "Khởi động lại để kiểm tra: sudo reboot"
echo ""
echo "Sau khi reboot, kiểm tra bằng:"
echo "    journalctl -b -u sddm --no-pager | grep -i 'falling back\|HELPER_DISPLAYSERVER'"
echo "Nếu không có dòng nào hiện ra -> đã hết đen màn hình."
