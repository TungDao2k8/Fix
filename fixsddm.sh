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

echo "=== BƯỚC 1: Cài weston (bắt buộc để SDDM chạy Wayland greeter) ==="
sudo pacman -S --needed weston

echo "=== BƯỚC 2: Cấu hình SDDM dùng đúng GPU AMD cho weston ==="
sudo mkdir -p /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/99z-hybrid-gpu.conf > /dev/null <<EOF
[General]
DisplayServer=wayland

[Wayland]
CompositorCommand=weston --shell=kiosk --drm-device=${CARD_AMD}
EOF
echo "Đã ghi /etc/sddm.conf.d/20-hybrid-gpu.conf"
cat /etc/sddm.conf.d/99z-hybrid-gpu.conf

echo ""
echo "=== HOÀN TẤT ==="
echo "Khởi động lại để kiểm tra: sudo reboot"
echo ""
echo "Sau khi reboot, kiểm tra bằng:"
echo "    journalctl -b -u sddm --no-pager | grep -i 'falling back\|HELPER_DISPLAYSERVER'"
echo "Nếu không có dòng nào hiện ra -> đã hết đen màn hình."
