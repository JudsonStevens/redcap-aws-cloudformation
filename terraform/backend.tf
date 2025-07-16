terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    bucket         = "your-terraform-state-bucket"  # Update with your bucket name
    key            = "redcap/terraform.tfstate"
    region         = "us-east-1"                    # Update with your preferred region
    dynamodb_table = "terraform-state-locks"       # Update with your table name
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "REDCap"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}