#!/bin/bash

# REDCap EC2 Instance Setup Script
# This script installs and configures REDCap on Amazon Linux 2

set -e

# Variables from Terraform
NAME_PREFIX="${name_prefix}"
AWS_REGION="${aws_region}"
PHP_VERSION="${php_version}"
DB_ENDPOINT="${database_endpoint}"
DB_PASSWORD="${database_master_password}"
S3_BUCKET="${s3_file_bucket}"
S3_ACCESS_KEY="${s3_access_key_id}"
S3_SECRET_KEY="${s3_secret_access_key}"
SES_USERNAME="${ses_username}"
SES_PASSWORD="${ses_password}"
SES_REGION="${ses_region}"
REDCAP_METHOD="${redcap_download_method}"
REDCAP_S3_BUCKET="${redcap_s3_bucket}"
REDCAP_S3_KEY="${redcap_s3_key}"
REDCAP_S3_REGION="${redcap_s3_bucket_region}"
REDCAP_USERNAME="${redcap_community_username}"
REDCAP_PASSWORD="${redcap_community_password}"
REDCAP_VERSION="${redcap_version}"
USE_ACM="${use_acm}"
USE_ROUTE53="${use_route53}"
DOMAIN_NAME="${domain_name}"
HOSTED_ZONE="${hosted_zone_name}"
ALB_ENDPOINT="${alb_endpoint_name}"

# Logging setup
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting REDCap installation at $(date)"

# Update system
yum update -y

# Install required packages
yum install -y \
    amazon-linux-extras \
    wget \
    unzip \
    mysql \
    awscli \
    amazon-cloudwatch-agent \
    amazon-ssm-agent \
    postfix \
    cyrus-sasl-plain

# Configure timezone
timedatectl set-timezone UTC

# Install and configure Nginx
amazon-linux-extras install -y nginx1
systemctl enable nginx
systemctl start nginx

# Install PHP based on version
if [[ "$PHP_VERSION" == "8.1" ]]; then
    amazon-linux-extras install -y php8.1
elif [[ "$PHP_VERSION" == "8.0" ]]; then
    amazon-linux-extras install -y php8.0
else
    amazon-linux-extras install -y php7.4
fi

# Install PHP extensions required by REDCap
yum install -y \
    php-fpm \
    php-mysqlnd \
    php-gd \
    php-ldap \
    php-zip \
    php-curl \
    php-mbstring \
    php-xml \
    php-json \
    php-openssl

# Start PHP-FPM
systemctl enable php-fpm
systemctl start php-fpm

# Configure PHP settings for REDCap
cat >> /etc/php.ini << 'EOF'
max_input_vars = 100000
upload_max_filesize = 32M
post_max_size = 32M
memory_limit = 512M
max_execution_time = 300
session.gc_maxlifetime = 1440
date.timezone = "America/New_York"
EOF

# Set session cookie secure if using HTTPS
if [[ "$USE_ACM" == "true" ]]; then
    echo "session.cookie_secure = on" >> /etc/php.ini
fi

# Mount encrypted volume for logs (HIPAA compliance)
LOG_DEVICE="/dev/nvme1n1"
LOG_MOUNT="/var/log/nginx"

if [[ -b "$LOG_DEVICE" ]]; then
    # Format and mount the encrypted volume
    mkfs -t ext4 "$LOG_DEVICE"
    mkdir -p /tmp/nginx_logs_backup
    cp -a "$LOG_MOUNT"/* /tmp/nginx_logs_backup/ 2>/dev/null || true
    mount "$LOG_DEVICE" "$LOG_MOUNT"
    cp -a /tmp/nginx_logs_backup/* "$LOG_MOUNT"/ 2>/dev/null || true
    rm -rf /tmp/nginx_logs_backup
    
    # Add to fstab for persistence
    echo "$LOG_DEVICE $LOG_MOUNT ext4 defaults,nofail 0 2" >> /etc/fstab
fi

# Configure Nginx for REDCap
cat > /etc/nginx/conf.d/redcap.conf << 'EOF'
server {
    listen 80;
    listen 443 ssl http2;
    server_name _;
    root /var/www/html;
    index index.php index.html index.htm;

    # SSL configuration
    ssl_certificate /etc/ssl/certs/server.crt;
    ssl_certificate_key /etc/ssl/private/server.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE+AESGCM:ECDHE+AES256:ECDHE+AES128:!aNULL:!MD5:!DSS;

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";

    # REDCap specific configuration
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/var/run/php-fpm/www.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
        
        # Increase timeouts for REDCap
        fastcgi_read_timeout 300;
        fastcgi_send_timeout 300;
    }

    # Deny access to sensitive files
    location ~ /\. {
        deny all;
    }
    
    location ~ ~$ {
        deny all;
    }

    # REDCap specific denies
    location ~* \.(log|txt)$ {
        deny all;
    }
}
EOF

# Generate self-signed certificate for HTTPS
mkdir -p /etc/ssl/private
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/server.key \
    -out /etc/ssl/certs/server.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/OU=OrgUnit/CN=localhost"

chmod 600 /etc/ssl/private/server.key

# Create web directory
mkdir -p /var/www/html
chown nginx:nginx /var/www/html

# Download and install REDCap
cd /tmp

if [[ "$REDCAP_METHOD" == "api" ]]; then
    echo "Downloading REDCap via API..."
    curl -o redcap.zip -d "username=$REDCAP_USERNAME&password=$REDCAP_PASSWORD&version=$REDCAP_VERSION&install=1" \
         -X POST https://redcap.vumc.org/plugins/redcap_consortium/versions.php
    REDCAP_FILE="redcap.zip"
else
    echo "Downloading REDCap from S3..."
    aws s3 cp "s3://$REDCAP_S3_BUCKET/$REDCAP_S3_KEY" . --region "$REDCAP_S3_REGION"
    REDCAP_FILE=$(basename "$REDCAP_S3_KEY")
fi

# Extract REDCap
unzip -q "$REDCAP_FILE"
cp -r redcap/* /var/www/html/
rm -f "$REDCAP_FILE"
rm -rf redcap

# Set proper permissions
chown -R nginx:nginx /var/www/html
find /var/www/html -type d -exec chmod 755 {} \;
find /var/www/html -type f -exec chmod 644 {} \;

# Configure database connection
cat > /var/www/html/redcap/database.php << EOF
<?php
\$hostname   = '$DB_ENDPOINT';
\$db         = 'redcap';
\$username   = 'redcap_user';
\$password   = '$DB_PASSWORD';
\$salt       = '';

// Get or create salt from Parameter Store
\$salt_param = shell_exec("aws ssm get-parameter --name '/$NAME_PREFIX/redcap/salt' --with-decryption --query 'Parameter.Value' --output text --region $AWS_REGION 2>/dev/null");
if (empty(\$salt_param) || strpos(\$salt_param, 'ParameterNotFound') !== false) {
    \$salt = bin2hex(random_bytes(16));
    shell_exec("aws ssm put-parameter --name '/$NAME_PREFIX/redcap/salt' --type 'SecureString' --value '\$salt' --region $AWS_REGION");
} else {
    \$salt = trim(\$salt_param);
}
EOF

# Wait for database to be available
echo "Waiting for database to be available..."
until mysql -h "$DB_ENDPOINT" -u master -p"$DB_PASSWORD" -e "SELECT 1" >/dev/null 2>&1; do
    echo "Database not ready, waiting..."
    sleep 10
done

# Create REDCap database users
mysql -h "$DB_ENDPOINT" -u master -p"$DB_PASSWORD" -e "
CREATE USER IF NOT EXISTS 'redcap_user'@'%' IDENTIFIED BY '$DB_PASSWORD';
GRANT SELECT, INSERT, UPDATE, DELETE ON redcap.* TO 'redcap_user'@'%';
CREATE USER IF NOT EXISTS 'redcap_user2'@'%' IDENTIFIED BY '$DB_PASSWORD';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, ALTER, REFERENCES ON redcap.* TO 'redcap_user2'@'%';
FLUSH PRIVILEGES;
"

# Install REDCap database schema (only on first instance)
LOCK_FILE="/tmp/redcap_install.lock"
if (
    flock -n 9 || exit 1
    
    # Check if REDCap is already installed
    if ! mysql -h "$DB_ENDPOINT" -u master -p"$DB_PASSWORD" redcap -e "SELECT * FROM redcap_config LIMIT 1" >/dev/null 2>&1; then
        echo "Installing REDCap database schema..."
        
        # Determine the URL for REDCap install
        if [[ "$USE_ROUTE53" == "true" ]]; then
            if [[ "$USE_ACM" == "true" ]]; then
                REDCAP_URL="https://$DOMAIN_NAME.$HOSTED_ZONE"
            else
                REDCAP_URL="http://$DOMAIN_NAME.$HOSTED_ZONE"
            fi
        else
            REDCAP_URL="http://localhost"
        fi
        
        # Wait for nginx to be ready
        sleep 30
        
        # Run REDCap install
        curl -k -X POST "$REDCAP_URL/install.php" \
            -d "redcap_csrf_token=" \
            -d "superusers_only_create_project=0" \
            -d "superusers_only_move_to_prod=1" \
            -d "auto_report_stats=1" \
            -d "bioportal_api_token=" \
            -d "redcap_base_url=$REDCAP_URL/" \
            -d "enable_url_shortener=1" \
            -d "default_datetime_format=D/M/Y_12" \
            -d "default_number_format_decimal=," \
            -d "default_number_format_thousands_sep=." \
            -d "homepage_contact=REDCap Administrator" \
            -d "homepage_contact_email=admin@example.com" \
            -d "project_contact_name=REDCap Administrator" \
            -d "project_contact_email=admin@example.com" \
            -d "institution=Your Institution" \
            -d "site_org_type=Research Institution" \
            -o /tmp/install_output.html
        
        # Extract SQL from install output and run it
        if grep -q "onclick='this.select()'" /tmp/install_output.html; then
            sed -n "/onclick='this.select()'/,/<\/textarea>/p" /tmp/install_output.html | \
            sed '1d;$d' > /tmp/redcap_install.sql
            
            mysql -h "$DB_ENDPOINT" -u master -p"$DB_PASSWORD" redcap < /tmp/redcap_install.sql
            
            # Create admin user and configure S3
            mysql -h "$DB_ENDPOINT" -u master -p"$DB_PASSWORD" redcap -e "
                UPDATE redcap_config SET value = 'table' WHERE field_name = 'auth_meth_global';
                INSERT INTO redcap_user_information (username, user_email, user_firstname, user_lastname, super_user) 
                VALUES ('redcap_admin', 'admin@example.com', 'REDCap', 'Administrator', '1');
                INSERT INTO redcap_auth (username, password, legacy_hash, temp_pwd) 
                VALUES ('redcap_admin', MD5('$DB_PASSWORD'), '1', '1');
                UPDATE redcap_config SET value = '2' WHERE field_name = 'edoc_storage_option';
                UPDATE redcap_config SET value = '$S3_BUCKET' WHERE field_name = 'amazon_s3_bucket';
                UPDATE redcap_config SET value = '$S3_ACCESS_KEY' WHERE field_name = 'amazon_s3_key';
                UPDATE redcap_config SET value = '$S3_SECRET_KEY' WHERE field_name = 'amazon_s3_secret';
                UPDATE redcap_config SET value = '$AWS_REGION' WHERE field_name = 'amazon_s3_endpoint';
                REPLACE INTO redcap_config (field_name, value) VALUES ('aws_quickstart', '1');
                REPLACE INTO redcap_config (field_name, value) VALUES ('redcap_updates_user', 'redcap_user2');
                REPLACE INTO redcap_config (field_name, value) VALUES ('redcap_updates_password', '$DB_PASSWORD');
                REPLACE INTO redcap_config (field_name, value) VALUES ('redcap_updates_password_encrypted', '0');
            "
            
            rm -f /tmp/redcap_install.sql /tmp/install_output.html
        fi
    fi
) 9>"$LOCK_FILE"

# Configure email (Postfix with SES)
cat > /etc/postfix/main.cf << EOF
compatibility_level = 2
queue_directory = /var/spool/postfix
command_directory = /usr/sbin
daemon_directory = /usr/libexec/postfix
data_directory = /var/lib/postfix
mail_owner = postfix
inet_interfaces = localhost
inet_protocols = all
mydestination = \$myhostname, localhost.\$mydomain, localhost
unknown_local_recipient_reject_code = 550
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
debug_peer_level = 2
debugger_command =
         PATH=/bin:/usr/bin:/usr/local/bin:/usr/X11R6/bin
         ddd \$daemon_directory/\$process_name \$process_id & sleep 5
sendmail_path = /usr/sbin/sendmail.postfix
newaliases_path = /usr/bin/newaliases.postfix
mailq_path = /usr/bin/mailq.postfix
setgid_group = postdrop
html_directory = no
manpage_directory = /usr/share/man
sample_directory = /usr/share/doc/postfix-2.10.1/samples
readme_directory = /usr/share/doc/postfix-2.10.1/README_FILES

# SES Configuration
relayhost = [email-smtp.$SES_REGION.amazonaws.com]:587
smtp_sasl_auth_enable = yes
smtp_sasl_security_options = noanonymous
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_use_tls = yes
smtp_tls_security_level = encrypt
smtp_tls_note_starttls_offer = yes
smtp_tls_CAfile = /etc/ssl/certs/ca-bundle.crt
EOF

# Configure SES credentials
echo "[email-smtp.$SES_REGION.amazonaws.com]:587 $SES_USERNAME:$SES_PASSWORD" > /etc/postfix/sasl_passwd
postmap hash:/etc/postfix/sasl_passwd
chmod 600 /etc/postfix/sasl_passwd*

# Start and enable postfix
systemctl enable postfix
systemctl start postfix

# Configure REDCap cron job
(crontab -l 2>/dev/null; echo "* * * * * /usr/bin/php /var/www/html/redcap/cron.php > /dev/null 2>&1") | crontab -

# Install and configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/nginx/access.log",
                        "log_group_name": "/aws/ec2/$NAME_PREFIX/nginx/access",
                        "log_stream_name": "{instance_id}"
                    },
                    {
                        "file_path": "/var/log/nginx/error.log",
                        "log_group_name": "/aws/ec2/$NAME_PREFIX/nginx/error",
                        "log_stream_name": "{instance_id}"
                    },
                    {
                        "file_path": "/var/log/php-fpm/www-error.log",
                        "log_group_name": "/aws/ec2/$NAME_PREFIX/php-fpm/error",
                        "log_stream_name": "{instance_id}"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "REDCap/EC2",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "diskio": {
                "measurement": [
                    "io_time"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            }
        }
    }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

# Restart services
systemctl restart nginx
systemctl restart php-fpm

# Create marker file to indicate installation is complete
touch /var/log/redcap-installation-complete

echo "REDCap installation completed at $(date)"
echo "Access REDCap at: $(if [[ "$USE_ROUTE53" == "true" ]]; then echo "https://$DOMAIN_NAME.$HOSTED_ZONE"; else echo "http://\$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"; fi)"
echo "Default admin user: redcap_admin"
echo "Default admin password: $DB_PASSWORD (change immediately after first login)"