# REDCap on AWS - Terraform Infrastructure

This Terraform configuration deploys a HIPAA-compliant REDCap (Research Electronic Data Capture) environment on AWS, replacing the original CloudFormation stack with modern EC2-based infrastructure.

## Architecture Overview

The infrastructure includes:

- **VPC with 3-tier architecture** (public, application, database subnets)
- **Application Load Balancer** with SSL termination
- **Auto Scaling Group** with EC2 instances running Nginx + PHP-FPM
- **RDS Aurora MySQL** cluster with encryption and backups
- **S3 buckets** for file storage with encryption and lifecycle policies
- **Route53 and ACM** for DNS and SSL certificate management
- **CloudWatch** monitoring, logging, and alerting
- **Systems Manager** for secure instance access

## HIPAA Compliance Features

- Encryption at rest and in transit
- VPC isolation with security groups
- Encrypted EBS volumes for logs
- S3 bucket encryption with KMS
- VPC Flow Logs for network monitoring
- CloudWatch logging and monitoring
- Access logging for all services

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **Terraform** >= 1.0 installed
3. **AWS CLI** configured
4. **REDCap Consortium membership** for downloading REDCap
5. **SES configured** in your AWS account
6. **Route53 hosted zone** (if using custom domain)

## Quick Start

### 1. Setup Terraform Backend

First, create the S3 bucket and DynamoDB table for Terraform state:

```bash
# Create S3 bucket for Terraform state
aws s3 mb s3://your-terraform-state-bucket

# Create DynamoDB table for state locking
aws dynamodb create-table \
    --table-name terraform-state-locks \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
```

### 2. Configure Backend

Update `backend.tf` with your S3 bucket and DynamoDB table names:

```hcl
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "redcap/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }
}
```

### 3. Create Configuration

Copy the example configuration and customize:

```bash
cp environments/prod/terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your specific values:

```hcl
# Required variables
ec2_key_name             = "my-redcap-key"
database_master_password = "your-secure-password"
ses_username            = "your-ses-username"
ses_password            = "your-ses-password"
alb_endpoint_name       = "my-redcap"

# REDCap Community credentials (if using API download)
redcap_community_username = "your-redcap-username"
redcap_community_password = "your-redcap-password"

# Optional: Route53 and ACM for custom domain
use_route53      = true
use_acm          = true
hosted_zone_id   = "Z1234567890ABC"
hosted_zone_name = "example.com"
domain_name      = "redcap"
```

### 4. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

The deployment typically takes 15-20 minutes.

### 5. Access REDCap

After deployment, find your REDCap URL in the Terraform outputs:

```bash
terraform output redcap_url
```

Login with:
- **Username:** `redcap_admin`
- **Password:** Your database master password (change immediately after first login)

## DNS Configuration

### Option 1: Use Route53 for DNS Management (Recommended)

If you want Terraform to automatically manage your DNS records, configure these variables:

```hcl
# Enable Route53 and ACM
use_route53      = true
use_acm          = true

# Your existing Route53 hosted zone
hosted_zone_id   = "Z1234567890ABC"  # Found in Route53 console
hosted_zone_name = "example.com"     # Your domain (e.g., mycompany.org)

# Subdomain for REDCap
domain_name      = "redcap"          # Creates redcap.example.com
```

**How it works:**
1. Terraform creates an ACM certificate for `redcap.example.com`
2. ACM automatically validates the certificate using DNS validation
3. Terraform creates Route53 A and AAAA records pointing to the ALB
4. ALB uses the ACM certificate for HTTPS termination

**Prerequisites:**
- You must already have a Route53 hosted zone for your domain
- The hosted zone must be active and receiving queries
- You need the hosted zone ID (found in Route53 console)

### Option 2: Manual DNS Configuration

If you prefer to manage DNS manually or use a different DNS provider:

```hcl
# Disable automatic DNS management
use_route53 = false
use_acm     = false

# You'll get the ALB DNS name to configure manually
alb_endpoint_name = "my-redcap-alb"
```

**Manual steps required:**
1. After deployment, get the ALB DNS name:
   ```bash
   terraform output alb_dns_name
   # Example output: my-redcap-alb-1234567890.us-east-1.elb.amazonaws.com
   ```

2. Create DNS records in your DNS provider:
   ```
   Type: CNAME
   Name: redcap.yourcompany.com
   Value: my-redcap-alb-1234567890.us-east-1.elb.amazonaws.com
   TTL: 300
   ```

3. Configure SSL certificate:
   - Option A: Upload certificate to ACM and update ALB listener
   - Option B: Use ALB's default certificate (not recommended for production)
   - Option C: Terminate SSL at application level

### Option 3: Using Existing ACM Certificate

If you already have an ACM certificate:

```hcl
use_route53 = true   # Still use Route53 for DNS records
use_acm     = false  # Don't create new certificate

# In the compute module, you would need to modify the configuration
# to reference your existing certificate ARN
```

**Note:** This requires modifying the `modules/compute/main.tf` to accept an existing certificate ARN.

### Finding Your Route53 Hosted Zone ID

1. Go to AWS Console → Route53 → Hosted zones
2. Click on your domain name
3. Copy the "Hosted zone ID" (starts with Z)

Example:
```
Domain: mycompany.org
Hosted Zone ID: Z2ABC123DEF456GH
```

Your configuration would be:
```hcl
hosted_zone_id   = "Z2ABC123DEF456GH"
hosted_zone_name = "mycompany.org"
domain_name      = "redcap"  # Creates redcap.mycompany.org
```

## Configuration Options

### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | AWS region for deployment | `us-east-1` | No |
| `environment` | Environment name | `prod` | No |
| `ec2_key_name` | EC2 Key Pair name | | Yes |
| `web_instance_type` | EC2 instance type | `t3.medium` | No |
| `web_asg_min` | Minimum instances | `2` | No |
| `web_asg_max` | Maximum instances | `4` | No |
| `database_instance_type` | RDS instance type | `db.t3.small` | No |
| `database_master_password` | RDS password | | Yes |
| `multi_az_database` | Enable Multi-AZ | `false` | No |

### REDCap Download Methods

**Option 1: API Download (Recommended)**
```hcl
redcap_download_method = "api"
redcap_community_username = "your-username"
redcap_community_password = "your-password"
redcap_version = "latest"
```

**Option 2: S3 Upload**
```hcl
redcap_download_method = "s3"
redcap_s3_bucket = "my-redcap-bucket"
redcap_s3_key = "redcap/redcap14.0.0.zip"
redcap_s3_bucket_region = "us-east-1"
```

### Network Configuration

```hcl
# VPC CIDR blocks
vpc_cidr = "10.1.0.0/16"
public_subnet_cidrs = ["10.1.0.0/24", "10.1.1.0/24"]
app_subnet_cidrs = ["10.1.2.0/24", "10.1.3.0/24"]
db_subnet_cidrs = ["10.1.4.0/24", "10.1.5.0/24"]

# Access restriction
access_cidr = "10.0.0.0/8"  # Restrict to your network
```

## Module Structure

```
terraform/
├── main.tf                 # Root module orchestration
├── variables.tf           # Root variables
├── outputs.tf            # Root outputs
├── backend.tf            # S3/DynamoDB backend
├── modules/
│   ├── networking/       # VPC, subnets, security groups
│   ├── database/         # RDS Aurora MySQL
│   ├── compute/          # ALB, ASG, Launch Template
│   ├── storage/          # S3 buckets with encryption
│   ├── dns/              # Route53 and ACM
│   └── monitoring/       # CloudWatch logs and alarms
├── environments/
│   └── prod/
│       └── terraform.tfvars.example
└── README.md
```

## Management and Operations

### Accessing EC2 Instances

Use AWS Systems Manager Session Manager (no SSH required):

```bash
aws ssm start-session --target i-1234567890abcdef0
```

### Monitoring

- **CloudWatch Dashboard:** Check the `dashboard_url` output
- **Log Groups:** Application, Nginx, and PHP-FPM logs
- **Alarms:** Response time, error rates, health checks
- **Synthetics:** End-to-end health monitoring

### Scaling

Modify the Auto Scaling Group:

```hcl
web_asg_min = 3
web_asg_max = 6
```

Apply with `terraform apply`.

### Database Management

- **Backups:** Automated daily backups with 7-day retention
- **Monitoring:** CPU, connections, latency alarms
- **Encryption:** At rest with KMS, in transit with SSL

### Updates and Maintenance

**Application Updates:**
1. Update the REDCap version in `terraform.tfvars`
2. Run `terraform apply`
3. The Auto Scaling Group will perform rolling updates

**Infrastructure Updates:**
1. Modify Terraform configuration
2. Run `terraform plan` to review changes
3. Run `terraform apply` to implement

## REDCap Code Customization and Updates

### Making Changes to REDCap Code

There are several approaches to customize REDCap code depending on your needs:

#### Option 1: File-Level Customizations (Simple)

For small changes like configuration files or custom hooks:

1. **Access running instance:**
   ```bash
   # Find instance ID
   aws ec2 describe-instances --filters "Name=tag:Name,Values=*redcap*" --query 'Reservations[].Instances[].InstanceId'
   
   # Connect via Session Manager
   aws ssm start-session --target i-1234567890abcdef0
   ```

2. **Make changes directly:**
   ```bash
   sudo su -
   cd /var/www/html
   # Make your changes
   nano redcap/hooks/redcap_connect.php
   
   # Restart services
   systemctl restart nginx php-fpm
   ```

3. **Persist changes across scaling events:**
   Create a custom configuration in the user data script or use S3 to store custom files.

#### Option 2: Custom AMI Approach (Recommended for Major Changes)

For significant customizations that need to persist across Auto Scaling events:

1. **Create a custom AMI:**
   ```bash
   # Deploy base infrastructure first
   terraform apply
   
   # Connect to instance and make all your customizations
   aws ssm start-session --target i-1234567890abcdef0
   
   # Make your changes, test thoroughly
   # ...
   
   # Create AMI from customized instance
   aws ec2 create-image \
     --instance-id i-1234567890abcdef0 \
     --name "redcap-custom-$(date +%Y%m%d)" \
     --description "REDCap with custom configurations"
   ```

2. **Update Launch Template to use custom AMI:**
   
   Modify `modules/compute/main.tf`:
   ```hcl
   # Replace the data source for AMI
   data "aws_ami" "custom_redcap" {
     most_recent = true
     owners      = ["self"]  # Your account
     
     filter {
       name   = "name"
       values = ["redcap-custom-*"]
     }
   }
   
   # Update launch template
   resource "aws_launch_template" "main" {
     # ... other configuration ...
     image_id = data.aws_ami.custom_redcap.id
     # ... rest of configuration ...
   }
   ```

3. **Deploy updated infrastructure:**
   ```bash
   terraform apply
   ```

#### Option 3: S3-Based Configuration Management

For configuration files and small customizations:

1. **Create S3 bucket for customizations:**
   ```bash
   aws s3 mb s3://your-redcap-customizations
   ```

2. **Upload custom files:**
   ```bash
   # Upload custom configuration files
   aws s3 cp custom_config.php s3://your-redcap-customizations/config/
   aws s3 cp custom_hooks.php s3://your-redcap-customizations/hooks/
   ```

3. **Modify user data script to download customizations:**
   
   Update `modules/compute/userdata.sh`:
   ```bash
   # Add after REDCap installation
   echo "Downloading custom configurations..."
   aws s3 sync s3://your-redcap-customizations/config/ /var/www/html/redcap/
   aws s3 sync s3://your-redcap-customizations/hooks/ /var/www/html/redcap/hooks/
   
   # Set proper permissions
   chown -R nginx:nginx /var/www/html
   ```

#### Option 4: Git-Based Deployment

For version-controlled customizations:

1. **Create Git repository for your REDCap customizations:**
   ```bash
   # Structure your repo like:
   redcap-customizations/
   ├── config/
   │   └── custom_settings.php
   ├── hooks/
   │   └── redcap_connect.php
   ├── modules/
   │   └── custom_module/
   └── plugins/
       └── custom_plugin/
   ```

2. **Modify user data to clone and apply customizations:**
   ```bash
   # Add to userdata.sh after REDCap installation
   cd /tmp
   git clone https://github.com/yourorg/redcap-customizations.git
   
   # Copy customizations
   cp -r redcap-customizations/config/* /var/www/html/redcap/
   cp -r redcap-customizations/hooks/* /var/www/html/redcap/hooks/
   cp -r redcap-customizations/modules/* /var/www/html/redcap/modules/
   
   # Set permissions
   chown -R nginx:nginx /var/www/html
   ```

### Deploying REDCap Updates

#### Updating REDCap Version

1. **Update version in terraform.tfvars:**
   ```hcl
   redcap_version = "14.0.5"  # or "latest"
   ```

2. **Apply changes:**
   ```bash
   terraform apply
   ```

3. **Auto Scaling Group handles rolling update:**
   - Creates new instances with updated REDCap version
   - Waits for health checks to pass
   - Terminates old instances
   - Zero-downtime deployment

#### Testing Updates

**Blue-Green Deployment Approach:**

1. **Create a staging environment:**
   ```bash
   # Copy production tfvars
   cp terraform.tfvars terraform-staging.tfvars
   
   # Modify for staging
   sed -i 's/environment = "prod"/environment = "staging"/' terraform-staging.tfvars
   sed -i 's/domain_name = "redcap"/domain_name = "redcap-staging"/' terraform-staging.tfvars
   
   # Deploy staging
   terraform apply -var-file="terraform-staging.tfvars"
   ```

2. **Test thoroughly in staging**

3. **Promote to production:**
   ```bash
   terraform apply -var-file="terraform.tfvars"
   ```

#### Database Schema Updates

For REDCap versions that require database changes:

1. **Backup database before update:**
   ```bash
   # Create RDS snapshot
   aws rds create-db-cluster-snapshot \
     --db-cluster-identifier redcap-prod-aurora-cluster \
     --db-cluster-snapshot-identifier redcap-backup-$(date +%Y%m%d)
   ```

2. **Apply infrastructure update**

3. **Monitor for database migration completion:**
   - Check CloudWatch logs
   - Verify REDCap admin interface
   - Test key functionality

#### Rollback Strategy

If an update fails:

1. **Immediate rollback:**
   ```bash
   # Revert to previous version
   git checkout HEAD~1 terraform.tfvars
   terraform apply
   ```

2. **Database rollback (if needed):**
   ```bash
   # Restore from snapshot
   aws rds restore-db-cluster-from-snapshot \
     --db-cluster-identifier redcap-prod-aurora-cluster-restored \
     --snapshot-identifier redcap-backup-20241201
   ```

### Best Practices for REDCap Customizations

1. **Version Control:** Always version control your customizations
2. **Testing:** Test all changes in staging environment first
3. **Documentation:** Document all customizations and their purposes
4. **Backup:** Backup database before major updates
5. **Monitoring:** Monitor application logs during and after updates
6. **Gradual Rollout:** Use Auto Scaling to gradually replace instances

### Custom Module Development

For developing REDCap External Modules:

1. **Development workflow:**
   ```bash
   # Clone your module repo to local development
   git clone https://github.com/yourorg/redcap-custom-module.git
   
   # Make changes locally
   # Test in staging environment
   
   # Deploy to production via S3 or Git integration
   ```

2. **Production deployment:**
   - Upload modules to S3 and download via user data
   - Include in custom AMI
   - Use REDCap's module repository system

## Security Considerations

### Network Security
- Private subnets for application and database tiers
- Security groups with least-privilege access
- VPC Flow Logs for network monitoring
- WAF recommended for production (not included)

### Data Protection
- EBS encryption for all volumes
- RDS encryption at rest with KMS
- S3 encryption with KMS
- SSL/TLS for all data in transit

### Access Control
- IAM roles with minimal required permissions
- No direct SSH access (use Session Manager)
- Database credentials in Secrets Manager
- Application secrets in Parameter Store

### Monitoring and Auditing
- CloudWatch logs for all services
- CloudTrail for API auditing (configure separately)
- VPC Flow Logs for network traffic
- Application-level error monitoring

## Troubleshooting

### Common Issues

**REDCap Installation Fails:**
- Check user data logs: `/var/log/user-data.log`
- Verify database connectivity
- Ensure REDCap credentials are correct

**Database Connection Issues:**
- Check security groups allow port 3306
- Verify database is in available state
- Check RDS connectivity from app subnets

**SSL Certificate Issues:**
- Ensure Route53 hosted zone is configured
- Check ACM certificate validation
- Verify DNS propagation

### Debugging

```bash
# Check instance logs
aws ssm start-session --target i-1234567890abcdef0
sudo tail -f /var/log/user-data.log

# Check CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix "/aws/ec2/redcap"

# Check Auto Scaling Group health
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names redcap-prod-asg
```

## Cost Optimization

### Development Environment

```hcl
# Reduce costs for dev/test
web_instance_type = "t3.micro"
web_asg_min = 1
web_asg_max = 2
database_instance_type = "db.t3.micro"
multi_az_database = false
```

### Production Optimization

- Use Reserved Instances for predictable workloads
- Enable S3 Intelligent Tiering
- Monitor CloudWatch costs and set billing alarms
- Review and optimize instance types based on utilization

## Disaster Recovery

### Backup Strategy
- **RDS:** Automated backups with point-in-time recovery
- **S3:** Cross-region replication (configure separately)
- **Infrastructure:** Terraform state in S3 with versioning

### Recovery Process
1. Deploy infrastructure in new region using Terraform
2. Restore RDS from snapshot or backup
3. Sync S3 data from backup region
4. Update DNS to point to new environment

## Migration from CloudFormation

If migrating from the existing CloudFormation stack:

1. **Parallel Deployment:** Deploy Terraform infrastructure alongside CloudFormation
2. **Data Migration:** Export data from old RDS and import to new
3. **DNS Cutover:** Update Route53 records to point to new ALB
4. **Cleanup:** Remove CloudFormation stack after validation

## Support and Contributing

For issues and questions:
1. Check CloudWatch logs and alarms
2. Review AWS service health dashboards
3. Consult REDCap community forums
4. Submit issues via your organization's support process

## License

This Terraform configuration is provided under the same license terms as the original CloudFormation templates.