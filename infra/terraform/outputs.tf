output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "ec2_public_ip" {
  description = "Elastic IP assigned to EC2 (use this for DNS and EC2_HOST secret)"
  value       = aws_eip.app.public_ip
}

output "ec2_elastic_ip" {
  description = "Elastic IP assigned to EC2"
  value       = aws_eip.app.public_ip
}

output "ec2_instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.app.id
}

output "rds_endpoint" {
  description = "RDS endpoint hostname (injected into .env.aws automatically at deployment)"
  value       = aws_db_instance.postgres.address
}

output "rds_port" {
  description = "RDS port"
  value       = aws_db_instance.postgres.port
}

output "rds_master_secret_arn" {
  description = "RDS-managed credential secret ARN (readable by the EC2 role only)"
  value       = aws_db_instance.postgres.master_user_secret[0].secret_arn
}

output "app_runtime_secret_arn" {
  description = "Application runtime secret ARN (initialized by EC2 on first deployment)"
  value       = aws_secretsmanager_secret.app_runtime.arn
}

output "s3_bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.storage.bucket
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.storage.arn
}
