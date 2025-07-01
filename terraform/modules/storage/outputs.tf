output "file_repository_bucket_name" {
  description = "Name of the S3 bucket for REDCap file repository"
  value       = aws_s3_bucket.file_repository.bucket
}

output "file_repository_bucket_arn" {
  description = "ARN of the S3 bucket for REDCap file repository"
  value       = aws_s3_bucket.file_repository.arn
}

output "backup_bucket_name" {
  description = "Name of the S3 bucket for backups"
  value       = aws_s3_bucket.backup.bucket
}

output "backup_bucket_arn" {
  description = "ARN of the S3 bucket for backups"
  value       = aws_s3_bucket.backup.arn
}

output "s3_access_key_id" {
  description = "Access key ID for S3 user"
  value       = aws_iam_access_key.s3_user.id
  sensitive   = true
}

output "s3_secret_access_key" {
  description = "Secret access key for S3 user"
  value       = aws_iam_access_key.s3_user.secret
  sensitive   = true
}

output "s3_user_arn" {
  description = "ARN of the S3 IAM user"
  value       = aws_iam_user.s3_user.arn
}

output "kms_key_id" {
  description = "KMS key ID used for S3 encryption"
  value       = aws_kms_key.s3.key_id
}

output "kms_key_arn" {
  description = "KMS key ARN used for S3 encryption"
  value       = aws_kms_key.s3.arn
}