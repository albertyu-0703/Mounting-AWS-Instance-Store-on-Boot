#!/bin/bash
# ============================================================
# AWS Instance Store Mount - 安裝腳本
# ============================================================

set -euo pipefail

# 顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/instance-store-mount"
SYSTEMD_DIR="/etc/systemd/system"
LOG_DIR="/var/log"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}AWS Instance Store Mount 安裝程式${NC}"
echo -e "${BLUE}========================================${NC}"

# 檢查 root 權限
if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} 請使用 root 權限執行此腳本"
    echo "使用方式: sudo $0"
    exit 1
fi

# 檢測作業系統
detect_os() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif [[ -f /etc/redhat-release ]]; then
        OS="rhel"
    else
        OS="unknown"
    fi
    echo -e "${GREEN}[INFO]${NC} 偵測到作業系統: $OS ${OS_VERSION:-}"
}

# 安裝依賴
install_dependencies() {
    echo -e "${GREEN}[INFO]${NC} 檢查並安裝依賴..."

    case "$OS" in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y -qq mdadm nvme-cli curl
            ;;
        amzn|rhel|centos|rocky|fedora)
            if command -v dnf &> /dev/null; then
                dnf install -y -q mdadm nvme-cli curl
            else
                yum install -y -q mdadm nvme-cli curl
            fi
            ;;
        *)
            echo -e "${YELLOW}[WARN]${NC} 未知的作業系統，請手動安裝: mdadm, nvme-cli, curl"
            ;;
    esac
}

# 建立目錄結構
create_directories() {
    echo -e "${GREEN}[INFO]${NC} 建立目錄結構..."
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"
}

# 檢查必要的來源檔案
check_source_files() {
    local required_files=(
        "$PROJECT_DIR/scripts/mount-instance-store.sh"
        "$PROJECT_DIR/config/mount-instance-store.conf"
        "$PROJECT_DIR/systemd/instance-store-mount.service"
    )

    for f in "${required_files[@]}"; do
        if [[ ! -f "$f" ]]; then
            echo -e "${RED}[ERROR]${NC} 找不到必要檔案: $f"
            echo "請確認從完整的專案目錄執行安裝腳本"
            exit 1
        fi
    done
    echo -e "${GREEN}[INFO]${NC} 來源檔案檢查通過"
}

# 安裝腳本
install_scripts() {
    echo -e "${GREEN}[INFO]${NC} 安裝腳本..."

    # 複製主腳本
    cp "$PROJECT_DIR/scripts/mount-instance-store.sh" "$INSTALL_DIR/mount-instance-store"
    chmod +x "$INSTALL_DIR/mount-instance-store"

    # 複製設定檔 (如果不存在)
    if [[ ! -f "$CONFIG_DIR/mount-instance-store.conf" ]]; then
        cp "$PROJECT_DIR/config/mount-instance-store.conf" "$CONFIG_DIR/"
        echo -e "${GREEN}[INFO]${NC} 已安裝預設設定檔"
    else
        echo -e "${YELLOW}[WARN]${NC} 設定檔已存在，保留現有設定"
        # 備份新版設定檔供參考
        cp "$PROJECT_DIR/config/mount-instance-store.conf" "$CONFIG_DIR/mount-instance-store.conf.new"
    fi
}

# 安裝 systemd 服務
install_systemd_service() {
    echo -e "${GREEN}[INFO]${NC} 安裝 systemd 服務..."

    # 使用 repo 中的 systemd unit 檔案 (包含完整的重試、逾時等設定)
    cp "$PROJECT_DIR/systemd/instance-store-mount.service" "$SYSTEMD_DIR/instance-store-mount.service"

    # 重新載入 systemd
    systemctl daemon-reload

    # 啟用服務
    systemctl enable instance-store-mount.service

    echo -e "${GREEN}[INFO]${NC} systemd 服務已安裝並啟用"
}

# 安裝 udev 規則 (可選，用於熱插拔)
install_udev_rules() {
    echo -e "${GREEN}[INFO]${NC} 安裝 udev 規則..."

    cat > /etc/udev/rules.d/99-instance-store.rules << 'EOF'
# AWS EC2 Instance Store NVMe 裝置規則
# 當偵測到新的 Instance Store 時觸發掛載腳本

ACTION=="add", SUBSYSTEM=="block", ENV{ID_MODEL}=="Amazon EC2 NVMe Instance Storage", \
    RUN+="/usr/local/bin/mount-instance-store"
EOF

    udevadm control --reload-rules
}

# 顯示安裝資訊
show_install_info() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}安裝完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "安裝位置:"
    echo "  腳本: $INSTALL_DIR/mount-instance-store"
    echo "  設定: $CONFIG_DIR/mount-instance-store.conf"
    echo "  服務: $SYSTEMD_DIR/instance-store-mount.service"
    echo "  日誌: $LOG_DIR/instance-store-mount.log"
    echo ""
    echo "使用方式:"
    echo "  1. 編輯設定檔:"
    echo "     sudo vim $CONFIG_DIR/mount-instance-store.conf"
    echo ""
    echo "  2. 手動執行:"
    echo "     sudo mount-instance-store"
    echo ""
    echo "  3. 服務管理:"
    echo "     sudo systemctl status instance-store-mount"
    echo "     sudo systemctl start instance-store-mount"
    echo "     sudo systemctl restart instance-store-mount"
    echo ""
    echo "  4. 查看日誌:"
    echo "     sudo tail -f $LOG_DIR/instance-store-mount.log"
    echo "     sudo journalctl -u instance-store-mount"
    echo ""
}

# 主程式
main() {
    detect_os
    check_source_files
    install_dependencies
    create_directories
    install_scripts
    install_systemd_service
    install_udev_rules
    show_install_info
}

main "$@"
