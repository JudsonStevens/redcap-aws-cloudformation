# Data source for current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# S3 Bucket for REDCap file repository
resource "aws_s3_bucket" "file_repository" {
  bucket = "${data.aws_caller_identity.current.account_id}-${var.name_prefix}-redcap-files"

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-redcap-files"
    Purpose     = "REDCap File Repository"
    Compliance  = "HIPAA"
  })
}

# S3 Bucket for backups
resource "aws_s3_bucket" "backup" {
  bucket = "${data.aws_caller_identity.current.account_id}-${var.name_prefix}-redcap-backups"

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-redcap-backups"
    Purpose     = "REDCap Backups"
    Compliance  = "HIPAA"
  })
}

# S3 Bucket versioning
resource "aws_s3_bucket_versioning" "file_repository" {
  bucket = aws_s3_bucket.file_repository.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "file_repository" {
  bucket = aws_s3_bucket.file_repository.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket public access block (HIPAA compliance)
resource "aws_s3_bucket_public_access_block" "file_repository" {
  bucket = aws_s3_bucket.file_repository.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket = aws_s3_bucket.backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket logging
resource "aws_s3_bucket_logging" "file_repository" {
  bucket = aws_s3_bucket.file_repository.id

  target_bucket = aws_s3_bucket.backup.id
  target_prefix = "access-logs/file-repository/"
}

resource "aws_s3_bucket_logging" "backup" {
  bucket = aws_s3_bucket.backup.id

  target_bucket = aws_s3_bucket.backup.id
  target_prefix = "access-logs/backup/"
}

# S3 Bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "file_repository" {
  bucket = aws_s3_bucket.file_repository.id

  rule {
    id     = "transition_to_ia"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    id     = "backup_lifecycle"
    status = "Enabled"

    transition {
      days          = 7
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# KMS Key for S3 encryption
resource "aws_kms_key" "s3" {
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 7

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-s3-kms-key"
  })
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${var.name_prefix}-s3"
  target_key_id = aws_kms_key.s3.key_id
}

# IAM User for S3 access (for REDCap application)
resource "aws_iam_user" "s3_user" {
  name = "${var.name_prefix}-s3-user"
  path = "/"

  tags = var.tags
}

resource "aws_iam_access_key" "s3_user" {
  user = aws_iam_user.s3_user.name
}

# IAM Policy for S3 access
resource "aws_iam_user_policy" "s3_user" {
  name = "${var.name_prefix}-s3-policy"
  user = aws_iam_user.s3_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.file_repository.arn,
          "${aws_s3_bucket.file_repository.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.s3.arn
      }
    ]
  })
}

# S3 Bucket notification for monitoring
resource "aws_s3_bucket_notification" "file_repository" {
  bucket = aws_s3_bucket.file_repository.id

  cloudwatch_configuration {
    cloudwatch_configuration_id = "file-upload-monitoring"
    filter_prefix              = ""
    filter_suffix              = ""
    events = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
  }
}

# CloudWatch metric filter for S3 access logs
resource "aws_cloudwatch_log_group" "s3_access" {
  name              = "/aws/s3/${var.name_prefix}/access-logs"
  retention_in_days = 90

  tags = var.tags
}

# S3 Bucket policy for additional security
resource "aws_s3_bucket_policy" "file_repository" {
  bucket = aws_s3_bucket.file_repository.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureConnections"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.file_repository.arn,
          "${aws_s3_bucket.file_repository.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_policy" "backup" {
  bucket = aws_s3_bucket.backup.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureConnections"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.backup.arn,
          "${aws_s3_bucket.backup.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}