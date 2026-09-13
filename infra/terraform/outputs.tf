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
  description = "RDS endpoint hostname (use this for RDS_HOSTNAME secret)"
  value       = aws_db_instance.postgres.address
}

output "rds_port" {
  description = "RDS port"
  value       = aws_db_instance.postgres.port
}

output "s3_bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.storage.bucket
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.storage.arn
}
