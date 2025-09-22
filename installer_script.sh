#!/usr/bin/env bash
set -euo pipefail

# ==============================================
# stackctl.sh (corrected)
# One-host setup for:
#   - Docker + docker compose plugin
#   - MySQL 8 (Docker)
#   - phpMyAdmin (Docker)
#   - GitLab Omnibus (Docker)
#   - Nginx (host) TLS reverse proxy
#   - k3s (Kubernetes) + AWX Operator + AWX (NodePort)
#   - Local Docker Registry with basic auth
#
# HTTPS for all apps via Nginx (mkcert for LAN/dev).
# CoreDNS patch allows pods to resolve hostnames (gitlab/awx/pma/registry) to this node IP.
# ==============================================

# ----------------- Defaults -----------------
: "${DOMAIN:=example.lan}"
: "${GITLAB_HOST:=gitlab.${DOMAIN}}"
: "${AWX_HOST:=awx.${DOMAIN}}"
: "${PMA_HOST:=pma.${DOMAIN}}"

: "${SERVER_IP:=$(hostname -I | awk '{print $1}')}"
: "${OS_RELEASE:=$(. /etc/os-release; echo "$ID")}"  # ubuntu

# Docker compose project dir
STACK_DIR=/opt/stack
COMPOSE_DIR="$STACK_DIR/compose"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"
# Ensure docker compose always uses the same project name (usually 'compose')
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-$(basename "$COMPOSE_DIR")}"

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
AWX_OPERATOR_VERSION="2.19.0"  # tag in awx-operator repo

# GitLab container ports
GITLAB_HTTP_PORT=8929
GITLAB_SSH_PORT=2222

# phpMyAdmin bind port (loopback only)
PMA_BIND_PORT=9001

# MySQL
MYSQL_PORT=3306
MYSQL_ROOT_PASSWORD="ChangeMe!Strong123"
APP_DB_NAME=appdb
APP_DB_USER=awx_app
APP_DB_PASS="AppDbStrong!123"

# ---- Local registry ----
: "${REGISTRY_HOST:=registry.${DOMAIN}}"
: "${REGISTRY_USER:=awx}"
: "${REGISTRY_PASS:=ChangeMe!Reg123}"
REGISTRY_DIR="$STACK_DIR/registry"
REGISTRY_AUTH_FILE="$REGISTRY_DIR/htpasswd"
REGISTRY_DATA_DIR="$REGISTRY_DIR/data"

# Internal flags (targets)
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
DO_DNS_PATCH=true    # run CoreDNS patch during --k3s
DO_PATCH_DNS=false   # run only the CoreDNS patch step (with --dns-patch)

# ----------------- Helpers -----------------
log() { echo -e "[+] $*"; }
err() { echo -e "[!] $*" >&2; }

need_root() {
  if [[ $EUID -ne 0 ]]; then
    err "Please run as root (sudo)."; exit 1
  fi
}

usage() {
  cat <<USAGE
Usage: $0 [--all] [--mysql] [--pma] [--gitlab] [--nginx] [--certs] [--k3s] [--awx] [--status] [--registry]
           [--domain DOMAIN] [--gitlab-host HOST] [--awx-host HOST] [--pma-host HOST] [--registry-host HOST]
           [--server-ip IP] [--mysql-port PORT] [--mysql-root-pass PASS]
           [--app-db-name NAME] [--app-db-user USER] [--app-db-pass PASS]
           [--gitlab-ssh-port PORT] [--awx-nodeport PORT] [--dns-patch] [--no-dns-patch]

Examples:
  sudo bash $0 --all --domain example.lan --gitlab-host gitlab.example.lan --awx-host awx.example.lan --pma-host pma.example.lan
  sudo bash $0 --mysql --pma
  sudo bash $0 --gitlab
  sudo bash $0 --k3s --awx
  sudo bash $0 --registry --domain fritz.lan --registry-host registry.fritz.lan
  sudo bash $0 --status
USAGE
}

# Prefer the IP of the default route; fall back to hostname -I
get_primary_ip() {
  local ip
  ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src"){print $(i+1); exit}}') || true
  [[ -z "${ip:-}" ]] && ip=$(hostname -I | awk '{print $1}')
  echo "$ip"
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
      --dns-patch) DO_PATCH_DNS=true ;;
      --status) DO_STATUS=true ;;
      --registry) DO_REGISTRY=true ;;
      --no-dns-patch) DO_DNS_PATCH=false ;;
      --domain) DOMAIN="$2"; shift ;;
      --gitlab-host) GITLAB_HOST="$2"; DID_SET_GITLAB_HOST=true; shift ;;
      --awx-host) AWX_HOST="$2"; DID_SET_AWX_HOST=true; shift ;;
      --pma-host) PMA_HOST="$2"; DID_SET_PMA_HOST=true; shift ;;
      --registry-host) REGISTRY_HOST="$2"; DID_SET_REGISTRY_HOST=true; shift ;;
      --server-ip) SERVER_IP="$2"; shift ;;
      --mysql-port) MYSQL_PORT="$2"; shift ;;
      --mysql-root-pass) MYSQL_ROOT_PASSWORD="$2"; shift ;;
      --app-db-name) APP_DB_NAME="$2"; shift ;;
      --app-db-user) APP_DB_USER="$2"; shift ;;
      --app-db-pass) APP_DB_PASS="$2"; shift ;;
      --gitlab-ssh-port) GITLAB_SSH_PORT="$2"; shift ;;
      --awx-nodeport) AWX_NODEPORT="$2"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) err "Unknown arg: $1"; usage; exit 1 ;;
    esac
    shift
  done

  if $DO_ALL; then
    DO_MYSQL=true; DO_PMA=true; DO_GITLAB=true; DO_K3S=true; DO_AWX=true; DO_CERTS=true; DO_NGINX=true; DO_REGISTRY=true
  fi

  # Recompute hosts if only --domain was changed
  if ! $DID_SET_GITLAB_HOST;   then GITLAB_HOST="gitlab.${DOMAIN}";     fi
  if ! $DID_SET_AWX_HOST;      then AWX_HOST="awx.${DOMAIN}";           fi
  if ! $DID_SET_PMA_HOST;      then PMA_HOST="pma.${DOMAIN}";           fi
  if ! $DID_SET_REGISTRY_HOST; then REGISTRY_HOST="registry.${DOMAIN}"; fi
}

check_os() {
  if [[ "$OS_RELEASE" != "ubuntu" ]]; then
    err "This script targets Ubuntu. Detected: $OS_RELEASE"; exit 1
  fi
}

apt_install() {
  DEBIAN_FRONTEND=noninteractive apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apt-transport-https ca-certificates curl gnupg lsb-release jq git make openssl \
    docker.io nginx python3 python3-yaml apache2-utils
  systemctl enable --now docker nginx
}

ensure_compose() {
  if ! docker compose version >/dev/null 2>&1; then
    log "Installing docker compose plugin"
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -L "https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-$(uname -s)-$(uname -m)" \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
  fi
}

install_mkcert() {
  if ! command -v mkcert >/dev/null 2>&1; then
    log "Installing mkcert"
    curl -L https://github.com/FiloSottile/mkcert/releases/latest/download/mkcert-v1.4.4-linux-amd64 \
      -o /usr/local/bin/mkcert && chmod +x /usr/local/bin/mkcert
    mkcert -install || true
  fi
}

ensure_registry_trust_for_k3s() {
  install -d -m 755 /etc/rancher/k3s
  local reg=/etc/rancher/k3s/registries.yaml
  local caroot
  caroot=$(mkcert -CAROOT)

  # Install mkcert root CA into system trust (helps containerd)
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

setup_registry_auth() {
  mkdir -p "$REGISTRY_DIR" "$REGISTRY_DATA_DIR"
  if [[ ! -s "$REGISTRY_AUTH_FILE" ]]; then
    log "Creating registry htpasswd for ${REGISTRY_USER}"
    docker run --rm --entrypoint htpasswd httpd:2 -Bbn "$REGISTRY_USER" "$REGISTRY_PASS" > "$REGISTRY_AUTH_FILE"
    chmod 640 "$REGISTRY_AUTH_FILE"
  fi
}

# Ensure Docker client trusts the mkcert CA for our registry host
ensure_docker_client_trust_for_registry() {
  local caroot
  caroot="$(mkcert -CAROOT)"
  install -d -m 0755 "/etc/docker/certs.d/${REGISTRY_HOST}"
  install -m 0644 "${caroot}/rootCA.pem" "/etc/docker/certs.d/${REGISTRY_HOST}/ca.crt"
  systemctl restart docker || true
}

# Enable htpasswd auth inside the registry container via a compose override
# (Only writes the override; first compose_up will use it automatically)
enable_registry_auth_in_compose() {
  mkdir -p "$COMPOSE_DIR"
  [[ -s "${REGISTRY_AUTH_FILE}" ]] || {
    log "Creating registry htpasswd for ${REGISTRY_USER}"
    docker run --rm --entrypoint htpasswd httpd:2 -Bbn "${REGISTRY_USER}" "${REGISTRY_PASS}" > "${REGISTRY_AUTH_FILE}"
    chmod 640 "${REGISTRY_AUTH_FILE}"
  }

  cat > "${COMPOSE_DIR}/docker-compose.override.yml" <<EOF
services:
  registry:
    environment:
      REGISTRY_AUTH: "htpasswd"
      REGISTRY_AUTH_HTPASSWD_REALM: "Registry"
      REGISTRY_AUTH_HTPASSWD_PATH: "/auth/htpasswd"
    volumes:
      - ${REGISTRY_AUTH_FILE}:/auth/htpasswd:ro
EOF
}

# Remove a previously created container with a mismatched compose project label
cleanup_stray_registry_container() {
  local cname="${COMPOSE_PROJECT_NAME}-registry-1"
  if docker inspect "$cname" >/dev/null 2>&1; then
    local proj
    proj="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' "$cname" 2>/dev/null || true)"
    if [[ "$proj" != "$COMPOSE_PROJECT_NAME" ]]; then
      log "Removing stray $cname (compose project '$proj' != '$COMPOSE_PROJECT_NAME')"
      docker rm -f "$cname" || true
    fi
  fi
}

# Quick smoke tests (does not fail the run)
smoke_test_registry() {
  set +e
  echo
  log "Quick registry checks:"
  curl -sI "http://127.0.0.1:5000/v2/" | head -n1
  curl -skI "https://${REGISTRY_HOST}/v2/" | head -n1
  printf '%s' "${REGISTRY_PASS}" | docker login "${REGISTRY_HOST}" -u "${REGISTRY_USER}" --password-stdin
  set -e
}

make_certs() {
  mkdir -p "$CERT_DIR"
  local need=0
  if [[ -s "$CERT_PEM" && -s "$CERT_KEY" ]]; then
    for h in "$GITLAB_HOST" "$AWX_HOST" "$PMA_HOST" "$REGISTRY_HOST"; do
      if ! openssl x509 -in "$CERT_PEM" -noout -text 2>/dev/null | grep -q "DNS:${h}"; then
        need=1
      fi
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

write_compose() {
  mkdir -p "$COMPOSE_DIR"
  : > "$COMPOSE_FILE"
  echo "services:" >> "$COMPOSE_FILE"

  # MySQL (required if DO_MYSQL or DO_PMA)
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
      test: ["CMD-SHELL", "mysqladmin ping -uroot -p\$${MYSQL_ROOT_PASSWORD} --silent"]
      interval: 5s
      timeout: 3s
      retries: 60
      start_period: 20s
    volumes:
      - mysql_data:/var/lib/mysql
    networks: [back]
YAML
  fi

  # Local Registry (base: no auth; auth is injected via override)
  if $DO_REGISTRY; then
cat >> "$COMPOSE_FILE" <<YAML
  registry:
    image: registry:2
    restart: unless-stopped
    environment:
      REGISTRY_HTTP_ADDR: "0.0.0.0:5000"
      REGISTRY_STORAGE_DELETE_ENABLED: "true"
    ports:
      - "127.0.0.1:5000:5000"
    volumes:
      - ${REGISTRY_DATA_DIR}:/var/lib/registry
    networks: [back]
YAML
  fi

  # phpMyAdmin (requires MySQL)
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

  # Networks
cat >> "$COMPOSE_FILE" <<'YAML'

networks:
  back:

volumes:
YAML

  # Volumes conditionally
  if $DO_MYSQL || $DO_PMA; then echo "  mysql_data:" >> "$COMPOSE_FILE"; fi
  if $DO_GITLAB; then
    echo "  gitlab_config:" >> "$COMPOSE_FILE"
    echo "  gitlab_logs:"   >> "$COMPOSE_FILE"
    echo "  gitlab_data:"   >> "$COMPOSE_FILE"
  fi
  if $DO_REGISTRY; then echo "  registry_data:" >> "$COMPOSE_FILE"; fi
}

compose_up() {
  (cd "$COMPOSE_DIR" && docker compose up -d)
}

mysql_bootstrap_db_user() {
  log "Waiting for MySQL to report healthy"
  for i in {1..60}; do
    if docker exec "${COMPOSE_PROJECT_NAME}-mysql-1" mysqladmin ping -uroot -p"${MYSQL_ROOT_PASSWORD}" --silent >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  err "MySQL did not become ready in time"; return 1
}

write_nginx() {
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

  ssl_certificate     ${CERT_PEM};
  ssl_certificate_key ${CERT_KEY};

  client_max_body_size 512m;
  proxy_read_timeout   3600s;
  proxy_send_timeout   3600s;

  location / {
    proxy_set_header Host              \$host;
    proxy_set_header X-Real-IP         \$remote_addr;
    proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_pass http://127.0.0.1:${GITLAB_HTTP_PORT};
  }
}

# ============= Local Docker Registry =============
server {
  listen 443 ssl http2;
  server_name ${REGISTRY_HOST};

  ssl_certificate     ${CERT_PEM};
  ssl_certificate_key ${CERT_KEY};

  # Docker registry likes streaming uploads
  client_max_body_size 0;
  chunked_transfer_encoding on;
  add_header Docker-Distribution-Api-Version "registry/2.0" always;

  location /v2/ {
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_set_header Host              \$http_host;
    proxy_set_header Authorization     \$http_authorization;
    proxy_set_header X-Real-IP         \$remote_addr;
    proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_pass http://127.0.0.1:5000;

    proxy_request_buffering off;
    proxy_buffering off;
    proxy_read_timeout 900;
    proxy_send_timeout 900;
    auth_basic "Registry";
    auth_basic_user_file /opt/stack/registry/htpasswd;
  }
}

# ============= AWX =============
server {
  listen 443 ssl http2;
  server_name ${AWX_HOST};

  ssl_certificate     ${CERT_PEM};
  ssl_certificate_key ${CERT_KEY};

  proxy_read_timeout  3600s;
  proxy_send_timeout  3600s;

  location / {
    proxy_set_header Host              \$host;
    proxy_set_header X-Real-IP         \$remote_addr;
    proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_pass http://127.0.0.1:${AWX_NODEPORT};
  }

  location /websocket {
    proxy_http_version 1.1;
    proxy_set_header Upgrade    \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host       \$host;
    proxy_set_header X-Forwarded-Proto https;
    proxy_read_timeout 86400;
    proxy_pass http://127.0.0.1:${AWX_NODEPORT};
  }
}

# ============= phpMyAdmin =============
server {
  listen 443 ssl http2;
  server_name ${PMA_HOST};

  ssl_certificate     ${CERT_PEM};
  ssl_certificate_key ${CERT_KEY};

  location / {
    proxy_set_header Host              \$host;
    proxy_set_header X-Real-IP         \$remote_addr;
    proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_pass http://127.0.0.1:${PMA_BIND_PORT};
  }
}
NGINX

  ln -sf "$NGINX_SITE" "$NGINX_SITE_LINK"
  nginx -t && systemctl reload nginx
}

# Ensure k3s config disables Traefik + ServiceLB so Nginx can own 80/443
ensure_k3s_config() {
  install -d -m 755 /etc/rancher/k3s
  local cfg=/etc/rancher/k3s/config.yaml
  if [[ -f "$cfg" ]] && ! grep -q "disable:" "$cfg"; then
    cp "$cfg" "$cfg.bak.$(date +%s)" || true
  fi
  cat >"$cfg" <<EOF
write-kubeconfig-mode: "0644"
disable:
  - traefik
  - servicelb
EOF
}

install_compose_autostart() {
  cat > /etc/systemd/system/stackctl-compose.service <<'EOF'
[Unit]
Description=StackCTL Docker Compose app stack
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=/opt/stack/compose
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
RemainAfterExit=yes
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable stackctl-compose.service
  systemctl start stackctl-compose.service || true
}

install_k3s() {
  ensure_k3s_config
  if [[ -f "$K3S_KUBECONFIG" ]]; then
    log "k3s already installed; ensuring traefik/servicelb are disabled and restarting"
    systemctl restart k3s
    return
  fi
  log "Installing k3s (traefik/servicelb disabled via /etc/rancher/k3s/config.yaml)"
  curl -sfL https://get.k3s.io | sh -
}

cleanup_k3s_port_claimers() {
  export KUBECONFIG="$K3S_KUBECONFIG"
  kubectl -n kube-system delete deploy/traefik --ignore-not-found
  kubectl -n kube-system delete svc/traefik --ignore-not-found
  kubectl -n kube-system delete ds/svclb-traefik --ignore-not-found
}

kube_ready() {
  export KUBECONFIG="$K3S_KUBECONFIG"
  for i in {1..60}; do
    if kubectl get nodes >/dev/null 2>&1; then return 0; fi
    sleep 2
  done
  err "kubectl not ready"; return 1
}

install_awx_operator() {
  export KUBECONFIG="$K3S_KUBECONFIG"
  kubectl create ns "$AWX_NAMESPACE" 2>/dev/null || true
  log "Deploying AWX Operator (version ${AWX_OPERATOR_VERSION})"
  kubectl apply -k "https://github.com/ansible/awx-operator/config/default?ref=${AWX_OPERATOR_VERSION}" -n "$AWX_NAMESPACE"
}

# wait until the AWX CRD exists to avoid race
wait_for_awx_crd() {
  export KUBECONFIG="$K3S_KUBECONFIG"
  log "Waiting for AWX CRDs to register..."
  for i in {1..60}; do
    if kubectl get crd awxs.awx.ansible.com >/dev/null 2>&1; then
      log "AWX CRD found"
      return 0
    fi
    sleep 2
  done
  err "Timed out waiting for AWX CRD"
  return 1
}

deploy_awx() {
  export KUBECONFIG="$K3S_KUBECONFIG"
  cat <<YAML | kubectl apply -n "$AWX_NAMESPACE" -f -
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: ${AWX_NAME}
spec:
  service_type: NodePort
  nodeport_port: ${AWX_NODEPORT}
  ingress_type: none
  host_aliases:
    - ip: ${SERVER_IP}
      hostnames:
        - ${GITLAB_HOST}
        - ${AWX_HOST}
        - ${PMA_HOST}
        - ${REGISTRY_HOST}
YAML
}

patch_coredns_hosts() {
  if ! $DO_DNS_PATCH; then return; fi
  export KUBECONFIG="$K3S_KUBECONFIG"

  local A_HOST="$GITLAB_HOST" B_HOST="$AWX_HOST" C_HOST="$PMA_HOST" D_HOST="$REGISTRY_HOST"
  if [[ "$A_HOST" == "gitlab.example.lan" || "$B_HOST" == "awx.example.lan" || "$C_HOST" == "pma.example.lan" || "$D_HOST" == "registry.example.lan" ]]; then
    log "Skipping CoreDNS patch: hostnames still set to example.lan. Pass --domain/--*-host to set real names."
    return 0
  fi

  log "Waiting for CoreDNS ConfigMap..."
  for i in {1..120}; do
    kubectl -n kube-system get cm coredns >/dev/null 2>&1 && break || sleep 2
  done
  if ! kubectl -n kube-system get cm coredns >/dev/null 2>&1; then
    err "CoreDNS configmap not found; try again shortly with --dns-patch."
    return 1
  fi

  local CUR_IP; CUR_IP="$(get_primary_ip)"
  log "Syncing CoreDNS NodeHosts -> ${CUR_IP} ${A_HOST} ${B_HOST} ${C_HOST} ${D_HOST}"

  python3 - "$CUR_IP" "$A_HOST" "$B_HOST" "$C_HOST" "$D_HOST" <<'PY'
import sys, json, subprocess
ip,a,b,c,d = sys.argv[1:]
ns="kube-system"; name="coredns"

dobj=json.loads(subprocess.check_output(["kubectl","-n",ns,"get","cm",name,"-o","json"]))
core=dobj["data"].get("Corefile","")
needle="hosts /etc/coredns/NodeHosts {"
if needle not in core:
    ins = "    hosts /etc/coredns/NodeHosts {\n        ttl 60\n        reload 15s\n        fallthrough\n    }\n"
    fwd = "forward . /etc/resolv.conf"
    if fwd in core:
        core = core.replace(fwd, ins + "    " + fwd)
    else:
        core = core + "\n" + ins
    dobj["data"]["Corefile"]=core
    subprocess.run(["kubectl","-n",ns,"apply","-f","-"], input=json.dumps(dobj).encode(), check=True)

dobj=json.loads(subprocess.check_output(["kubectl","-n",ns,"get","cm",name,"-o","json"]))
nodehosts=dobj["data"].get("NodeHosts","")
targets={a,b,c,d}
def line_has_targets(ln):
    toks=ln.split()
    return any(h in toks[1:] for h in targets)
lines=[ln for ln in nodehosts.splitlines() if ln.strip() and not line_has_targets(ln)]
lines.append(f"{ip} {a} {b} {c} {d}")
new="\n".join(lines)+"\n"

if dobj["data"].get("NodeHosts","") != new:
    dobj["data"]["NodeHosts"]=new
    subprocess.run(["kubectl","-n",ns,"apply","-f","-"], input=json.dumps(dobj).encode(), check=True)
    subprocess.run(["kubectl","-n",ns,"rollout","restart","deploy/coredns"], check=True)
PY
}

awx_admin_password() {
  export KUBECONFIG="$K3S_KUBECONFIG"
  kubectl get secret ${AWX_NAME}-admin-password -n "$AWX_NAMESPACE" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true
}

gitlab_initial_password() {
  local cid
  cid=$(docker ps --filter "name=gitlab" --format '{{.ID}}' | head -n1 || true)
  if [[ -n "$cid" ]]; then
    docker exec -t "$cid" bash -lc "cat /etc/gitlab/initial_root_password 2>/dev/null || true"
  fi
}

print_summary() {
  echo
  echo "================ Deployment Summary ================"
  echo "Server IP:        $SERVER_IP"
  echo "Domain:           $DOMAIN"
  echo "GitLab:           https://$GITLAB_HOST  (SSH: $GITLAB_SSH_PORT)"
  echo "AWX:              https://$AWX_HOST"
  echo "phpMyAdmin:       https://$PMA_HOST"
  echo "Local Registry:   https://$REGISTRY_HOST (user: $REGISTRY_USER)"
  echo
  echo "MySQL DSN example for Ansible/Python:"
  echo "  mysql+pymysql://${APP_DB_USER}:${APP_DB_PASS}@${SERVER_IP}:${MYSQL_PORT}/${APP_DB_NAME}"
  echo
  echo "GitLab initial root password file (if present, valid ~24h):"
  gitlab_initial_password | sed 's/^/  /'
  echo
  echo "AWX admin password:"
  awx_admin_password | sed 's/^/  /'
  echo
  echo "Notes:"
  echo "- AWX pods can resolve ${GITLAB_HOST} and reach it via Nginx on this node (CoreDNS patched)."
  echo "- AWX/Ansible can reach MySQL at ${SERVER_IP}:${MYSQL_PORT}."
  echo "- phpMyAdmin manages the same MySQL database; credentials above."
  echo "===================================================="
}

status() {
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

if $DO_MYSQL || $DO_PMA || $DO_GITLAB || $DO_NGINX || $DO_CERTS || $DO_K3S || $DO_AWX || $DO_ALL || $DO_REGISTRY; then
  apt_install
  ensure_compose
fi

if $DO_CERTS; then
  install_mkcert
  make_certs
fi

# Compose services are written only for the requested components
if $DO_MYSQL || $DO_PMA || $DO_GITLAB || $DO_REGISTRY; then
  # If we’re doing the registry, ensure htpasswd & override exist BEFORE first up
  if $DO_REGISTRY; then
    install_mkcert
    setup_registry_auth
    enable_registry_auth_in_compose
  fi
  cleanup_stray_registry_container
  write_compose
  compose_up
  install_compose_autostart
fi

if $DO_MYSQL; then
  mysql_bootstrap_db_user
fi

if $DO_K3S; then
  install_k3s
  kube_ready
  cleanup_k3s_port_claimers
  if $DO_DNS_PATCH; then patch_coredns_hosts; fi
fi

if $DO_AWX; then
  kube_ready
  install_awx_operator
  wait_for_awx_crd
  deploy_awx
fi

if $DO_PATCH_DNS; then
  kube_ready
  patch_coredns_hosts
fi

if $DO_NGINX; then
  write_nginx
fi

if $DO_REGISTRY; then
  # certs/nginx/trust and tests (compose already up with override)
  make_certs
  write_nginx
  ensure_registry_trust_for_k3s
  ensure_docker_client_trust_for_registry
  smoke_test_registry
  if $DO_DNS_PATCH || $DO_K3S || $DO_AWX; then
    kube_ready || true
    patch_coredns_hosts || true
  fi
fi

if $DO_STATUS; then
  status
fi

if $DO_ALL; then
  print_summary
fi
