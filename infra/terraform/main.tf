terraform {
  required_version = ">= 1.5.0"
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
# Data Sources
# ============================================================

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

# ============================================================
# VPC
# ============================================================

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

# ============================================================
# Subnets
# ============================================================

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = { Name = "${var.project_name}-public-subnet" }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}a"

  tags = { Name = "${var.project_name}-private-subnet-a" }
}

# RDS DB Subnet Group은 최소 2개 AZ를 요구하므로 2c도 생성
resource "aws_subnet" "private_c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${var.aws_region}c"

  tags = { Name = "${var.project_name}-private-subnet-c" }
}

# ============================================================
# Internet Gateway & Routing
# ============================================================

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.project_name}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ============================================================
# Security Groups
# ============================================================

resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "EC2 inbound: 80, 443, 22"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-ec2-sg" }
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "RDS inbound: 5432 from EC2 SG only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-rds-sg" }
}

# ============================================================
# IAM (EC2 → AWS services)
# ============================================================

resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = { Name = "${var.project_name}-ec2-role" }
}

resource "aws_iam_policy" "ec2_s3" {
  name        = "${var.project_name}-ec2-s3-policy"
  description = "Allow EC2 to access the project S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.storage.arn,
        "${aws_s3_bucket.storage.arn}/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_s3" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.ec2_s3.arn
}

# Spring AI가 사용하는 Claude 채팅과 Titan 임베딩 모델에만 추론 권한을 부여한다.
# `apac.*` inference profile은 APAC 내 여러 리전으로 요청을 분산할 수 있다.
resource "aws_iam_policy" "ec2_bedrock_inference" {
  name        = "${var.project_name}-ec2-bedrock-inference-policy"
  description = "Allow EC2 to invoke Bubli's Bedrock chat and embedding models"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeBubliModels"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          "arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0",
          "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-haiku-20240307-v1:0",
          "arn:aws:bedrock:*:*:inference-profile/apac.anthropic.claude-3-haiku-20240307-v1:0"
        ]
      },
      {
        Sid      = "ReadBubliInferenceProfile"
        Effect   = "Allow"
        Action   = "bedrock:GetInferenceProfile"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_bedrock_inference" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.ec2_bedrock_inference.arn
}

# RDS가 Secrets Manager에 관리하는 마스터 비밀번호는 EC2 역할만 읽는다.
resource "aws_iam_policy" "ec2_rds_master_secret" {
  name        = "${var.project_name}-ec2-rds-master-secret-policy"
  description = "Allow EC2 to read the RDS-managed database credential"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = aws_db_instance.postgres.master_user_secret[0].secret_arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_rds_master_secret" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.ec2_rds_master_secret.arn
}

# JWT와 Grafana 비밀번호는 첫 배포 때 EC2가 생성해 이 빈 시크릿에 보관한다.
resource "aws_secretsmanager_secret" "app_runtime" {
  name                    = "${var.project_name}/app-runtime"
  description             = "Bubli application secrets generated on first deployment"
  recovery_window_in_days = 7

  tags = { Name = "${var.project_name}-app-runtime" }
}

resource "aws_iam_policy" "ec2_app_runtime_secret" {
  name        = "${var.project_name}-ec2-app-runtime-secret-policy"
  description = "Allow EC2 to initialize and read Bubli runtime secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:PutSecretValue"
      ]
      Resource = aws_secretsmanager_secret.app_runtime.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_app_runtime_secret" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.ec2_app_runtime_secret.arn
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# ============================================================
# EC2
# ============================================================

resource "aws_instance" "app" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.ec2_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
  }

  user_data = <<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y docker git jq openssl unzip
    if ! command -v aws >/dev/null 2>&1; then
      curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscliv2.zip
      unzip -q /tmp/awscliv2.zip -d /tmp
      /tmp/aws/install
      rm -rf /tmp/aws /tmp/awscliv2.zip
    fi
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ec2-user
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -fsSL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

    cat > /home/ec2-user/.bubli-runtime.env <<'RUNTIME_ENV'
    BUBLI_AWS_REGION=${var.aws_region}
    BUBLI_DB_NAME=${var.db_name}
    BUBLI_S3_BUCKET_NAME=${aws_s3_bucket.storage.bucket}
    BUBLI_RDS_SECRET_ARN=${aws_db_instance.postgres.master_user_secret[0].secret_arn}
    BUBLI_APP_RUNTIME_SECRET_ARN=${aws_secretsmanager_secret.app_runtime.arn}
    RUNTIME_ENV
    chown ec2-user:ec2-user /home/ec2-user/.bubli-runtime.env
    chmod 600 /home/ec2-user/.bubli-runtime.env
  EOF

  tags = { Name = "${var.project_name}-app" }
}

# 도메인 DNS가 EC2 재시작 후에도 바뀌지 않도록 고정 공인 IP를 할당한다.
resource "aws_eip" "app" {
  domain = "vpc"

  tags = { Name = "${var.project_name}-app-eip" }
}

resource "aws_eip_association" "app" {
  instance_id   = aws_instance.app.id
  allocation_id = aws_eip.app.id
}

# ============================================================
# RDS PostgreSQL
# ============================================================

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_c.id]

  tags = { Name = "${var.project_name}-db-subnet-group" }
}

resource "aws_db_instance" "postgres" {
  identifier        = "${var.project_name}-postgres"
  engine            = "postgres"
  engine_version    = "16"
  instance_class    = var.rds_instance_type
  allocated_storage = 20
  storage_type      = "gp3"

  db_name                     = var.db_name
  username                    = var.db_username
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az                  = false
  publicly_accessible       = false
  backup_retention_period   = 0
  skip_final_snapshot       = false
  final_snapshot_identifier = "bubli-rds-final-snapshot"
  deletion_protection       = true

  tags = { Name = "${var.project_name}-postgres" }
}

# ============================================================
# S3
# ============================================================

resource "aws_s3_bucket" "storage" {
  bucket = var.s3_bucket_name

  tags = { Name = "${var.project_name}-storage" }
}

resource "aws_s3_bucket_public_access_block" "storage" {
  bucket = aws_s3_bucket.storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "storage" {
  bucket = aws_s3_bucket.storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
