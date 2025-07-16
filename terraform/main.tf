locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Data sources for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC and Networking
module "networking" {
  source = "./modules/networking"

  name_prefix           = local.name_prefix
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  app_subnet_cidrs     = var.app_subnet_cidrs
  db_subnet_cidrs      = var.db_subnet_cidrs
  availability_zones   = data.aws_availability_zones.available.names
  access_cidr          = var.access_cidr
  use_acm              = var.use_acm
  use_route53          = var.use_route53

  tags = local.common_tags
}

# DNS and SSL Certificate
module "dns" {
  source = "./modules/dns"
  count  = var.use_route53 ? 1 : 0

  domain_name      = var.domain_name
  hosted_zone_id   = var.hosted_zone_id
  hosted_zone_name = var.hosted_zone_name
  use_acm          = var.use_acm
  alb_dns_name     = module.compute.alb_dns_name
  alb_zone_id      = module.compute.alb_zone_id

  tags = local.common_tags
}

# S3 Storage
module "storage" {
  source = "./modules/storage"

  name_prefix = local.name_prefix
  tags        = local.common_tags
}

# RDS Database
module "database" {
  source = "./modules/database"

  name_prefix              = local.name_prefix
  vpc_id                   = module.networking.vpc_id
  db_subnet_ids           = module.networking.db_subnet_ids
  db_security_group_id    = module.networking.db_security_group_id
  database_instance_type  = var.database_instance_type
  database_master_password = var.database_master_password
  multi_az_database       = var.multi_az_database

  tags = local.common_tags
}

# EC2 Compute Resources
module "compute" {
  source = "./modules/compute"

  name_prefix                = local.name_prefix
  vpc_id                     = module.networking.vpc_id
  public_subnet_ids          = module.networking.public_subnet_ids
  app_subnet_ids             = module.networking.app_subnet_ids
  alb_security_group_id      = module.networking.alb_security_group_id
  app_security_group_id      = module.networking.app_security_group_id
  
  # EC2 Configuration
  ec2_key_name               = var.ec2_key_name
  web_instance_type          = var.web_instance_type
  web_asg_min               = var.web_asg_min
  web_asg_max               = var.web_asg_max
  
  # Application Configuration
  php_version               = var.php_version
  database_endpoint         = module.database.cluster_endpoint
  database_master_password  = var.database_master_password
  s3_file_bucket           = module.storage.file_repository_bucket_name
  s3_access_key_id         = module.storage.s3_access_key_id
  s3_secret_access_key     = module.storage.s3_secret_access_key
  
  # SES Configuration
  ses_username             = var.ses_username
  ses_password             = var.ses_password
  ses_region               = var.ses_region
  
  # REDCap Configuration
  redcap_download_method      = var.redcap_download_method
  redcap_s3_bucket           = var.redcap_s3_bucket
  redcap_s3_key              = var.redcap_s3_key
  redcap_s3_bucket_region    = var.redcap_s3_bucket_region
  redcap_community_username  = var.redcap_community_username
  redcap_community_password  = var.redcap_community_password
  redcap_version             = var.redcap_version
  
  # SSL Configuration
  use_acm                   = var.use_acm
  use_route53               = var.use_route53
  ssl_certificate_arn       = var.use_acm && var.use_route53 ? module.dns[0].certificate_arn : ""
  domain_name               = var.domain_name
  hosted_zone_name          = var.hosted_zone_name
  alb_endpoint_name         = var.alb_endpoint_name

  tags = local.common_tags

  depends_on = [module.database]
}

# CloudWatch Monitoring
module "monitoring" {
  source = "./modules/monitoring"

  name_prefix            = local.name_prefix
  auto_scaling_group_name = module.compute.auto_scaling_group_name
  alb_arn_suffix         = module.compute.alb_arn_suffix
  target_group_arn_suffix = module.compute.target_group_arn_suffix
  rds_cluster_id         = module.database.cluster_id

  tags = local.common_tags
}