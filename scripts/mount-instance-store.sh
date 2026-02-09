#!/bin/bash
# ============================================================
# AWS EC2 Instance Store Auto-Mount Script
# Version: 5.1
# Author: Albert Yu
# Description: 自動偵測並掛載 EC2 Instance Store (NVMe SSD)
#              支援單獨掛載、RAID 0 模式、動態/靜態掛載點
#              整合 v1-v4 所有功能並加強
# ============================================================
#
# 執行說明:
# 1. 將腳本上傳到 EC2 實例，建議放置路徑: /usr/local/bin/mount-instance-store
# 2. 使用 install.sh 自動安裝，或手動設定 systemd 服務
# 3. 執行: sudo mount-instance-store
# 4. 日誌存放: /var/log/instance-store-mount.log
#
# 開機執行方式 (建議使用 Systemd):
# - Systemd: systemctl enable instance-store-mount.service
# - Cron: @reboot /usr/local/bin/mount-instance-store
# - rc.local: 在 /etc/rc.local 中添加腳本路徑
#
# ============================================================

set -euo pipefail

# 腳本所在目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 預設配置檔路徑 (可透過 -c 參數覆蓋，載入在 parse_arguments 之後)
CONFIG_FILE="${CONFIG_FILE:-/etc/instance-store-mount/mount-instance-store.conf}"

# ============================================================
# 預設配置值
# ============================================================

# 掛載模式: single (個別掛載) 或 raid0 (組成 RAID 0)
MOUNT_MODE="${MOUNT_MODE:-single}"

# 是否使用動態生成掛載點
DYNAMIC_MOUNT="${DYNAMIC_MOUNT:-true}"

# 靜態掛載點陣列 (當 DYNAMIC_MOUNT=false 時使用)
# 以空格分隔，例如: "/mnt/data1 /mnt/data2 /mnt/data3"
MOUNT_POINTS="${MOUNT_POINTS:-/mnt/instance_store1 /mnt/instance_store2 /mnt/instance_store3 /mnt/instance_store4}"

# 掛載點基礎路徑 (動態生成時使用)
BASE_MOUNT_POINT="${BASE_MOUNT_POINT:-/mnt/instance_store}"

# RAID 0 模式的掛載點
RAID_MOUNT_POINT="${RAID_MOUNT_POINT:-/mnt/instance_store}"

# RAID 裝置名稱
RAID_DEVICE="${RAID_DEVICE:-/dev/md0}"

# 檔案系統類型: ext4 或 xfs
FILESYSTEM_TYPE="${FILESYSTEM_TYPE:-ext4}"

# 日誌檔案路徑
LOG_FILE="${LOG_FILE:-/var/log/instance-store-mount.log}"

# 掛載選項
MOUNT_OPTIONS="${MOUNT_OPTIONS:-defaults,noatime,nodiratime}"

# 格式化選項 (ext4)
EXT4_FORMAT_OPTIONS="${EXT4_FORMAT_OPTIONS:--E lazy_itable_init=0,lazy_journal_init=0}"

# 格式化選項 (xfs)
XFS_FORMAT_OPTIONS="${XFS_FORMAT_OPTIONS:--K}"

# RAID chunk size (KB)
RAID_CHUNK_SIZE="${RAID_CHUNK_SIZE:-256}"

# 是否在格式化前清除裝置
WIPE_DEVICE_BEFORE_FORMAT="${WIPE_DEVICE_BEFORE_FORMAT:-false}"

# 是否嚴格比對掛載點數量與 Instance Store 數量
STRICT_MOUNT_POINT_CHECK="${STRICT_MOUNT_POINT_CHECK:-false}"

# 郵件通知設定
ENABLE_EMAIL_NOTIFICATION="${ENABLE_EMAIL_NOTIFICATION:-false}"
EMAIL_SENDER="${EMAIL_SENDER:-noreply@example.com}"
EMAIL_RECIPIENTS="${EMAIL_RECIPIENTS:-admin@example.com}"
SMTP_SERVER="${SMTP_SERVER:-email-smtp.us-east-1.amazonaws.com}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_USER="${SMTP_USER:-}"
SMTP_PASSWORD="${SMTP_PASSWORD:-}"

# 執行完成後呼叫的腳本 (可選)
POST_MOUNT_SCRIPT="${POST_MOUNT_SCRIPT:-}"

# 模擬執行模式
DRY_RUN="${DRY_RUN:-false}"

# ============================================================
# 全域變數
# ============================================================

declare -a INSTANCE_STORE_DEVICES=()
INSTANCE_STORE_COUNT=0
INSTANCE_ID=""
INSTANCE_TYPE=""
AVAILABILITY_ZONE=""
REGION=""
ACCOUNT_ID=""
START_TIME=""
END_TIME=""

# 顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================
# 函數定義
# ============================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # 確保日誌目錄存在
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"

    # 終端輸出 (帶顏色)
    case "$level" in
        INFO)
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        DEBUG)
            echo -e "${BLUE}[DEBUG]${NC} $message"
            ;;
    esac
}

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log ERROR "此腳本需要 root 權限執行"
        log ERROR "請使用: sudo $0"
        exit 1
    fi
    log INFO "Root 權限驗證通過"
}

check_dependencies() {
    local deps=("lsblk" "blkid" "mount" "umount" "curl")
    local missing=()

    # 根據檔案系統類型檢查
    case "$FILESYSTEM_TYPE" in
        ext4) deps+=("mkfs.ext4") ;;
        xfs) deps+=("mkfs.xfs") ;;
    esac

    # RAID 模式需要 mdadm
    if [[ "$MOUNT_MODE" == "raid0" ]]; then
        deps+=("mdadm")
    fi

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log ERROR "缺少必要工具: ${missing[*]}"
        log ERROR "請先安裝: sudo yum install -y mdadm nvme-cli 或 sudo apt install -y mdadm nvme-cli"
        exit 1
    fi

    log INFO "依賴檢查通過"
}

get_imdsv2_token() {
    local token
    token=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
        --connect-timeout 2 2>/dev/null) || true
    echo "$token"
}

get_instance_metadata() {
    local token="$1"
    local metadata_path="$2"

    if [[ -n "$token" ]]; then
        curl -s -H "X-aws-ec2-metadata-token: $token" \
            "http://169.254.169.254/latest/$metadata_path" \
            --connect-timeout 2 2>/dev/null || echo ""
    else
        curl -s "http://169.254.169.254/latest/$metadata_path" \
            --connect-timeout 2 2>/dev/null || echo ""
    fi
}

collect_instance_info() {
    log INFO "收集 EC2 實例資訊..."

    local token
    token=$(get_imdsv2_token)

    if [[ -z "$token" ]]; then
        log WARN "無法獲取 IMDSv2 令牌，嘗試使用 IMDSv1"
    fi

    INSTANCE_ID=$(get_instance_metadata "$token" "meta-data/instance-id")
    INSTANCE_TYPE=$(get_instance_metadata "$token" "meta-data/instance-type")
    AVAILABILITY_ZONE=$(get_instance_metadata "$token" "meta-data/placement/availability-zone")
    # 移除尾端所有小寫字母 (如 ap-northeast-1a -> ap-northeast-1)
    REGION=$(echo "$AVAILABILITY_ZONE" | sed 's/[a-z]*$//')

    local identity_doc
    identity_doc=$(get_instance_metadata "$token" "dynamic/instance-identity/document")
    ACCOUNT_ID=$(echo "$identity_doc" | grep -o '"accountId"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")

    log INFO "Instance ID: ${INSTANCE_ID:-N/A}"
    log INFO "Instance Type: ${INSTANCE_TYPE:-N/A}"
    log INFO "Availability Zone: ${AVAILABILITY_ZONE:-N/A}"
    log INFO "Region: ${REGION:-N/A}"
    log INFO "Account ID: ${ACCOUNT_ID:-N/A}"
}

detect_instance_stores() {
    log INFO "偵測 Instance Store 裝置..."

    local devices=()

    # 方法 1: 透過 lsblk MODEL 欄位偵測 "Instance Storage"
    while IFS= read -r line; do
        [[ -n "$line" ]] && devices+=("$line")
    done < <(lsblk -d -o NAME,MODEL 2>/dev/null | grep -i "Instance Storage" | awk '{print $1}')

    # 方法 2: 透過 nvme list 命令偵測 (如果方法 1 沒有結果)
    if [[ ${#devices[@]} -eq 0 ]] && command -v nvme &> /dev/null; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && devices+=("$line")
        done < <(nvme list 2>/dev/null | grep -i "Instance Storage" | awk '{print $1}' | sed 's|/dev/||')
    fi

    # 方法 3: 檢查 /dev/nvme*n1 裝置並排除 EBS (最後手段)
    if [[ ${#devices[@]} -eq 0 ]]; then
        for dev in /dev/nvme*n1; do
            [[ ! -b "$dev" ]] && continue
            local dev_name
            dev_name=$(basename "$dev")
            # 檢查是否為 EBS 裝置
            local model
            model=$(cat "/sys/block/$dev_name/device/model" 2>/dev/null | tr -d ' ')
            if [[ "$model" != "AmazonElasticBlockStore" ]] && [[ "$model" != *"EBS"* ]]; then
                devices+=("$dev_name")
            fi
        done
    fi

    # 去重並排序
    mapfile -t INSTANCE_STORE_DEVICES < <(printf '%s\n' "${devices[@]}" | sort -u)
    INSTANCE_STORE_COUNT=${#INSTANCE_STORE_DEVICES[@]}

    log INFO "偵測到 $INSTANCE_STORE_COUNT 個 Instance Store 裝置"

    if [[ $INSTANCE_STORE_COUNT -eq 0 ]]; then
        log WARN "未偵測到任何 Instance Store 裝置"
        return 1
    fi

    # 收集並顯示裝置資訊
    local sizes=""
    for dev in "${INSTANCE_STORE_DEVICES[@]}"; do
        local size
        size=$(lsblk -d -o SIZE "/dev/$dev" 2>/dev/null | tail -1 | tr -d ' ')
        log INFO "  - /dev/$dev (${size:-unknown})"
        if [[ -n "$sizes" ]]; then
            sizes="${sizes},${size:-N/A}"
        else
            sizes="${size:-N/A}"
        fi
    done

    log INFO "Instance Store 總大小: $sizes"

    return 0
}

unmount_existing() {
    log INFO "檢查並解除現有掛載..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] 將解除現有掛載 (跳過實際操作)"
        return 0
    fi

    # 解除 RAID 裝置
    if [[ -b "$RAID_DEVICE" ]]; then
        if mount | grep -q "$RAID_DEVICE"; then
            umount "$RAID_DEVICE" 2>/dev/null || true
            log INFO "已解除 $RAID_DEVICE 掛載"
        fi
        mdadm --stop "$RAID_DEVICE" 2>/dev/null || true
        log INFO "已停止 RAID 裝置 $RAID_DEVICE"
    fi

    # 解除各個 Instance Store 的掛載 (根據 mount 輸出)
    local mounted_points
    mounted_points=$(mount | grep -i "Instance Storage" | awk '{print $3}' 2>/dev/null || true)

    for mounted_point in $mounted_points; do
        if [[ -n "$mounted_point" ]]; then
            umount "$mounted_point" 2>/dev/null || true
            log INFO "已解除 Instance Store 從 $mounted_point 的掛載"
        fi
    done

    # 解除各個 Instance Store 的掛載 (根據裝置)
    for dev in "${INSTANCE_STORE_DEVICES[@]}"; do
        if mount | grep -q "/dev/$dev"; then
            local mount_point
            mount_point=$(mount | grep "/dev/$dev" | awk '{print $3}')
            umount "/dev/$dev" 2>/dev/null || true
            log INFO "已解除 /dev/$dev 從 $mount_point 的掛載"
        fi
    done

    # 僅在 RAID 模式下清除 superblock (避免 single 模式不必要的 mdadm 呼叫)
    if [[ "$MOUNT_MODE" == "raid0" ]] && command -v mdadm &> /dev/null; then
        for dev in "${INSTANCE_STORE_DEVICES[@]}"; do
            mdadm --zero-superblock "/dev/$dev" 2>/dev/null || true
        done
    fi
}

format_device() {
    local device="$1"
    local fs_type="${2:-$FILESYSTEM_TYPE}"

    log INFO "格式化裝置 $device 為 $fs_type..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] 將格式化 $device 為 $fs_type (跳過實際操作)"
        return 0
    fi

    # 選擇性清除裝置
    if [[ "$WIPE_DEVICE_BEFORE_FORMAT" == "true" ]]; then
        log INFO "清除裝置 $device..."
        wipefs -a "$device" 2>/dev/null || true
    fi

    local mkfs_output
    case "$fs_type" in
        ext4)
            if ! mkfs_output=$(mkfs.ext4 -F $EXT4_FORMAT_OPTIONS "$device" 2>&1); then
                log ERROR "格式化 $device 為 ext4 失敗: $mkfs_output"
                return 1
            fi
            ;;
        xfs)
            if ! mkfs_output=$(mkfs.xfs -f $XFS_FORMAT_OPTIONS "$device" 2>&1); then
                log ERROR "格式化 $device 為 xfs 失敗: $mkfs_output"
                return 1
            fi
            ;;
        *)
            log ERROR "不支援的檔案系統類型: $fs_type"
            return 1
            ;;
    esac

    log DEBUG "mkfs 輸出: $mkfs_output"
    log INFO "裝置 $device 格式化完成"
    return 0
}

generate_mount_points() {
    local -n mount_points_ref=$1

    if [[ "$DYNAMIC_MOUNT" == "true" ]]; then
        # 動態生成掛載點
        log INFO "使用動態掛載點模式"
        mount_points_ref=()
        for i in $(seq 1 $INSTANCE_STORE_COUNT); do
            mount_points_ref+=("${BASE_MOUNT_POINT}${i}")
        done
    else
        # 使用靜態掛載點
        log INFO "使用靜態掛載點模式"
        IFS=' ' read -ra mount_points_ref <<< "$MOUNT_POINTS"

        # 嚴格比對檢查
        if [[ "$STRICT_MOUNT_POINT_CHECK" == "true" ]]; then
            local mount_point_count=${#mount_points_ref[@]}
            if [[ "$mount_point_count" -ne "$INSTANCE_STORE_COUNT" ]]; then
                log ERROR "掛載點數量 ($mount_point_count) 與 Instance Store 數量 ($INSTANCE_STORE_COUNT) 不符"
                log ERROR "請調整 MOUNT_POINTS 設定或將 STRICT_MOUNT_POINT_CHECK 設為 false"
                exit 1
            fi
        fi
    fi

    log INFO "設定的掛載點: ${mount_points_ref[*]}"
}

mount_single_mode() {
    log INFO "使用單獨掛載模式..."

    local -a mount_points_array
    generate_mount_points mount_points_array

    local idx=0
    for dev in "${INSTANCE_STORE_DEVICES[@]}"; do
        if [[ $idx -ge ${#mount_points_array[@]} ]]; then
            log WARN "掛載點不足，剩餘裝置未掛載: /dev/$dev"
            break
        fi

        local device="/dev/$dev"
        local mount_point="${mount_points_array[$idx]}"

        # 建立掛載點目錄
        if [[ ! -d "$mount_point" ]]; then
            mkdir -p "$mount_point"
            log INFO "建立掛載點目錄: $mount_point"
        fi

        # 檢查是否需要格式化
        local current_fs
        current_fs=$(blkid -o value -s TYPE "$device" 2>/dev/null || echo "")

        if [[ "$current_fs" != "$FILESYSTEM_TYPE" ]]; then
            if ! format_device "$device" "$FILESYSTEM_TYPE"; then
                log ERROR "格式化 $device 失敗，跳過此裝置"
                ((idx++))
                continue
            fi
        else
            log INFO "裝置 $device 已經是 $FILESYSTEM_TYPE 格式"
        fi

        # 掛載
        if [[ "$DRY_RUN" == "true" ]]; then
            log INFO "[DRY-RUN] 將掛載 $device 到 $mount_point (跳過實際操作)"
        elif mount -o "$MOUNT_OPTIONS" "$device" "$mount_point"; then
            log INFO "成功掛載 $device 到 $mount_point"

            # 設定權限 (sticky bit，允許所有用戶寫入)
            chmod 1777 "$mount_point"
        else
            log ERROR "掛載 $device 到 $mount_point 失敗"
        fi

        ((idx++))
    done
}

mount_raid0_mode() {
    log INFO "使用 RAID 0 模式..."

    if [[ $INSTANCE_STORE_COUNT -lt 1 ]]; then
        log ERROR "RAID 0 模式至少需要 1 個裝置"
        return 1
    fi

    # 準備裝置路徑
    local device_paths=()
    for dev in "${INSTANCE_STORE_DEVICES[@]}"; do
        device_paths+=("/dev/$dev")
    done

    # 建立 RAID 陣列
    log INFO "建立 RAID 0 陣列，包含 $INSTANCE_STORE_COUNT 個裝置..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] 將建立 RAID 0: ${device_paths[*]} -> $RAID_DEVICE"
        log INFO "[DRY-RUN] 將格式化 $RAID_DEVICE 為 $FILESYSTEM_TYPE"
        log INFO "[DRY-RUN] 將掛載 $RAID_DEVICE 到 $RAID_MOUNT_POINT"
        return 0
    fi

    # 使用 yes 自動確認
    if ! yes | mdadm --create "$RAID_DEVICE" \
        --level=0 \
        --raid-devices="$INSTANCE_STORE_COUNT" \
        --chunk="$RAID_CHUNK_SIZE" \
        "${device_paths[@]}" 2>&1; then
        log ERROR "建立 RAID 陣列失敗"
        return 1
    fi

    log INFO "RAID 0 陣列建立成功: $RAID_DEVICE"

    # 格式化 RAID 裝置
    if ! format_device "$RAID_DEVICE" "$FILESYSTEM_TYPE"; then
        log ERROR "格式化 RAID 裝置失敗"
        return 1
    fi

    # 建立掛載點
    if [[ ! -d "$RAID_MOUNT_POINT" ]]; then
        mkdir -p "$RAID_MOUNT_POINT"
        log INFO "建立掛載點目錄: $RAID_MOUNT_POINT"
    fi

    # 掛載
    if mount -o "$MOUNT_OPTIONS" "$RAID_DEVICE" "$RAID_MOUNT_POINT"; then
        log INFO "成功掛載 RAID 陣列到 $RAID_MOUNT_POINT"
        chmod 1777 "$RAID_MOUNT_POINT"
    else
        log ERROR "掛載 RAID 陣列失敗"
        return 1
    fi

    # 顯示 RAID 資訊
    log INFO "RAID 陣列詳細資訊:"
    mdadm --detail "$RAID_DEVICE" >> "$LOG_FILE" 2>&1

    return 0
}

show_mount_status() {
    log INFO "=========================================="
    log INFO "掛載狀態摘要"
    log INFO "=========================================="

    if [[ "$MOUNT_MODE" == "raid0" ]] && mount | grep -q "$RAID_DEVICE"; then
        local size used avail use_pct
        read -r _ size used avail use_pct _ < <(df -h "$RAID_MOUNT_POINT" 2>/dev/null | tail -1)
        log INFO "RAID 0 掛載點: $RAID_MOUNT_POINT"
        log INFO "  總容量: ${size:-N/A}"
        log INFO "  已使用: ${used:-N/A} (${use_pct:-N/A})"
        log INFO "  可用: ${avail:-N/A}"
    else
        # 顯示所有 instance_store 掛載點
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                local fs mp size used avail use_pct
                read -r fs size used avail use_pct mp <<< "$line"
                log INFO "掛載點: $mp"
                log INFO "  裝置: $fs"
                log INFO "  總容量: $size"
                log INFO "  已使用: $used ($use_pct)"
                log INFO "  可用: $avail"
            fi
        done < <(df -h 2>/dev/null | grep -E "instance_store|$BASE_MOUNT_POINT")
    fi

    log INFO "=========================================="
}

send_email_notification() {
    if [[ "$ENABLE_EMAIL_NOTIFICATION" != "true" ]]; then
        return 0
    fi

    log INFO "發送郵件通知..."

    local subject="[AWS Instance Store] 掛載完成通知 - ${INSTANCE_ID:-unknown}"

    # 使用 awk 過濾出本次執行的日誌
    local email_body
    email_body=$(awk -v start="$START_TIME" -v end="$END_TIME" \
        '$0 ~ start, $0 ~ end' "$LOG_FILE" 2>/dev/null || cat "$LOG_FILE")

    # 建立臨時郵件檔案
    local temp_mail_file
    temp_mail_file=$(mktemp)

    cat > "$temp_mail_file" << EOF
Subject: $subject
From: $EMAIL_SENDER
To: $EMAIL_RECIPIENTS

AWS Instance Store 掛載腳本執行完成

執行時間: $START_TIME ~ $END_TIME
Instance ID: ${INSTANCE_ID:-N/A}
Instance Type: ${INSTANCE_TYPE:-N/A}
Region: ${REGION:-N/A}

掛載模式: $MOUNT_MODE
Instance Store 數量: $INSTANCE_STORE_COUNT

=== 執行日誌 ===
$email_body

=== 掛載狀態 ===
$(df -h 2>/dev/null | grep -E "instance_store|$BASE_MOUNT_POINT" || echo "N/A")
EOF

    # 發送郵件
    if command -v sendmail &> /dev/null; then
        local mail_failed=false
        for recipient in $EMAIL_RECIPIENTS; do
            local send_result=0
            if [[ -n "$SMTP_USER" ]] && [[ -n "$SMTP_PASSWORD" ]]; then
                sendmail -f "$EMAIL_SENDER" -S "${SMTP_SERVER}:${SMTP_PORT}" \
                    -au "$SMTP_USER" -ap "$SMTP_PASSWORD" \
                    "$recipient" < "$temp_mail_file" 2>/dev/null || send_result=$?
            else
                sendmail -f "$EMAIL_SENDER" "$recipient" < "$temp_mail_file" 2>/dev/null || send_result=$?
            fi

            if [[ $send_result -ne 0 ]]; then
                log WARN "郵件發送至 $recipient 失敗"
                mail_failed=true
            fi
        done

        if [[ "$mail_failed" == "false" ]]; then
            log INFO "郵件通知已全部發送"
        fi
    else
        log WARN "sendmail 未安裝，跳過郵件通知"
    fi

    # 清理臨時檔案
    rm -f "$temp_mail_file"
}

run_post_mount_script() {
    if [[ -n "$POST_MOUNT_SCRIPT" ]] && [[ -x "$POST_MOUNT_SCRIPT" ]]; then
        log INFO "執行後置腳本: $POST_MOUNT_SCRIPT"
        if "$POST_MOUNT_SCRIPT"; then
            log INFO "後置腳本執行成功"
        else
            log WARN "後置腳本執行失敗"
        fi
    fi
}

cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log ERROR "腳本執行失敗，退出碼: $exit_code"
    fi
}

show_usage() {
    cat << EOF
用法: $(basename "$0") [選項]

選項:
    -h, --help          顯示此幫助訊息
    -c, --config FILE   指定配置檔路徑
    -m, --mode MODE     掛載模式: single 或 raid0
    -f, --filesystem FS 檔案系統類型: ext4 或 xfs
    -d, --dynamic       使用動態掛載點
    -s, --static        使用靜態掛載點
    --dry-run           模擬執行，不實際掛載

範例:
    $(basename "$0")                        # 使用預設配置
    $(basename "$0") -m raid0               # 使用 RAID 0 模式
    $(basename "$0") -c /path/to/config     # 使用指定配置檔
    $(basename "$0") -m single -f xfs       # 單獨掛載，使用 XFS

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -m|--mode)
                MOUNT_MODE="$2"
                shift 2
                ;;
            -f|--filesystem)
                FILESYSTEM_TYPE="$2"
                shift 2
                ;;
            -d|--dynamic)
                DYNAMIC_MOUNT="true"
                shift
                ;;
            -s|--static)
                DYNAMIC_MOUNT="false"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            *)
                log ERROR "未知選項: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# ============================================================
# 主程式
# ============================================================

main() {
    trap cleanup_on_exit EXIT

    START_TIME=$(date '+%Y-%m-%d %H:%M:%S')

    log INFO "=========================================="
    log INFO "AWS Instance Store 掛載腳本啟動"
    log INFO "版本: 5.1"
    log INFO "開始時間: $START_TIME"
    if [[ "$DRY_RUN" == "true" ]]; then
        log WARN "模擬執行模式 (DRY-RUN) - 不會執行實際操作"
    fi
    log INFO "=========================================="

    # 前置檢查
    check_root
    check_dependencies

    # 收集實例資訊
    collect_instance_info

    # 偵測 Instance Store
    if ! detect_instance_stores; then
        log WARN "沒有可用的 Instance Store，腳本結束"
        exit 0
    fi

    # 解除現有掛載
    unmount_existing

    # 根據模式執行掛載
    log INFO "掛載模式: $MOUNT_MODE"
    log INFO "檔案系統: $FILESYSTEM_TYPE"

    case "$MOUNT_MODE" in
        single)
            mount_single_mode
            ;;
        raid0)
            mount_raid0_mode
            ;;
        *)
            log ERROR "不支援的掛載模式: $MOUNT_MODE"
            exit 1
            ;;
    esac

    # 顯示狀態
    show_mount_status

    END_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    log INFO "腳本執行完成: $END_TIME"

    # 發送通知
    send_email_notification

    # 執行後置腳本
    run_post_mount_script
}

# 解析命令列參數
parse_arguments "$@"

# 載入配置檔 (在 parse_arguments 之後，讓 -c 參數能覆蓋預設路徑)
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# 命令列參數優先於配置檔，重新套用
parse_arguments "$@"

# 執行主程式
main
