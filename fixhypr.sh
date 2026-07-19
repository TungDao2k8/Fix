#!/bin/bash
# fix-aquamarine-amd-igpu.sh
#
# Patch + build Aquamarine để fix bug atomic commit "Cannot allocate memory"
# trên AMD iGPU dòng Strix Point / Strix Halo (Radeon 890M, Ryzen AI 9 HX 370, gfx1150...)
#
# Tham khảo: https://github.com/hyprwm/Hyprland/discussions/10248
#
# Chạy: bash fix-aquamarine-amd-igpu.sh

set -e

BUILD_DIR="$HOME/aquamarine-patched"
ATOMIC_FILE="src/backend/drm/impl/Atomic.cpp"

echo "==> Kiểm tra dependencies build (cmake, git)..."
for cmd in git cmake make; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Thiếu '$cmd'. Cài bằng: sudo pacman -S base-devel cmake git"
        exit 1
    fi
done

echo "==> Clone aquamarine về $BUILD_DIR"
rm -rf "$BUILD_DIR"
git clone --recursive https://github.com/hyprwm/aquamarine "$BUILD_DIR"
cd "$BUILD_DIR"

echo "==> Patch: vô hiệu hóa getMaxBPC() gây atomic commit fail trên AMD iGPU"
if ! grep -q "getMaxBPC" "$ATOMIC_FILE"; then
    echo "CẢNH BÁO: không tìm thấy dòng getMaxBPC trong $ATOMIC_FILE."
    echo "Có thể code upstream đã đổi. Kiểm tra thủ công trước khi tiếp tục."
    exit 1
fi

sed -E 's@^(.+getMaxBPC\(data.mainFB->buffer->dmabuf\(\).format\))@//\1@g' \
    -i "$ATOMIC_FILE"

echo "==> Build (release)..."
cmake --no-warn-unused-cli \
    -DCMAKE_BUILD_TYPE:STRING=Release \
    -DCMAKE_INSTALL_PREFIX:PATH=/usr \
    -S . -B ./build
cmake --build ./build --config Release --target all -j"$(nproc)"

echo "==> Gỡ bản aquamarine hệ thống cũ và cài bản đã patch"
sudo rm -fv /usr/lib/libaquamarine.so*
sudo cmake --install ./build

echo ""
echo "=== XONG ==="
echo "Bản aquamarine đã patch được cài vào /usr/lib."
echo ""
echo "Việc cần làm tiếp:"
echo "1. Xóa các workaround cũ (nếu có) khỏi ~/.config/caelestia/hypr-user.lua:"
echo "   - AQ_NO_ATOMIC"
echo "   - WLR_NO_HARDWARE_CURSORS"
echo "   - AQ_NO_MODIFIERS"
echo ""
echo "2. Ngăn pacman ghi đè bản patch khi update hệ thống:"
echo "   Thêm dòng sau vào /etc/pacman.conf (phần [options]):"
echo "   IgnorePkg = aquamarine"
echo ""
echo "3. Đăng xuất và đăng nhập lại (hoặc reboot) để Hyprland dùng bản aquamarine mới."
echo ""
echo "4. Muốn cập nhật aquamarine sau này: gỡ IgnorePkg tạm thời, hoặc chạy lại script này"
echo "   để build bản mới nhất kèm patch (script sẽ tự clone lại từ đầu)."
