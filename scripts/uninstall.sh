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

# 詢問是否解除 Instance Store 掛載
active_mounts=$(mount 2>/dev/null | grep -E "instance_store|/dev/md0" | awk '{print $3}' || true)
if [[ -n "$active_mounts" ]]; then
    echo ""
    echo -e "${YELLOW}[WARN]${NC} 偵測到以下 Instance Store 掛載點仍在使用中:"
    echo "$active_mounts"
    read -p "是否解除這些掛載？(y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        for mp in $active_mounts; do
            umount "$mp" 2>/dev/null && echo -e "${GREEN}[INFO]${NC} 已解除掛載: $mp" \
                || echo -e "${YELLOW}[WARN]${NC} 無法解除掛載: $mp (可能仍有程序使用中)"
        done
        # 停止 RAID 裝置
        if [[ -b /dev/md0 ]]; then
            mdadm --stop /dev/md0 2>/dev/null && echo -e "${GREEN}[INFO]${NC} 已停止 RAID 裝置 /dev/md0" || true
        fi
    fi
fi

# 詢問是否移除日誌檔案
read -p "是否移除日誌檔案？(y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -f /var/log/instance-store-mount.log
    echo -e "${GREEN}[INFO]${NC} 日誌檔案已移除"
else
    echo -e "${YELLOW}[INFO]${NC} 日誌檔案保留於: /var/log/instance-store-mount.log"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}解除安裝完成！${NC}"
echo -e "${GREEN}========================================${NC}"
