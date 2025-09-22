#!/usr/bin/env bash
set -euo pipefail

# ==============================================
# stackctl.sh (refined)
# One-host setup for:
#   - Docker + docker compose plugin
#   - MySQL 8 (Docker)
#   - phpMyAdmin (Docker)
#   - GitLab Omnibus (Docker)
#   - Nginx (host) TLS reverse proxy
#   - k3s (Kubernetes) + AWX Operator + AWX (NodePort)
#   - Local Docker Registry with basic auth
#
# HTTPS via Nginx (mkcert for LAN/dev).
# CoreDNS patch lets pods resolve gitlab/awx/pma/registry to this node IP.
# Includes fixes validated in your logs: registry auth + proxy bits, mkcert trust
# for Docker & k3s, /etc/hosts entries, and preset AWX admin password.
# ==============================================

# ----------------- Defaults -----------------
: "${DOMAIN:=fritz.lan}"
: "${GITLAB_HOST:=gitlab.${DOMAIN}}"
: "${AWX_HOST:=awx.${DOMAIN}}"
: "${PMA_HOST:=pma.${DOMAIN}}"
: "${REGISTRY_HOST:=registry.${DOMAIN}}"

: "${SERVER_IP:=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src"){print $(i+1); exit}}' || true)}"
[[ -z "${SERVER_IP}" ]] && SERVER_IP="$(hostname -I | awk '{print $1}')"

: "${OS_RELEASE:=$(. /etc/os-release; echo "$ID")}" # ubuntu

# Docker compose project dir
STACK_DIR=/opt/stack
COMPOSE_DIR="$STACK_DIR/compose"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"

# Certificates for Nginx (SAN cert for all hosts)
CERT_DIR=/etc/nginx/certs
CERT_PEM="$CERT_DIR/internal.pem"
CERT_KEY="$CERT_DIR/internal.key"

# Nginx config
NGINX_SITE=/etc/nginx/sites-available/stack_apps.conf
NGINX_SITE_LINK=/etc/nginx/sites-enabled/stack_apps.conf

# k3s & AWX
K3S_KUBECONFIG=/etc/rancher/k3s/k3s.yaml
AWX_NAMESPACE=awx
AWX_NAME=awx
AWX_NODEPORT=30090
AWX_OPERATOR_VERSION="2.19.0"

# GitLab container ports
GITLAB_HTTP_PORT=8929
GITLAB_SSH_PORT=2222

# phpMyAdmin bind port (loopback only)
PMA_BIND_PORT=9001

# MySQL
MYSQL_PORT=3306
MYSQL_ROOT_PASSWORD="ChangeMeStrong123"
APP_DB_NAME=appdb
APP_DB_USER=awx_app
APP_DB_PASS="AppDbStrong!123"

# Local Docker Registry with Basic Auth (proxied via Nginx@443)
REGISTRY_DIR="$STACK_DIR/registry"
REGISTRY_AUTH_FILE="$REGISTRY_DIR/htpasswd"
REGISTRY_DATA_DIR="$REGISTRY_DIR/data"
REGISTRY_REALM="Registry"

: "${REGISTRY_USER:=awx}"
: "${REGISTRY_PASS:=ChangeMeReg123}"

# AWX admin (preset so you don't have to read the random secret)
: "${AWX_ADMIN_USER:=admin}"
: "${AWX_ADMIN_PASS:=ChangeMeAwx123}"

# Flags
DO_REGISTRY=false
DO_MYSQL=false
DO_PMA=false
DO_GITLAB=false
DO_NGINX=false
DO_CERTS=false
DO_K3S=false
DO_AWX=false
DO_STATUS=false
DO_ALL=false
DO_MYSQL_RESET=false
DO_PATCH_DNS=true  # patch CoreDNS NodeHosts during/after k3s

usage() {
  cat <<USAGE
Usage: $0 [--all] [--mysql] [--pma] [--gitlab] [--nginx] [--certs] [--k3s] [--awx] [--status] [--registry]
            [--domain DOMAIN] [--gitlab-host HOST] [--awx-host HOST] [--pma-host HOST] [--registry-host HOST]
            [--server-ip IP]
            [--mysql-port PORT] [--mysql-root-pass PASS]
            [--app-db-name NAME] [--app-db-user USER] [--app-db-pass PASS]
            [--gitlab-ssh-port PORT] [--awx-nodeport PORT]
            [--awx-admin-user USER] [--awx-admin-pass PASS]
            [--no-dns-patch]

Examples:
  sudo bash $0 --all --domain fritz.lan
  sudo bash $0 --mysql --pma
  sudo bash $0 --gitlab
  sudo bash $0 --k3s --awx
  sudo bash $0 --registry --domain fritz.lan --registry-host registry.fritz.lan
  sudo bash $0 --status
USAGE
}

parse_args() {
  local DID_SET_GITLAB_HOST=false
  local DID_SET_AWX_HOST=false
  local DID_SET_PMA_HOST=false
  local DID_SET_REGISTRY_HOST=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all) DO_ALL=true ;;
      --mysql) DO_MYSQL=true ;;
      --pma) DO_PMA=true ;;
      --gitlab) DO_GITLAB=true ;;
      --nginx) DO_NGINX=true ;;
      --certs) DO_CERTS=true ;;
      --k3s) DO_K3S=true ;;
      --awx) DO_AWX=true ;;
      --status) DO_STATUS=true ;;
      --registry) DO_REGISTRY=true ;;
      --no-dns-patch) DO_PATCH_DNS=false ;;
      --domain) DOMAIN="$2"; shift ;;
      --gitlab-host) GITLAB_HOST="$2"; DID_SET_GITLAB_HOST=true; shift ;;
      --awx-host) AWX_HOST="$2"; DID_SET_AWX_HOST=true; shift ;;
      --pma-host) PMA_HOST="$2"; DID_SET_PMA_HOST=true; shift ;;
      --registry-host) REGISTRY_HOST="$2"; DID_SET_REGISTRY_HOST=true; shift ;;
      --server-ip) SERVER_IP="$2"; shift ;;
      --mysql-port) MYSQL_PORT="$2"; shift ;;
      --mysql-root-pass) MYSQL_ROOT_PASSWORD="$2"; shift ;;
      --mysql-reset) DO_MYSQL_RESET=true ;;
      --app-db-name) APP_DB_NAME="$2"; shift ;;
      --app-db-user) APP_DB_USER="$2"; shift ;;
      --app-db-pass) APP_DB_PASS="$2"; shift ;;
      --gitlab-ssh-port) GITLAB_SSH_PORT="$2"; shift ;;
      --awx-nodeport) AWX_NODEPORT="$2"; shift ;;
      --awx-admin-user) AWX_ADMIN_USER="$2"; shift ;;
      --awx-admin-pass) AWX_ADMIN_PASS="$2"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "[!] Unknown arg: $1" >&2; usage; exit 1 ;;
    esac
    shift
  done

  if $DO_ALL; then
    DO_MYSQL=true; DO_PMA=true; DO_GITLAB=true; DO_K3S=true; DO_AWX=true; DO_CERTS=true; DO_NGINX=true; DO_REGISTRY=true
  fi

  # Recompute hosts if only --domain was changed
  $DID_SET_GITLAB_HOST     || GITLAB_HOST="gitlab.${DOMAIN}"
  $DID_SET_AWX_HOST        || AWX_HOST="awx.${DOMAIN}"
  $DID_SET_PMA_HOST        || PMA_HOST="pma.${DOMAIN}"
  $DID_SET_REGISTRY_HOST   || REGISTRY_HOST="registry.${DOMAIN}"
}

# ----------------- Helpers -----------------
log(){ echo -e "[+] $*"; }
err(){ echo -e "[!] $*" >&2; }

need_root(){
  if [[ $EUID -ne 0 ]]; then
    err "Please run as root (sudo)."
    exit 1
  fi
}

check_os(){
  if [[ "$OS_RELEASE" != "ubuntu" ]]; then
    err "This script targets Ubuntu. Detected: $OS_RELEASE"
    exit 1
  fi
}

apt_install(){
  DEBIAN_FRONTEND=noninteractive apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apt-transport-https ca-certificates curl gnupg lsb-release jq git make openssl \
    docker.io nginx python3 python3-yaml apache2-utils
  systemctl enable --now docker
  systemctl enable --now nginx
}

mysql_reset_volume(){
  log "Resetting MySQL data volume (compose_mysql_data) — this will DELETE all DB data"
  (cd "$COMPOSE_DIR" && docker compose down) || true
  docker volume rm compose_mysql_data || true
}

ensure_compose(){
  if ! docker compose version >/dev/null 2>&1; then
    log "Installing docker compose plugin"
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -L "https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-$(uname -s)-$(uname -m)" \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
  fi
}

install_mkcert(){
  if ! command -v mkcert >/dev/null 2>&1; then
    log "Installing mkcert"
    curl -L https://github.com/FiloSottile/mkcert/releases/latest/download/mkcert-v1.4.4-linux-amd64 \
      -o /usr/local/bin/mkcert && chmod +x /usr/local/bin/mkcert
    mkcert -install || true
  fi
}

make_certs(){
  mkdir -p "$CERT_DIR"
  local need=0
  if [[ -s "$CERT_PEM" && -s "$CERT_KEY" ]]; then
    for h in "$GITLAB_HOST" "$AWX_HOST" "$PMA_HOST" "$REGISTRY_HOST"; do
      if ! openssl x509 -in "$CERT_PEM" -noout -text 2>/dev/null | grep -q "DNS:${h}"; then need=1; fi
    done
  else
    need=1
  fi
  if [[ $need -eq 1 ]]; then
    log "Generating SAN cert for $GITLAB_HOST, $AWX_HOST, $PMA_HOST, $REGISTRY_HOST"
    mkcert -cert-file "$CERT_PEM" -key-file "$CERT_KEY" \
      "$GITLAB_HOST" "$AWX_HOST" "$PMA_HOST" "$REGISTRY_HOST"
  else
    log "Existing cert already has required SANs (skipping)"
  fi
}

# Trust mkcert CA for Docker daemon (so docker login/push to https://registry.host works)
ensure_docker_trust(){
  local caroot; caroot="$(mkcert -CAROOT)"
  install -D -m 644 "${caroot}/rootCA.pem" /etc/docker/certs.d/${REGISTRY_HOST}/ca.crt || true
  systemctl restart docker || true
}

# Trust mkcert CA for k3s/containerd & configure mirror to https registry host
ensure_registry_trust_for_k3s(){
  install -d -m 755 /etc/rancher/k3s
  local reg=/etc/rancher/k3s/registries.yaml
  local caroot; caroot=$(mkcert -CAROOT)
  install -D -m 644 "${caroot}/rootCA.pem" /usr/local/share/ca-certificates/mkcert-rootCA.crt || true
  update-ca-certificates || true
  cat >"$reg" <<EOF
mirrors:
  ${REGISTRY_HOST}:
    endpoint:
      - "https://${REGISTRY_HOST}"
configs:
  ${REGISTRY_HOST}:
    tls:
      ca_file: /usr/local/share/ca-certificates/mkcert-rootCA.crt
EOF
  systemctl restart k3s || true
}

setup_registry_auth(){
  mkdir -p "$REGISTRY_DIR" "$REGISTRY_DATA_DIR"
  if [[ ! -s "$REGISTRY_AUTH_FILE" ]]; then
    log "Creating registry htpasswd for ${REGISTRY_USER}"
    docker run --rm --entrypoint htpasswd httpd:2 -Bbn "$REGISTRY_USER" "$REGISTRY_PASS" > "$REGISTRY_AUTH_FILE"
    chmod 640 "$REGISTRY_AUTH_FILE"
  fi
}

ensure_hosts_entries(){
  # helpful for the host itself (pods get CoreDNS NodeHosts below)
  local hosts_line="${SERVER_IP} ${GITLAB_HOST} ${AWX_HOST} ${PMA_HOST} ${REGISTRY_HOST}"
  if ! grep -qE "[[:space:]]${GITLAB_HOST}([[:space:]]|$)" /etc/hosts; then
    log "Adding host entries to /etc/hosts -> $hosts_line"
    printf "%s\n" "$hosts_line" >> /etc/hosts
  fi
}

mysql_volume_maybe_reset_first_boot(){
  # Only act if the named volume already exists *and* looks half-initialized.
  local vol="compose_mysql_data"
  local mnt
  mnt="$(docker volume inspect "$vol" --format '{{.Mountpoint}}' 2>/dev/null || true)"
  [[ -z "$mnt" ]] && return 0  # volume doesn't exist yet, nothing to do

  # Count files and key markers inside the volume
  local count ibdata sysdir
  count=$(find "$mnt" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
  [[ -f "$mnt/ibdata1" ]] && ibdata=1 || ibdata=0
  [[ -d "$mnt/mysql" ]] && sysdir=1 || sysdir=0

  # If there are a few files but NOT both ibdata1 and mysql system dir,
  # it's almost certainly a broken init. Auto-reset once.
  if [[ "$count" -gt 0 && ( "$ibdata" -eq 0 || "$sysdir" -eq 0 ) ]]; then
    log "MySQL volume appears half-initialized ($vol). Auto-resetting it once."
    (cd "$COMPOSE_DIR" && docker compose down) || true
    docker volume rm "$vol" || true
  fi
}

write_compose(){
  DOLLAR='$'
  mkdir -p "$COMPOSE_DIR"
  : > "$COMPOSE_FILE"
  echo "services:" >> "$COMPOSE_FILE"

  # MySQL
  if $DO_MYSQL || $DO_PMA; then
    cat >> "$COMPOSE_FILE" <<YAML
  mysql:
    image: mysql:8.4
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: "${MYSQL_ROOT_PASSWORD}"
      MYSQL_DATABASE: "${APP_DB_NAME}"
      MYSQL_USER: "${APP_DB_USER}"
      MYSQL_PASSWORD: "${APP_DB_PASS}"
    ports:
      - "0.0.0.0:${MYSQL_PORT}:3306"
    healthcheck:
      test: ["CMD-SHELL", "mysqladmin ping -uroot -p${DOLLAR}${DOLLAR}{MYSQL_ROOT_PASSWORD} --silent"]
      interval: 5s
      timeout: 5s
      retries: 120
      start_period: 60s
    volumes:
      - mysql_data:/var/lib/mysql
    networks: [back]
YAML
  fi

  # Local Registry (listens 127.0.0.1:5000; TLS via Nginx@443)
  if $DO_REGISTRY; then
    cat >> "$COMPOSE_FILE" <<YAML
  registry:
    image: registry:2
    restart: unless-stopped
    environment:
      REGISTRY_HTTP_ADDR: "0.0.0.0:5000"
      REGISTRY_STORAGE_DELETE_ENABLED: "true"
      REGISTRY_AUTH: htpasswd
      REGISTRY_AUTH_HTPASSWD_REALM: "${REGISTRY_REALM}"
      REGISTRY_AUTH_HTPASSWD_PATH: /auth/htpasswd
    ports:
      - "127.0.0.1:5000:5000"
    volumes:
      - ${REGISTRY_DATA_DIR}:/var/lib/registry
      - ${REGISTRY_AUTH_FILE}:/auth/htpasswd:ro
    networks: [back]
YAML
  fi

  # phpMyAdmin
  if $DO_PMA; then
    cat >> "$COMPOSE_FILE" <<YAML
  phpmyadmin:
    image: phpmyadmin:latest
    restart: unless-stopped
    environment:
      PMA_HOST: mysql
      PMA_ABSOLUTE_URI: https://${PMA_HOST}/
    depends_on: [mysql]
    ports:
      - "127.0.0.1:${PMA_BIND_PORT}:80"
    networks: [back]
YAML
  fi

  # GitLab
  if $DO_GITLAB; then
    cat >> "$COMPOSE_FILE" <<YAML
  gitlab:
    image: gitlab/gitlab-ee:latest
    restart: unless-stopped
    hostname: gitlab
    shm_size: "512m"
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'https://${GITLAB_HOST}'
        nginx['listen_port'] = ${GITLAB_HTTP_PORT}
        nginx['listen_https'] = false
        gitlab_rails['gitlab_shell_ssh_port'] = ${GITLAB_SSH_PORT}
    ports:
      - "127.0.0.1:${GITLAB_HTTP_PORT}:${GITLAB_HTTP_PORT}"
      - "0.0.0.0:${GITLAB_SSH_PORT}:22"
    volumes:
      - gitlab_config:/etc/gitlab
      - gitlab_logs:/var/log/gitlab
      - gitlab_data:/var/opt/gitlab
    networks: [back]
YAML
  fi

  # Networks + Volumes
  cat >> "$COMPOSE_FILE" <<'YAML'
networks:
  back:
volumes:
YAML

  if $DO_MYSQL || $DO_PMA; then echo "  mysql_data:" >> "$COMPOSE_FILE"; fi
  if $DO_GITLAB; then
    echo "  gitlab_config:" >> "$COMPOSE_FILE"
    echo "  gitlab_logs:"   >> "$COMPOSE_FILE"
    echo "  gitlab_data:"   >> "$COMPOSE_FILE"
  fi
  if $DO_REGISTRY; then echo "  registry_data:" >> "$COMPOSE_FILE"; fi
}

compose_up(){ (cd "$COMPOSE_DIR" && docker compose up -d); }

mysql_reset_on_init_error(){
  local cid
  cid=$(docker ps --filter 'name=compose-mysql-1' -q || true)
  [[ -z "$cid" ]] && return 0
  if docker logs "$cid" --since=10m 2>&1 | grep -qE \
     'data directory has files in it|designated data directory .* is unusable|Cannot create redo log files'; then
    log "Detected MySQL init failure (bad data dir). Resetting volume once."
    (cd "$COMPOSE_DIR" && docker compose down) || true
    docker volume rm compose_mysql_data || true
    compose_up
  fi
}

mysql_bootstrap_db_user(){
  log "Waiting for MySQL (container health=healthy)"
  local cid
  cid=$(docker ps --filter 'name=compose-mysql-1' --format '{{.ID}}' | head -n1 || true)
  if [[ -z "$cid" ]]; then err "MySQL container not found"; return 1; fi
  for i in {1..240}; do  # up to ~8 minutes for first init
    state=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$cid" 2>/dev/null || true)
    [[ "$state" == "healthy" ]] && return 0
    sleep 2
  done
  err "MySQL did not become healthy in time"; return 1
}

write_nginx(){
  cat > "$NGINX_SITE" <<NGINX
# Redirect HTTP -> HTTPS for all hosts
server {
  listen 80;
  server_name ${GITLAB_HOST} ${AWX_HOST} ${PMA_HOST} ${REGISTRY_HOST};
  return 301 https://\$host\$request_uri;
}

# ============= GitLab =============
server {
  listen 443 ssl http2;
  server_name ${GITLAB_HOST};
  ssl_certificate ${CERT_PEM};
  ssl_certificate_key ${CERT_KEY};
  client_max_body_size 512m;
  proxy_read_timeout 3600s;
  proxy_send_timeout 3600s;
  location / {
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_pass http://127.0.0.1:${GITLAB_HTTP_PORT};
  }
}

# ============= Local Docker Registry (TLS via Nginx) =============
# NOTE: HTTP/2 disabled for registry to avoid 400s on docker login/push.
server {
  listen 443 ssl;
  server_name ${REGISTRY_HOST};
  ssl_certificate ${CERT_PEM};
  ssl_certificate_key ${CERT_KEY};
  client_max_body_size 0;
  chunked_transfer_encoding on;
  add_header Docker-Distribution-Api-Version "registry/2.0" always;

  location /v2/ {
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_set_header Host \$http_host;
    proxy_set_header Authorization \$http_authorization;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_pass http://127.0.0.1:5000;
    proxy_request_buffering off;
    proxy_buffering off;
    proxy_read_timeout 900;
    proxy_send_timeout 900;
  }
}

# ============= AWX =============
server {
  listen 443 ssl;
  server_name ${AWX_HOST};
  ssl_certificate ${CERT_PEM};
  ssl_certificate_key ${CERT_KEY};
  proxy_read_timeout 3600s;
  proxy_send_timeout 3600s;

  location / {
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_pass http://127.0.0.1:${AWX_NODEPORT};
  }

  location /websocket {
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-Proto https;
    proxy_read_timeout 86400;
    proxy_pass http://127.0.0.1:${AWX_NODEPORT};
  }
}

# ============= phpMyAdmin =============
server {
  listen 443 ssl;
  server_name ${PMA_HOST};
  ssl_certificate ${CERT_PEM};
  ssl_certificate_key ${CERT_KEY};
  location / {
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_pass http://127.0.0.1:${PMA_BIND_PORT};
  }
}
NGINX
  ln -sf "$NGINX_SITE" "$NGINX_SITE_LINK"
  nginx -t && systemctl reload nginx
}

ensure_k3s_config(){
  install -d -m 755 /etc/rancher/k3s
  cat >/etc/rancher/k3s/config.yaml <<EOF
write-kubeconfig-mode: "0644"
disable:
  - traefik
  - servicelb
EOF
}

install_k3s(){
  ensure_k3s_config
  if [[ -f "$K3S_KUBECONFIG" ]]; then
    log "k3s already installed; restarting"
    systemctl restart k3s
    return
  fi
  log "Installing k3s"
  curl -sfL https://get.k3s.io | sh -
}

cleanup_k3s_port_claimers(){
  export KUBECONFIG="$K3S_KUBECONFIG"
  kubectl -n kube-system delete deploy/traefik --ignore-not-found
  kubectl -n kube-system delete svc/traefik --ignore-not-found
  kubectl -n kube-system delete ds/svclb-traefik --ignore-not-found
}

kube_ready(){
  export KUBECONFIG="$K3S_KUBECONFIG"
  for i in {1..60}; do
    kubectl get nodes >/dev/null 2>&1 && return 0
    sleep 2
  done
  err "kubectl not ready"; return 1
}

install_awx_operator(){
  export KUBECONFIG="$K3S_KUBECONFIG"
  kubectl create ns "$AWX_NAMESPACE" 2>/dev/null || true
  log "Deploying AWX Operator (version ${AWX_OPERATOR_VERSION})"
  kubectl apply -k "https://github.com/ansible/awx-operator/config/default?ref=${AWX_OPERATOR_VERSION}" -n "$AWX_NAMESPACE"
}

wait_for_awx_crd(){
  export KUBECONFIG="$K3S_KUBECONFIG"
  log "Waiting for AWX CRDs to register..."
  for i in {1..60}; do
    kubectl get crd awxs.awx.ansible.com >/dev/null 2>&1 && return 0
    sleep 2
  done
  err "Timed out waiting for AWX CRD"; return 1
}

# Optional: create imagePullSecret for your private registry in the awx namespace
ensure_k8s_registry_secret(){
  export KUBECONFIG="$K3S_KUBECONFIG"
  if kubectl -n "$AWX_NAMESPACE" get secret regcred >/dev/null 2>&1; then
    return 0
  fi
  kubectl -n "$AWX_NAMESPACE" create secret docker-registry regcred \
    --docker-server="${REGISTRY_HOST}" \
    --docker-username="${REGISTRY_USER}" \
    --docker-password="${REGISTRY_PASS}" || true
}

deploy_awx(){
  export KUBECONFIG="$K3S_KUBECONFIG"

  # Ensure admin password secret exists (idempotent)
  kubectl -n "$AWX_NAMESPACE" create secret generic ${AWX_NAME}-admin-password \
    --from-literal=password="${AWX_ADMIN_PASS}" \
    --dry-run=client -o yaml | kubectl apply -f -

  cat <<YAML | kubectl apply -n "$AWX_NAMESPACE" -f -
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: ${AWX_NAME}
spec:
  service_type: NodePort
  nodeport_port: ${AWX_NODEPORT}
  ingress_type: none
  admin_user: ${AWX_ADMIN_USER}
  admin_password_secret: ${AWX_NAME}-admin-password
  host_aliases:
    - ip: ${SERVER_IP}
      hostnames:
        - ${GITLAB_HOST}
        - ${AWX_HOST}
        - ${PMA_HOST}
        - ${REGISTRY_HOST}
YAML
}

patch_coredns_hosts(){
  $DO_PATCH_DNS || return 0
  export KUBECONFIG="$K3S_KUBECONFIG"
  local LINE="${SERVER_IP} ${GITLAB_HOST} ${AWX_HOST} ${PMA_HOST} ${REGISTRY_HOST}"

  # Wait for CoreDNS ConfigMap
  for i in {1..120}; do
    kubectl -n kube-system get cm coredns >/dev/null 2>&1 && break || sleep 2
  done || { err "CoreDNS configmap not found"; return 1; }

  # Ensure hosts plugin exists once (merge Corefile if missing)
  if ! kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' | grep -q 'hosts /etc/coredns/NodeHosts'; then
    kubectl -n kube-system patch cm coredns --type merge --patch \
      '{"data":{"Corefile":".:53 {\n    errors\n    health\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n      pods insecure\n      fallthrough in-addr.arpa ip6.arpa\n    }\n    hosts /etc/coredns/NodeHosts {\n      ttl 60\n      reload 15s\n      fallthrough\n    }\n    prometheus :9153\n    forward . /etc/resolv.conf\n    cache 30\n    loop\n    reload\n    loadbalance\n    import /etc/coredns/custom/*.override\n}\nimport /etc/coredns/custom/*.server\n"}}'
  fi

  # Merge NodeHosts content, JSON-escape via jq -Rs, retry on conflict
  for i in {1..10}; do
    cur="$(kubectl -n kube-system get cm coredns -o jsonpath='{.data.NodeHosts}' 2>/dev/null || true)"
    # append, trim duplicate spaces, unique lines, ensure trailing newline
    new="$(printf "%s\n%s\n" "$cur" "$LINE" | awk '{$1=$1} NF' | awk '!seen[$0]++')"$'\n'
    json_str="$(printf "%s" "$new" | jq -Rs .)"  # proper JSON string

    if kubectl -n kube-system patch cm coredns --type merge --patch "{\"data\":{\"NodeHosts\":${json_str}}}"; then
      kubectl -n kube-system rollout restart deploy/coredns
      return 0
    fi
    sleep 1
  done

  err "Failed to patch CoreDNS NodeHosts after retries"
}

docker_login_registry(){
  log "Testing docker login to https://${REGISTRY_HOST}"
  if ! printf '%s' "$REGISTRY_PASS" | docker login "$REGISTRY_HOST" -u "$REGISTRY_USER" --password-stdin; then
    err "docker login to ${REGISTRY_HOST} failed (check DNS/certs/Nginx/htpasswd)"
  fi
}

awx_admin_password(){
  export KUBECONFIG="$K3S_KUBECONFIG"
  kubectl get secret ${AWX_NAME}-admin-password -n "$AWX_NAMESPACE" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true
}

gitlab_initial_password(){
  local cid
  cid=$(docker ps --filter "name=gitlab" --format '{{.ID}}' | head -n1 || true)
  if [[ -n "$cid" ]]; then
    docker exec -t "$cid" bash -lc "cat /etc/gitlab/initial_root_password 2>/dev/null || true"
  fi
}

print_summary(){
  echo
  echo "================ Deployment Summary ================"
  echo "Server IP:        $SERVER_IP"
  echo "Domain:           $DOMAIN"
  echo "GitLab:           https://$GITLAB_HOST  (SSH: $GITLAB_SSH_PORT)"
  echo "AWX:              https://$AWX_HOST"
  echo "phpMyAdmin:       https://$PMA_HOST"
  echo "Local Registry:   https://$REGISTRY_HOST (user: $REGISTRY_USER)"
  echo
  echo "MySQL DSN example:"
  echo "  mysql+pymysql://${APP_DB_USER}:${APP_DB_PASS}@${SERVER_IP}:${MYSQL_PORT}/${APP_DB_NAME}"
  echo
  echo "GitLab initial root password file (if present, valid ~24h):"
  gitlab_initial_password | sed 's/^/  /'
  echo
  echo "AWX admin password:"
  echo "  ${AWX_ADMIN_PASS}"
  echo "===================================================="
}

status(){
  echo "Docker containers:"; docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
  echo
  echo "Kubernetes (k3s) AWX pods:"; export KUBECONFIG="$K3S_KUBECONFIG"; kubectl -n "$AWX_NAMESPACE" get pods 2>/dev/null || true
  echo
  echo "Nginx vhosts:"; grep -n "server_name" "$NGINX_SITE" 2>/dev/null || true
}

# ----------------- Main -----------------
need_root
parse_args "$@"
check_os

# Base tooling
if $DO_MYSQL || $DO_PMA || $DO_GITLAB || $DO_NGINX || $DO_CERTS || $DO_K3S || $DO_AWX || $DO_ALL || $DO_REGISTRY; then
  apt_install
  ensure_compose
fi

# Certs first (needed by Nginx & trust steps)
if $DO_CERTS || $DO_REGISTRY || $DO_NGINX || $DO_ALL; then
  install_mkcert
  make_certs
fi

# Compose services
if $DO_MYSQL || $DO_PMA || $DO_GITLAB || $DO_REGISTRY; then
  setup_registry_auth
  if $DO_MYSQL_RESET; then
    mysql_reset_volume
  else
    $DO_MYSQL && mysql_volume_maybe_reset_first_boot
  fi
  write_compose
  compose_up
  $DO_MYSQL && mysql_reset_on_init_error
fi

if $DO_MYSQL; then
  # Watch logs briefly for "Cannot create redo log files" and auto-reset once
  cid=$(docker ps --filter 'name=compose-mysql-1' -q || true)
  if [[ -n "$cid" ]] && docker logs "$cid" --since=30s 2>&1 \
      | grep -q 'Cannot create redo log files'; then
    log "Detected MySQL redo-log init failure right after start; auto-resetting volume."
    (cd "$COMPOSE_DIR" && docker compose down) || true
    docker volume rm compose_mysql_data || true
    compose_up
  fi
fi

# Nginx (after compose so backends exist)
if $DO_NGINX || $DO_REGISTRY || $DO_PMA || $DO_GITLAB; then
  write_nginx
fi

# Hostname resolution for the host itself
ensure_hosts_entries

# Docker trust for internal TLS registry, then test login
if $DO_REGISTRY; then
  ensure_docker_trust
  docker_login_registry || true
fi

# k3s (and its trust to the internal registry)
if $DO_K3S || $DO_AWX; then
  install_k3s
  kube_ready
  cleanup_k3s_port_claimers
  ensure_registry_trust_for_k3s
  $DO_PATCH_DNS && patch_coredns_hosts || true
fi

# MySQL bootstrap wait
$DO_MYSQL && mysql_bootstrap_db_user || true

# AWX
if $DO_AWX; then
  kube_ready
  install_awx_operator
  wait_for_awx_crd
  # Prepare regcred for later private pulls (optional):
  ensure_k8s_registry_secret || true
  # Deploy AWX with preset admin credentials
  deploy_awx
fi

# Patch DNS again after AWX (harmless if already done)
$DO_PATCH_DNS && { kube_ready && patch_coredns_hosts || true; }

$DO_STATUS && status
$DO_ALL && print_summary
