#!/usr/bin/bash
set -euo pipefail
: "${DEBUG:=0}"
[[ "$DEBUG" == "1" ]] && set -x

# make sure this exists even when no component flags are passed
declare -a TARGETS=()


# ================== Defaults ==================
DOMAIN="fritz.box"
GITLAB_HOST="gitlab.${DOMAIN}"
PMA_HOST="pma.${DOMAIN}"
AWX_HOST="awx.${DOMAIN}"
AWX_NODEPORT=30090

SERVER_IP="$(hostname -I | awk '{print $1}')"
SERVER_IP="${SERVER_IP:-127.0.0.1}"

CERT_DIR=/etc/ssl/certs
KEY_DIR=/etc/ssl/private
NGINX_SITES=/etc/nginx/sites-available
NGINX_ENABLED=/etc/nginx/sites-enabled

MYSQL_SSL_DIR="/etc/mysql/ssl"
PMA_DIR="/opt/phpMyAdmin"
AWX_NS="awx"
K3S_KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
AWX_OP_DIR="/opt/awx-operator"
AWX_CA_BUNDLE="/etc/ssl/certs/awx-bundle-ca.crt"

log(){ echo -e "\033[1;32m[+] $*\033[0m"; }
warn(){ echo -e "\033[1;33m[!] $*\033[0m"; }
die(){ echo -e "\033[1;31m[x] $*\033[0m"; exit 1; }
need_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run as root (sudo)."; }

print_help(){
  cat <<EOF
Usage: $0 [options] [components...]

Options:
  --domain <homelab domain>    (default: fritz.box)
  --gitlab-host <FQDN>         (default: gitlab.<domain>)
  --pma-host <FQDN>            (default: pma.<domain>)
  --awx-host <FQDN>            (default: awx.<domain>)
  -h, --help                   Show this help

Components (run one or many):
  --nginx          Install Nginx (+ stream support check)
  --mysql          Install MySQL (0.0.0.0:3306, TLS, admin@%)
  --mysql-stream   Add Nginx TLS stream proxy on :3307 (optional)
  --phpmyadmin     Install phpMyAdmin + Nginx HTTPS
  --gitlab         Install GitLab CE + Nginx HTTPS
  --awx            Install AWX (k3s + Operator) + Nginx HTTPS
  --status         Show overview
  --all            Install everything

Examples:
  $0                                # install everything
  $0 --domain fritz.box --nginx --gitlab
  DEBUG=1 $0 --status               # verbose status
EOF
}

# ================== Arg parsing ==================
parse_args(){
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain)      DOMAIN="${2:?}";       shift 2 ;;
      --gitlab-host) GITLAB_HOST="${2:?}";  shift 2 ;;
      --pma-host)    PMA_HOST="${2:?}";     shift 2 ;;
      --awx-host)    AWX_HOST="${2:?}";     shift 2 ;;
      -h|--help)
cat <<EOF
Usage: $0 [options] [components...]
  --domain <homelab domain>   (default: fritz.box)
  --gitlab-host <FQDN>        (default: gitlab.<domain>)
  --pma-host <FQDN>           (default: pma.<domain>)
  --awx-host <FQDN>           (default: awx.<domain>)
Components:
  --nginx --mysql --mysql-stream --phpmyadmin --gitlab --awx --status
Tips:
  DEBUG=1 $0 --status
EOF
        exit 0 ;;
      # anything else is a component flag → collect it
      --nginx|--mysql|--mysql-stream|--phpmyadmin|--gitlab|--awx|--status|--all)
		log "=== Installing Nginx ==="
		install_nginx
		log "=== Installing MySQL ==="
		install_mysql
		log "=== Enabling MySQL stream ==="
		enable_mysql_stream
		log "=== Installing phpMyAdmin ==="
		install_phpmyadmin
		log "=== Installing GitLab ==="
		install_gitlab
		log "=== Installing AWX ==="
		install_awx
		show_status
		;;
      *)
        die "Unknown option: $1" ;;
    esac
  done

  # derive hosts if user changed the domain
  [[ -z "${GITLAB_HOST:-}" ]] && GITLAB_HOST="gitlab.${DOMAIN}"
  [[ -z "${PMA_HOST:-}"   ]] && PMA_HOST="pma.${DOMAIN}"
  [[ -z "${AWX_HOST:-}"   ]] && AWX_HOST="awx.${DOMAIN}"
}

# ================== Helpers ==================
ensure_pkg(){ dpkg -s "$1" >/dev/null 2>&1 || apt-get install -y "$1"; }

ensure_nginx(){
  if ! command -v nginx >/dev/null 2>&1; then
    log "Installing Nginx (full)…"
    apt-get update -y
    apt-get install -y nginx-full || apt-get install -y nginx-extras || apt-get install -y nginx
    systemctl enable --now nginx
  fi
  # Ensure stream modules (for --mysql-stream)
  if ! nginx -V 2>&1 | grep -q -- --with-stream; then
    warn "Nginx missing --with-stream; installing nginx-full/nginx-extras…"
    apt-get install -y nginx-full || apt-get install -y nginx-extras || true
  fi
  if ! nginx -V 2>&1 | grep -q -- --with-stream_ssl_module; then
    warn "Nginx missing --with-stream_ssl_module; installing nginx-extras…"
    apt-get install -y nginx-extras || true
  fi
  systemctl enable --now nginx
}

gen_cert(){
  local host="$1" crt="$2" key="$3"
  if [[ -f "$crt" && -f "$key" ]]; then
    log "Cert exists for $host"
    return
  fi
  log "Generating self-signed cert for $host"
  install -d -m 0755 "$CERT_DIR" "$KEY_DIR"
  openssl req -x509 -nodes -newkey rsa:4096 -sha256 -days 825 \
    -keyout "$key" -out "$crt" \
    -subj "/CN=${host}" \
    -addext "subjectAltName=DNS:${host},IP:${SERVER_IP}"
  chmod 600 "$key"
}

detect_fpm_backend(){
  local sock
  sock="$(find /run/php /var/run/php -maxdepth 1 -type s -name 'php*-fpm.sock' 2>/dev/null | head -n1 || true)"
  [[ -n "$sock" ]] && echo "unix:${sock}" || echo "127.0.0.1:9000"
}

ensure_ws_map(){
  local f="/etc/nginx/conf.d/ws_upgrade_map.conf"
  [[ -f "$f" ]] && return
  log "Adding WebSocket map for upgrade headers"
  cat > "$f" <<'EOF'
map $http_upgrade $connection_upgrade { default upgrade; '' close; }
EOF
}

ensure_stream_include(){
  local conf="/etc/nginx/nginx.conf"
  local dir="/etc/nginx/streams-enabled"
  mkdir -p "$dir"
  if ! grep -q 'stream[[:space:]]*{' "$conf" ; then
    printf "\nstream {\n  include /etc/nginx/streams-enabled/*.conf;\n}\n" >> "$conf"
  elif ! grep -q '/etc/nginx/streams-enabled/\*\.conf' "$conf" ; then
    sed -i '/stream[[:space:]]*{/a \  include /etc/nginx/streams-enabled/*.conf;' "$conf"
  fi
}

nginx_reload(){ nginx -t && (systemctl reload nginx || systemctl restart nginx); }

# ================== Components ==================

install_nginx(){
  ensure_nginx
  ensure_ws_map
  log "Nginx ready."
}

install_mysql(){
  log "Installing MySQL + TLS"
  apt-get update -y
  ensure_pkg mysql-server
  mkdir -p "$MYSQL_SSL_DIR"; chmod 700 "$MYSQL_SSL_DIR"

  if [[ ! -s "$MYSQL_SSL_DIR/ca.pem" ]]; then
    openssl genrsa -out "$MYSQL_SSL_DIR/ca-key.pem" 4096
    openssl req -x509 -new -nodes -key "$MYSQL_SSL_DIR/ca-key.pem" -days 1825 \
      -out "$MYSQL_SSL_DIR/ca.pem" -subj "/CN=Homelab MySQL CA"
    openssl genrsa -out "$MYSQL_SSL_DIR/server-key.pem" 4096
    openssl req -new -key "$MYSQL_SSL_DIR/server-key.pem" -out "$MYSQL_SSL_DIR/server.csr" -subj "/CN=$(hostname -f)"
    cat > "$MYSQL_SSL_DIR/server-ext.cnf" <<EOF
subjectAltName=DNS:$(hostname -f),IP:${SERVER_IP}
extendedKeyUsage=serverAuth
EOF
    openssl x509 -req -in "$MYSQL_SSL_DIR/server.csr" -CA "$MYSQL_SSL_DIR/ca.pem" -CAkey "$MYSQL_SSL_DIR/ca-key.pem" \
      -CAcreateserial -out "$MYSQL_SSL_DIR/server-cert.pem" -days 825 -sha256 -extfile "$MYSQL_SSL_DIR/server-ext.cnf"
    chmod 600 "$MYSQL_SSL_DIR/"*-key.pem
  fi

  cat > /etc/mysql/mysql.conf.d/zz-homelab.cnf <<EOF
[mysqld]
bind-address = 0.0.0.0
ssl-ca   = ${MYSQL_SSL_DIR}/ca.pem
ssl-cert = ${MYSQL_SSL_DIR}/server-cert.pem
ssl-key  = ${MYSQL_SSL_DIR}/server-key.pem
EOF
  systemctl restart mysql

  local PASS_FILE="/root/mysql_admin_password.txt"
  if [[ ! -s "$PASS_FILE" ]]; then
    tr -dc 'A-Za-z0-9!@#%^_+-=' </dev/urandom | head -c 24 > "$PASS_FILE"
    chmod 600 "$PASS_FILE"
  fi
  local DBA_PASS; DBA_PASS="$(cat "$PASS_FILE")"
  mysql --protocol=socket -uroot <<SQL || true
CREATE USER IF NOT EXISTS 'admin'@'%' IDENTIFIED WITH caching_sha2_password BY '${DBA_PASS}';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%' WITH GRANT OPTION;
ALTER USER 'admin'@'%' REQUIRE SSL;
FLUSH PRIVILEGES;
SQL
  log "MySQL ready. admin password saved in ${PASS_FILE}"
}

enable_mysql_stream(){
  ensure_nginx
  ensure_stream_include
  gen_cert "mysql.${DOMAIN}" "${CERT_DIR}/mysql.crt" "${KEY_DIR}/mysql.key"
  cat > /etc/nginx/streams-enabled/mysql-3307.conf <<EOF
upstream mysql_backend { server 127.0.0.1:3306; }
server {
  listen 3307 ssl;
  ssl_certificate     ${CERT_DIR}/mysql.crt;
  ssl_certificate_key ${KEY_DIR}/mysql.key;
  proxy_pass mysql_backend;
  proxy_timeout 600s;
}
EOF
  nginx_reload
  log "Nginx MySQL TLS stream on :3307 enabled (SNI: mysql.${DOMAIN})"
}

download_pma(){
  local out="$1"
  local ver urls=()
  ver="$(curl -fsSL https://www.phpmyadmin.net/home_page/version.json | jq -r '.version' 2>/dev/null || true)"
  [[ -n "$ver" && "$ver" != "null" ]] && urls+=(
    "https://files.phpmyadmin.net/phpMyAdmin/${ver}/phpMyAdmin-${ver}-all-languages.tar.gz"
    "https://files.phpmyadmin.net/phpMyAdmin/${ver}/phpMyAdmin-${ver}-english.tar.gz"
  )
  urls+=(
    "https://files.phpmyadmin.net/phpMyAdmin/latest/phpMyAdmin-latest-all-languages.tar.gz"
    "https://files.phpmyadmin.net/phpMyAdmin/latest/phpMyAdmin-latest-english.tar.gz"
    "https://files.phpmyadmin.net/phpMyAdmin/5.2.2/phpMyAdmin-5.2.2-all-languages.tar.gz"
    "https://files.phpmyadmin.net/phpMyAdmin/5.2.1/phpMyAdmin-5.2.1-all-languages.tar.gz"
  )
  for u in "${urls[@]}"; do
    log "Fetching phpMyAdmin: $u"
    if curl -fL --retry 3 --retry-delay 2 -o "$out" "$u"; then return 0; fi
  done
  return 1
}

install_phpmyadmin(){
  ensure_nginx
  apt-get update -y
  ensure_pkg php-fpm; ensure_pkg php-mysql; ensure_pkg php-xml
  ensure_pkg php-mbstring; ensure_pkg php-zip; ensure_pkg php-gd
  ensure_pkg php-curl; ensure_pkg tar; ensure_pkg jq; ensure_pkg curl

  if [[ ! -d "$PMA_DIR" ]]; then
    mkdir -p "$PMA_DIR"
    local tmp; tmp="$(mktemp -d)"; pushd "$tmp" >/dev/null
    download_pma "pma.tgz" || die "Could not download phpMyAdmin"
    tar -xzf pma.tgz
    local src; src="$(find . -maxdepth 1 -type d -name 'phpMyAdmin-*' | head -n1)"
    shopt -s dotglob; mv "$src"/* "$PMA_DIR"/
    popd >/dev/null; rm -rf "$tmp"
  fi

  if [[ ! -f "$PMA_DIR/config.inc.php" ]]; then
    local blow; blow="$(tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' </dev/urandom | head -c 32)"
    cat > "$PMA_DIR/config.inc.php" <<EOF
<?php
declare(strict_types=1);
\$cfg = [];
\$cfg['blowfish_secret'] = '${blow}';
\$cfg['TempDir'] = '${PMA_DIR}/tmp';
@mkdir(\$cfg['TempDir'], 0750, true);
\$cfg['Servers'] = [];
\$i = 1;
\$cfg['Servers'][\$i]['auth_type'] = 'cookie';
\$cfg['Servers'][\$i]['host'] = '127.0.0.1';
\$cfg['Servers'][\$i]['port'] = 3306;
\$cfg['Servers'][\$i]['AllowNoPassword'] = false;
return \$cfg;
EOF
  fi
  chown -R www-data:www-data "$PMA_DIR"
  chmod -R u=rwX,go=rX "$PMA_DIR"

  local FPM_BACKEND; FPM_BACKEND="$(detect_fpm_backend)"
  gen_cert "${PMA_HOST}" "${CERT_DIR}/pma.crt" "${KEY_DIR}/pma.key"
  cat > "${NGINX_SITES}/phpmyadmin.conf" <<EOF
server { listen 80; server_name ${PMA_HOST}; return 301 https://\$host\$request_uri; }
server {
  listen 443 ssl http2;
  server_name ${PMA_HOST};
  ssl_certificate ${CERT_DIR}/pma.crt;
  ssl_certificate_key ${KEY_DIR}/pma.key;

  root ${PMA_DIR};
  index index.php index.html;
  client_max_body_size 32m;

  location / { try_files \$uri \$uri/ /index.php?\$args; }
  location ~ \.php\$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass ${FPM_BACKEND};
  }
  location ~* \.(?:css|js|ico|gif|jpg|jpeg|png|svg|woff2?)\$ {
    expires 7d; access_log off;
  }
}
EOF
  ln -sf "${NGINX_SITES}/phpmyadmin.conf" "${NGINX_ENABLED}/phpmyadmin.conf"
  nginx_reload
  log "phpMyAdmin ready at https://${PMA_HOST}"
}

install_gitlab(){
  ensure_nginx
  curl -sS https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | bash
  EXTERNAL_URL="http://127.0.0.1:8080" apt-get install -y gitlab-ce
  if ! grep -q 'external_url "http://127.0.0.1:8080"' /etc/gitlab/gitlab.rb 2>/dev/null; then
    sed -i 's|^external_url .*||' /etc/gitlab/gitlab.rb || true
    cat >> /etc/gitlab/gitlab.rb <<'EOF'

external_url "http://127.0.0.1:8080"
nginx['listen_port'] = 8080
nginx['listen_https'] = false
EOF
    gitlab-ctl reconfigure
  fi

  gen_cert "${GITLAB_HOST}" "${CERT_DIR}/gitlab.crt" "${KEY_DIR}/gitlab.key"
  ensure_ws_map
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
    proxy_set_header X-Real-IP         \$remote_addr;
    proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Host  \$host;
    proxy_set_header X-Forwarded-Port  443;

    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;

    proxy_pass http://127.0.0.1:8080;
  }
}
EOF
  ln -sf "${NGINX_SITES}/gitlab.conf" "${NGINX_ENABLED}/gitlab.conf"
  nginx_reload
  log "GitLab ready at https://${GITLAB_HOST}"
}

install_k3s(){
  if systemctl is-active --quiet k3s; then log "k3s already installed"; return; fi
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik" sh -
  systemctl enable --now k3s
}

install_awx(){
  ensure_nginx
  install_k3s
  export KUBECONFIG="${K3S_KUBECONFIG}"

  mkdir -p "$AWX_OP_DIR"
  cd "$AWX_OP_DIR"
  local TAG
  TAG="$(curl -fsSL https://api.github.com/repos/ansible/awx-operator/releases/latest | jq -r .tag_name 2>/dev/null || true)"
  [[ -n "${TAG:-}" && "$TAG" != "null" ]] || TAG="2.7.2"
  log "Using AWX Operator tag ${TAG}"

  cat > kustomization.yaml <<YAML
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - github.com/ansible/awx-operator/config/default?ref=${TAG}
images:
  - name: quay.io/ansible/awx-operator
    newTag: ${TAG}
namespace: ${AWX_NS}
YAML

  kubectl create namespace "${AWX_NS}" --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -k .
  kubectl -n "${AWX_NS}" rollout status deploy/awx-operator-controller-manager --timeout=300s || true

  : > "${AWX_CA_BUNDLE}"
  [[ -s "${CERT_DIR}/gitlab.crt" ]] && cat "${CERT_DIR}/gitlab.crt" >> "${AWX_CA_BUNDLE}"
  [[ -s "${MYSQL_SSL_DIR}/ca.pem" ]] && cat "${MYSQL_SSL_DIR}/ca.pem" >> "${AWX_CA_BUNDLE}"
  kubectl -n "${AWX_NS}" create secret generic awx-custom-certs \
    --from-file=bundle-ca.crt="${AWX_CA_BUNDLE}" \
    --dry-run=client -o yaml | kubectl apply -f -

  cat > "${AWX_OP_DIR}/awx.yml" <<YAML
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx
spec:
  service_type: NodePort
  nodeport_port: ${AWX_NODEPORT}
  bundle_cacert_secret: awx-custom-certs

  extra_volumes: |
    - name: awx-extra-ca
      secret:
        secretName: awx-custom-certs
        items:
          - key: bundle-ca.crt
            path: awx-extra-ca.crt
  ee_extra_volume_mounts: |
    - name: awx-extra-ca
      mountPath: /etc/pki/ca-trust/source/anchors/awx-extra-ca.crt
      subPath: awx-extra-ca.crt
      readOnly: true
  ee_extra_env: |
    - name: SSL_CERT_FILE
      value: /etc/pki/ca-trust/source/anchors/awx-extra-ca.crt
    - name: REQUESTS_CA_BUNDLE
      value: /etc/pki/ca-trust/source/anchors/awx-extra-ca.crt
YAML

  if ! grep -q "awx.yml" kustomization.yaml; then
    printf "\nresources:\n  - awx.yml\n" >> kustomization.yaml
  fi
  kubectl apply -k .
  kubectl -n "${AWX_NS}" wait --for=condition=available deploy/awx --timeout=900s || true

  gen_cert "${AWX_HOST}" "${CERT_DIR}/awx.crt" "${KEY_DIR}/awx.key"
  ensure_ws_map
  cat > "${NGINX_SITES}/awx.conf" <<EOF
server { listen 80; server_name ${AWX_HOST}; return 301 https://\$host\$request_uri; }
server {
  listen 443 ssl http2;
  server_name ${AWX_HOST};
  ssl_certificate ${CERT_DIR}/awx.crt;
  ssl_certificate_key ${KEY_DIR}/awx.key;

  client_max_body_size 0;
  proxy_read_timeout 3600;
  proxy_http_version 1.1;

  location /websocket {
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_pass http://127.0.0.1:${AWX_NODEPORT};
  }
  location / {
    proxy_set_header Host              \$host;
    proxy_set_header X-Real-IP         \$remote_addr;
    proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_pass http://127.0.0.1:${AWX_NODEPORT};
  }
}
EOF
  ln -sf "${NGINX_SITES}/awx.conf" "${NGINX_ENABLED}/awx.conf"
  nginx_reload
  log "AWX ready at https://${AWX_HOST}"
}

show_status(){
  echo "================ HOMELAB STATUS ================"
  echo "Server IP: ${SERVER_IP}"
  echo "Domain:    ${DOMAIN}"
  echo

  if command -v nginx >/dev/null 2>&1; then
    echo "Nginx: installed ✅  (stream: $(nginx -V 2>&1 | grep -q -- --with-stream && echo yes || echo no))"
    echo "  Sites enabled:"; ls -1 "${NGINX_ENABLED}" || true
  else
    echo "Nginx: not installed ❌"
  fi
  echo

  if dpkg -s mysql-server >/dev/null 2>&1; then
    echo "MySQL: installed ✅"
    echo "  Listen: 0.0.0.0:3306 (TLS) | CA: ${MYSQL_SSL_DIR}/ca.pem"
    [[ -f /root/mysql_admin_password.txt ]] && echo "  admin password: $(cat /root/mysql_admin_password.txt)"
  else
    echo "MySQL: not installed ❌"
  fi
  echo

  if [[ -d "${PMA_DIR}" ]]; then
    echo "phpMyAdmin: installed ✅ → https://${PMA_HOST}"
    echo "  Root: ${PMA_DIR} | Cert: ${CERT_DIR}/pma.crt"
  else
    echo "phpMyAdmin: not installed ❌"
  fi
  echo

  if dpkg -s gitlab-ce >/dev/null 2>&1; then
    echo "GitLab: installed ✅ → https://${GITLAB_HOST}"
    echo "  Backend: 127.0.0.1:8080 | Initial root password: /etc/gitlab/initial_root_password"
  else
    echo "GitLab: not installed ❌"
  fi
  echo

  if systemctl is-active --quiet k3s; then
    echo "AWX: k3s up ✅ → https://${AWX_HOST} (NodePort ${AWX_NODEPORT})"
    echo "  Admin password (run on host):"
    echo "    KUBECONFIG=${K3S_KUBECONFIG} kubectl -n ${AWX_NS} get secret awx-admin-password -o jsonpath='{.data.password}' | base64 --decode"
  else
    echo "AWX: not installed ❌"
  fi
  echo "================================================"
}

# ================== Main (your preferred style) ==================
main(){
  if [[ $# -eq 0 ]]; then
    print_help
    exit 0
  fi

  for arg in "$@"; do
    case $arg in
      --all)
        install_nginx
        install_mysql
        enable_mysql_stream
        install_phpmyadmin
        install_gitlab
        install_awx
        show_status
        ;;
      --nginx)         install_nginx ;;
      --mysql)         install_mysql ;;
      --mysql-stream)  enable_mysql_stream ;;
      --phpmyadmin)    install_phpmyadmin ;;
      --gitlab)        install_gitlab ;;
      --awx)           install_awx ;;
      --status)        show_status ;;
      *)               die "Unknown option $arg" ;;
    esac
  done
}



# ================== Boot ==================
need_root
log "Starting installer (domain=${DOMAIN}, gitlab=${GITLAB_HOST}, pma=${PMA_HOST}, awx=${AWX_HOST})"

parse_args "$@"

# Log which component flags we collected (safe with empty array)
if ((${#TARGETS[@]})); then
  log "Component flags: ${TARGETS[*]}"
else
  log "Component flags: <none>"
fi

# Pass only component flags to main; if none, main runs full stack
main "${TARGETS[@]}"
