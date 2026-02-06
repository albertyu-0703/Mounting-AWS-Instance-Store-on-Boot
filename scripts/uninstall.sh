#!/bin/bash
# ============================================================
# AWS Instance Store Mount - 解除安裝腳本
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/instance-store-mount"
SYSTEMD_DIR="/etc/systemd/system"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}AWS Instance Store Mount 解除安裝程式${NC}"
echo -e "${BLUE}========================================${NC}"

if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} 請使用 root 權限執行此腳本"
    exit 1
fi

# 確認解除安裝
read -p "確定要解除安裝 Instance Store Mount 嗎？(y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "取消解除安裝"
    exit 0
fi

# 停用並移除 systemd 服務
echo -e "${GREEN}[INFO]${NC} 移除 systemd 服務..."
systemctl stop instance-store-mount.service 2>/dev/null || true
systemctl disable instance-store-mount.service 2>/dev/null || true
rm -f "$SYSTEMD_DIR/instance-store-mount.service"
systemctl daemon-reload

# 移除 udev 規則
echo -e "${GREEN}[INFO]${NC} 移除 udev 規則..."
rm -f /etc/udev/rules.d/99-instance-store.rules
udevadm control --reload-rules 2>/dev/null || true

# 移除腳本
echo -e "${GREEN}[INFO]${NC} 移除腳本..."
rm -f "$INSTALL_DIR/mount-instance-store"

# 詢問是否保留設定檔
read -p "是否保留設定檔？(Y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    rm -rf "$CONFIG_DIR"
    echo -e "${GREEN}[INFO]${NC} 設定檔已移除"
else
    echo -e "${YELLOW}[INFO]${NC} 設定檔保留於: $CONFIG_DIR"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}解除安裝完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "注意: 日誌檔案保留於 /var/log/instance-store-mount.log"
echo "注意: 已掛載的 Instance Store 需手動解除掛載"
