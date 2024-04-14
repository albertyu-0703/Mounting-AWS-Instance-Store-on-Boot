#!/bin/bash

# 設定日誌文件的位置
LOG_FILE="/var/log/nvme_mount.log"

# 確保 TEMP_MAIL_FILE 變量已設置，否則設置一個預設值
TEMP_MAIL_FILE="${TEMP_MAIL_FILE:-/tmp/temp_mail_file.txt}"

# log 函數用於將信息寫入日誌文件，同時添加時間戳記
log() {
  echo "$(date): $1" >> "$LOG_FILE"
}

# 腳本開始，寫入日誌
START_TIME=$(date +"%Y-%m-%d %H:%M:%S")
log "Script started at $START_TIME"

# 確保腳本以root權限運行，否則給出提示並退出
if [[ "$EUID" -ne 0 ]]; then
  log "Script failed: Please run as root"  # 將失敗訊息寫入日誌
  echo "Please run as root"
  exit 1
else
  log "Script is running as root"  # 將成功訊息寫入日誌
fi

# 獲取IMDSv2令牌
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

# 如果無法獲取令牌，則記錄錯誤但不終止腳本
if [[ -z "$TOKEN" ]]; then
  log "Failed to obtain IMDSv2 token. Continuing without it."
fi

# 使用令牌獲取EC2實例的元數據並寫入日誌
ACCOUNT_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep accountId | awk -F\" '{print $4}')
AVAILABILITY_ZONE=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)
INSTANCE_TYPE=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-type)
log "Account ID: $ACCOUNT_ID"
log "Availability Zone: $AVAILABILITY_ZONE"
log "Instance ID: $INSTANCE_ID"
log "Instance Type: $INSTANCE_TYPE"

# 收集 Instance Store 的數量和大小，並用逗號分隔多個大小
INSTANCE_STORE_COUNT=$(lsblk -o NAME,MODEL | grep "Instance Storage" | wc -l)
INSTANCE_STORE_SIZES=$(lsblk -o NAME,MODEL,SIZE | grep "Instance Storage" | awk '{print $(NF)}' | paste -sd "," -)
log "Instance Store Count: $INSTANCE_STORE_COUNT"
log "Instance Store Sizes: $INSTANCE_STORE_SIZES"

# 如果沒有檢測到 Instance Store，則終止腳本
if [[ "$INSTANCE_STORE_COUNT" -eq 0 ]]; then
  log "No Instance Stores detected. Terminating script."
  exit 1
fi

# 先解除已經掛載的Instance Store
mounted_instance_stores=$(mount | grep "Instance Storage" | awk '{print $3}')  # 取得已掛載的Instance Store掛載點

for mounted_point in $mounted_instance_stores; do
  umount $mounted_point
  log "Unmounted Instance Store from $mounted_point"
done

# 初始化變數，設定掛載點陣列
MOUNT_POINTS=("/mnt/instance_store1" "/mnt/instance_store2" "/mnt/instance_store3")  # 您可以根據需要添加或移除掛載點

# 寫入日誌，顯示設定的掛載點
log "Configured Mount Points: ${MOUNT_POINTS[*]}"

# 探測系統上的所有 Instance Storage 裝置
lsblk -o NAME,MODEL,SERIAL | grep "Instance Storage" | awk '{print $1}' | while read -r DEVICE_NAME; do
  # 如果 MOUNT_POINTS 陣列為空，則跳出循環
  if [ ${#MOUNT_POINTS[@]} -eq 0 ]; then
    log "No more mount points available in the array. Exiting loop."
    break
  fi

  # 裝置名稱須添加"/dev/"前綴
  DEVICE_NAME="/dev/$DEVICE_NAME"

  # 從陣列中取出第一個掛載點，然後移除它，以便下次使用其餘掛載點
  MOUNT_POINT=${MOUNT_POINTS[0]}
  MOUNT_POINTS=("${MOUNT_POINTS[@]:1}")

  # 如果掛載點目錄不存在，則創建它
  if [[ ! -d "$MOUNT_POINT" ]]; then
    mkdir -p "$MOUNT_POINT"
    log "Created mount point $MOUNT_POINT."
  fi

  # 檢查裝置是否已經格式化為 ext4
  if ! blkid "$DEVICE_NAME" | grep -q "ext4"; then
    # 如果沒有，進行格式化
    if ! mkfs -t ext4 -F "$DEVICE_NAME"; then
      log "Failed to format $DEVICE_NAME. Exiting."
      exit 1
    fi
    log "Formatted $DEVICE_NAME as ext4."
  fi

  # 將裝置掛載到掛載點
  if ! mount "$DEVICE_NAME" "$MOUNT_POINT"; then
    log "Failed to mount $DEVICE_NAME. Exiting."
    exit 1
  fi

  # 輸出成功掛載的日誌信息
  log "Mounted $DEVICE_NAME to $MOUNT_POINT."
done

# 腳本執行結束，寫入日誌
END_TIME=$(date +"%Y-%m-%d %H:%M:%S")
log "Script ended at $END_TIME"

# 呼叫其他腳本
# /usr/local/bin/script.sh

# 使用 awk 來過濾出腳本啟動和結束時間之間的日誌條目
EMAIL_BODY=$(awk -v start="$START_TIME" -v end="$END_TIME" '$0 ~ start, $0 ~ end' "$LOG_FILE")

# 收件者以陣列格式
RECIPIENTS=("recipient1@example.com" "recipient2@example.com")

# 創建臨時郵件文件
TEMP_MAIL_FILE=$(mktemp)
echo "Subject: Instance Script Execution Log" > "$TEMP_MAIL_FILE"
echo "$EMAIL_BODY" >> "$TEMP_MAIL_FILE"

# 使用 Amazon SES SMTP 服務發送郵件
for email in "${RECIPIENTS[@]}"; do
  sendmail -f "sender@example.com" -S "email-smtp.us-east-1.amazonaws.com:587" \
           -au "Your-SMTP-User-Name" -ap "Your-SMTP-Password" \
           "$email" < "$TEMP_MAIL_FILE"
done

# 檢查是否成功發送郵件，並寫入日誌
if [[ $? -eq 0 ]]; then
  log "Successfully sent email."
else
  log "Failed to send email."
fi

# 刪除臨時郵件文件
rm -f "$TEMP_MAIL_FILE"