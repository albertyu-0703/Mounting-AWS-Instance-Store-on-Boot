# AWS EC2 Instance Store 自動掛載腳本 (Basic 版)

簡單易用的 Instance Store 自動掛載解決方案。

---

## 版本選擇指南

本專案提供兩個版本分支，請依據您的需求選擇：

| 分支 | 適用場景 | 特點 |
|------|----------|------|
| **`basic`** (目前) | 簡單部署、單一 Instance Store | 單檔腳本、易於理解、郵件通知 |
| **[`advanced`](../../tree/advanced)** | 生產環境、多磁碟 RAID | 模組化設計、外部配置檔、完整功能 |
| **[`main`](../../tree/main)** | 與 `advanced` 相同 | 預設分支 |

### 功能比較表

| 功能 | `basic` | `advanced` |
|------|:-------:|:----------:|
| 自動偵測 Instance Store | ✅ | ✅ |
| 動態/靜態掛載點 | ✅ | ✅ |
| IMDSv2 支援 | ✅ | ✅ |
| 郵件通知 | ✅ | ✅ |
| RAID 0 支援 | ❌ | ✅ |
| XFS 檔案系統 | ❌ | ✅ |
| 外部配置檔 | ❌ | ✅ |
| 命令列參數 | ❌ | ✅ |
| Dry-run 模式 | ❌ | ✅ |
| systemd 服務 | ❌ | ✅ |
| 安裝/解除安裝腳本 | ❌ | ✅ |
| Cloud-init 範例 | ❌ | ✅ |
| Terraform 範例 | ❌ | ✅ |
| 程式碼註解 | 繁體中文 | 繁體中文 |

---

## Basic 版本說明

這是 **Basic 版本**，特點是：
- 單一檔案，簡單直觀
- 約 570 行（含詳細繁體中文註解）
- 適合快速部署和學習

> 如需更完整的功能（RAID 0、XFS、模組化配置），請使用 [advanced 分支](../../tree/advanced)

## 功能

- 自動偵測 Instance Store NVMe 裝置
- 自動格式化為 ext4 檔案系統
- 自動掛載到指定目錄
- IMDSv2 支援
- 執行日誌記錄
- 郵件通知（選用）

## 系統需求

- **作業系統**: Amazon Linux 2/2023、Ubuntu、Debian、RHEL、CentOS
- **權限**: 需要 root 權限
- **EC2 類型**: 必須支援 Instance Store（如 c5d、i3、d2 等）

### 必要套件

```bash
# Amazon Linux
sudo yum install -y curl util-linux e2fsprogs

# Ubuntu/Debian
sudo apt install -y curl util-linux e2fsprogs

# 如需郵件通知功能
sudo yum install -y sendmail  # 或 apt install sendmail
```

## 快速開始

```bash
# 1. 下載腳本
curl -O https://raw.githubusercontent.com/albertyu-0703/Mounting-AWS-Instance-Store-on-Boot/basic/InstanceStore.sh

# 2. 給予執行權限
chmod +x InstanceStore.sh

# 3. 執行（需要 root 權限）
sudo ./InstanceStore.sh

# 4. 確認掛載結果
df -h | grep instance_store
```

## 設定修改

編輯 `InstanceStore.sh`，找到以下區塊進行修改：

### 掛載點設定（第 249 行）

```bash
# 修改這個陣列來設定掛載點
MOUNT_POINTS=("/mnt/instance_store1" "/mnt/instance_store2" "/mnt/instance_store3")
```

### 郵件通知設定（第 397-420 行）

```bash
# 收件者
RECIPIENTS=("your-email@example.com")

# 寄件者和 SMTP 設定
sendmail -f "sender@example.com" -S "email-smtp.us-east-1.amazonaws.com:587" \
         -au "Your-SMTP-User-Name" -ap "Your-SMTP-Password" \
         "$email" < "$TEMP_MAIL_FILE"
```

## 開機自動執行

### 方法 1: Cron（建議）

```bash
sudo crontab -e
# 添加以下行：
@reboot /usr/local/bin/InstanceStore.sh
```

### 方法 2: Systemd

建立 `/etc/systemd/system/instance-store.service`：

```ini
[Unit]
Description=Mount Instance Store
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/InstanceStore.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

啟用服務：

```bash
sudo systemctl daemon-reload
sudo systemctl enable instance-store.service
```

## 日誌查看

```bash
# 查看日誌
cat /var/log/nvme_mount.log

# 即時追蹤日誌
tail -f /var/log/nvme_mount.log
```

## 程式碼結構說明

腳本分為以下區塊（詳細註解請見腳本內容）：

| 區塊 | 說明 |
|------|------|
| 區塊一 | 全域變數設定 |
| 區塊二 | 函數定義 (log) |
| 區塊三 | 腳本開始執行 |
| 區塊四 | 權限檢查 |
| 區塊五 | 取得 EC2 Metadata |
| 區塊六 | 偵測 Instance Store |
| 區塊七 | 解除現有掛載 |
| 區塊八 | 設定掛載點 |
| 區塊九 | 主要掛載邏輯 |
| 區塊十 | 腳本結束 |
| 區塊十一 | 呼叫其他腳本（選用） |
| 區塊十二 | 郵件通知功能 |

## lsblk 常用指令參考

```bash
# 查看所有區塊裝置
lsblk

# 查看詳細資訊（含型號）
lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT,MODEL

# 只看 Instance Store
lsblk -o NAME,MODEL | grep "Instance Storage"

# 查看檔案系統類型
lsblk -f
```

## 常見問題

### Q: 沒有偵測到 Instance Store？

1. 確認 EC2 類型支援 Instance Store（如 c5d、i3、d2 等）
2. 執行 `lsblk -o NAME,MODEL` 確認裝置

### Q: 掛載失敗？

1. 確認以 root 執行：`sudo ./InstanceStore.sh`
2. 檢查日誌：`cat /var/log/nvme_mount.log`

### Q: 重開機後資料消失？

這是正常的！Instance Store 是暫時性儲存：
- 實例停止 (Stop) 時資料會遺失
- 實例重開機 (Reboot) 時資料保留，但需重新掛載

## 作者

Albert Yu

## 授權

詳見 [LICENSE.md](LICENSE.md)
