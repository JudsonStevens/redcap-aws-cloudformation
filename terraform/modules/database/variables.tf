variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "db_subnet_ids" {
  description = "List of database subnet IDs"
  type        = list(string)
}

variable "db_security_group_id" {
  description = "ID of the database security group"
  type        = string
}

variable "database_instance_type" {
  description = "RDS instance type"
  type        = string
}

variable "database_master_password" {
  description = "Master password for RDS database"
  type        = string
  sensitive   = true
}

variable "multi_az_database" {
  description = "Deploy RDS in Multi-AZ configuration"
  type        = bool
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}