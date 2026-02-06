# ============================================================
# Terraform 範例: EC2 + Instance Store 自動掛載
# ============================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ============================================================
# Variables
# ============================================================

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-west-2"
}

variable "instance_type" {
  description = "EC2 Instance Type (must support Instance Store)"
  type        = string
  default     = "c5d.large" # 1x 50GB NVMe SSD
}

variable "ami_id" {
  description = "AMI ID (Amazon Linux 2023)"
  type        = string
  default     = ""
}

variable "key_name" {
  description = "SSH Key Pair Name"
  type        = string
}

variable "mount_mode" {
  description = "Mount mode: single or raid0"
  type        = string
  default     = "single"
}

variable "filesystem_type" {
  description = "Filesystem type: ext4 or xfs"
  type        = string
  default     = "ext4"
}

# ============================================================
# Data Sources
# ============================================================

# 取得最新的 Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ============================================================
# User Data (cloud-init)
# ============================================================

locals {
  user_data = <<-EOF
    #!/bin/bash
    # Instance Store Auto-Mount Script

    LOG="/var/log/instance-store-mount.log"
    MOUNT_MODE="${var.mount_mode}"
    FS_TYPE="${var.filesystem_type}"

    log() { echo "$(date '+%F %T') $1" | tee -a "$LOG"; }

    log "INFO: Installing dependencies..."
    dnf install -y mdadm nvme-cli

    log "INFO: Detecting Instance Store..."
    DEVS=()
    for d in /dev/nvme*n1; do
        [[ ! -b "$d" ]] && continue
        name=$(basename "$d")
        model=$(cat "/sys/block/$name/device/model" 2>/dev/null | tr -d ' ')
        [[ "$model" != "AmazonElasticBlockStore" ]] && DEVS+=("$d")
    done

    COUNT=$${#DEVS[@]}
    log "INFO: Found $COUNT Instance Store device(s)"

    [[ $COUNT -eq 0 ]] && { log "WARN: No Instance Store"; exit 0; }

    if [[ "$MOUNT_MODE" == "raid0" ]] && [[ $COUNT -gt 1 ]]; then
        RAID_DEV="/dev/md0"
        MOUNT_PT="/mnt/instance_store"

        for d in "$${DEVS[@]}"; do
            mdadm --zero-superblock "$d" 2>/dev/null || true
        done

        yes | mdadm --create "$RAID_DEV" --level=0 --raid-devices=$COUNT "$${DEVS[@]}"
        mkfs.$FS_TYPE -f "$RAID_DEV" 2>/dev/null || mkfs.$FS_TYPE -F "$RAID_DEV"
        mkdir -p "$MOUNT_PT"
        mount -o defaults,noatime "$RAID_DEV" "$MOUNT_PT"
        chmod 1777 "$MOUNT_PT"
        log "INFO: RAID 0 mounted at $MOUNT_PT"
    else
        idx=1
        for d in "$${DEVS[@]}"; do
            MOUNT_PT="/mnt/instance_store$idx"
            mkfs.$FS_TYPE -f "$d" 2>/dev/null || mkfs.$FS_TYPE -F "$d"
            mkdir -p "$MOUNT_PT"
            mount -o defaults,noatime "$d" "$MOUNT_PT"
            chmod 1777 "$MOUNT_PT"
            log "INFO: Mounted $d at $MOUNT_PT"
            ((idx++))
        done
    fi

    df -h | grep instance_store | tee -a "$LOG"
  EOF
}

# ============================================================
# Resources
# ============================================================

resource "aws_security_group" "instance_store_demo" {
  name_prefix = "instance-store-demo-"
  description = "Security group for Instance Store demo"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "instance-store-demo"
  }
}

resource "aws_instance" "with_instance_store" {
  ami           = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2023.id
  instance_type = var.instance_type
  key_name      = var.key_name

  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.instance_store_demo.id]
  associate_public_ip_address = true

  user_data = local.user_data

  # Instance Store 需要設定 ephemeral block device mappings
  # 對於 NVMe Instance Store，這通常會自動處理

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = "instance-store-demo"
  }
}

# ============================================================
# Outputs
# ============================================================

output "instance_id" {
  value = aws_instance.with_instance_store.id
}

output "public_ip" {
  value = aws_instance.with_instance_store.public_ip
}

output "ssh_command" {
  value = "ssh -i ~/.ssh/${var.key_name}.pem ec2-user@${aws_instance.with_instance_store.public_ip}"
}

output "check_mount_command" {
  value = "ssh -i ~/.ssh/${var.key_name}.pem ec2-user@${aws_instance.with_instance_store.public_ip} 'df -h | grep instance_store'"
}
