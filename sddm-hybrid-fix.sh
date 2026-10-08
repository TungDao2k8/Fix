#!/usr/bin/env bash
# sddm-hybrid-fix.sh
# Cài một wrapper cho Weston của SDDM: mỗi lần greeter khởi động, wrapper tự tìm card DRM
# đang nối với màn hình laptop (eDP) rồi chạy weston với --drm-device=<card đó>.
# Nhờ vậy số card (card1/card2...) đổi sau khi cập nhật kernel/driver hay đổi GPU mode
# cũng không làm đen màn hình.
#
#   sudo bash sddm-hybrid-fix.sh                 # cài wrapper + drop-in SDDM
#   sudo bash sddm-hybrid-fix.sh --dry-run       # chỉ in ra, không ghi gì
#   sudo bash sddm-hybrid-fix.sh --detect        # chỉ in card sẽ được chọn (không cần root)
#   sudo bash sddm-hybrid-fix.sh --clean-legacy  # gỡ DisplayServer=x11 / InputMethod= khỏi inir-theme.conf cũ
#   sudo bash sddm-hybrid-fix.sh --uninstall     # gỡ wrapper + drop-in
set -uo pipefail

CONF_DIR="${CONF_DIR:-/etc/sddm.conf.d}"
# "zz-" xếp sau "99-inir-theme.conf" và sau hầu hết file khác theo thứ tự chữ cái.
OUT_FILE="${CONF_DIR}/zz-hybrid-gpu.conf"
WRAPPER="${WRAPPER:-/usr/local/bin/sddm-weston-auto}"
DRY_RUN=0; DETECT_ONLY=0; CLEAN_LEGACY=0; UNINSTALL=0

info() { printf '\033[1;34m[i]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[✓]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --detect) DETECT_ONLY=1 ;;
        --clean-legacy) CLEAN_LEGACY=1 ;;
        --uninstall) UNINSTALL=1 ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) die "Tham số không hợp lệ: $arg" ;;
    esac
done

# ---------------------------------------------------------------------------
# Nội dung wrapper (chạy mỗi lần SDDM khởi động greeter, dưới user sddm)
# ---------------------------------------------------------------------------
wrapper_content() {
cat <<'WRAP'
#!/usr/bin/env bash
# sddm-weston-auto — tạo bởi sddm-hybrid-fix.sh
# Tự chọn card DRM đúng cho Weston của greeter SDDM, mỗi lần khởi động.
#   1) Card sở hữu connector màn hình trong (eDP/LVDS/DSI) đang "connected"
#   2) Dự phòng: card dùng driver amdgpu / i915 / xe (iGPU)
#   3) Không tìm thấy: để Weston tự chọn như mặc định
DRM="${DRM_SYSFS:-/sys/class/drm}"

detect_card() {
    local p n c drv st
    for p in "$DRM"/card[0-9]*-eDP-* "$DRM"/card[0-9]*-LVDS-* "$DRM"/card[0-9]*-DSI-*; do
        [[ -e "$p" ]] || continue
        n="${p##*/}"; c="${n%%-*}"
        st="$(cat "$p/status" 2>/dev/null)"
        if [[ "$st" == "connected" ]]; then echo "$c"; return 0; fi
    done
    for p in "$DRM"/card[0-9]*; do
        n="${p##*/}"
        [[ "$n" == *-* ]] && continue
        drv="$(basename "$(readlink -f "$p/device/driver" 2>/dev/null)" 2>/dev/null)"
        case "$drv" in amdgpu|i915|xe) echo "$n"; return 0 ;; esac
    done
    return 1
}

if [[ "${1:-}" == "--print-card" ]]; then
    detect_card
    exit $?
fi

# Driver GPU có thể nạp muộn lúc boot: chờ tối đa ~5 giây để card xuất hiện.
card=""
for _ in $(seq 1 50); do
    if card="$(detect_card)"; then break; fi
    card=""
    sleep 0.1
done

args=(--shell=kiosk)
if [[ -n "$card" ]]; then
    args+=(--drm-device="$card")
    echo "sddm-weston-auto: dùng $card" >&2
else
    echo "sddm-weston-auto: không phát hiện được card, để Weston tự chọn" >&2
fi
exec weston "${args[@]}" "$@"
WRAP
}

# ---------------------------------------------------------------------------
# --detect: không cần root, chỉ in kết quả
# ---------------------------------------------------------------------------
if [[ $DETECT_ONLY -eq 1 ]]; then
    tmp="$(mktemp)"; wrapper_content > "$tmp"
    info "Các card DRM hiện tại:"
    for path in /sys/class/drm/card[0-9]*; do
        name="${path##*/}"; [[ "$name" == *-* ]] && continue
        [[ -e "$path/device/driver" ]] || continue
        drv="$(basename "$(readlink -f "$path/device/driver")")"
        edp="không"
        for conn in "$path"-eDP-* "$path"-LVDS-* "$path"-DSI-*; do
            [[ -e "$conn" ]] && edp="có ($(cat "$conn/status" 2>/dev/null))"
        done
        printf '    %-7s driver=%-10s màn hình trong: %s\n' "$name" "$drv" "$edp"
    done
    if card="$(bash "$tmp" --print-card)"; then ok "Card sẽ được chọn: $card"; else warn "Không tự chọn được card."; fi
    rm -f "$tmp"
    exit 0
fi

# ---------------------------------------------------------------------------
# --uninstall
# ---------------------------------------------------------------------------
if [[ $UNINSTALL -eq 1 ]]; then
    [[ $EUID -eq 0 ]] || die "Cần root. Chạy: sudo bash $0 --uninstall"
    rm -f "$OUT_FILE" "$WRAPPER"
    ok "Đã gỡ ${OUT_FILE} và ${WRAPPER}"
    exit 0
fi

[[ $DRY_RUN -eq 1 || $EUID -eq 0 ]] || die "Cần quyền root để ghi ${CONF_DIR}. Chạy: sudo bash $0"

# ---------------------------------------------------------------------------
# Kiểm tra môi trường
# ---------------------------------------------------------------------------
command -v weston >/dev/null 2>&1 || warn "Không thấy 'weston' trong PATH. Cài weston, nếu không greeter sẽ không khởi động."

if [[ -r /sys/module/nvidia_drm/parameters/modeset ]]; then
    [[ "$(cat /sys/module/nvidia_drm/parameters/modeset)" == "Y" ]] \
        || warn "nvidia-drm.modeset chưa bật (cần nvidia-drm.modeset=1 trên kernel cmdline)."
fi

info "Các file SDDM khác đang đặt DisplayServer / CompositorCommand:"
conflicts=0
for f in /etc/sddm.conf "$CONF_DIR"/*.conf /usr/lib/sddm/sddm.conf.d/*.conf; do
    [[ -f "$f" && "$f" != "$OUT_FILE" ]] || continue
    if grep -qE '^[[:space:]]*(DisplayServer|CompositorCommand)[[:space:]]*=' "$f" 2>/dev/null; then
        printf '    %s\n' "$f"
        grep -nE '^[[:space:]]*(DisplayServer|CompositorCommand)[[:space:]]*=' "$f" | sed 's/^/        /'
        conflicts=1
    fi
done
[[ $conflicts -eq 0 ]] && printf '    (không có)\n'
if [[ -f /etc/sddm.conf ]] && grep -qE '^[[:space:]]*(DisplayServer|CompositorCommand)' /etc/sddm.conf 2>/dev/null; then
    warn "/etc/sddm.conf cũng đặt các khoá này và có thể được ưu tiên hơn drop-in; hãy sửa hoặc xóa dòng đó."
fi

CONTENT="# Tạo bởi sddm-hybrid-fix.sh: greeter Weston tự chọn card đúng qua wrapper.
[General]
DisplayServer=wayland

[Wayland]
CompositorCommand=${WRAPPER}
"

if [[ $DRY_RUN -eq 1 ]]; then
    info "--dry-run: sẽ cài wrapper vào ${WRAPPER}"
    info "--dry-run: sẽ ghi ${OUT_FILE}:"
    printf '%s\n' "$CONTENT" | sed 's/^/    /'
    tmp="$(mktemp)"; wrapper_content > "$tmp"
    if card="$(bash "$tmp" --print-card)"; then info "Card hiện được chọn: $card"; else warn "Hiện chưa tự chọn được card."; fi
    rm -f "$tmp"
    exit 0
fi

# ---------------------------------------------------------------------------
# Cài đặt
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$WRAPPER")" "$CONF_DIR"
wrapper_content > "$WRAPPER"
chmod 755 "$WRAPPER"
ok "Đã cài wrapper: ${WRAPPER}"

if [[ -f "$OUT_FILE" ]]; then
    cp -a "$OUT_FILE" "${OUT_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
    info "Đã sao lưu drop-in cũ."
fi
printf '%s' "$CONTENT" > "$OUT_FILE"
chmod 644 "$OUT_FILE"
ok "Đã ghi drop-in: ${OUT_FILE}"

if [[ $CLEAN_LEGACY -eq 1 ]]; then
    legacy="${CONF_DIR}/inir-theme.conf"
    if [[ -f "$legacy" ]]; then
        cp -a "$legacy" "${legacy}.bak.$(date +%Y%m%d-%H%M%S)"
        sed -i -E '/^[[:space:]]*DisplayServer[[:space:]]*=[[:space:]]*x11[[:space:]]*$/d;/^[[:space:]]*InputMethod[[:space:]]*=[[:space:]]*$/d' "$legacy"
        ok "Đã gỡ DisplayServer=x11 / InputMethod= khỏi ${legacy}"
    else
        info "Không có ${legacy}, bỏ qua."
    fi
fi

if card="$(bash "$WRAPPER" --print-card)"; then
    ok "Ngay bây giờ wrapper sẽ chọn: $card"
else
    warn "Ngay bây giờ wrapper chưa chọn được card (bình thường nếu đang trong chroot/VM)."
fi

cat <<EOF

Xong. Bước tiếp theo:
  1. Reboot (hoặc: sudo systemctl restart sddm — sẽ đóng phiên đang chạy).
  2. Xem wrapper đã chọn card nào lúc boot:
       journalctl -b -u sddm --no-pager | grep -E 'sddm-weston-auto|pixman|weston'
     Dòng có "pixman" nghĩa là Weston rơi về render bằng CPU (lag), không dùng GPU.
  3. Gỡ khi không cần: sudo bash $0 --uninstall
EOF
