# 作業系統相容性與設定指南

本文件詳細說明各 Linux 發行版的相容性、設定差異及注意事項。

## 支援的作業系統

### 完整支援

| 作業系統 | 版本 | AMI 名稱範例 |
|----------|------|--------------|
| Amazon Linux | 2 | amzn2-ami-hvm-* |
| Amazon Linux | 2023 | al2023-ami-* |
| Ubuntu | 20.04 LTS | ubuntu/images/hvm-ssd/ubuntu-focal-* |
| Ubuntu | 22.04 LTS | ubuntu/images/hvm-ssd/ubuntu-jammy-* |
| Ubuntu | 24.04 LTS | ubuntu/images/hvm-ssd/ubuntu-noble-* |
| Debian | 11 (Bullseye) | debian-11-* |
| Debian | 12 (Bookworm) | debian-12-* |
| RHEL | 8 | RHEL-8* |
| RHEL | 9 | RHEL-9* |
| CentOS | 7 | CentOS-7* |
| Rocky Linux | 8, 9 | Rocky-8*, Rocky-9* |

### 應可運作 (未完整測試)

- Fedora 38+
- openSUSE Leap 15+
- Oracle Linux 8, 9

### 不支援

- Windows Server (所有版本)
- macOS
- FreeBSD

## 套件安裝指南

### Amazon Linux 2

```bash
# 更新系統
sudo yum update -y

# 安裝必要套件
sudo yum install -y \
    mdadm \
    nvme-cli \
    curl \
    util-linux \
    e2fsprogs \
    xfsprogs

# 驗證安裝
rpm -q mdadm nvme-cli
```

### Amazon Linux 2023

```bash
# 更新系統
sudo dnf update -y

# 安裝必要套件
sudo dnf install -y \
    mdadm \
    nvme-cli \
    curl \
    util-linux \
    e2fsprogs \
    xfsprogs

# 驗證安裝
rpm -q mdadm nvme-cli
```

### Ubuntu / Debian

```bash
# 更新套件列表
sudo apt update

# 安裝必要套件
sudo apt install -y \
    mdadm \
    nvme-cli \
    curl \
    util-linux \
    e2fsprogs \
    xfsprogs

# 驗證安裝
dpkg -l | grep -E "mdadm|nvme-cli"
```

### RHEL 8/9

```bash
# 註冊系統 (如果尚未註冊)
# sudo subscription-manager register

# 啟用必要的 repository
sudo dnf install -y epel-release

# 安裝必要套件
sudo dnf install -y \
    mdadm \
    nvme-cli \
    curl \
    util-linux \
    e2fsprogs \
    xfsprogs
```

### CentOS 7

```bash
# 啟用 EPEL repository
sudo yum install -y epel-release

# 安裝必要套件
sudo yum install -y \
    mdadm \
    nvme-cli \
    curl \
    util-linux \
    e2fsprogs \
    xfsprogs
```

### Rocky Linux / AlmaLinux

```bash
# 啟用 EPEL repository
sudo dnf install -y epel-release

# 安裝必要套件
sudo dnf install -y \
    mdadm \
    nvme-cli \
    curl \
    util-linux \
    e2fsprogs \
    xfsprogs
```

## 作業系統差異詳解

### 1. 初始化系統 (Init System)

所有現代 Linux 發行版都使用 **systemd**：

| 發行版 | Init System | 服務管理指令 |
|--------|-------------|--------------|
| Amazon Linux 2/2023 | systemd | systemctl |
| Ubuntu 20.04+ | systemd | systemctl |
| Debian 10+ | systemd | systemctl |
| RHEL 7+ | systemd | systemctl |
| CentOS 7+ | systemd | systemctl |

舊版系統 (如 CentOS 6) 使用 SysVinit，本腳本不支援。

### 2. 檔案系統工具

#### ext4

| 發行版 | 套件名稱 | 工具路徑 |
|--------|----------|----------|
| Amazon Linux | e2fsprogs | /sbin/mkfs.ext4 |
| Ubuntu/Debian | e2fsprogs | /sbin/mkfs.ext4 |
| RHEL/CentOS | e2fsprogs | /usr/sbin/mkfs.ext4 |

#### XFS

| 發行版 | 套件名稱 | 工具路徑 |
|--------|----------|----------|
| Amazon Linux | xfsprogs | /sbin/mkfs.xfs |
| Ubuntu/Debian | xfsprogs | /sbin/mkfs.xfs |
| RHEL/CentOS | xfsprogs | /usr/sbin/mkfs.xfs |

### 3. NVMe 裝置識別

不同作業系統識別 NVMe 裝置的方式相同：

```bash
# 方法 1: lsblk (所有發行版)
lsblk -o NAME,MODEL | grep "Instance Storage"

# 方法 2: nvme-cli (需安裝)
nvme list | grep "Instance Storage"

# 方法 3: 檢查 /sys (所有發行版)
cat /sys/block/nvme1n1/device/model
```

### 4. 預設掛載選項

各發行版的 `/etc/fstab` 格式相同，但預設掛載選項可能略有差異：

```bash
# 建議的掛載選項 (適用所有發行版)
defaults,noatime,nodiratime

# 高效能選項
defaults,noatime,nodiratime,discard
```

### 5. SELinux (RHEL 系列)

RHEL、CentOS、Rocky Linux 預設啟用 SELinux：

```bash
# 查看 SELinux 狀態
getenforce

# 暫時設為寬容模式 (排錯用)
sudo setenforce 0

# 永久停用 (不建議)
# sudo sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config

# 為掛載點設定正確的安全上下文
sudo chcon -R -t tmp_t /mnt/instance_store1
# 或
sudo chcon -R -t var_t /mnt/instance_store1
```

### 6. AppArmor (Ubuntu/Debian)

Ubuntu 和 Debian 使用 AppArmor，通常不會影響 Instance Store 掛載：

```bash
# 查看 AppArmor 狀態
sudo aa-status

# 如果遇到問題，可以查看日誌
sudo dmesg | grep apparmor
```

### 7. Cloud-init 差異

各發行版的 cloud-init 配置位置：

| 發行版 | Cloud-init 配置路徑 |
|--------|---------------------|
| Amazon Linux | /etc/cloud/cloud.cfg.d/ |
| Ubuntu | /etc/cloud/cloud.cfg.d/ |
| Debian | /etc/cloud/cloud.cfg.d/ |
| RHEL/CentOS | /etc/cloud/cloud.cfg.d/ |

所有發行版的 user-data 格式相同 (YAML)。

## 開機執行方式比較

### 方法 1: Systemd 服務 (建議)

適用所有現代發行版：

```bash
# 複製服務檔案
sudo cp systemd/instance-store-mount.service /etc/systemd/system/

# 重新載入 systemd
sudo systemctl daemon-reload

# 啟用開機自動執行
sudo systemctl enable instance-store-mount.service

# 立即啟動
sudo systemctl start instance-store-mount.service
```

### 方法 2: Cron @reboot

適用所有發行版：

```bash
# 編輯 root 的 crontab
sudo crontab -e

# 添加以下行
@reboot /usr/local/bin/mount-instance-store >> /var/log/instance-store-mount.log 2>&1
```

### 方法 3: rc.local (較舊的方法)

僅適用於仍支援 rc.local 的系統：

```bash
# 確保 rc.local 可執行
sudo chmod +x /etc/rc.local

# 編輯 rc.local
sudo vim /etc/rc.local

# 在 exit 0 之前添加
/usr/local/bin/mount-instance-store
```

> **注意**: Ubuntu 18.04+ 和 Debian 10+ 預設不啟用 rc.local，需要額外配置。

## 疑難排解

### Amazon Linux 特有問題

```bash
# 如果 nvme-cli 找不到
sudo amazon-linux-extras install epel -y
sudo yum install -y nvme-cli
```

### Ubuntu/Debian 特有問題

```bash
# 如果 mdadm 詢問郵件設定
echo "mdadm mdadm/mail_to string root" | sudo debconf-set-selections
sudo DEBIAN_FRONTEND=noninteractive apt install -y mdadm
```

### RHEL/CentOS 特有問題

```bash
# 如果缺少 EPEL repository
sudo yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E %rhel).noarch.rpm

# SELinux 阻擋問題
sudo ausearch -m avc -ts recent
sudo sealert -a /var/log/audit/audit.log
```

## 效能調校建議

### 通用建議 (所有發行版)

```bash
# I/O 排程器 (NVMe 建議使用 none 或 mq-deadline)
echo "none" | sudo tee /sys/block/nvme1n1/queue/scheduler

# 預讀大小
echo 256 | sudo tee /sys/block/nvme1n1/queue/read_ahead_kb
```

### 檔案系統選擇

| 使用案例 | 建議檔案系統 | 原因 |
|----------|--------------|------|
| 通用工作負載 | ext4 | 穩定、相容性好 |
| 大檔案、高並發 | XFS | 效能較佳 |
| 資料庫暫存 | XFS | 支援更大檔案 |
| 容器 overlay | ext4/XFS | 兩者皆可 |

## 參考資源

- [Amazon Linux 2 使用者指南](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/amazon-linux-2-virtual-machine.html)
- [Ubuntu EC2 AMI](https://cloud-images.ubuntu.com/locator/ec2/)
- [RHEL on AWS](https://aws.amazon.com/partners/redhat/)
- [EC2 Instance Store](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/InstanceStorage.html)
