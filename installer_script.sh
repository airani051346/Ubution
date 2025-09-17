#!/usr/bin/env bash
set -euo pipefail

# ==============================================
# stackctl.sh
# Install & wire up on one Ubuntu host:
#   - Docker + docker compose plugin
#   - MySQL 8 (Docker)
#   - phpMyAdmin (Docker)
#   - GitLab Omnibus (Docker)
#   - Nginx (host) for TLS termination
#   - k3s (Kubernetes) + AWX Operator + AWX (NodePort)
# HTTPS for all apps via Nginx. AWX can pull from GitLab and reach MySQL.
# Ports are chosen to avoid conflicts.
#
# Usage examples:
#   sudo bash stackctl.sh --all --domain example.lan \
#        --gitlab-host gitlab.example.lan --awx-host awx.example.lan --pma-host pma.example.lan
#
#   sudo bash stackctl.sh --mysql --pma
#   sudo bash stackctl.sh --gitlab
#   sudo bash stackctl.sh --awx
#   sudo bash stackctl.sh --nginx --certs
#   sudo bash stackctl.sh --status
#
# NOTE: Defaults are meant for a LAN/Dev setup with mkcert.
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
AWX_OPERATOR_VERSION="2.19.0"  # change if needed; tag in awx-operator repo

# GitLab container ports
GITLAB_HTTP_PORT=8929
GITLAB_SSH_PORT=2222

# phpMyAdmin bind port (loopback only)
PMA_BIND_PORT=9001

# MySQL
MYSQL_PORT=3306                 # host port (exposed on 0.0.0.0)
MYSQL_ROOT_PASSWORD="ChangeMe!Strong123"  # override with env or pass via --mysql-root-pass
APP_DB_NAME=appdb
APP_DB_USER=awx_app
APP_DB_PASS="AppDbStrong!123"  # AWX/Ansible can use this

# Internal flags (targets)
DO_MYSQL=false
DO_PMA=false
DO_GITLAB=false
DO_NGINX=false
DO_CERTS=false
DO_K3S=false
DO_AWX=false
DO_STATUS=false
DO_ALL=false
DO_DNS_PATCH=true   # patch CoreDNS so pods can resolve our hostnames to SERVER_IP
DO_PATCH_DNS=false    # run only the CoreDNS patch step (use --dns-patch)

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
Usage: $0 [--all] [--mysql] [--pma] [--gitlab] [--nginx] [--certs] [--k3s] [--awx] [--status]
           [--domain DOMAIN] [--gitlab-host HOST] [--awx-host HOST] [--pma-host HOST]
           [--server-ip IP] [--mysql-port PORT] [--mysql-root-pass PASS]
           [--app-db-name NAME] [--app-db-user USER] [--app-db-pass PASS]
           [--gitlab-ssh-port PORT] [--awx-nodeport PORT] [--no-dns-patch]

Examples:
  sudo bash $0 --all --domain example.lan --gitlab-host gitlab.example.lan --awx-host awx.example.lan --pma-host pma.example.lan
  sudo bash $0 --mysql --pma
  sudo bash $0 --gitlab
  sudo bash $0 --awx
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

# Persist important hostnames so the systemd unit can read them later
write_stack_env() {
  cat > /etc/stackctl.env <<EOF
DOMAIN="${DOMAIN}"
GITLAB_HOST="${GITLAB_HOST}"
AWX_HOST="${AWX_HOST}"
PMA_HOST="${PMA_HOST}"
K3S_KUBECONFIG="${K3S_KUBECONFIG}"
EOF
}

# Install a systemd unit + timer that keeps CoreDNS NodeHosts in sync
install_coredns_ensure_unit() {
  cat > /usr/local/sbin/stackctl-coredns-ensure.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG="${K3S_KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
[[ -f /etc/stackctl.env ]] && . /etc/stackctl.env

get_primary_ip() {
  local ip
  ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src"){print $(i+1); exit}}') || true
  [[ -z "${ip:-}" ]] && ip=$(hostname -I | awk '{print $1}')
  echo "$ip"
}

wait_for_k8s(){
  for i in {1..90}; do
    kubectl get nodes >/dev/null 2>&1 && return 0
    sleep 2
  done
  echo "[stackctl] kubectl not ready" >&2
  return 1
}

ensure_nodehosts(){
  local ip; ip="$(get_primary_ip)"
  local a="${GITLAB_HOST:-gitlab.example.lan}"
  local b="${AWX_HOST:-awx.example.lan}"
  local c="${PMA_HOST:-pma.example.lan}"

  # Skip if user left example.lan defaults
  if [[ "$a" == "gitlab.example.lan" || "$b" == "awx.example.lan" || "$c" == "pma.example.lan" ]]; then
    echo "[stackctl] Skipping ensure: example.lan still set"
    return 0
  fi

  python3 - "$ip" "$a" "$b" "$c" <<'PY'
import sys, json, subprocess
ip,a,b,c = sys.argv[1:]
ns="kube-system"; name="coredns"

# If CoreDNS CM isn't there yet, exit quietly
try:
    d=json.loads(subprocess.check_output(["kubectl","-n",ns,"get","cm",name,"-o","json"]))
except subprocess.CalledProcessError:
    sys.exit(0)

# 1) Ensure Corefile uses NodeHosts file
core=d["data"].get("Corefile","")
needle="hosts /etc/coredns/NodeHosts {"
if needle not in core:
    ins = "    hosts /etc/coredns/NodeHosts {\n        ttl 60\n        reload 15s\n        fallthrough\n    }\n"
    fwd = "forward . /etc/resolv.conf"
    if fwd in core:
        core = core.replace(fwd, ins + "    " + fwd)
    else:
        core = core + "\n" + ins
    d["data"]["Corefile"]=core
    subprocess.run(["kubectl","-n",ns,"apply","-f","-"], input=json.dumps(d).encode(), check=False)

# 2) Idempotently update NodeHosts content
d=json.loads(subprocess.check_output(["kubectl","-n",ns,"get","cm",name,"-o","json"]))
nodehosts=d["data"].get("NodeHosts","")
targets={a,b,c}
def line_has_targets(ln):
    toks=ln.split()
    return any(h in toks[1:] for h in targets)
lines=[ln for ln in nodehosts.splitlines() if ln.strip() and not line_has_targets(ln)]
lines.append(f"{ip} {a} {b} {c}")
new="\n".join(lines)+"\n"

if d["data"].get("NodeHosts","") != new:
    d["data"]["NodeHosts"]=new
    subprocess.run(["kubectl","-n",ns,"apply","-f","-"], input=json.dumps(d).encode(), check=False)
    subprocess.run(["kubectl","-n",ns,"rollout","restart","deploy/coredns"], check=False)
PY
}

wait_for_k8s && ensure_nodehosts
EOS
  chmod +x /usr/local/sbin/stackctl-coredns-ensure.sh

  cat > /etc/systemd/system/stackctl-coredns-ensure.service <<'EOF'
[Unit]
Description=Ensure CoreDNS NodeHosts has current host IP for GitLab/AWX/pma
Wants=network-online.target
After=network-online.target k3s.service

[Service]
Type=oneshot
EnvironmentFile=-/etc/stackctl.env
Environment=K3S_KUBECONFIG=/etc/rancher/k3s/k3s.yaml
ExecStart=/usr/local/sbin/stackctl-coredns-ensure.sh
EOF

  cat > /etc/systemd/system/stackctl-coredns-ensure.timer <<'EOF'
[Unit]
Description=Periodic CoreDNS NodeHosts ensure

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Unit=stackctl-coredns-ensure.service

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now stackctl-coredns-ensure.timer
  systemctl start stackctl-coredns-ensure.service || true
}

parse_args() {
  # Track explicit host overrides so we can recompute when only --domain is given
  local DID_SET_GITLAB_HOST=false
  local DID_SET_AWX_HOST=false
  local DID_SET_PMA_HOST=false

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
      --no-dns-patch) DO_DNS_PATCH=false ;;
      --domain) DOMAIN="$2"; shift ;;
      --gitlab-host) GITLAB_HOST="$2"; DID_SET_GITLAB_HOST=true; shift ;;
      --awx-host) AWX_HOST="$2"; DID_SET_AWX_HOST=true; shift ;;
      --pma-host) PMA_HOST="$2"; DID_SET_PMA_HOST=true; shift ;;
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
    DO_MYSQL=true; DO_PMA=true; DO_GITLAB=true; DO_K3S=true; DO_AWX=true; DO_CERTS=true; DO_NGINX=true
  fi

  # If user only changed --domain, recompute hosts accordingly
  if ! $DID_SET_GITLAB_HOST; then GITLAB_HOST="gitlab.${DOMAIN}"; fi
  if ! $DID_SET_AWX_HOST; then AWX_HOST="awx.${DOMAIN}"; fi
  if ! $DID_SET_PMA_HOST; then PMA_HOST="pma.${DOMAIN}"; fi
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
    docker.io nginx python3 python3-yaml
  systemctl enable --now docker nginx
}

ensure_compose() {
  if ! docker compose version >/dev/null 2>&1; then
    log "Installing docker compose plugin"
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -L https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-$(uname -s)-$(uname -m) \
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

make_certs() {
  mkdir -p "$CERT_DIR"
  if [[ ! -s "$CERT_PEM" || ! -s "$CERT_KEY" ]]; then
    log "Generating SAN cert for $GITLAB_HOST, $AWX_HOST, $PMA_HOST"
    mkcert -cert-file "$CERT_PEM" -key-file "$CERT_KEY" \
      "$GITLAB_HOST" "$AWX_HOST" "$PMA_HOST"
  else
    log "Existing certs found in $CERT_DIR (skipping)"
  fi
}

write_compose() {
  mkdir -p "$COMPOSE_DIR"
  cat > "$COMPOSE_FILE" <<YAML
services:
  mysql:
    image: mysql:8.4
    environment:
      MYSQL_ROOT_PASSWORD: "${MYSQL_ROOT_PASSWORD}"
      MYSQL_DATABASE: "${APP_DB_NAME}"
      MYSQL_USER: "${APP_DB_USER}"
      MYSQL_PASSWORD: "${APP_DB_PASS}"
    ports:
      - "0.0.0.0:${MYSQL_PORT}:3306"   # reachable from k8s pods
    healthcheck:
      test: ["CMD-SHELL", "mysqladmin ping -uroot -p$${MYSQL_ROOT_PASSWORD} --silent"]
      interval: 5s
      timeout: 3s
      retries: 60
      start_period: 20s
    volumes:
      - mysql_data:/var/lib/mysql
    networks: [back]

  phpmyadmin:
    image: phpmyadmin:latest
    environment:
      PMA_HOST: mysql
      PMA_ABSOLUTE_URI: https://${PMA_HOST}/
    depends_on: [mysql]
    ports:
      - "127.0.0.1:${PMA_BIND_PORT}:80"  # loopback; proxied by Nginx
    networks: [back]

  gitlab:
    image: gitlab/gitlab-ee:latest
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

networks:
  back:

volumes:
  mysql_data:
  gitlab_config:
  gitlab_logs:
  gitlab_data:
YAML
}

compose_up() {
  (cd "$COMPOSE_DIR" && docker compose up -d)
}

mysql_bootstrap_db_user() {
  # No-op: DB and user are now created by the MySQL image on first init via env vars
  # Still wait briefly until healthy for nicer UX
  log "Waiting for MySQL to report healthy"
  for i in {1..60}; do
    if docker exec compose-mysql-1 mysqladmin ping -uroot -p"${MYSQL_ROOT_PASSWORD}" --silent >/dev/null 2>&1; then
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
  server_name ${GITLAB_HOST} ${AWX_HOST} ${PMA_HOST};
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
  # Backup existing config if we are changing it
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

# After k3s is ready, make sure any leftover Traefik/ServiceLB resources are gone
cleanup_k3s_port_claimers() {
  export KUBECONFIG="$K3S_KUBECONFIG"
  # These may or may not exist depending on timing; ignore errors
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
YAML
}

patch_coredns_hosts() {
  if ! $DO_DNS_PATCH; then return; fi
  export KUBECONFIG="$K3S_KUBECONFIG"

  local A_HOST="$GITLAB_HOST" B_HOST="$AWX_HOST" C_HOST="$PMA_HOST"
  if [[ "$A_HOST" == "gitlab.example.lan" || "$B_HOST" == "awx.example.lan" || "$C_HOST" == "pma.example.lan" ]]; then
    log "Skipping CoreDNS patch: hostnames still set to example.lan. Pass --domain/--*-host to set real names."
    return 0
  fi

  log "Waiting for CoreDNS ConfigMap..."
  for i in {1..120}; do
    kubectl -n kube-system get cm coredns >/dev/null 2>&1 && break || sleep 2
  done
  if ! kubectl -n kube-system get cm coredns >/div/null 2>&1; then
    err "CoreDNS configmap not found; try again shortly with --dns-patch."
    return 1
  fi

  local CUR_IP; CUR_IP="$(get_primary_ip)"
  log "Syncing CoreDNS NodeHosts -> ${CUR_IP} ${A_HOST} ${B_HOST} ${C_HOST}"

  python3 - "$CUR_IP" "$A_HOST" "$B_HOST" "$C_HOST" <<'PY'
import sys, json, subprocess
ip,a,b,c = sys.argv[1:]
ns="kube-system"; name="coredns"

# Ensure Corefile points at NodeHosts file (k3s default, but make sure)
d=json.loads(subprocess.check_output(["kubectl","-n",ns,"get","cm",name,"-o","json"]))
core=d["data"].get("Corefile","")
needle="hosts /etc/coredns/NodeHosts {"
if needle not in core:
    ins = "    hosts /etc/coredns/NodeHosts {\n        ttl 60\n        reload 15s\n        fallthrough\n    }\n"
    fwd = "forward . /etc/resolv.conf"
    if fwd in core:
        core = core.replace(fwd, ins + "    " + fwd)
    else:
        core = core + "\n" + ins
    d["data"]["Corefile"]=core
    subprocess.check_call(["kubectl","-n",ns,"apply","-f","-"], input=json.dumps(d).encode())

# Update NodeHosts content idempotently
d=json.loads(subprocess.check_output(["kubectl","-n",ns,"get","cm",name,"-o","json"]))
nodehosts=d["data"].get("NodeHosts","")
targets={a,b,c}
def line_has_targets(ln):
    toks=ln.split()
    return any(h in toks[1:] for h in targets)
lines=[ln for ln in nodehosts.splitlines() if ln.strip() and not line_has_targets(ln)]
lines.append(f"{ip} {a} {b} {c}")
new="\n".join(lines)+"\n"

changed = d["data"].get("NodeHosts","") != new
if changed:
    d["data"]["NodeHosts"]=new
    subprocess.check_call(["kubectl","-n",ns,"apply","-f","-"], input=json.dumps(d).encode())
    subprocess.check_call(["kubectl","-n",ns,"rollout","restart","deploy/coredns"])
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
  echo "Docker containers:"; docker ps --format 'table {{.Names}}	{{.Image}}	{{.Status}}	{{.Ports}}'
  echo
  echo "Kubernetes (k3s) AWX pods:"; export KUBECONFIG="$K3S_KUBECONFIG"; kubectl -n "$AWX_NAMESPACE" get pods 2>/dev/null || true
  echo
  echo "Nginx vhosts:"; grep -n "server_name" "$NGINX_SITE" 2>/dev/null || true
}

# ----------------- Main -----------------
need_root
parse_args "$@"
check_os

if $DO_MYSQL || $DO_PMA || $DO_GITLAB || $DO_NGINX || $DO_CERTS || $DO_K3S || $DO_AWX || $DO_ALL; then
  apt_install
  ensure_compose
fi

if $DO_CERTS; then
  install_mkcert
  make_certs
fi

if $DO_MYSQL || $DO_PMA || $DO_GITLAB; then
  write_compose
  compose_up
fi

if $DO_MYSQL; then
  mysql_bootstrap_db_user
fi

if $DO_K3S; then
  install_k3s
  kube_ready
  cleanup_k3s_port_claimers
  if $DO_DNS_PATCH; then patch_coredns_hosts; fi
  **install_coredns_ensure_unit**
fi

if $DO_AWX; then
  kube_ready
  install_awx_operator
  deploy_awx
fi

if $DO_PATCH_DNS; then
  kube_ready
  patch_coredns_hosts
  **install_coredns_ensure_unit**
fi

if $DO_NGINX; then
  write_nginx
fi

if $DO_STATUS; then
  status
fi

if $DO_ALL; then
  print_summary
fi
