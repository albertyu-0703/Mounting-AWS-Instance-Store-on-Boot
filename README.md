# EC2 Instance Storage Mount Script

這個 Bash 腳本用於自動掛載 Amazon EC2 Instance 的 Instance Storage，並將腳本的運行日誌記錄到指定的日誌文件中。此外，腳本會在掛載完成後向指定的收件人發送執行日誌。

## 功能

- 驗證腳本是否以 root 權限運行。
- 從 EC2 Instance Metadata Service (IMDS) 獲取實例的元數據。
- 檢測並掛載可用的 Instance Storage。
- 如果掛載失敗，腳本將終止執行。
- 將腳本的啟動和結束時間記錄到日誌文件。
- 創建臨時郵件文件並通過 SMTP 服務發送執行日誌。

## 前提條件

- 需要有 root 權限。
- 系統需安裝 `curl` 和 `sendmail` 工具。
- 必須在 EC2 實例上執行此腳本。

## 安裝與配置

1. 將腳本文件下載到您的 EC2 實例。
2. 確保腳本文件 (`mount_nvme.sh`) 具有可執行權限：
    
```bash
chmod +x mount_nvme.sh
````

## 使用方法

要運行腳本，使用以下命令：

```bash
sudo ./mount_nvme.sh
````

## **`lsblk`** 的常用指令及參數

1. **`lsblk`**：無參數時，顯示所有塊設備的列表。
2. **`lsblk -a`**：列出所有的塊設備，包括空的設備。
3. **`lsblk -f`**：列出所有塊設備，並且顯示文件系統的類型。
4. **`lsblk -l`**：以列表格式顯示塊設備。
5. **`lsblk -m`**：顯示塊設備的擁有者和權限信息。
6. **`lsblk -p`**：顯示設備的完整路徑名。
7. **`lsblk -s`**：顯示每個塊設備的大小。
8. **`lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT`**：自定義列的輸出。在這個例子中，它顯示了設備名稱、大小、文件系統類型、設備類型和掛載點。
9. **`lsblk /dev/sda`**：顯示特定設備的信息，如 **`/dev/sda`**。