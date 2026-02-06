#!/bin/bash
# ============================================================
# AWS EC2 Instance Store 自動掛載腳本 (V5)
# ============================================================
#
# 【腳本說明】
# 這是一個功能完整的 Instance Store 自動掛載解決方案。
# 相較於 V4 版本，V5 提供了更多進階功能：
# - RAID 0 模式：將多個 Instance Store 組合成單一高速陣列
# - XFS 支援：除了 ext4，還支援高效能的 XFS 檔案系統
# - 外部配置檔：設定與程式碼分離，方便管理
# - 命令列參數：可在執行時覆蓋配置
# - 模組化設計：程式碼分成多個函數，易於維護
#
# 【什麼是 Instance Store？】
# Instance Store 是 EC2 實例本地的 NVMe SSD 儲存空間。
# 特點：
# - 極高的 I/O 效能（比 EBS 快很多）
# - 資料是「暫時性」的（實例停止時資料會遺失）
# - 包含在 EC2 費用中，無額外費用
# - 適合：快取、暫存檔、資料處理中間結果
#
# 【適用的 EC2 類型】
# 只有特定類型的 EC2 才有 Instance Store：
# - c5d、m5d、r5d 系列（名稱中帶 d）
# - i3、i3en 系列（儲存優化型）
# - d2、d3 系列（高密度儲存型）
#
# 【執行方式】
# 1. 使用安裝腳本：sudo bash scripts/install.sh
# 2. 手動執行：sudo ./mount-instance-store.sh
# 3. 使用命令列參數：sudo ./mount-instance-store.sh -m raid0 -f xfs
#
# 【版本資訊】
# 版本：5.0
# 作者：Albert Yu
# ============================================================


# ============================================================
# 【Bash 嚴格模式設定】
# ============================================================
# set 指令用來設定 Shell 的行為
#
# -e (errexit)：當任何指令執行失敗時，立即退出腳本
#    這可以防止錯誤被忽略，讓問題更容易被發現
#
# -u (nounset)：當使用未定義的變數時，顯示錯誤並退出
#    這可以避免因為打錯變數名稱而造成的問題
#
# -o pipefail：管線中任何指令失敗時，整個管線就算失敗
#    預設情況下，管線的退出碼是最後一個指令的退出碼
#    加上這個選項後，只要有一個指令失敗，管線就算失敗
# ============================================================
set -euo pipefail


# ============================================================
# 【區塊一】取得腳本所在目錄
# ============================================================
# 這段程式碼用來取得腳本檔案所在的目錄路徑
# 不論從哪裡執行腳本，都能正確找到相關檔案
#
# ${BASH_SOURCE[0]} - 當前腳本的檔案路徑
# dirname           - 取得目錄部分（去掉檔案名稱）
# cd ... && pwd     - 切換到該目錄並顯示完整路徑
# $()               - 命令替換，將指令的輸出存入變數
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# ============================================================
# 【區塊二】載入外部配置檔
# ============================================================
# V5 的特色之一是支援外部配置檔
# 這樣可以將設定與程式碼分開，方便管理和版本控制
#
# ${變數:-預設值} 語法說明：
# 如果 CONFIG_FILE 環境變數已設定，就使用它的值
# 否則使用預設路徑 /etc/instance-store-mount/mount-instance-store.conf
#
# -f 測試檔案是否存在
# source 指令會執行配置檔中的內容，將變數載入到當前環境
#
# shellcheck source=/dev/null 是給 ShellCheck 工具的註解
# 告訴它不要檢查 source 的檔案（因為路徑是動態的）
# ============================================================
CONFIG_FILE="${CONFIG_FILE:-/etc/instance-store-mount/mount-instance-store.conf}"
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi


# ============================================================
# 【區塊三】預設配置值
# ============================================================
# 這裡定義所有可配置的選項和它們的預設值
# 如果配置檔中沒有設定某個選項，就會使用這裡的預設值
#
# ${變數:-預設值} 的作用：
# 1. 如果變數已經有值（可能來自配置檔），保持原值
# 2. 如果變數沒有值，使用預設值
#
# 這種設計讓腳本可以：
# - 完全不用配置檔就能執行（使用預設值）
# - 只在配置檔中設定需要修改的選項
# - 透過環境變數覆蓋設定
# ============================================================

# 【掛載模式】
# single: 每個 Instance Store 個別掛載到不同目錄
#         例如：nvme1n1 → /mnt/instance_store1
#               nvme2n1 → /mnt/instance_store2
#
# raid0:  所有 Instance Store 組成 RAID 0 陣列
#         RAID 0 會將資料分散到多個磁碟，提供更高的讀寫速度
#         但沒有容錯能力，任一磁碟故障就會遺失所有資料
#         由於 Instance Store 本來就是暫時性儲存，RAID 0 是適合的選擇
MOUNT_MODE="${MOUNT_MODE:-single}"

# 【動態掛載點】
# true:  自動產生掛載點 /mnt/instance_store1, /mnt/instance_store2, ...
#        掛載點數量會根據偵測到的 Instance Store 數量自動調整
#
# false: 使用下方 MOUNT_POINTS 指定的固定掛載點
DYNAMIC_MOUNT="${DYNAMIC_MOUNT:-true}"

# 【靜態掛載點】（當 DYNAMIC_MOUNT=false 時使用）
# 以空格分隔多個路徑
# 掛載點會按順序對應到偵測到的 Instance Store
MOUNT_POINTS="${MOUNT_POINTS:-/mnt/instance_store1 /mnt/instance_store2 /mnt/instance_store3 /mnt/instance_store4}"

# 【掛載點基礎路徑】（動態生成時使用）
# 動態生成的掛載點會是：{基礎路徑}1, {基礎路徑}2, ...
BASE_MOUNT_POINT="${BASE_MOUNT_POINT:-/mnt/instance_store}"

# 【RAID 掛載點】（RAID 0 模式專用）
# RAID 陣列會掛載到這個目錄
RAID_MOUNT_POINT="${RAID_MOUNT_POINT:-/mnt/instance_store}"

# 【RAID 裝置名稱】
# Linux 中 RAID 裝置的命名慣例是 /dev/md0, /dev/md1, ...
# md 代表 multiple devices（多重裝置）
RAID_DEVICE="${RAID_DEVICE:-/dev/md0}"

# 【檔案系統類型】
# ext4: Linux 最常用的檔案系統，穩定可靠
# xfs:  適合大檔案和高並發的檔案系統，效能較好
FILESYSTEM_TYPE="${FILESYSTEM_TYPE:-ext4}"

# 【日誌檔案路徑】
# 所有執行記錄都會寫入這個檔案
LOG_FILE="${LOG_FILE:-/var/log/instance-store-mount.log}"

# 【掛載選項】
# defaults:    使用預設的掛載選項
# noatime:     不更新檔案的存取時間，可以減少磁碟寫入，提升效能
# nodiratime:  不更新目錄的存取時間
MOUNT_OPTIONS="${MOUNT_OPTIONS:-defaults,noatime,nodiratime}"

# 【ext4 格式化選項】
# -E lazy_itable_init=0: 延遲初始化 inode 表
# -E lazy_journal_init=0: 延遲初始化日誌
# 這些選項可以加速格式化過程
EXT4_FORMAT_OPTIONS="${EXT4_FORMAT_OPTIONS:--E lazy_itable_init=0,lazy_journal_init=0}"

# 【XFS 格式化選項】
# -K: 不清除舊資料區塊，加速格式化
XFS_FORMAT_OPTIONS="${XFS_FORMAT_OPTIONS:--K}"

# 【RAID chunk size】
# Chunk 是 RAID 分散資料的最小單位（單位：KB）
# 較大的 chunk 適合大檔案循序讀寫
# 較小的 chunk 適合小檔案隨機讀寫
RAID_CHUNK_SIZE="${RAID_CHUNK_SIZE:-256}"

# 【格式化前清除裝置】
# 設為 true 會在格式化前清除裝置上的舊資料
# 這是安全考量，防止舊資料被讀取
WIPE_DEVICE_BEFORE_FORMAT="${WIPE_DEVICE_BEFORE_FORMAT:-false}"

# 【嚴格比對掛載點數量】
# 設為 true 時，如果掛載點數量與 Instance Store 數量不符，會終止腳本
STRICT_MOUNT_POINT_CHECK="${STRICT_MOUNT_POINT_CHECK:-false}"

# 【郵件通知設定】
# 可以在腳本執行完成後發送郵件通知
ENABLE_EMAIL_NOTIFICATION="${ENABLE_EMAIL_NOTIFICATION:-false}"
EMAIL_SENDER="${EMAIL_SENDER:-noreply@example.com}"
EMAIL_RECIPIENTS="${EMAIL_RECIPIENTS:-admin@example.com}"
SMTP_SERVER="${SMTP_SERVER:-email-smtp.us-east-1.amazonaws.com}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_USER="${SMTP_USER:-}"
SMTP_PASSWORD="${SMTP_PASSWORD:-}"

# 【後置腳本】
# 掛載完成後可以自動執行指定的腳本
POST_MOUNT_SCRIPT="${POST_MOUNT_SCRIPT:-}"


# ============================================================
# 【區塊四】全域變數宣告
# ============================================================
# 這些變數會在腳本執行過程中被設定和使用
#
# declare -a 宣告一個陣列變數
# 陣列可以存放多個值，例如多個 Instance Store 裝置名稱
# ============================================================

# 【Instance Store 裝置陣列】
# 存放偵測到的所有 Instance Store 裝置名稱
# 例如：("nvme1n1" "nvme2n1")
declare -a INSTANCE_STORE_DEVICES=()

# 【Instance Store 數量】
INSTANCE_STORE_COUNT=0

# 【EC2 實例資訊】
# 這些資訊會從 EC2 Metadata Service 取得
INSTANCE_ID=""       # 實例 ID，如 i-0abc123def
INSTANCE_TYPE=""     # 實例類型，如 c5d.large
AVAILABILITY_ZONE="" # 可用區域，如 ap-northeast-1a
REGION=""            # 區域，如 ap-northeast-1
ACCOUNT_ID=""        # AWS 帳戶 ID

# 【執行時間記錄】
START_TIME=""        # 腳本開始時間
END_TIME=""          # 腳本結束時間


# ============================================================
# 【區塊五】終端顏色定義
# ============================================================
# 這些是 ANSI 跳脫序列，用來在終端機顯示彩色文字
#
# \033[ 是 ANSI 跳脫序列的開始
# 數字代表不同的顏色
# m 是序列的結束
#
# 0;31m = 紅色
# 0;32m = 綠色
# 1;33m = 黃色（1 表示粗體）
# 0;34m = 藍色
# 0m    = 重設顏色（No Color）
# ============================================================
RED='\033[0;31m'     # 錯誤訊息用紅色
GREEN='\033[0;32m'   # 成功/資訊訊息用綠色
YELLOW='\033[1;33m'  # 警告訊息用黃色
BLUE='\033[0;34m'    # 除錯訊息用藍色
NC='\033[0m'         # No Color - 重設為預設顏色


# ============================================================
# 【區塊六】函數定義 - log()
# ============================================================
# 這是一個進階的日誌函數，比 V4 版本更完整
#
# 功能：
# 1. 將訊息寫入日誌檔案（附帶時間戳記和等級）
# 2. 在終端機顯示彩色訊息
#
# 用法：
#   log INFO "這是一般訊息"
#   log WARN "這是警告訊息"
#   log ERROR "這是錯誤訊息"
#   log DEBUG "這是除錯訊息"
#
# 【參數說明】
# $1     - 日誌等級（INFO, WARN, ERROR, DEBUG）
# $*     - 其餘所有參數組成訊息內容
#
# 【local 關鍵字】
# local 宣告的變數只在函數內有效，不會影響外部的同名變數
# 這是良好的程式設計習慣，可以避免變數污染
# ============================================================
log() {
    # 取得日誌等級（第一個參數）
    local level="$1"

    # shift 指令會移除第一個參數，讓 $* 只包含訊息內容
    # 這樣 level 存放等級，message 存放訊息
    shift

    # 將剩餘的所有參數組合成訊息
    local message="$*"

    # 取得當前時間戳記
    # 格式：2024-01-15 14:30:45
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # 確保日誌目錄存在
    # dirname 取得目錄路徑，mkdir -p 建立目錄（含父目錄）
    # 2>/dev/null 隱藏錯誤訊息，|| true 確保指令不會導致腳本退出
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

    # 寫入日誌檔案
    # 格式：[時間] [等級] 訊息
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"

    # 終端輸出（帶顏色）
    # case 語句類似 switch-case，根據 level 的值執行不同的程式碼
    case "$level" in
        INFO)
            # -e 選項讓 echo 能解析跳脫序列（顏色碼）
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


# ============================================================
# 【區塊七】函數定義 - check_root()
# ============================================================
# 檢查腳本是否以 root 權限執行
# 掛載磁碟需要 root 權限，所以這是必要的檢查
# ============================================================
check_root() {
    # $EUID 是有效使用者 ID（Effective User ID）
    # root 使用者的 EUID 永遠是 0
    if [[ "$EUID" -ne 0 ]]; then
        log ERROR "此腳本需要 root 權限執行"
        log ERROR "請使用: sudo $0"
        exit 1  # 退出腳本，返回錯誤碼 1
    fi
    log INFO "Root 權限驗證通過"
}


# ============================================================
# 【區塊八】函數定義 - check_dependencies()
# ============================================================
# 檢查腳本需要的外部工具是否已安裝
#
# 這個函數會根據配置動態決定需要哪些工具：
# - 基本工具：lsblk, blkid, mount, umount, curl
# - ext4 需要：mkfs.ext4
# - xfs 需要：mkfs.xfs
# - RAID 0 模式需要：mdadm
# ============================================================
check_dependencies() {
    # 基本必要工具陣列
    local deps=("lsblk" "blkid" "mount" "umount" "curl")
    # 存放缺少的工具
    local missing=()

    # 根據檔案系統類型添加需要的工具
    case "$FILESYSTEM_TYPE" in
        ext4) deps+=("mkfs.ext4") ;;  # += 是將元素加入陣列
        xfs) deps+=("mkfs.xfs") ;;
    esac

    # RAID 模式需要 mdadm
    if [[ "$MOUNT_MODE" == "raid0" ]]; then
        deps+=("mdadm")
    fi

    # 檢查每個工具是否存在
    for dep in "${deps[@]}"; do
        # command -v 會回傳指令的路徑，如果找不到則返回失敗
        # &> /dev/null 將所有輸出（stdout 和 stderr）丟棄
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")  # 將缺少的工具加入陣列
        fi
    done

    # 如果有缺少的工具，顯示錯誤並退出
    # ${#missing[@]} 取得陣列長度
    if [[ ${#missing[@]} -gt 0 ]]; then
        log ERROR "缺少必要工具: ${missing[*]}"
        log ERROR "請先安裝: sudo yum install -y mdadm nvme-cli 或 sudo apt install -y mdadm nvme-cli"
        exit 1
    fi

    log INFO "依賴檢查通過"
}


# ============================================================
# 【區塊九】函數定義 - get_imdsv2_token()
# ============================================================
# 取得 EC2 Instance Metadata Service v2 (IMDSv2) 的存取令牌
#
# 【什麼是 IMDS？】
# IMDS (Instance Metadata Service) 是 AWS 提供的服務，
# 讓 EC2 實例可以查詢自己的資訊（ID、類型、網路設定等）
#
# 【IMDSv1 vs IMDSv2】
# v1: 直接用 GET 請求取得資料（較不安全）
# v2: 需要先用 PUT 取得 Token，再用 Token 取得資料（較安全）
#
# AWS 建議使用 v2，因為它可以防止 SSRF 攻擊
# ============================================================
get_imdsv2_token() {
    local token

    # 使用 curl 發送 PUT 請求取得 Token
    # -s: silent mode，不顯示進度
    # -X PUT: 使用 PUT 方法
    # -H: 設定 HTTP Header
    # X-aws-ec2-metadata-token-ttl-seconds: Token 有效期（秒）
    # --connect-timeout 2: 連線逾時 2 秒
    # 2>/dev/null: 隱藏錯誤訊息
    # || true: 即使失敗也不要退出腳本（因為 set -e）
    token=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
        --connect-timeout 2 2>/dev/null) || true

    # echo 會將 token 值輸出，供呼叫者使用
    # 在 Bash 中，函數的「回傳值」通常是透過 echo 輸出
    echo "$token"
}


# ============================================================
# 【區塊十】函數定義 - get_instance_metadata()
# ============================================================
# 從 IMDS 取得指定的 metadata
#
# 【參數】
# $1 - IMDSv2 Token（可以為空）
# $2 - Metadata 路徑（例如 "meta-data/instance-id"）
#
# 【169.254.169.254 是什麼？】
# 這是 AWS 預留的特殊 IP 位址（link-local address）
# 只能從 EC2 實例內部存取，用來查詢該實例的各種資訊
# ============================================================
get_instance_metadata() {
    local token="$1"
    local metadata_path="$2"

    # 如果有 Token，就使用 IMDSv2
    # -n 測試字串是否非空
    if [[ -n "$token" ]]; then
        curl -s -H "X-aws-ec2-metadata-token: $token" \
            "http://169.254.169.254/latest/$metadata_path" \
            --connect-timeout 2 2>/dev/null || echo ""
    else
        # 沒有 Token 就嘗試 IMDSv1（直接 GET）
        curl -s "http://169.254.169.254/latest/$metadata_path" \
            --connect-timeout 2 2>/dev/null || echo ""
    fi
}


# ============================================================
# 【區塊十一】函數定義 - collect_instance_info()
# ============================================================
# 收集 EC2 實例的各種資訊
# 這些資訊會用於日誌記錄和郵件通知
# ============================================================
collect_instance_info() {
    log INFO "收集 EC2 實例資訊..."

    # 取得 IMDSv2 Token
    local token
    token=$(get_imdsv2_token)

    # 如果取得 Token 失敗，顯示警告但繼續執行
    if [[ -z "$token" ]]; then
        log WARN "無法獲取 IMDSv2 令牌，嘗試使用 IMDSv1"
    fi

    # 取得各種 metadata
    INSTANCE_ID=$(get_instance_metadata "$token" "meta-data/instance-id")
    INSTANCE_TYPE=$(get_instance_metadata "$token" "meta-data/instance-type")
    AVAILABILITY_ZONE=$(get_instance_metadata "$token" "meta-data/placement/availability-zone")

    # 從 Availability Zone 推算 Region
    # ap-northeast-1a → ap-northeast-1
    # ${變數%模式} 會移除變數尾端符合模式的部分
    # [a-z] 匹配一個小寫字母
    REGION="${AVAILABILITY_ZONE%[a-z]}"

    # 取得 Account ID
    # instance-identity/document 回傳 JSON 格式的資料
    # 使用 grep 和 cut 來解析 JSON（簡單但不夠嚴謹的做法）
    local identity_doc
    identity_doc=$(get_instance_metadata "$token" "dynamic/instance-identity/document")
    ACCOUNT_ID=$(echo "$identity_doc" | grep -o '"accountId"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")

    # 記錄收集到的資訊
    # ${變數:-預設值} 在變數為空時顯示預設值
    log INFO "Instance ID: ${INSTANCE_ID:-N/A}"
    log INFO "Instance Type: ${INSTANCE_TYPE:-N/A}"
    log INFO "Availability Zone: ${AVAILABILITY_ZONE:-N/A}"
    log INFO "Region: ${REGION:-N/A}"
    log INFO "Account ID: ${ACCOUNT_ID:-N/A}"
}


# ============================================================
# 【區塊十二】函數定義 - detect_instance_stores()
# ============================================================
# 偵測系統上的 Instance Store 裝置
#
# 這個函數使用三種方法來偵測 Instance Store：
# 1. lsblk 的 MODEL 欄位（最可靠）
# 2. nvme list 命令（需要 nvme-cli）
# 3. 檢查 /sys/block 並排除 EBS（最後手段）
#
# 【為什麼需要多種方法？】
# 不同的 Linux 發行版和版本可能有不同的行為
# 使用多種方法可以提高相容性
# ============================================================
detect_instance_stores() {
    log INFO "偵測 Instance Store 裝置..."

    # 本地陣列，暫存偵測到的裝置
    local devices=()

    # 【方法 1】使用 lsblk 的 MODEL 欄位
    # Instance Store 的 MODEL 會顯示 "Amazon EC2 NVMe Instance Storage"
    #
    # lsblk -d: 只顯示磁碟（disk），不顯示分割區
    # -o NAME,MODEL: 只顯示名稱和型號欄位
    # grep -i: 不分大小寫搜尋
    # awk '{print $1}': 只取第一個欄位（裝置名稱）
    #
    # while IFS= read -r line 是逐行讀取的慣用寫法
    # IFS= 防止空白被移除
    # -r 防止反斜線被解釋
    while IFS= read -r line; do
        [[ -n "$line" ]] && devices+=("$line")
    done < <(lsblk -d -o NAME,MODEL 2>/dev/null | grep -i "Instance Storage" | awk '{print $1}')

    # 【方法 2】使用 nvme list 命令
    # 只有在方法 1 沒有結果時才嘗試
    if [[ ${#devices[@]} -eq 0 ]] && command -v nvme &> /dev/null; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && devices+=("$line")
        done < <(nvme list 2>/dev/null | grep -i "Instance Storage" | awk '{print $1}' | sed 's|/dev/||')
    fi

    # 【方法 3】檢查 /dev/nvme*n1 並排除 EBS
    # 這是最後手段，透過排除法找出 Instance Store
    if [[ ${#devices[@]} -eq 0 ]]; then
        # /dev/nvme*n1 會展開成所有符合的裝置路徑
        for dev in /dev/nvme*n1; do
            # -b 測試是否為區塊裝置
            [[ ! -b "$dev" ]] && continue

            local dev_name
            dev_name=$(basename "$dev")  # 取得檔案名稱部分

            # 從 /sys/block 讀取裝置型號
            local model
            model=$(cat "/sys/block/$dev_name/device/model" 2>/dev/null | tr -d ' ')

            # 排除 EBS 裝置（型號包含 EBS 字樣）
            if [[ "$model" != "AmazonElasticBlockStore" ]] && [[ "$model" != *"EBS"* ]]; then
                devices+=("$dev_name")
            fi
        done
    fi

    # 【去重並排序】
    # printf '%s\n' 將陣列元素逐行輸出
    # sort -u 排序並去除重複
    # mapfile -t 將輸出讀入陣列
    mapfile -t INSTANCE_STORE_DEVICES < <(printf '%s\n' "${devices[@]}" | sort -u)
    INSTANCE_STORE_COUNT=${#INSTANCE_STORE_DEVICES[@]}

    log INFO "偵測到 $INSTANCE_STORE_COUNT 個 Instance Store 裝置"

    # 如果沒有偵測到任何裝置，返回失敗
    if [[ $INSTANCE_STORE_COUNT -eq 0 ]]; then
        log WARN "未偵測到任何 Instance Store 裝置"
        return 1  # 返回非零值表示失敗
    fi

    # 顯示每個裝置的資訊
    local sizes=""
    for dev in "${INSTANCE_STORE_DEVICES[@]}"; do
        local size
        size=$(lsblk -d -o SIZE "/dev/$dev" 2>/dev/null | tail -1 | tr -d ' ')
        log INFO "  - /dev/$dev (${size:-unknown})"

        # 收集大小資訊（用逗號分隔）
        if [[ -n "$sizes" ]]; then
            sizes="${sizes},${size:-N/A}"
        else
            sizes="${size:-N/A}"
        fi
    done

    log INFO "Instance Store 總大小: $sizes"

    return 0  # 返回 0 表示成功
}


# ============================================================
# 【區塊十三】函數定義 - unmount_existing()
# ============================================================
# 解除現有的掛載
#
# 在重新掛載之前，需要先解除已經存在的掛載
# 這包括：
# 1. RAID 裝置
# 2. 個別的 Instance Store 裝置
# 3. 清除 RAID superblock（避免影響新的 RAID 建立）
# ============================================================
unmount_existing() {
    log INFO "檢查並解除現有掛載..."

    # 【解除 RAID 裝置】
    # -b 測試是否為區塊裝置
    if [[ -b "$RAID_DEVICE" ]]; then
        # 檢查 RAID 裝置是否已掛載
        if mount | grep -q "$RAID_DEVICE"; then
            umount "$RAID_DEVICE" 2>/dev/null || true
            log INFO "已解除 $RAID_DEVICE 掛載"
        fi
        # 停止 RAID 陣列
        mdadm --stop "$RAID_DEVICE" 2>/dev/null || true
        log INFO "已停止 RAID 裝置 $RAID_DEVICE"
    fi

    # 【解除 Instance Store 的掛載】（根據 mount 輸出）
    local mounted_points
    mounted_points=$(mount | grep -i "Instance Storage" | awk '{print $3}' 2>/dev/null || true)

    for mounted_point in $mounted_points; do
        if [[ -n "$mounted_point" ]]; then
            umount "$mounted_point" 2>/dev/null || true
            log INFO "已解除 Instance Store 從 $mounted_point 的掛載"
        fi
    done

    # 【解除 Instance Store 的掛載】（根據裝置名稱）
    for dev in "${INSTANCE_STORE_DEVICES[@]}"; do
        if mount | grep -q "/dev/$dev"; then
            local mount_point
            mount_point=$(mount | grep "/dev/$dev" | awk '{print $3}')
            umount "/dev/$dev" 2>/dev/null || true
            log INFO "已解除 /dev/$dev 從 $mount_point 的掛載"
        fi
    done

    # 【清除 RAID superblock】
    # 如果裝置之前曾經是 RAID 成員，會有 superblock 殘留
    # 這可能會干擾新的 RAID 建立，所以要清除
    for dev in "${INSTANCE_STORE_DEVICES[@]}"; do
        mdadm --zero-superblock "/dev/$dev" 2>/dev/null || true
    done
}


# ============================================================
# 【區塊十四】函數定義 - format_device()
# ============================================================
# 格式化裝置（建立檔案系統）
#
# 【參數】
# $1 - 裝置路徑（例如 /dev/nvme1n1）
# $2 - 檔案系統類型（可選，預設使用 FILESYSTEM_TYPE）
#
# 【什麼是格式化？】
# 格式化是在儲存裝置上建立檔案系統的過程
# 檔案系統決定了資料如何被組織和存取
# 常見的 Linux 檔案系統：ext4、xfs、btrfs 等
# ============================================================
format_device() {
    local device="$1"
    # ${2:-預設值} 如果沒有提供第二個參數，使用預設值
    local fs_type="${2:-$FILESYSTEM_TYPE}"

    log INFO "格式化裝置 $device 為 $fs_type..."

    # 【選擇性清除裝置】
    # wipefs 會清除裝置上的檔案系統簽章
    if [[ "$WIPE_DEVICE_BEFORE_FORMAT" == "true" ]]; then
        log INFO "清除裝置 $device..."
        wipefs -a "$device" 2>/dev/null || true
    fi

    # 【根據檔案系統類型執行格式化】
    case "$fs_type" in
        ext4)
            # mkfs.ext4: 建立 ext4 檔案系統
            # -F: 強制執行，不詢問確認
            # $EXT4_FORMAT_OPTIONS: 額外的格式化選項
            if ! mkfs.ext4 -F $EXT4_FORMAT_OPTIONS "$device" 2>&1; then
                log ERROR "格式化 $device 為 ext4 失敗"
                return 1
            fi
            ;;
        xfs)
            # mkfs.xfs: 建立 XFS 檔案系統
            # -f: 強制執行，覆蓋現有檔案系統
            if ! mkfs.xfs -f $XFS_FORMAT_OPTIONS "$device" 2>&1; then
                log ERROR "格式化 $device 為 xfs 失敗"
                return 1
            fi
            ;;
        *)
            log ERROR "不支援的檔案系統類型: $fs_type"
            return 1
            ;;
    esac

    log INFO "裝置 $device 格式化完成"
    return 0
}


# ============================================================
# 【區塊十五】函數定義 - generate_mount_points()
# ============================================================
# 生成掛載點陣列
#
# 【參數】
# $1 - 陣列變數的名稱（使用 nameref 參考）
#
# 【什麼是 nameref？】
# local -n 宣告一個「名稱參考」變數
# 它會指向另一個變數，修改它就等於修改原變數
# 這是 Bash 4.3+ 的功能，用來模擬「傳參考」
# ============================================================
generate_mount_points() {
    # -n 宣告 nameref，mount_points_ref 會指向傳入的變數
    local -n mount_points_ref=$1

    if [[ "$DYNAMIC_MOUNT" == "true" ]]; then
        # 【動態生成掛載點】
        log INFO "使用動態掛載點模式"
        mount_points_ref=()  # 清空陣列

        # seq 1 $N 會產生 1 到 N 的數字序列
        for i in $(seq 1 $INSTANCE_STORE_COUNT); do
            mount_points_ref+=("${BASE_MOUNT_POINT}${i}")
        done
    else
        # 【使用靜態掛載點】
        log INFO "使用靜態掛載點模式"

        # IFS=' ' 設定分隔符為空格
        # read -ra 將字串分割後讀入陣列
        # <<< 是 here string，將字串作為輸入
        IFS=' ' read -ra mount_points_ref <<< "$MOUNT_POINTS"

        # 【嚴格比對檢查】
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


# ============================================================
# 【區塊十六】函數定義 - mount_single_mode()
# ============================================================
# 單獨掛載模式
# 將每個 Instance Store 掛載到不同的目錄
# ============================================================
mount_single_mode() {
    log INFO "使用單獨掛載模式..."

    # 生成掛載點陣列
    local -a mount_points_array
    generate_mount_points mount_points_array

    # 使用索引來配對裝置和掛載點
    local idx=0
    for dev in "${INSTANCE_STORE_DEVICES[@]}"; do
        # 檢查是否還有可用的掛載點
        if [[ $idx -ge ${#mount_points_array[@]} ]]; then
            log WARN "掛載點不足，剩餘裝置未掛載: /dev/$dev"
            break
        fi

        local device="/dev/$dev"
        local mount_point="${mount_points_array[$idx]}"

        # 【建立掛載點目錄】
        if [[ ! -d "$mount_point" ]]; then
            mkdir -p "$mount_point"
            log INFO "建立掛載點目錄: $mount_point"
        fi

        # 【檢查是否需要格式化】
        # blkid 可以查詢裝置的檔案系統類型
        # -o value -s TYPE: 只輸出 TYPE（檔案系統類型）的值
        local current_fs
        current_fs=$(blkid -o value -s TYPE "$device" 2>/dev/null || echo "")

        if [[ "$current_fs" != "$FILESYSTEM_TYPE" ]]; then
            # 需要格式化
            if ! format_device "$device" "$FILESYSTEM_TYPE"; then
                log ERROR "格式化 $device 失敗，跳過此裝置"
                ((idx++))
                continue  # 跳過這個裝置，繼續下一個
            fi
        else
            log INFO "裝置 $device 已經是 $FILESYSTEM_TYPE 格式"
        fi

        # 【掛載裝置】
        # mount -o 選項: 指定掛載選項
        if mount -o "$MOUNT_OPTIONS" "$device" "$mount_point"; then
            log INFO "成功掛載 $device 到 $mount_point"

            # 設定權限
            # chmod 1777: 設定 sticky bit 和完全開放的權限
            # sticky bit (1000): 只有檔案擁有者可以刪除檔案
            # 777: 所有人可以讀寫執行
            # 這類似 /tmp 的權限設定
            chmod 1777 "$mount_point"
        else
            log ERROR "掛載 $device 到 $mount_point 失敗"
        fi

        ((idx++))  # 索引加 1
    done
}


# ============================================================
# 【區塊十七】函數定義 - mount_raid0_mode()
# ============================================================
# RAID 0 掛載模式
# 將所有 Instance Store 組成 RAID 0 陣列
#
# 【什麼是 RAID 0？】
# RAID 0（也稱為 striping）會將資料分散儲存在多個磁碟上
# 優點：讀寫速度是單一磁碟的倍數
# 缺點：沒有容錯能力，任一磁碟故障就會遺失所有資料
#
# 由於 Instance Store 本來就是暫時性儲存，
# 使用 RAID 0 可以獲得最大的效能，是合理的選擇
# ============================================================
mount_raid0_mode() {
    log INFO "使用 RAID 0 模式..."

    # 檢查裝置數量
    if [[ $INSTANCE_STORE_COUNT -lt 1 ]]; then
        log ERROR "RAID 0 模式至少需要 1 個裝置"
        return 1
    fi

    # 【準備裝置路徑陣列】
    local device_paths=()
    for dev in "${INSTANCE_STORE_DEVICES[@]}"; do
        device_paths+=("/dev/$dev")
    done

    # 【建立 RAID 陣列】
    log INFO "建立 RAID 0 陣列，包含 $INSTANCE_STORE_COUNT 個裝置..."

    # mdadm 是 Linux 的 RAID 管理工具
    # --create: 建立新的 RAID 陣列
    # --level=0: RAID 等級 0（striping）
    # --raid-devices: RAID 中的裝置數量
    # --chunk: chunk size（資料分割的單位大小）
    #
    # yes | 是將 "y" 持續輸入到 mdadm，自動確認所有詢問
    if ! yes | mdadm --create "$RAID_DEVICE" \
        --level=0 \
        --raid-devices="$INSTANCE_STORE_COUNT" \
        --chunk="$RAID_CHUNK_SIZE" \
        "${device_paths[@]}" 2>&1; then
        log ERROR "建立 RAID 陣列失敗"
        return 1
    fi

    log INFO "RAID 0 陣列建立成功: $RAID_DEVICE"

    # 【格式化 RAID 裝置】
    if ! format_device "$RAID_DEVICE" "$FILESYSTEM_TYPE"; then
        log ERROR "格式化 RAID 裝置失敗"
        return 1
    fi

    # 【建立掛載點】
    if [[ ! -d "$RAID_MOUNT_POINT" ]]; then
        mkdir -p "$RAID_MOUNT_POINT"
        log INFO "建立掛載點目錄: $RAID_MOUNT_POINT"
    fi

    # 【掛載 RAID 陣列】
    if mount -o "$MOUNT_OPTIONS" "$RAID_DEVICE" "$RAID_MOUNT_POINT"; then
        log INFO "成功掛載 RAID 陣列到 $RAID_MOUNT_POINT"
        chmod 1777 "$RAID_MOUNT_POINT"
    else
        log ERROR "掛載 RAID 陣列失敗"
        return 1
    fi

    # 【記錄 RAID 詳細資訊】
    log INFO "RAID 陣列詳細資訊:"
    mdadm --detail "$RAID_DEVICE" >> "$LOG_FILE" 2>&1

    return 0
}


# ============================================================
# 【區塊十八】函數定義 - show_mount_status()
# ============================================================
# 顯示掛載狀態摘要
# ============================================================
show_mount_status() {
    log INFO "=========================================="
    log INFO "掛載狀態摘要"
    log INFO "=========================================="

    # 根據掛載模式顯示不同的資訊
    if [[ "$MOUNT_MODE" == "raid0" ]] && mount | grep -q "$RAID_DEVICE"; then
        # RAID 模式：顯示 RAID 陣列的資訊
        local size used avail use_pct

        # df -h: 以人類可讀的格式顯示磁碟使用狀況
        # tail -1: 取最後一行（跳過標題行）
        # read 將輸出讀入多個變數
        read -r _ size used avail use_pct _ < <(df -h "$RAID_MOUNT_POINT" 2>/dev/null | tail -1)

        log INFO "RAID 0 掛載點: $RAID_MOUNT_POINT"
        log INFO "  總容量: ${size:-N/A}"
        log INFO "  已使用: ${used:-N/A} (${use_pct:-N/A})"
        log INFO "  可用: ${avail:-N/A}"
    else
        # 單獨模式：顯示每個掛載點的資訊
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


# ============================================================
# 【區塊十九】函數定義 - send_email_notification()
# ============================================================
# 發送郵件通知
# 將腳本執行的結果透過 Email 發送給管理員
# ============================================================
send_email_notification() {
    # 檢查是否啟用郵件通知
    if [[ "$ENABLE_EMAIL_NOTIFICATION" != "true" ]]; then
        return 0
    fi

    log INFO "發送郵件通知..."

    local subject="[AWS Instance Store] 掛載完成通知 - ${INSTANCE_ID:-unknown}"

    # 擷取本次執行的日誌
    local email_body
    email_body=$(awk -v start="$START_TIME" -v end="$END_TIME" \
        '$0 ~ start, $0 ~ end' "$LOG_FILE" 2>/dev/null || cat "$LOG_FILE")

    # 建立臨時郵件檔案
    local temp_mail_file
    temp_mail_file=$(mktemp)

    # 使用 Here Document 寫入郵件內容
    # << EOF ... EOF 之間的內容會被當作輸入
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
        for recipient in $EMAIL_RECIPIENTS; do
            if [[ -n "$SMTP_USER" ]] && [[ -n "$SMTP_PASSWORD" ]]; then
                sendmail -f "$EMAIL_SENDER" -S "${SMTP_SERVER}:${SMTP_PORT}" \
                    -au "$SMTP_USER" -ap "$SMTP_PASSWORD" \
                    "$recipient" < "$temp_mail_file" 2>/dev/null
            else
                sendmail -f "$EMAIL_SENDER" "$recipient" < "$temp_mail_file" 2>/dev/null
            fi
        done

        if [[ $? -eq 0 ]]; then
            log INFO "郵件通知已發送"
        else
            log WARN "郵件發送失敗"
        fi
    else
        log WARN "sendmail 未安裝，跳過郵件通知"
    fi

    # 清理臨時檔案
    rm -f "$temp_mail_file"
}


# ============================================================
# 【區塊二十】函數定義 - run_post_mount_script()
# ============================================================
# 執行後置腳本
# 掛載完成後可以自動執行指定的腳本
# ============================================================
run_post_mount_script() {
    # -n 測試字串非空
    # -x 測試檔案是否可執行
    if [[ -n "$POST_MOUNT_SCRIPT" ]] && [[ -x "$POST_MOUNT_SCRIPT" ]]; then
        log INFO "執行後置腳本: $POST_MOUNT_SCRIPT"
        if "$POST_MOUNT_SCRIPT"; then
            log INFO "後置腳本執行成功"
        else
            log WARN "後置腳本執行失敗"
        fi
    fi
}


# ============================================================
# 【區塊二十一】函數定義 - cleanup_on_exit()
# ============================================================
# 腳本退出時的清理函數
# 使用 trap 機制，在腳本退出時自動呼叫
# ============================================================
cleanup_on_exit() {
    # $? 是上一個指令的退出碼
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log ERROR "腳本執行失敗，退出碼: $exit_code"
    fi
}


# ============================================================
# 【區塊二十二】函數定義 - show_usage()
# ============================================================
# 顯示使用說明
# ============================================================
show_usage() {
    # Here Document 用來輸出多行文字
    # $(basename "$0") 取得腳本的檔案名稱
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


# ============================================================
# 【區塊二十三】函數定義 - parse_arguments()
# ============================================================
# 解析命令列參數
#
# 【命令列參數的處理】
# $# - 參數的數量
# $1, $2, ... - 第 1、2、... 個參數
# shift - 移除第一個參數，讓 $2 變成 $1
# shift 2 - 移除前兩個參數
# ============================================================
parse_arguments() {
    # 持續處理參數，直到沒有參數為止
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -c|--config)
                CONFIG_FILE="$2"  # 下一個參數是配置檔路徑
                shift 2           # 移除這兩個參數
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
                shift             # 這個選項沒有值，只移除一個參數
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
# 【區塊二十四】主程式 - main()
# ============================================================
# 這是腳本的主要執行邏輯
# 按照順序執行各個步驟
# ============================================================
main() {
    # 【設定退出時的清理函數】
    # trap 指令可以在收到信號或腳本退出時執行指定的程式碼
    # EXIT 是一個特殊信號，在腳本退出時觸發
    trap cleanup_on_exit EXIT

    # 記錄開始時間
    START_TIME=$(date '+%Y-%m-%d %H:%M:%S')

    # 顯示腳本標題
    log INFO "=========================================="
    log INFO "AWS Instance Store 掛載腳本啟動"
    log INFO "版本: 5.0"
    log INFO "開始時間: $START_TIME"
    log INFO "=========================================="

    # 【步驟 1】前置檢查
    check_root           # 檢查 root 權限
    check_dependencies   # 檢查必要工具

    # 【步驟 2】收集實例資訊
    collect_instance_info

    # 【步驟 3】偵測 Instance Store
    if ! detect_instance_stores; then
        log WARN "沒有可用的 Instance Store，腳本結束"
        exit 0
    fi

    # 【步驟 4】解除現有掛載
    unmount_existing

    # 【步驟 5】執行掛載
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

    # 【步驟 6】顯示狀態
    show_mount_status

    # 記錄結束時間
    END_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    log INFO "腳本執行完成: $END_TIME"

    # 【步驟 7】發送通知
    send_email_notification

    # 【步驟 8】執行後置腳本
    run_post_mount_script
}


# ============================================================
# 【區塊二十五】腳本入口點
# ============================================================
# 以下是腳本實際執行的起點
# 先解析命令列參數，再執行主程式
# ============================================================

# 解析命令列參數
# "$@" 代表所有命令列參數（保持引號）
parse_arguments "$@"

# 執行主程式
main


# ============================================================
# 【腳本結束】
# ============================================================
# 腳本執行完畢後，Instance Store 應該已經掛載完成
#
# 【確認掛載狀態的指令】
#   df -h | grep instance_store     # 查看磁碟使用狀況
#   lsblk                            # 查看區塊裝置
#   mount | grep instance_store      # 查看掛載資訊
#   cat /proc/mdstat                 # 查看 RAID 狀態
#   mdadm --detail /dev/md0          # 查看 RAID 詳細資訊
#
# 【日誌檔案位置】
#   /var/log/instance-store-mount.log
#
# 【重要提醒】
# Instance Store 是暫時性儲存，資料會在以下情況遺失：
# - 實例停止 (Stop)
# - 實例終止 (Terminate)
# - 硬體故障
# 請勿存放重要資料！
# ============================================================
