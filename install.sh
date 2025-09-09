#!/usr/bin/env bash
set -euo pipefail

############################
# ===== USER SETTINGS =====
############################
# Adjust these to your needs. Make sure DNS (or /etc/hosts) points all of them to this machine.
GITLAB_FQDN="gitlab.local"
AWX_FQDN="awx.local"
PHPMYADMIN_FQDN="pma.local"
APP_FQDN="app.local"

# MySQL settings (root uses unix_socket; we create an app user+db)
MYSQL_APP_DB="demo_db"
MYSQL_APP_USER="demo_user"
MYSQL_APP_PASS="demo_pass_ChangeMe123!"

# AWX admin password
AWX_ADMIN_PASSWORD="AdminPass_ChangeMe123!"
# AWX project/data dirs
AWX_BASE="/opt/awx"

# Self-signed cert paths (used by GitLab, Apache, Nginx)
SSL_KEY="/etc/ssl/private/multiapp-selfsigned.key"
SSL_CRT="/etc/ssl/certs/multiapp-selfsigned.crt"
SSL_CONF="/etc/ssl/multiapp-openssl.cnf"

# Non-interactive
export DEBIAN_FRONTEND=noninteractive

########################################
# ===== Helper: require root =====
########################################
if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root (sudo)." >&2
  exit 1
fi

########################################
# ===== APT updates + base tools =====
########################################
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https software-properties-common jq

########################################
# ===== Create SAN self-signed cert ===
########################################
mkdir -p /etc/ssl/private /etc/ssl/certs
chmod 700 /etc/ssl/private

cat > "${SSL_CONF}" <<EOF
[req]
default_bits       = 4096
prompt             = no
default_md         = sha256
distinguished_name = dn
x509_extensions    = v3_req

[dn]
C=DE
ST=NRW
L=Cologne
O=Local
OU=IT
CN=${GITLAB_FQDN}

[v3_req]
subjectAltName = @alt_names
basicConstraints = CA:FALSE
keyUsage = keyEncipherment,dataEncipherment,digitalSignature
extendedKeyUsage = serverAuth

[alt_names]
DNS.1 = ${GITLAB_FQDN}
DNS.2 = ${AWX_FQDN}
DNS.3 = ${PHPMYADMIN_FQDN}
DNS.4 = ${APP_FQDN}
EOF

if [[ ! -f "${SSL_KEY}" || ! -f "${SSL_CRT}" ]]; then
  openssl req -x509 -nodes -days 825 -newkey rsa:4096 \
    -keyout "${SSL_KEY}" -out "${SSL_CRT}" -config "${SSL_CONF}"
  chmod 600 "${SSL_KEY}"
  echo "Created self-signed SAN cert covering: ${GITLAB_FQDN}, ${AWX_FQDN}, ${PHPMYADMIN_FQDN}, ${APP_FQDN}"
fi

########################################
# ===== Docker engine (for AWX) ========
########################################
if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) stable" \
    | tee /etc/apt/sources.list.d/docker.list >/dev/null
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
fi

########################################
# ===== MySQL Server ===================
########################################
if ! dpkg -s mysql-server >/dev/null 2>&1; then
  apt-get install -y mysql-server
  systemctl enable --now mysql
fi

# Create DB + user (idempotent)
mysql --protocol=socket -uroot <<SQL || true
CREATE DATABASE IF NOT EXISTS \`${MYSQL_APP_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${MYSQL_APP_USER}'@'localhost' IDENTIFIED BY '${MYSQL_APP_PASS}';
GRANT ALL PRIVILEGES ON \`${MYSQL_APP_DB}\`.* TO '${MYSQL_APP_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

# Seed demo table
mysql --protocol=socket -uroot "${MYSQL_APP_DB}" <<SQL
CREATE TABLE IF NOT EXISTS items(
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO items(name) VALUES ('First Row'), ('Second Row') ON DUPLICATE KEY UPDATE name=VALUES(name);
SQL

########################################
# ===== Apache + phpMyAdmin (HTTPS) ===
########################################
apt-get install -y apache2 php php-mbstring php-zip php-gd php-json php-curl php-xml php-mysql php-cli libapache2-mod-php
a2enmod ssl rewrite proxy proxy_http headers

# phpMyAdmin
if ! dpkg -s phpmyadmin >/dev/null 2>&1; then
  echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
  echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
  echo "phpmyadmin phpmyadmin/mysql/admin-pass password ''" | debconf-set-selections
  echo "phpmyadmin phpmyadmin/mysql/app-pass password ${MYSQL_APP_PASS}" | debconf-set-selections
  echo "phpmyadmin phpmyadmin/app-password-confirm password ${MYSQL_APP_PASS}" | debconf-set-selections
  apt-get install -y phpmyadmin
fi

# Apache vhost for phpMyAdmin over HTTPS
cat > /etc/apache2/sites-available/phpmyadmin-ssl.conf <<EOF
<VirtualHost *:443>
    ServerName ${PHPMYADMIN_FQDN}
    DocumentRoot /usr/share/phpmyadmin

    SSLEngine on
    SSLCertificateFile ${SSL_CRT}
    SSLCertificateKeyFile ${SSL_KEY}

    <Directory /usr/share/phpmyadmin>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/pma_error.log
    CustomLog \${APACHE_LOG_DIR}/pma_access.log combined
</VirtualHost>
EOF

a2ensite phpmyadmin-ssl.conf
a2dissite 000-default.conf || true
systemctl reload apache2

########################################
# ===== Nginx + PHP-FPM for app & AWX =
########################################
apt-get install -y nginx php-fpm
systemctl enable --now php8.1-fpm || true
systemctl enable --now php8.2-fpm || true

# Pick active php-fpm sock
PHPFPM_SOCK="$(find /run/php -maxdepth 1 -type s -name "php*-fpm.sock" | head -n1)"
if [[ -z "${PHPFPM_SOCK}" ]]; then
  echo "ERROR: Could not find PHP-FPM socket." >&2
  exit 1
fi

# Simple PHP demo app showing MySQL data
mkdir -p /var/www/app
cat > /var/www/app/index.php <<'EOF'
<?php
$host = 'localhost';
$db   = getenv('APP_DB') ?: 'demo_db';
$user = getenv('APP_USER') ?: 'demo_user';
$pass = getenv('APP_PASS') ?: 'demo_pass_ChangeMe123!';
$dsn = "mysql:host=$host;dbname=$db;charset=utf8mb4";
try {
  $pdo = new PDO($dsn, $user, $pass, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
  $rows = $pdo->query("SELECT id,name,created_at FROM items ORDER BY id")->fetchAll(PDO::FETCH_ASSOC);
} catch (Exception $e) {
  http_response_code(500);
  echo "<h1>DB error</h1><pre>".htmlspecialchars($e->getMessage())."</pre>";
  exit;
}
?>
<!doctype html><html><head><meta charset="utf-8"><title>Demo App</title>
<style>body{font-family:sans-serif;margin:2rem} table{border-collapse:collapse} td,th{border:1px solid #ccc;padding:.4rem .6rem}</style>
</head><body>
<h1>Demo App (MySQL items)</h1>
<table>
<tr><th>ID</th><th>Name</th><th>Created</th></tr>
<?php foreach ($rows as $r): ?>
<tr><td><?=htmlspecialchars($r['id'])?></td><td><?=htmlspecialchars($r['name'])?></td><td><?=htmlspecialchars($r['created_at'])?></td></tr>
<?php endforeach; ?>
</table>
<p>Edit data via <a href="https://<?=htmlspecialchars(getenv('PHPMYADMIN_HOST') ?: 'pma.local')?>">phpMyAdmin</a>.</p>
</body></html>
EOF
chown -R www-data:www-data /var/www/app

# Nginx server for the demo app (HTTPS + PHP-FPM)
cat > /etc/nginx/sites-available/app.conf <<EOF
server {
    listen 443 ssl http2;
    server_name ${APP_FQDN};

    ssl_certificate ${SSL_CRT};
    ssl_certificate_key ${SSL_KEY};

    root /var/www/app;
    index index.php;

    location / {
        try_files \$uri /index.php;
    }
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHPFPM_SOCK};
        fastcgi_param APP_DB ${MYSQL_APP_DB};
        fastcgi_param APP_USER ${MYSQL_APP_USER};
        fastcgi_param APP_PASS ${MYSQL_APP_PASS};
        fastcgi_param PHPMYADMIN_HOST ${PHPMYADMIN_FQDN};
    }
    access_log /var/log/nginx/app_access.log;
    error_log  /var/log/nginx/app_error.log;
}
EOF

ln -sf /etc/nginx/sites-available/app.conf /etc/nginx/sites-enabled/app.conf

########################################
# ===== AWX in Docker + Nginx TLS =====
########################################
mkdir -p "${AWX_BASE}"/{postgres-data,redis-data,compose,logs}

# docker compose file
cat > "${AWX_BASE}/compose/docker-compose.yml" <<'EOF'
services:
  postgres:
    image: postgres:13
    environment:
      POSTGRES_DB: awx
      POSTGRES_USER: awx
      POSTGRES_PASSWORD: awxpass
    volumes:
      - ../postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U awx -d awx"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7
    command: ["redis-server", "--appendonly", "yes"]
    volumes:
      - ../redis-data:/data

  awx:
    image: quay.io/ansible/awx:latest
    depends_on:
      - postgres
      - redis
    environment:
      SECRET_KEY: "change_me_secret_key_please"
      DATABASE_USER: "awx"
      DATABASE_NAME: "awx"
      DATABASE_HOST: "postgres"
      DATABASE_PORT: "5432"
      DATABASE_PASSWORD: "awxpass"
      REDIS_HOST: "redis"
      REDIS_PORT: "6379"
      AWX_ADMIN_USER: "admin"
      AWX_ADMIN_PASSWORD: "REPLACE_ADMIN_PASS"
      # Optional: set a base URL if desired
      # AWX_BASE_URL: "https://REPLACE_AWX_FQDN"
    ports:
      - "8051:8052"   # awx web (container listens 8052)
      - "8053:22"     # optional: ssh for execution envs (if used)
    volumes:
      - ../logs:/var/log/tower
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8052/api/v2/ping/"]
      interval: 20s
      timeout: 5s
      retries: 10
EOF

# Inject AWX admin pass from variable
sed -i "s/REPLACE_ADMIN_PASS/${AWX_ADMIN_PASSWORD//\//\\/}/" "${AWX_BASE}/compose/docker-compose.yml"

# Nginx reverse-proxy for AWX over HTTPS
cat > /etc/nginx/sites-available/awx.conf <<EOF
server {
    listen 443 ssl http2;
    server_name ${AWX_FQDN};

    ssl_certificate ${SSL_CRT};
    ssl_certificate_key ${SSL_KEY};

    location / {
        proxy_pass http://127.0.0.1:8051/;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 300;
    }

    access_log /var/log/nginx/awx_access.log;
    error_log  /var/log/nginx/awx_error.log;
}
EOF
ln -sf /etc/nginx/sites-available/awx.conf /etc/nginx/sites-enabled/awx.conf

########################################
# ===== GitLab CE (Omnibus) HTTPS =====
########################################
if ! dpkg -s gitlab-ce >/dev/null 2>&1; then
  curl -fsSL https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | bash
  EXTERNAL_URL="https://${GITLAB_FQDN}" apt-get install -y gitlab-ce
fi

# Configure GitLab to use the self-signed cert
GITLAB_CFG="/etc/gitlab/gitlab.rb"
if ! grep -q "external_url 'https://${GITLAB_FQDN}'" "${GITLAB_CFG}"; then
  sed -i "s|^external_url .*|external_url 'https://${GITLAB_FQDN}'|g" "${GITLAB_CFG}" || echo "external_url 'https://${GITLAB_FQDN}'" >> "${GITLAB_CFG}"
fi

add_gitlab_line() {
  local key="$1"; local val="$2"
  if grep -q "^[# ]*${key}" "${GITLAB_CFG}"; then
    sed -i "s|^[# ]*${key}.*|${key} = ${val}|g" "${GITLAB_CFG}"
  else
    echo "${key} = ${val}" >> "${GITLAB_CFG}"
  fi
}

add_gitlab_line "nginx['ssl_certificate']" "'${SSL_CRT}'"
add_gitlab_line "nginx['ssl_certificate_key']" "'${SSL_KEY}'"
add_gitlab_line "letsencrypt['enable']" "false"

gitlab-ctl reconfigure

########################################
# ===== Nginx final reload ============
########################################
nginx -t
systemctl enable --now nginx
systemctl reload nginx

########################################
# ===== Docker compose up (AWX) =======
########################################
# Pull and start AWX stack
docker compose -f "${AWX_BASE}/compose/docker-compose.yml" pull
docker compose -f "${AWX_BASE}/compose/docker-compose.yml" up -d

########################################
# ===== UFW (optional) ================
########################################
if command -v ufw >/dev/null 2>&1; then
  ufw allow 443/tcp || true
  ufw allow 80/tcp || true
fi

########################################
# ===== Summary =======================
########################################
cat <<INFO

All set!

Use these HTTPS endpoints (self-signed; your browser will warn):

- GitLab:        https://${GITLAB_FQDN}
- AWX:           https://${AWX_FQDN}   (admin / ${AWX_ADMIN_PASSWORD})
- phpMyAdmin:    https://${PHPMYADMIN_FQDN}
- Demo Web App:  https://${APP_FQDN}

If you don't have DNS set up, add entries to /etc/hosts on your client, e.g.:
  <SERVER_IP>  ${GITLAB_FQDN} ${AWX_FQDN} ${PHPMYADMIN_FQDN} ${APP_FQDN}

MySQL demo database:
  DB:   ${MYSQL_APP_DB}
  User: ${MYSQL_APP_USER}
  Pass: ${MYSQL_APP_PASS}

AWX compose files:      ${AWX_BASE}/compose/docker-compose.yml
Self-signed certificate:
  CRT: ${SSL_CRT}
  KEY: ${SSL_KEY}

INFO
