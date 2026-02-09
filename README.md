# AWS EC2 Instance Store Auto-Mount

自動偵測並掛載 Amazon EC2 Instance Store (NVMe SSD) 的解決方案。

---

## 版本選擇指南

本專案提供兩個版本分支，請依據您的需求選擇：

| 分支 | 適用場景 | 特點 |
|------|----------|------|
| **[`basic`](../../tree/basic)** | 簡單部署、單一 Instance Store | 單檔腳本、易於理解、郵件通知 |
| **[`advanced`](../../tree/advanced)** | 生產環境、多磁碟 RAID | 模組化設計、外部配置檔、完整功能 |
| **`main`** | 與 `advanced` 相同 | 預設分支 |

### 如何選擇？

#### 選擇 `basic` 分支，如果您：

- 只有 **1 個 Instance Store** 裝置
- 想要 **簡單、快速** 部署
- 不需要 RAID 0 或 XFS
- 偏好 **單一腳本檔案**，易於閱讀與修改
- 需要 **郵件通知** 功能

```bash
# 切換到 basic 分支
git checkout basic

# 或直接下載
curl -O https://raw.githubusercontent.com/albertyu-0703/Mounting-AWS-Instance-Store-on-Boot/basic/InstanceStore.sh
```

#### 選擇 `advanced` 分支（或 main），如果您：

- 有 **多個 Instance Store** 裝置需要 RAID 0
- 需要 **XFS 檔案系統** 支援
- 想要 **外部配置檔** 管理設定
- 需要 **命令列參數** 彈性控制
- 部署於 **生產環境**，需要完整的服務管理
- 使用 **Cloud-init** 或 **Terraform** 自動化部署

```bash
# 使用 main 分支 (預設)
git clone https://github.com/albertyu-0703/Mounting-AWS-Instance-Store-on-Boot.git

# 或切換到 advanced 分支
git checkout advanced
```

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
| systemd 服務 | ❌ | ✅ |
| 安裝/解除安裝腳本 | ❌ | ✅ |
| Cloud-init 範例 | ❌ | ✅ |
| Terraform 範例 | ❌ | ✅ |
| Dry-run 模擬執行 | ❌ | ✅ |
| 程式碼註解 | 繁體中文 | 繁體中文 |

---

## 支援的作業系統

本腳本支援以下 Linux 發行版：

| 作業系統 | 版本 | 套件管理器 | 測試狀態 |
|----------|------|------------|----------|
| Amazon Linux | 2, 2023 | yum / dnf | ✅ 完整支援 |
| Ubuntu | 20.04, 22.04, 24.04 | apt | ✅ 完整支援 |
| Debian | 10, 11, 12 | apt | ✅ 完整支援 |
| RHEL | 7, 8, 9 | yum / dnf | ✅ 完整支援 |
| CentOS | 7, 8 Stream | yum / dnf | ✅ 完整支援 |
| Rocky Linux | 8, 9 | dnf | ✅ 完整支援 |
| Fedora | 38+ | dnf | ⚠️ 應可運作 |

> **注意**: 本腳本僅支援 Linux 作業系統，不支援 Windows。

## 系統需求與前置條件

### 必要條件

- **Root 權限**: 腳本需要 root 權限執行掛載操作
- **Bash 4.0+**: 腳本使用 bash 陣列功能，需要 bash 4.0 以上版本
- **EC2 環境**: 必須在 AWS EC2 實例上執行
- **Instance Store**: EC2 實例類型必須支援 Instance Store (如 c5d, i3, d2 等)

### 必要套件

| 套件 | 用途 | 必要性 |
|------|------|--------|
| `curl` | 取得 EC2 Metadata | 必要 |
| `util-linux` | lsblk, blkid, mount 等工具 | 必要 |
| `e2fsprogs` | ext4 檔案系統工具 (mkfs.ext4) | 使用 ext4 時必要 |
| `xfsprogs` | XFS 檔案系統工具 (mkfs.xfs) | 使用 XFS 時必要 |
| `mdadm` | RAID 管理工具 | 使用 RAID 0 模式時必要 |
| `nvme-cli` | NVMe 裝置管理工具 | 建議安裝 |

### 各作業系統安裝依賴

#### Amazon Linux 2 / Amazon Linux 2023

```bash
# Amazon Linux 2
sudo yum install -y mdadm nvme-cli curl util-linux e2fsprogs xfsprogs

# Amazon Linux 2023
sudo dnf install -y mdadm nvme-cli curl util-linux e2fsprogs xfsprogs
```

#### Ubuntu / Debian

```bash
sudo apt update
sudo apt install -y mdadm nvme-cli curl util-linux e2fsprogs xfsprogs
```

#### RHEL / CentOS / Rocky Linux

```bash
# RHEL 7 / CentOS 7
sudo yum install -y mdadm nvme-cli curl util-linux e2fsprogs xfsprogs

# RHEL 8+ / CentOS 8 Stream / Rocky Linux
sudo dnf install -y mdadm nvme-cli curl util-linux e2fsprogs xfsprogs
```

### 作業系統差異說明

#### 1. 套件管理器差異

| 發行版系列 | 套件管理器 | 安裝指令 |
|------------|------------|----------|
| Amazon Linux 2, RHEL 7, CentOS 7 | yum | `sudo yum install -y <package>` |
| Amazon Linux 2023, RHEL 8+, Rocky, Fedora | dnf | `sudo dnf install -y <package>` |
| Ubuntu, Debian | apt | `sudo apt install -y <package>` |

#### 2. 服務管理差異

所有支援的作業系統都使用 **systemd** 作為服務管理器：

```bash
# 啟用開機自動執行
sudo systemctl enable instance-store-mount.service

# 手動啟動服務
sudo systemctl start instance-store-mount.service

# 查看服務狀態
sudo systemctl status instance-store-mount.service
```

#### 3. NVMe 裝置命名

在所有支援的作業系統中，NVMe Instance Store 裝置名稱格式一致：

- **Instance Store**: `/dev/nvme1n1`, `/dev/nvme2n1`, ...
- **EBS (根磁碟)**: 通常為 `/dev/nvme0n1`

#### 4. 預設 Shell 差異

| 發行版 | 預設 Shell | 注意事項 |
|--------|------------|----------|
| Amazon Linux | bash | 無需調整 |
| Ubuntu | dash (sh), bash (login) | 腳本指定使用 bash |
| Debian | dash (sh), bash (login) | 腳本指定使用 bash |
| RHEL/CentOS | bash | 無需調整 |

> 本腳本在 shebang 中明確指定 `#!/bin/bash`，因此不受預設 shell 影響。

#### 5. SELinux 考量 (RHEL/CentOS)

在啟用 SELinux 的系統上，掛載點可能需要正確的安全上下文：

```bash
# 查看 SELinux 狀態
getenforce

# 如果遇到權限問題，可以設定掛載點的安全上下文
sudo chcon -R -t tmp_t /mnt/instance_store1
```

### 驗證系統環境

執行以下指令驗證系統是否符合需求：

```bash
# 檢查 bash 版本 (需要 4.0+)
bash --version

# 檢查是否在 EC2 環境
curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/instance-id && echo " - EC2 環境確認"

# 檢查是否有 Instance Store
lsblk -o NAME,MODEL | grep -i "Instance Storage"

# 檢查必要工具
for cmd in curl lsblk blkid mount mkfs.ext4; do
    command -v $cmd &>/dev/null && echo "✓ $cmd" || echo "✗ $cmd (缺少)"
done
```

## 功能特點

- **自動偵測** - 自動識別所有 Instance Store NVMe 裝置
- **多種掛載模式** - 支援單獨掛載 (single) 或 RAID 0 模式
- **動態/靜態掛載點** - 可自動生成或使用固定掛載點
- **多種檔案系統** - 支援 ext4 和 xfs
- **IMDSv2 支援** - 相容最新的 EC2 Metadata Service
- **開機自動執行** - 透過 systemd 服務自動掛載
- **郵件通知** - 可選的執行結果通知
- **模擬執行 (Dry-run)** - 預覽操作而不實際執行
- **Cloud-init 支援** - 提供 user-data 配置範例
- **Terraform 支援** - 提供 IaC 自動化部署範例

## 快速開始

### 方法 1: 使用安裝腳本

```bash
# 下載專案
git clone https://github.com/albertyu-0703/Mounting-AWS-Instance-Store-on-Boot.git
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

### 解除安裝

```bash
cd Mounting-AWS-Instance-Store-on-Boot
sudo bash scripts/uninstall.sh
```

解除安裝腳本會引導您：
- 停用並移除 systemd 服務與 udev 規則
- 選擇是否保留設定檔
- 選擇是否解除目前的 Instance Store 掛載
- 選擇是否移除日誌檔案

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

# 模擬執行 (不實際掛載，僅顯示將執行的操作)
sudo mount-instance-store --dry-run

# 組合使用
sudo mount-instance-store -m raid0 -f xfs --dry-run
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

# 模擬執行 (不實際操作)
DRY_RUN="false"
```

完整配置說明請參考 `config/mount-instance-store.conf`。

## Terraform 部署

使用 `terraform/main.tf` 可快速部署含 Instance Store 自動掛載的 EC2：

```bash
cd terraform

# 初始化
terraform init

# 預覽 (必須指定 SSH Key Pair 名稱)
terraform plan -var="key_name=my-key"

# 部署
terraform apply -var="key_name=my-key"

# 自訂設定
terraform apply \
  -var="key_name=my-key" \
  -var="instance_type=i3.xlarge" \
  -var="mount_mode=raid0" \
  -var="filesystem_type=xfs" \
  -var="allowed_ssh_cidr=203.0.113.0/24"
```

| 變數 | 預設值 | 說明 |
|------|--------|------|
| `aws_region` | `us-west-2` | AWS 區域 |
| `instance_type` | `c5d.large` | EC2 Instance 類型 |
| `key_name` | (必填) | SSH Key Pair 名稱 |
| `mount_mode` | `single` | 掛載模式: `single` 或 `raid0` |
| `filesystem_type` | `ext4` | 檔案系統: `ext4` 或 `xfs` |
| `allowed_ssh_cidr` | `0.0.0.0/0` | 允許 SSH 的 CIDR (建議限制為您的 IP) |

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
    ├── instance-store-types.md    # Instance Store 類型參考
    └── os-compatibility.md        # 作業系統相容性指南
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

- **v5.1** - 修復多項 bug：實作 dry-run、修復 --config 載入順序、修復 systemd oneshot 重試機制、修復 cloud-init mkfs 參數、Terraform 加入 IMDSv2 與變數驗證、uninstall 加入掛載清理
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
