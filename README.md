# AWS EC2 Instance Store Auto-Mount

自動偵測並掛載 Amazon EC2 Instance Store (NVMe SSD) 的解決方案。

## 功能特點

- **自動偵測** - 自動識別所有 Instance Store NVMe 裝置
- **多種掛載模式** - 支援單獨掛載 (single) 或 RAID 0 模式
- **動態/靜態掛載點** - 可自動生成或使用固定掛載點
- **多種檔案系統** - 支援 ext4 和 xfs
- **IMDSv2 支援** - 相容最新的 EC2 Metadata Service
- **開機自動執行** - 透過 systemd 服務自動掛載
- **郵件通知** - 可選的執行結果通知
- **Cloud-init 支援** - 提供 user-data 配置範例

## 快速開始

### 方法 1: 使用安裝腳本

```bash
# 下載專案
git clone https://github.com/your-repo/Mounting-AWS-Instance-Store-on-Boot.git
cd Mounting-AWS-Instance-Store-on-Boot

# 執行安裝
sudo bash scripts/install.sh
```

### 方法 2: Cloud-init (Launch Template)

將 `cloud-init/user-data.yaml` 的內容貼到 EC2 的 User Data 欄位。

### 方法 3: 手動安裝

```bash
# 複製腳本
sudo cp scripts/mount-instance-store.sh /usr/local/bin/mount-instance-store
sudo chmod +x /usr/local/bin/mount-instance-store

# 複製設定檔
sudo mkdir -p /etc/instance-store-mount
sudo cp config/mount-instance-store.conf /etc/instance-store-mount/

# 複製 systemd 服務
sudo cp systemd/instance-store-mount.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable instance-store-mount.service

# 立即執行
sudo systemctl start instance-store-mount.service
```

## 使用方式

### 命令列選項

```bash
# 顯示幫助
mount-instance-store --help

# 使用預設配置執行
sudo mount-instance-store

# 使用 RAID 0 模式
sudo mount-instance-store -m raid0

# 使用 XFS 檔案系統
sudo mount-instance-store -f xfs

# 指定配置檔
sudo mount-instance-store -c /path/to/config.conf

# 使用動態掛載點
sudo mount-instance-store -d

# 使用靜態掛載點
sudo mount-instance-store -s
```

### 服務管理

```bash
# 查看服務狀態
sudo systemctl status instance-store-mount

# 手動啟動
sudo systemctl start instance-store-mount

# 重新執行
sudo systemctl restart instance-store-mount

# 查看日誌
sudo journalctl -u instance-store-mount
sudo tail -f /var/log/instance-store-mount.log
```

## 配置說明

編輯 `/etc/instance-store-mount/mount-instance-store.conf`:

```bash
# 掛載模式: single 或 raid0
MOUNT_MODE="single"

# 動態生成掛載點
DYNAMIC_MOUNT="true"

# 靜態掛載點 (當 DYNAMIC_MOUNT=false)
MOUNT_POINTS="/mnt/data1 /mnt/data2"

# 檔案系統: ext4 或 xfs
FILESYSTEM_TYPE="ext4"

# RAID 設定
RAID_MOUNT_POINT="/mnt/instance_store"
RAID_CHUNK_SIZE="256"
```

完整配置說明請參考 `config/mount-instance-store.conf`。

## 支援的 EC2 Instance 類型

以下是常見支援 Instance Store 的 EC2 類型:

| 類型 | Instance Store 數量 | 單個容量 |
|------|---------------------|----------|
| c5d.large | 1 | 50 GB |
| c5d.xlarge | 1 | 100 GB |
| c5d.2xlarge | 1 | 200 GB |
| c5d.4xlarge | 1 | 400 GB |
| c5d.9xlarge | 1 | 900 GB |
| c5d.18xlarge | 2 | 900 GB |
| i3.large | 1 | 475 GB |
| i3.xlarge | 1 | 950 GB |
| i3.2xlarge | 1 | 1900 GB |
| i3.4xlarge | 2 | 1900 GB |
| i3.8xlarge | 4 | 1900 GB |
| i3.16xlarge | 8 | 1900 GB |
| d2.xlarge | 3 | 2000 GB |
| d2.2xlarge | 6 | 2000 GB |
| d2.4xlarge | 12 | 2000 GB |
| d2.8xlarge | 24 | 2000 GB |

## 開機執行方式

### 1. Systemd (建議)

```bash
sudo systemctl enable instance-store-mount.service
```

### 2. Cron @reboot

```bash
sudo crontab -e
# 添加以下行:
@reboot /usr/local/bin/mount-instance-store
```

### 3. rc.local

```bash
# 編輯 /etc/rc.local
sudo vim /etc/rc.local

# 在 exit 0 之前添加:
/usr/local/bin/mount-instance-store
```

## 目錄結構

```
Mounting-AWS-Instance-Store-on-Boot/
├── README.md                  # 本文件
├── LICENSE.md                 # 授權條款
├── scripts/
│   ├── mount-instance-store.sh    # 主要掛載腳本
│   ├── install.sh                 # 安裝腳本
│   └── uninstall.sh               # 解除安裝腳本
├── config/
│   └── mount-instance-store.conf  # 配置檔範例
├── systemd/
│   └── instance-store-mount.service  # systemd 服務檔
├── cloud-init/
│   ├── user-data.yaml             # Cloud-init 配置 (單獨掛載)
│   └── user-data-raid0.yaml       # Cloud-init 配置 (RAID 0)
├── terraform/
│   └── main.tf                    # Terraform 範例
└── docs/
    └── instance-store-types.md    # Instance Store 類型參考
```

## 常用指令參考

### lsblk 查看區塊裝置

```bash
# 查看所有區塊裝置
lsblk

# 查看詳細資訊 (含 MODEL)
lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT,MODEL

# 查看 Instance Store
lsblk -o NAME,MODEL | grep "Instance Storage"
```

### nvme 工具

```bash
# 列出所有 NVMe 裝置
sudo nvme list

# 查看 NVMe 裝置資訊
sudo nvme id-ctrl /dev/nvme1n1
```

### 掛載相關

```bash
# 查看目前掛載
mount | grep instance_store
df -h | grep instance_store

# 手動掛載
sudo mount /dev/nvme1n1 /mnt/instance_store1

# 解除掛載
sudo umount /mnt/instance_store1
```

## 版本歷史

- **v5.0** - 整合所有版本功能，新增命令列選項、模組化配置
- **v4.0** - 新增郵件通知功能
- **v3.0** - 新增解除現有掛載、固定掛載點陣列
- **v2.0** - 新增動態/靜態掛載點切換、嚴格比對檢查
- **v1.0** - 基本掛載功能、支援多個 Instance Store

## 注意事項

1. **Instance Store 是暫時性儲存** - 資料會在實例停止、終止或硬體故障時遺失
2. **重開機後需重新掛載** - Instance Store 的資料在重開機後會被清除
3. **不適合存放重要資料** - 請使用 EBS 或 S3 儲存重要資料
4. **RAID 0 無冗餘** - RAID 0 提供效能但無容錯能力

## 疑難排解

### 未偵測到 Instance Store

1. 確認 EC2 Instance 類型支援 Instance Store
2. 檢查 Instance Store 是否在啟動時已配置
3. 使用 `lsblk -o NAME,MODEL` 確認裝置

### 掛載失敗

1. 檢查裝置是否已被掛載: `mount | grep nvme`
2. 確認有 root 權限
3. 查看日誌: `cat /var/log/instance-store-mount.log`

### RAID 建立失敗

1. 確認 mdadm 已安裝: `which mdadm`
2. 清除舊的 RAID superblock: `sudo mdadm --zero-superblock /dev/nvme*n1`
3. 檢查是否有其他 RAID 使用中: `cat /proc/mdstat`

## 授權

本軟體採用自訂授權條款，允許自由使用和修改，但禁止作為商業解決方案提供。
詳見 [LICENSE.md](LICENSE.md)。

## 作者

Albert Yu

## 貢獻

歡迎提交 Issue 和 Pull Request。
