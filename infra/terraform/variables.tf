variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "Project name used as a prefix for all resource names"
  type        = string
  default     = "bubli"
}

variable "key_name" {
  description = "EC2 key pair name (must already exist in AWS)"
  type        = string
  default     = "bubli-key"
}

variable "ec2_instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "rds_instance_type" {
  description = "RDS instance type"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "bublidb"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "bubli"
}

variable "s3_bucket_name" {
  description = "S3 bucket name for file storage (must be globally unique)"
  type        = string
}
