variable "domain_name" {
  description = "Domain name for REDCap application"
  type        = string
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
}

variable "hosted_zone_name" {
  description = "Route53 hosted zone name"
  type        = string
}

variable "use_acm" {
  description = "Whether to create and use ACM certificate"
  type        = bool
}

variable "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  type        = string
}

variable "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  type        = string
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}