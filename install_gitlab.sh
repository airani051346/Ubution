#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
need_root

GITLAB_HOST="gitlab.${DOMAIN}"

log "Installing GitLab CE..."
apt-get update -y
curl -sS https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | bash
EXTERNAL_URL="http://127.0.0.1:8081" apt-get install -y gitlab-ce

# Ensure GitLab config uses Puma on port 8081 (localhost only)
if ! grep -q 'external_url "http://127.0.0.1:8081"' /etc/gitlab/gitlab.rb 2>/dev/null; then
  sed -i 's|^external_url .*||' /etc/gitlab/gitlab.rb || true
  cat >> /etc/gitlab/gitlab.rb <<'EOF'

external_url "https://127.0.0.1:8081"
nginx['listen_port'] = 8081
nginx['listen_https'] = false

# Puma settings
external_url "http://\$GITLAB_HOST"
# gitlab_workhorse['auth_backend'] = "http://127.0.0.1:8081"
# puma['listen'] = '127.0.0.1'
# puma['port'] = 8081
EOF
  gitlab-ctl reconfigure
fi

# Patch PostgreSQL pg_hba.conf to trust instead of peer map
PG_HBA="/var/opt/gitlab/postgresql/data/pg_hba.conf"
if [[ -f "$PG_HBA" ]]; then
  log "Patching $PG_HBA to use trust authentication..."
  sed -i 's/^\(local[[:space:]]\+all[[:space:]]\+all[[:space:]]\+\)peer.*/\1trust/' "$PG_HBA" || true
  systemctl restart gitlab-psql || gitlab-ctl restart postgresql
fi

# Nginx reverse proxy
gen_cert "$GITLAB_HOST" "${CERT_DIR}/gitlab.crt" "${KEY_DIR}/gitlab.key"
cat > "${NGINX_SITES}/gitlab.conf" <<EOF
server { listen 80; server_name ${GITLAB_HOST}; return 301 https://\$host\$request_uri; }
server {
  listen 443 ssl http2;
  server_name ${GITLAB_HOST};
  ssl_certificate ${CERT_DIR}/gitlab.crt;
  ssl_certificate_key ${KEY_DIR}/gitlab.key;

  client_max_body_size 0;
  proxy_read_timeout 3600;
  proxy_http_version 1.1;

  location / {
    proxy_set_header Host              \$http_host;
	proxy_set_header X-Forwarded-Ssl   on;
    proxy_set_header X-Real-IP         \$remote_addr;
    proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_pass http://127.0.0.1:8081;
  }
}
EOF

ln -sf "${NGINX_SITES}/gitlab.conf" "${NGINX_ENABLED}/gitlab.conf"
nginx_reload

log "GitLab installed and proxied."
echo "URL: https://${GITLAB_HOST}"
echo "Initial root password: /etc/gitlab/initial_root_password"
