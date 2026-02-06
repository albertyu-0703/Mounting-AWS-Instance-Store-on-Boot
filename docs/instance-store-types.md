# AWS EC2 Instance Store 類型參考

本文件列出支援 Instance Store 的 EC2 Instance 類型及其規格。

## Instance Store 特性

- **暫時性儲存**: 資料在實例停止、終止或硬體故障時遺失
- **NVMe SSD**: 現代 Instance Store 使用 NVMe SSD，提供高 IOPS
- **無額外費用**: Instance Store 包含在 EC2 費用中
- **重開機保留**: Reboot 時資料保留，但 Stop/Start 時會遺失

## 通用運算 (General Purpose)

### M5d 系列

| Instance Type | Instance Store | 容量 | 備註 |
|---------------|----------------|------|------|
| m5d.large | 1 x 75 GB | 75 GB | |
| m5d.xlarge | 1 x 150 GB | 150 GB | |
| m5d.2xlarge | 1 x 300 GB | 300 GB | |
| m5d.4xlarge | 2 x 300 GB | 600 GB | |
| m5d.8xlarge | 2 x 600 GB | 1.2 TB | |
| m5d.12xlarge | 2 x 900 GB | 1.8 TB | |
| m5d.16xlarge | 4 x 600 GB | 2.4 TB | |
| m5d.24xlarge | 4 x 900 GB | 3.6 TB | |
| m5d.metal | 4 x 900 GB | 3.6 TB | |

### M6id 系列 (第六代)

| Instance Type | Instance Store | 容量 |
|---------------|----------------|------|
| m6id.large | 1 x 118 GB | 118 GB |
| m6id.xlarge | 1 x 237 GB | 237 GB |
| m6id.2xlarge | 1 x 474 GB | 474 GB |
| m6id.4xlarge | 1 x 950 GB | 950 GB |
| m6id.8xlarge | 1 x 1900 GB | 1.9 TB |
| m6id.12xlarge | 2 x 1425 GB | 2.85 TB |
| m6id.16xlarge | 2 x 1900 GB | 3.8 TB |
| m6id.24xlarge | 4 x 1425 GB | 5.7 TB |
| m6id.32xlarge | 4 x 1900 GB | 7.6 TB |

## 運算優化 (Compute Optimized)

### C5d 系列

| Instance Type | Instance Store | 容量 |
|---------------|----------------|------|
| c5d.large | 1 x 50 GB | 50 GB |
| c5d.xlarge | 1 x 100 GB | 100 GB |
| c5d.2xlarge | 1 x 200 GB | 200 GB |
| c5d.4xlarge | 1 x 400 GB | 400 GB |
| c5d.9xlarge | 1 x 900 GB | 900 GB |
| c5d.12xlarge | 2 x 900 GB | 1.8 TB |
| c5d.18xlarge | 2 x 900 GB | 1.8 TB |
| c5d.24xlarge | 4 x 900 GB | 3.6 TB |
| c5d.metal | 4 x 900 GB | 3.6 TB |

### C6id 系列 (第六代)

| Instance Type | Instance Store | 容量 |
|---------------|----------------|------|
| c6id.large | 1 x 118 GB | 118 GB |
| c6id.xlarge | 1 x 237 GB | 237 GB |
| c6id.2xlarge | 1 x 474 GB | 474 GB |
| c6id.4xlarge | 1 x 950 GB | 950 GB |
| c6id.8xlarge | 1 x 1900 GB | 1.9 TB |
| c6id.12xlarge | 2 x 1425 GB | 2.85 TB |
| c6id.16xlarge | 2 x 1900 GB | 3.8 TB |
| c6id.24xlarge | 4 x 1425 GB | 5.7 TB |
| c6id.32xlarge | 4 x 1900 GB | 7.6 TB |

## 記憶體優化 (Memory Optimized)

### R5d 系列

| Instance Type | Instance Store | 容量 |
|---------------|----------------|------|
| r5d.large | 1 x 75 GB | 75 GB |
| r5d.xlarge | 1 x 150 GB | 150 GB |
| r5d.2xlarge | 1 x 300 GB | 300 GB |
| r5d.4xlarge | 2 x 300 GB | 600 GB |
| r5d.8xlarge | 2 x 600 GB | 1.2 TB |
| r5d.12xlarge | 2 x 900 GB | 1.8 TB |
| r5d.16xlarge | 4 x 600 GB | 2.4 TB |
| r5d.24xlarge | 4 x 900 GB | 3.6 TB |
| r5d.metal | 4 x 900 GB | 3.6 TB |

## 儲存優化 (Storage Optimized)

### I3 系列 (高 IOPS)

| Instance Type | Instance Store | 容量 | IOPS |
|---------------|----------------|------|------|
| i3.large | 1 x 475 GB | 475 GB | 103,000 |
| i3.xlarge | 1 x 950 GB | 950 GB | 206,000 |
| i3.2xlarge | 1 x 1900 GB | 1.9 TB | 412,000 |
| i3.4xlarge | 2 x 1900 GB | 3.8 TB | 825,000 |
| i3.8xlarge | 4 x 1900 GB | 7.6 TB | 1.65M |
| i3.16xlarge | 8 x 1900 GB | 15.2 TB | 3.3M |
| i3.metal | 8 x 1900 GB | 15.2 TB | 3.3M |

### I3en 系列 (高密度)

| Instance Type | Instance Store | 容量 |
|---------------|----------------|------|
| i3en.large | 1 x 1250 GB | 1.25 TB |
| i3en.xlarge | 1 x 2500 GB | 2.5 TB |
| i3en.2xlarge | 2 x 2500 GB | 5 TB |
| i3en.3xlarge | 1 x 7500 GB | 7.5 TB |
| i3en.6xlarge | 2 x 7500 GB | 15 TB |
| i3en.12xlarge | 4 x 7500 GB | 30 TB |
| i3en.24xlarge | 8 x 7500 GB | 60 TB |
| i3en.metal | 8 x 7500 GB | 60 TB |

### D2 系列 (高密度 HDD)

| Instance Type | Instance Store | 容量 |
|---------------|----------------|------|
| d2.xlarge | 3 x 2000 GB | 6 TB |
| d2.2xlarge | 6 x 2000 GB | 12 TB |
| d2.4xlarge | 12 x 2000 GB | 24 TB |
| d2.8xlarge | 24 x 2000 GB | 48 TB |

### D3 系列 (新一代高密度)

| Instance Type | Instance Store | 容量 |
|---------------|----------------|------|
| d3.xlarge | 3 x 1980 GB | 5.94 TB |
| d3.2xlarge | 6 x 1980 GB | 11.88 TB |
| d3.4xlarge | 12 x 1980 GB | 23.76 TB |
| d3.8xlarge | 24 x 1980 GB | 47.52 TB |

## GPU 運算

### G4dn 系列

| Instance Type | Instance Store | 容量 |
|---------------|----------------|------|
| g4dn.xlarge | 1 x 125 GB | 125 GB |
| g4dn.2xlarge | 1 x 225 GB | 225 GB |
| g4dn.4xlarge | 1 x 225 GB | 225 GB |
| g4dn.8xlarge | 1 x 900 GB | 900 GB |
| g4dn.12xlarge | 1 x 900 GB | 900 GB |
| g4dn.16xlarge | 1 x 900 GB | 900 GB |
| g4dn.metal | 2 x 900 GB | 1.8 TB |

### P3dn 系列

| Instance Type | Instance Store | 容量 |
|---------------|----------------|------|
| p3dn.24xlarge | 2 x 900 GB | 1.8 TB |

## 選擇建議

### 依使用案例

| 使用案例 | 建議 Instance 類型 |
|----------|-------------------|
| 資料庫暫存 | i3, i3en |
| 快取服務 | c5d, c6id |
| 機器學習訓練 | g4dn, p3dn |
| 大數據處理 | d2, d3 |
| 通用工作負載 | m5d, m6id |

### 依效能需求

| 需求 | 建議 |
|------|------|
| 最高 IOPS | i3.16xlarge (3.3M IOPS) |
| 最大容量 | i3en.metal (60 TB) |
| 成本效益 | d2/d3 系列 |
| 低延遲 | c5d/c6id 系列 |

## 參考資源

- [AWS EC2 Instance Types](https://aws.amazon.com/ec2/instance-types/)
- [Instance Store Volumes](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/InstanceStorage.html)
- [EC2 Pricing](https://aws.amazon.com/ec2/pricing/)
