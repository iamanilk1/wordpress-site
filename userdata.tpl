#!/bin/bash
set -e

# Force yum/httpd path (Amazon Linux style)
PM="yum"
PKGS="httpd php php-mysqlnd php-mbstring php-xml php-fpm unzip awscli jq mariadb"
NFS_PKG="nfs-utils"
SERVICE_NAME="httpd"

# Prefer modern PHP on Amazon Linux (amazon-linux-extras) or enable Remi on RHEL/CentOS
if command -v amazon-linux-extras >/dev/null 2>&1; then
  # Amazon Linux 2: prefer a PHP 8 topic if available
  amazon-linux-extras enable php8.0 || amazon-linux-extras enable php8.2 || true
  yum clean metadata || true
else
  # Provide a Remi fallback for CentOS/RHEL style distros to get newer PHP
  yum install -y yum-utils || true
  yum install -y https://rpms.remirepo.net/enterprise/remi-release-7.rpm || true
  yum-config-manager --enable remi-php80 || true
fi

# install dependencies (with retries)
yum makecache -y || true
yum install -y $PKGS || true

# If secret ARN is provided, fetch DB credentials from Secrets Manager
if [ "${secret_arn}" != "" ]; then
  echo "Fetching DB credentials from Secrets Manager"
  CREDS_JSON=$(aws secretsmanager get-secret-value --secret-id ${secret_arn} --region ${region} --query SecretString --output text)
  DB_PASSWORD=$(echo $CREDS_JSON | jq -r '.password')
  DB_USER=$(echo $CREDS_JSON | jq -r '.username')
else
  DB_USER="${db_user}"
  DB_PASSWORD=""
fi

# Only attempt to wait/create DB if we have a password (i.e., secret was provided)
if [ "$${DB_PASSWORD}" != "" ]; then
  # Wait for DB to be reachable
  until mysql -h ${db_endpoint} -u $${DB_USER} -p$${DB_PASSWORD} -e "select 1" >/dev/null 2>&1; do
    echo "Waiting for DB..."
    sleep 5
  done

  # Create DB if not exists
  mysql -h ${db_endpoint} -u $${DB_USER} -p$${DB_PASSWORD} -e "CREATE DATABASE IF NOT EXISTS ${db_name};"
else
  echo "No DB password available on instance; skipping DB wait/creation."
fi

# Mount EFS if provided
if [ "${efs_id}" != "" ] && [ "${efs_ap_id}" != "" ]; then
  # Prefer amazon-efs-utils for TLS mount support
  yum install -y amazon-efs-utils || true
  mkdir -p /var/www/html/wp-content

  FS_HOST="${efs_id}:/"
  MOUNT_POINT="/var/www/html/wp-content"

  for i in $(seq 1 12); do
    echo "Attempt $i: trying to mount EFS with efs-utils (TLS)..."
  if mount -t efs -o tls ${efs_id}:/ $${MOUNT_POINT} 2>/tmp/efs-mount.err; then
      echo "EFS mounted with efs-utils"
      break
    fi

    echo "efs-utils mount failed: $(tail -n 20 /tmp/efs-mount.err || true)"
    echo "Attempt $i: trying fallback nfs4 mount..."
  if mount -t nfs4 -o nfsvers=4.1 ${efs_id}.efs.${region}.amazonaws.com:/ $${MOUNT_POINT} 2>/tmp/efs-mount.err; then
      echo "EFS mounted via nfs4 fallback"
      break
    fi

    echo "Fallback mount failed: $(tail -n 20 /tmp/efs-mount.err || true)"
    sleep 5
  done

  if mount | grep -q "$${MOUNT_POINT}"; then
    echo "EFS mount succeeded"
  else
    echo "EFS mount failed after retries"
  fi
fi

# Ensure web service is enabled and started
systemctl enable $SERVICE_NAME || true
systemctl restart $SERVICE_NAME || true

# create a lightweight static health check page for ALB
mkdir -p /var/www/html
cat > /var/www/html/health.html <<'HEALTH'
OK
HEALTH
chown apache:apache /var/www/html/health.html || chown www-data:www-data /var/www/html/health.html || true

# Install WordPress
cd /tmp
wget -q https://wordpress.org/latest.zip
unzip -q latest.zip
cp -r wordpress/* /var/www/html/
chown -R apache:apache /var/www/html || chown -R www-data:www-data /var/www/html || true

# Configure wp-config.php
cat > /var/www/html/wp-config.php <<EOF
<?php
define('DB_NAME', '${db_name}');
define('DB_USER', '$${DB_USER}');
define('DB_PASSWORD', '$${DB_PASSWORD}');
define('DB_HOST', '${db_endpoint}');
define('DB_CHARSET', 'utf8');
define('DB_COLLATE', '');

// Authentication Unique Keys and Salts.
define('AUTH_KEY',         'put your unique phrase here');
define('SECURE_AUTH_KEY',  'put your unique phrase here');
define('LOGGED_IN_KEY',    'put your unique phrase here');
define('NONCE_KEY',        'put your unique phrase here');
define('AUTH_SALT',        'put your unique phrase here');
define('SECURE_AUTH_SALT', 'put your unique phrase here');
define('LOGGED_IN_SALT',   'put your unique phrase here');
define('NONCE_SALT',       'put your unique phrase here');

\$table_prefix = 'wp_';
if ( !defined('ABSPATH') )
    define('ABSPATH', dirname(__FILE__) . '/');

require_once(ABSPATH . 'wp-settings.php');
EOF

# If DB is configured and WP tables are missing, perform a non-interactive WP install using WP-CLI
if [ "${db_endpoint}" != "" ]; then
  # Build mysql auth options safely (avoid '-p' prompt when password empty)
  if [ "${secret_arn}" != "" ] || [ "$${DB_PASSWORD}" != "" ]; then
    MYSQL_AUTH="-u $${DB_USER} -p$${DB_PASSWORD}"
  else
    MYSQL_AUTH="-u $${DB_USER}"
  fi

  echo "Checking for existing WordPress tables in database ${db_name}..."
  if mysql -h ${db_endpoint} $MYSQL_AUTH -e "USE ${db_name}; SHOW TABLES LIMIT 1;" >/dev/null 2>&1; then
    echo "WordPress tables found; skipping wp-cli install/auto-install."
  else
    echo "No WordPress tables detected; attempting non-interactive install with WP-CLI"

    # install wp-cli if missing
    if ! command -v wp >/dev/null 2>&1; then
      curl -fsSL -o /tmp/wp-cli.phar https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar || true
      if [ -f /tmp/wp-cli.phar ]; then
        chmod +x /tmp/wp-cli.phar
        mv /tmp/wp-cli.phar /usr/local/bin/wp || mv /tmp/wp-cli.phar /usr/bin/wp || true
      fi
    fi

    # detect web user (apache or www-data)
    WEB_USER="apache"
    if ! id "$WEB_USER" >/dev/null 2>&1; then
      WEB_USER="www-data"
    fi

    chown -R $WEB_USER:$WEB_USER /var/www/html || true
    cd /var/www/html || true

    # Ensure required wp-cli PHP modules are available; wait briefly for php to be ready
    sleep 2

    # Run wp core install non-interactively. Terraform variables expected: site_url, admin_user, admin_password, admin_email, site_title
    # Assumption: Terraform will provide these variables; if any are empty the install may fail.
  SITE_URL="$${site_url:-http://localhost}"
  ADMIN_USER="$${admin_user:-admin}"
  ADMIN_PASS="$${admin_password:-ChangeMeStrong!}"
  ADMIN_EMAIL="$${admin_email:-admin@example.com}"
  SITE_TITLE="$${site_title:-WordPress Site}"

    if [ -z "$SITE_TITLE" ]; then SITE_TITLE="WordPress Site"; fi

    if command -v wp >/dev/null 2>&1; then
      echo "Running wp core install..."
      # allow-root is used because userdata runs as root; wp will still create files as $WEB_USER
      wp core install --url="$SITE_URL" --title="$SITE_TITLE" --admin_user="$ADMIN_USER" --admin_password="$ADMIN_PASS" --admin_email="$ADMIN_EMAIL" --skip-email --allow-root || true
    else
      echo "wp-cli not available; skipping automatic install."
    fi
  fi

fi

systemctl restart $SERVICE_NAME || true
