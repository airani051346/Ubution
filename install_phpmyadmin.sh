#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
need_root

PMA_DIR="/opt/phpMyAdmin"
PMA_HOST="pma.${DOMAIN}"

log "Installing phpMyAdmin..."
apt-get update -y
ensure_pkg php-fpm; ensure_pkg php-mysql; ensure_pkg tar; ensure_pkg jq; ensure_pkg curl
apt-get install php-mbstring -y

mkdir -p "$PMA_DIR"
tmp="$(mktemp -d)"
pushd "$tmp" >/dev/null
curl -L https://files.phpmyadmin.net/phpMyAdmin/5.2.1/phpMyAdmin-5.2.1-all-languages.tar.gz -o pma.tgz
tar -xzf pma.tgz
mv phpMyAdmin-*/* "$PMA_DIR"/
popd >/dev/null
rm -rf "$tmp"

# Config
cat > "$PMA_DIR/config.inc.php" <<EOF
<?php
declare(strict_types=1);
\$cfg['blowfish_secret'] = '$(openssl rand -base64 32)';
\$cfg['Servers'][1]['auth_type'] = 'cookie';
\$cfg['Servers'][1]['host'] = '127.0.0.1';
\$cfg['Servers'][1]['port'] = 3306;
EOF
chown -R www-data:www-data "$PMA_DIR"

# Nginx site
gen_cert "$PMA_HOST" "${CERT_DIR}/pma.crt" "${KEY_DIR}/pma.key"
cat >"${NGINX_SITES}/phpmyadmin.conf" <<EOF
server { listen 80; server_name ${PMA_HOST}; return 301 https://\$host\$request_uri; }
server {
  listen 443 ssl http2;
  server_name ${PMA_HOST};
  ssl_certificate ${CERT_DIR}/pma.crt;
  ssl_certificate_key ${KEY_DIR}/pma.key;

  root ${PMA_DIR};
  index index.php;

  location / { try_files \$uri \$uri/ /index.php?\$args; }
  location ~ \.php\$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:/var/run/php/php-fpm.sock;
  }
}
EOF

ln -sf "${NGINX_SITES}/phpmyadmin.conf" "${NGINX_ENABLED}/phpmyadmin.conf"
nginx_reload

log "phpMyAdmin installed."
echo "URL: https://${PMA_HOST}"
