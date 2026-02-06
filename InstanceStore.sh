#!/bin/bash
# ============================================================
# AWS EC2 Instance Store 自動掛載腳本 (V4)
# ============================================================
#
# 【腳本說明】
# 這個腳本的用途是自動偵測並掛載 AWS EC2 的 Instance Store。
# Instance Store 是 EC2 實例上的本地 NVMe SSD 儲存空間，
# 具有極高的 I/O 效能，但資料是「暫時性」的：
# - 實例停止 (Stop) 或終止 (Terminate) 時，資料會遺失
# - 實例重新開機 (Reboot) 時，資料會保留但需重新掛載
#
# 【適用情境】
# - 需要高速暫存空間的應用 (如資料處理、快取)
# - 不需要持久化的臨時資料儲存
#
# 【執行方式】
# 1. 將腳本上傳到 EC2，建議路徑：/usr/local/bin/InstanceStore.sh
# 2. 給予執行權限：chmod +x /usr/local/bin/InstanceStore.sh
# 3. 以 root 執行：sudo /usr/local/bin/InstanceStore.sh
#
# 【開機自動執行】
# 可使用以下方式設定開機自動執行：
# - Cron: @reboot /usr/local/bin/InstanceStore.sh
# - Systemd: 建立 service 檔案
# - rc.local: 在 /etc/rc.local 中加入腳本路徑
#
# 【版本資訊】
# 版本：4.0
# 作者：Albert Yu
# ============================================================


# ============================================================
# 【區塊一】全域變數設定
# ============================================================
# 這個區塊定義了腳本中會用到的全域變數
# 全域變數就像是「設定值」，可以在腳本任何地方使用
# ============================================================

# 【日誌檔案路徑】
# 所有執行記錄都會寫入這個檔案，方便日後查看和除錯
# /var/log 是 Linux 系統存放日誌的標準目錄
LOG_FILE="/var/log/nvme_mount.log"

# 【臨時郵件檔案路徑】
# ${變數:-預設值} 的語法表示：
# 如果 TEMP_MAIL_FILE 變數已經有值就用它，否則用預設值
# /tmp 是系統的臨時目錄，重開機後會被清空
TEMP_MAIL_FILE="${TEMP_MAIL_FILE:-/tmp/temp_mail_file.txt}"


# ============================================================
# 【區塊二】函數定義
# ============================================================
# 函數是一段可以重複使用的程式碼
# 定義函數後，可以在腳本中多次呼叫它
# ============================================================

# 【log 函數】
# 功能：將訊息寫入日誌檔案，並自動加上時間戳記
# 參數：$1 是傳入的第一個參數，代表要記錄的訊息
# 用法：log "要記錄的訊息"
#
# 【語法解釋】
# $(date) - 執行 date 指令並取得結果（當前時間）
# >>      - 將內容「附加」到檔案末端（不會覆蓋原有內容）
# >       - 將內容「覆寫」到檔案（會清空原有內容）
log() {
  echo "$(date): $1" >> "$LOG_FILE"
}


# ============================================================
# 【區塊三】腳本開始執行
# ============================================================
# 記錄腳本開始執行的時間，用於日誌和後續郵件通知
# ============================================================

# 【記錄開始時間】
# date +"%Y-%m-%d %H:%M:%S" 會輸出格式化的時間
# 例如：2024-01-15 14:30:45
# %Y=年(4位) %m=月 %d=日 %H=時(24小時) %M=分 %S=秒
START_TIME=$(date +"%Y-%m-%d %H:%M:%S")
log "Script started at $START_TIME"


# ============================================================
# 【區塊四】權限檢查
# ============================================================
# 掛載磁碟需要 root 權限，這裡檢查是否以 root 身份執行
# ============================================================

# 【檢查 root 權限】
# $EUID 是一個特殊變數，代表當前使用者的有效 UID（User ID）
# root 使用者的 UID 永遠是 0
# -ne 表示 "not equal"（不等於）
#
# 【if 語法解釋】
# [[ 條件 ]] - 測試條件是否成立
# then       - 如果條件成立，執行以下程式碼
# else       - 如果條件不成立，執行以下程式碼
# fi         - if 區塊結束（fi 是 if 的倒寫）
if [[ "$EUID" -ne 0 ]]; then
  # 不是 root 使用者，記錄錯誤並退出
  log "Script failed: Please run as root"  # 將失敗訊息寫入日誌
  echo "Please run as root"                 # 在終端顯示錯誤訊息
  exit 1                                    # 退出腳本，返回錯誤碼 1
else
  # 是 root 使用者，記錄成功訊息
  log "Script is running as root"  # 將成功訊息寫入日誌
fi


# ============================================================
# 【區塊五】取得 EC2 Metadata（元數據）
# ============================================================
# EC2 Metadata 是 AWS 提供的實例資訊服務
# 可以從特殊的 IP 位址 169.254.169.254 取得實例的各種資訊
#
# 【什麼是 IMDSv2？】
# IMDS = Instance Metadata Service（實例元數據服務）
# v2 是較新且更安全的版本，需要先取得 Token 才能查詢
# v1 則不需要 Token，但較不安全
# ============================================================

# 【取得 IMDSv2 Token】
# curl 是用來發送 HTTP 請求的工具
# -X PUT    - 使用 PUT 方法（取得 Token 必須用 PUT）
# -H        - 設定 HTTP Header
# X-aws-ec2-metadata-token-ttl-seconds: 21600 表示 Token 有效期為 6 小時
#
# 【169.254.169.254 是什麼？】
# 這是 AWS 預留的特殊 IP，只能從 EC2 實例內部存取
# 用來查詢該實例的各種資訊（ID、類型、網路設定等）
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

# 【檢查 Token 是否取得成功】
# -z 表示檢查字串是否為空
# 如果 TOKEN 是空的，表示取得失敗（可能是 IMDSv2 被停用）
if [[ -z "$TOKEN" ]]; then
  log "Failed to obtain IMDSv2 token. Continuing without it."
  # 注意：這裡不退出腳本，因為還可以嘗試用 IMDSv1
fi

# 【取得 EC2 實例資訊】
# 使用取得的 Token 來查詢各種元數據
# -H "X-aws-ec2-metadata-token: $TOKEN" - 在 Header 中帶入 Token
# -s 表示 silent mode（安靜模式），不顯示進度資訊
#
# 【Account ID（帳戶 ID）】
# 從 instance-identity/document 取得 JSON 格式的資料
# 使用 grep 找到 accountId 那行，再用 awk 取出值
# awk -F\" 表示用雙引號作為分隔符，'{print $4}' 取第 4 個欄位
ACCOUNT_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep accountId | awk -F\" '{print $4}')

# 【Availability Zone（可用區域）】
# 例如：ap-northeast-1a（東京區域的 a 可用區）
AVAILABILITY_ZONE=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/placement/availability-zone)

# 【Instance ID（實例 ID）】
# 每個 EC2 實例都有唯一的 ID，格式如：i-0abc123def456789
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)

# 【Instance Type（實例類型）】
# 例如：c5d.large、i3.xlarge 等
# 只有類型名稱中帶 d（如 c5d）或特定類型（如 i3）才有 Instance Store
INSTANCE_TYPE=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-type)

# 將取得的資訊寫入日誌
log "Account ID: $ACCOUNT_ID"
log "Availability Zone: $AVAILABILITY_ZONE"
log "Instance ID: $INSTANCE_ID"
log "Instance Type: $INSTANCE_TYPE"


# ============================================================
# 【區塊六】偵測 Instance Store
# ============================================================
# 使用 lsblk 指令來偵測系統上的 Instance Store 裝置
#
# 【什麼是 lsblk？】
# lsblk = list block devices（列出區塊裝置）
# 區塊裝置就是硬碟、SSD、USB 隨身碟等儲存裝置
# ============================================================

# 【統計 Instance Store 數量】
# lsblk -o NAME,MODEL  - 只顯示裝置名稱和型號
# grep "Instance Storage" - 篩選出 Instance Store（型號會顯示 "Amazon EC2 NVMe Instance Storage"）
# wc -l - 計算行數（word count -lines）
INSTANCE_STORE_COUNT=$(lsblk -o NAME,MODEL | grep "Instance Storage" | wc -l)

# 【取得 Instance Store 大小】
# awk '{print $(NF)}' - 取得每行的最後一個欄位（NF = Number of Fields）
# paste -sd "," - 將多行合併成一行，用逗號分隔
# 例如輸出：475G,475G（如果有兩個 Instance Store）
INSTANCE_STORE_SIZES=$(lsblk -o NAME,MODEL,SIZE | grep "Instance Storage" | awk '{print $(NF)}' | paste -sd "," -)

log "Instance Store Count: $INSTANCE_STORE_COUNT"
log "Instance Store Sizes: $INSTANCE_STORE_SIZES"

# 【檢查是否有 Instance Store】
# -eq 表示 "equal"（等於）
# 如果數量為 0，表示這個實例類型不支援或沒有 Instance Store
if [[ "$INSTANCE_STORE_COUNT" -eq 0 ]]; then
  log "No Instance Stores detected. Terminating script."
  exit 1  # 退出腳本，因為沒有東西可以掛載
fi


# ============================================================
# 【區塊七】解除現有掛載
# ============================================================
# 在掛載之前，先解除已經掛載的 Instance Store
# 這是為了避免重複掛載造成的問題
# ============================================================

# 【找出已掛載的 Instance Store】
# mount - 顯示目前所有掛載的檔案系統
# grep "Instance Storage" - 篩選 Instance Store
# awk '{print $3}' - 取得第 3 個欄位（掛載點路徑）
mounted_instance_stores=$(mount | grep "Instance Storage" | awk '{print $3}')

# 【解除掛載】
# for ... in ... - 對每個項目執行迴圈
# $mounted_instance_stores 可能包含多個掛載點，用空格分隔
for mounted_point in $mounted_instance_stores; do
  umount $mounted_point  # umount = unmount（解除掛載）
  log "Unmounted Instance Store from $mounted_point"
done


# ============================================================
# 【區塊八】設定掛載點
# ============================================================
# 定義要將 Instance Store 掛載到哪些目錄
#
# 【什麼是掛載點？】
# 在 Linux 中，儲存裝置不能直接使用
# 必須「掛載」到一個目錄，才能透過該目錄存取裝置內的檔案
# 例如：將 /dev/nvme1n1 掛載到 /mnt/instance_store1
#       之後存取 /mnt/instance_store1 就是存取該磁碟
# ============================================================

# 【掛載點陣列】
# () 是 Bash 陣列的語法
# 每個元素用空格分隔，用雙引號包住
# 您可以根據需要修改這些路徑，例如改成 /data1、/data2 等
MOUNT_POINTS=("/mnt/instance_store1" "/mnt/instance_store2" "/mnt/instance_store3")

# 【顯示設定的掛載點】
# ${MOUNT_POINTS[*]} - 展開陣列中的所有元素
# [*] 和 [@] 的差異：
#   [*] - 將所有元素當作一個字串
#   [@] - 保持每個元素獨立
log "Configured Mount Points: ${MOUNT_POINTS[*]}"


# ============================================================
# 【區塊九】主要掛載邏輯
# ============================================================
# 這是腳本的核心部分，執行實際的掛載操作
# 流程：偵測裝置 → 建立目錄 → 格式化 → 掛載
# ============================================================

# 【探測所有 Instance Store 裝置】
# lsblk -o NAME,MODEL,SERIAL - 顯示裝置名稱、型號、序號
# grep "Instance Storage" - 篩選 Instance Store
# awk '{print $1}' - 只取裝置名稱（如 nvme1n1）
#
# 【管線（Pipe）解釋】
# | 符號叫做「管線」，將前一個指令的輸出傳給下一個指令
# 例如：lsblk | grep | awk | while read
# 資料流：lsblk輸出 → grep篩選 → awk取欄位 → while讀取
#
# 【while read 迴圈】
# while read -r DEVICE_NAME - 逐行讀取輸入，存入 DEVICE_NAME 變數
# -r 表示不對反斜線做特殊處理（raw mode）
# do ... done - 迴圈的開始和結束
lsblk -o NAME,MODEL,SERIAL | grep "Instance Storage" | awk '{print $1}' | while read -r DEVICE_NAME; do

  # 【檢查掛載點陣列是否還有剩餘】
  # ${#MOUNT_POINTS[@]} - 取得陣列的長度（元素數量）
  # 如果長度為 0，表示掛載點已經用完了
  if [ ${#MOUNT_POINTS[@]} -eq 0 ]; then
    log "No more mount points available in the array. Exiting loop."
    break  # 跳出迴圈（不是退出腳本）
  fi

  # 【組合完整的裝置路徑】
  # lsblk 輸出的是 nvme1n1，但實際裝置路徑是 /dev/nvme1n1
  # 所以要加上 /dev/ 前綴
  DEVICE_NAME="/dev/$DEVICE_NAME"

  # 【從陣列取出掛載點】
  # ${MOUNT_POINTS[0]} - 取得陣列的第一個元素（索引從 0 開始）
  MOUNT_POINT=${MOUNT_POINTS[0]}

  # 【從陣列移除已使用的掛載點】
  # ${MOUNT_POINTS[@]:1} - 取得從索引 1 開始的所有元素（跳過第一個）
  # 這樣下次迴圈就會使用下一個掛載點
  MOUNT_POINTS=("${MOUNT_POINTS[@]:1}")

  # 【建立掛載點目錄】
  # -d 測試目錄是否存在
  # ! 表示「非」（NOT），所以 ! -d 表示「目錄不存在」
  # mkdir -p 會建立目錄，-p 表示連同父目錄一起建立（如果不存在）
  if [[ ! -d "$MOUNT_POINT" ]]; then
    mkdir -p "$MOUNT_POINT"
    log "Created mount point $MOUNT_POINT."
  fi

  # 【檢查並格式化裝置】
  # blkid 用來顯示裝置的檔案系統資訊
  # grep -q "ext4" - 檢查是否已經是 ext4 格式，-q 表示安靜模式（不輸出）
  #
  # 【為什麼要格式化？】
  # 新的 Instance Store 是空白的，沒有檔案系統
  # 必須先格式化（建立檔案系統）才能儲存檔案
  # ext4 是 Linux 最常用的檔案系統之一
  if ! blkid "$DEVICE_NAME" | grep -q "ext4"; then
    # 裝置尚未格式化為 ext4，進行格式化
    # mkfs -t ext4 - 建立 ext4 檔案系統
    # -F 表示強制執行，不詢問確認
    #
    # 【! 指令 的用法】
    # if ! command - 如果指令執行「失敗」則進入 if 區塊
    if ! mkfs -t ext4 -F "$DEVICE_NAME"; then
      log "Failed to format $DEVICE_NAME. Exiting."
      exit 1
    fi
    log "Formatted $DEVICE_NAME as ext4."
  fi

  # 【掛載裝置】
  # mount 指令將裝置掛載到指定目錄
  # 用法：mount 裝置路徑 掛載點
  if ! mount "$DEVICE_NAME" "$MOUNT_POINT"; then
    log "Failed to mount $DEVICE_NAME. Exiting."
    exit 1
  fi

  # 掛載成功，記錄日誌
  log "Mounted $DEVICE_NAME to $MOUNT_POINT."

done
# 【迴圈結束】done 標記迴圈的結束


# ============================================================
# 【區塊十】腳本結束
# ============================================================
# 記錄腳本結束時間，並準備發送郵件通知
# ============================================================

# 記錄結束時間
END_TIME=$(date +"%Y-%m-%d %H:%M:%S")
log "Script ended at $END_TIME"


# ============================================================
# 【區塊十一】呼叫其他腳本（選用）
# ============================================================
# 如果掛載完成後需要執行其他腳本，可以在這裡加入
# 取消下面這行的註解並修改路徑即可
# ============================================================

# /usr/local/bin/script.sh


# ============================================================
# 【區塊十二】郵件通知功能
# ============================================================
# 將腳本執行的日誌透過郵件發送給管理員
# 使用 Amazon SES（Simple Email Service）SMTP 服務
#
# 【注意事項】
# 1. 需要先設定好 Amazon SES
# 2. 需要安裝 sendmail 或 mailx
# 3. 需要修改以下設定：
#    - RECIPIENTS：收件者 Email
#    - sender@example.com：寄件者 Email
#    - SMTP 使用者名稱和密碼
# ============================================================

# 【擷取本次執行的日誌】
# awk 是強大的文字處理工具
# -v start="$START_TIME" - 設定 awk 變數 start
# -v end="$END_TIME" - 設定 awk 變數 end
# '$0 ~ start, $0 ~ end' - 印出從 start 到 end 之間的所有行
# $0 代表整行內容，~ 表示正規表達式匹配
EMAIL_BODY=$(awk -v start="$START_TIME" -v end="$END_TIME" '$0 ~ start, $0 ~ end' "$LOG_FILE")

# 【設定收件者】
# 可以設定多個收件者，用陣列的方式列出
# 【請修改】將 recipient1@example.com 改成實際的 Email
RECIPIENTS=("recipient1@example.com" "recipient2@example.com")

# 【建立臨時郵件檔案】
# mktemp 會在 /tmp 建立一個唯一的臨時檔案
# 檔案名稱類似：/tmp/tmp.ABC123xyz
TEMP_MAIL_FILE=$(mktemp)

# 寫入郵件主旨
echo "Subject: Instance Script Execution Log" > "$TEMP_MAIL_FILE"
# 寫入郵件內容（日誌）
echo "$EMAIL_BODY" >> "$TEMP_MAIL_FILE"

# 【發送郵件】
# 對每個收件者發送郵件
for email in "${RECIPIENTS[@]}"; do
  # sendmail 是 Linux 的郵件發送工具
  # -f "sender@example.com" - 設定寄件者地址【請修改】
  # -S "email-smtp....:587" - 設定 SMTP 伺服器和埠號
  # -au "username" - SMTP 認證使用者名稱【請修改】
  # -ap "password" - SMTP 認證密碼【請修改】
  # < "$TEMP_MAIL_FILE" - 將檔案內容作為郵件內容
  sendmail -f "sender@example.com" -S "email-smtp.us-east-1.amazonaws.com:587" \
           -au "Your-SMTP-User-Name" -ap "Your-SMTP-Password" \
           "$email" < "$TEMP_MAIL_FILE"
done

# 【檢查郵件發送結果】
# $? 是特殊變數，存放上一個指令的退出碼
# 0 表示成功，非 0 表示失敗
if [[ $? -eq 0 ]]; then
  log "Successfully sent email."
else
  log "Failed to send email."
fi

# 【清理臨時檔案】
# rm -f 刪除檔案，-f 表示強制刪除（不詢問確認）
rm -f "$TEMP_MAIL_FILE"


# ============================================================
# 【腳本結束】
# ============================================================
# 腳本執行完畢，Instance Store 應該已經掛載完成
# 可以使用以下指令確認掛載狀態：
#   df -h | grep instance_store
#   lsblk
#   mount | grep instance_store
# ============================================================
