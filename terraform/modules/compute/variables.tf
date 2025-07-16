variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for ALB"
  type        = list(string)
}

variable "app_subnet_ids" {
  description = "List of application subnet IDs for EC2 instances"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "ID of the ALB security group"
  type        = string
}

variable "app_security_group_id" {
  description = "ID of the application security group"
  type        = string
}

variable "ec2_key_name" {
  description = "Name of EC2 Key Pair for SSH access"
  type        = string
}

variable "web_instance_type" {
  description = "EC2 instance type for web servers"
  type        = string
}

variable "web_asg_min" {
  description = "Minimum number of instances in Auto Scaling Group"
  type        = number
}

variable "web_asg_max" {
  description = "Maximum number of instances in Auto Scaling Group"
  type        = number
}

variable "php_version" {
  description = "PHP version to install"
  type        = string
}

variable "database_endpoint" {
  description = "RDS database endpoint"
  type        = string
}

variable "database_master_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}

variable "s3_file_bucket" {
  description = "S3 bucket name for file repository"
  type        = string
}

variable "s3_access_key_id" {
  description = "S3 access key ID"
  type        = string
  sensitive   = true
}

variable "s3_secret_access_key" {
  description = "S3 secret access key"
  type        = string
  sensitive   = true
}

variable "ses_username" {
  description = "SES SMTP username"
  type        = string
}

variable "ses_password" {
  description = "SES SMTP password"
  type        = string
  sensitive   = true
}

variable "ses_region" {
  description = "SES region"
  type        = string
}

variable "redcap_download_method" {
  description = "Method to download REDCap (s3 or api)"
  type        = string
}

variable "redcap_s3_bucket" {
  description = "S3 bucket containing REDCap source"
  type        = string
}

variable "redcap_s3_key" {
  description = "S3 key for REDCap source file"
  type        = string
}

variable "redcap_s3_bucket_region" {
  description = "Region of S3 bucket containing REDCap source"
  type        = string
}

variable "redcap_community_username" {
  description = "REDCap Community username"
  type        = string
  sensitive   = true
}

variable "redcap_community_password" {
  description = "REDCap Community password"
  type        = string
  sensitive   = true
}

variable "redcap_version" {
  description = "REDCap version to install"
  type        = string
}

variable "use_acm" {
  description = "Whether to use ACM for SSL certificates"
  type        = bool
}

variable "use_route53" {
  description = "Whether to use Route53 for DNS"
  type        = bool
}

variable "ssl_certificate_arn" {
  description = "ARN of SSL certificate (if using ACM)"
  type        = string
}

variable "domain_name" {
  description = "Domain name for REDCap"
  type        = string
}

variable "hosted_zone_name" {
  description = "Route53 hosted zone name"
  type        = string
}

variable "alb_endpoint_name" {
  description = "ALB endpoint name"
  type        = string
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}