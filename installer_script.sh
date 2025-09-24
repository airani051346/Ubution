#!/usr/bin/env bash
# shellcheck disable=SC2155
set -euo pipefail

# ==============================================
# install_fritz_stack.sh
# One-host setup for:
#   - Docker + Nginx (host)
#   - Self-signed wildcard TLS for fritz.lan
#   - MySQL 8 (Docker)
#   - phpMyAdmin (Docker)
#   - GitLab CE (Docker)
#   - Nginx TLS reverse proxy
#   - Ansible + pip stack (AFTER Docker), Ansible collection, Python modules
# ==============================================

# ----------------- Defaults -----------------
: "${DOMAIN:=fritz.lan}"
: "${GITLAB_HOST:=gitlab.${DOMAIN}}"
: "${PMA_HOST:=pma.${DOMAIN}}"
: "${STACK_DIR:=/opt/fritz_stack}"
: "${CERT_DIR:=/etc/nginx/certs/${DOMAIN}}"
: "${MYSQL_ROOT_PASSWORD:=}"          # if empty, will be generated and saved

# Containers / images / network
NET_NAME="fritz_net"
MYSQL_CONT="mysql8"
PMA_CONT="pma"
GITLAB_CONT="gitlab"
MYSQL_IMAGE="mysql:8"
PMA_IMAGE="phpmyadmin:latest"
GITLAB_IMAGE="gitlab/gitlab-ce:latest"

# Host ports
MYSQL_PORT=3306
PMA_PORT=8081
GITLAB_HTTP_PORT=8929
GITLAB_SSH_PORT=2222

# Flags
DO_ALL=false
DO_PACKAGES=false
DO_CERTS=false
DO_NGINX=false
DO_MYSQL=false
DO_PMA=false
DO_GITLAB=false
DO_ANSIBLE_COLLECTION=false
DO_PIP_MODULES=false
DEBUG=false

# ----------------- Helpers -----------------
log()  { echo -e "\033[1;32m[+] $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }
err()  { echo -e "\033[1;31m[!] $*\033[0m" >&2; }
need_root() { [[ $EUID -eq 0 ]] || { err "Please run as root (sudo)."; exit 1; }; }

trap 'err "Failed at line $LINENO. Last command: \"${BASH_COMMAND}\""' ERR

usage() {
  cat <<EOF
Usage: $0 [actions] [options]

Actions:
  --all                      Run everything in the correct order
  --packages                 Install Docker + Nginx + base packages, then (AFTER Docker) Ansible + pip stack
  --certs                    Generate self-signed TLS for ${DOMAIN} and *.${DOMAIN}
  --nginx                    Configure Nginx reverse proxy for GitLab + phpMyAdmin
  --mysql                    Deploy MySQL 8 container
  --pma                      Deploy phpMyAdmin container
  --gitlab                   Deploy GitLab CE container
  --ansible-collection       Install Ansible collection check_point.mgmt (ensures Docker first)
  --pip-modules              Install Python (pip) modules list (ensures Docker first)
  --debug                    Bash trace mode

Options:
  --domain <name>            Base domain (default: ${DOMAIN})
  --gitlab-host <fqdn>       GitLab host (default: gitlab.\${DOMAIN})
  --pma-host <fqdn>          phpMyAdmin host (default: pma.\${DOMAIN})
  --mysql-root-password <pw> MySQL root password (random if omitted)

Examples:
  sudo $0 --all
  sudo $0 --packages --certs --nginx
  sudo $0 --mysql --pma --gitlab
EOF
  exit 1
}

# ----------------- Arg parsing -----------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all) DO_ALL=true ;;
    --packages) DO_PACKAGES=true ;;
    --certs) DO_CERTS=true ;;
    --nginx) DO_NGINX=true ;;
    --mysql) DO_MYSQL=true ;;
    --pma) DO_PMA=true ;;
    --gitlab) DO_GITLAB=true ;;
    --ansible-collection) DO_ANSIBLE_COLLECTION=true ;;
    --pip-modules) DO_PIP_MODULES=true ;;
    --debug) DEBUG=true ;;
    --domain) DOMAIN="$2"; shift ;;
    --gitlab-host) GITLAB_HOST="$2"; shift ;;
    --pma-host) PMA_HOST="$2"; shift ;;
    --mysql-root-password) MYSQL_ROOT_PASSWORD="$2"; shift ;;
    -h|--help) usage ;;
    *) err "Unknown arg: $1"; usage ;;
  esac
  shift
done

$DEBUG && set -x
need_root

# Apply domain-dependent defaults after possible overrides
GITLAB_HOST="${GITLAB_HOST:-gitlab.${DOMAIN}}"
PMA_HOST="${PMA_HOST:-pma.${DOMAIN}}"
CERT_DIR="/etc/nginx/certs/${DOMAIN}"

# If --all, flip all toggles in the right order
if $DO_ALL; then
  DO_PACKAGES=true
  DO_CERTS=true
  DO_NGINX=true
  DO_MYSQL=true
  DO_PMA=true
  DO_GITLAB=true
  DO_ANSIBLE_COLLECTION=true
  DO_PIP_MODULES=true
fi

# If no actions, show help
if ! $DO_PACKAGES && ! $DO_CERTS && ! $DO_NGINX && ! $DO_MYSQL && ! $DO_PMA && ! $DO_GITLAB && ! $DO_ANSIBLE_COLLECTION && ! $DO_PIP_MODULES; then
  usage
fi

mkdir -p "${STACK_DIR}"

# ----------------- Functions -----------------
ensure_service() {
  local svc="$1"
  systemctl enable --now "$svc" >/dev/null 2>&1 || true
}

install_docker_and_nginx() {
  log "Installing Docker + Nginx + base packages ..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y \
    apt-transport-https ca-certificates curl gnupg lsb-release jq git make openssl \
    docker.io nginx python3 python3-yaml apache2-utils software-properties-common

  ensure_service docker
  ensure_service nginx

  # Create docker network (idempotent)
  if ! docker network ls --format '{{.Name}}' | grep -qx "${NET_NAME}"; then
    log "Creating docker network: ${NET_NAME}"
    docker network create "${NET_NAME}"
  else
    warn "Docker network ${NET_NAME} already exists."
  fi
}

ensure_docker_installed() {
  if ! command -v docker >/dev/null 2>&1; then
    warn "Docker not found. Installing Docker + Nginx first ..."
    install_docker_and_nginx
  else
    ensure_service docker
    docker network inspect "${NET_NAME}" >/dev/null 2>&1 || docker network create "${NET_NAME}"
  fi
}

# >>> This block runs AFTER Docker is installed (per your request)
setup_ansible_and_python_stack() {
  ensure_docker_installed  # keep the order constraint

  log "Adding Ansible PPA and installing Ansible + pip ..."
  add-apt-repository --yes --update ppa:ansible/ansible
  apt-get update -y
  # 'pip' package is not present on modern Ubuntu; use python3-pip
  apt-get install -y software-properties-common ansible python3-pip

  # Create a 'pip' shim if missing, to satisfy scripts that call 'pip'
  if ! command -v pip >/dev/null 2>&1 && command -v pip3 >/dev/null 2>&1; then
    ln -sf "$(command -v pip3)" /usr/local/bin/pip
  fi

  log "Installing Ansible collection check_point.mgmt ..."
  ansible-galaxy collection install check_point.mgmt --force

  local PIP_CMD="$(command -v pip || command -v pip3)"
  log "Installing Python modules via ${PIP_CMD} ..."
  "${PIP_CMD}" install -U setuptools
  "${PIP_CMD}" install \
    psycopg2-binary gitpython pymysql mysql-connector-python requests netmiko pyats \
    httpx beautifulsoup4 lxml python-dateutil pytz pymongo cryptography bcrypt \
    boto3 azure-mgmt-resource azure-storage-blob pexpect paramiko-expect paramiko
}
# <<< End of AFTER-Docker block

generate_certs() {
  log "Generating self-signed wildcard certificate for ${DOMAIN} ..."
  mkdir -p "${CERT_DIR}"
  local KEY="${CERT_DIR}/privkey.pem"
  local CRT="${CERT_DIR}/fullchain.pem"

  if [[ -s "${KEY}" && -s "${CRT}" ]]; then
    warn "Certificates already exist in ${CERT_DIR}, skipping."
    return
  fi

  openssl req -x509 -nodes -newkey rsa:4096 -days 825 \
    -keyout "${KEY}" -out "${CRT}" \
    -subj "/CN=${DOMAIN}" \
    -addext "subjectAltName = DNS:${DOMAIN},DNS:*.${DOMAIN}" \
    -addext "keyUsage = digitalSignature, keyEncipherment" \
    -addext "extendedKeyUsage = serverAuth"

  chmod 600 "${KEY}"
  log "Created: ${CRT} and ${KEY}"
}

configure_hostsfile() {
  if ! grep -qE "\\s${GITLAB_HOST}(\\s|$)" /etc/hosts; then
    log "Adding ${GITLAB_HOST} to /etc/hosts -> 127.0.0.1"
    echo "127.0.0.1 ${GITLAB_HOST}" >> /etc/hosts
  fi
  if ! grep -qE "\\s${PMA_HOST}(\\s|$)" /etc/hosts; then
    log "Adding ${PMA_HOST} to /etc/hosts -> 127.0.0.1"
    echo "127.0.0.1 ${PMA_HOST}" >> /etc/hosts
  fi
}

configure_nginx() {
  log "Configuring Nginx reverse proxy ..."
  configure_hostsfile

  local SSL_CRT="${CERT_DIR}/fullchain.pem"
  local SSL_KEY="${CERT_DIR}/privkey.pem"
  if [[ ! -s "${SSL_CRT}" || ! -s "${SSL_KEY}" ]]; then
    warn "TLS files missing in ${CERT_DIR}. Generating now ..."
    generate_certs
  fi

  cat > /etc/nginx/conf.d/websocket_upgrade.conf <<'CONF'
map $http_upgrade $connection_upgrade {
  default upgrade;
  ''      close;
}
CONF

  mkdir -p /etc/nginx/snippets
  cat > /etc/nginx/snippets/proxy_common.conf <<'PROXY'
proxy_http_version 1.1;
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto https;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection $connection_upgrade;
proxy_read_timeout 300;
client_max_body_size 512m;
PROXY

  cat > "/etc/nginx/sites-available/${GITLAB_HOST}.conf" <<NGINX
server {
    listen 80;
    server_name ${GITLAB_HOST};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name ${GITLAB_HOST};
    ssl_certificate ${SSL_CRT};
    ssl_certificate_key ${SSL_KEY};
    location / {
        proxy_pass http://127.0.0.1:${GITLAB_HTTP_PORT};
        include snippets/proxy_common.conf;
    }
}
NGINX

  cat > "/etc/nginx/sites-available/${PMA_HOST}.conf" <<NGINX
server {
    listen 80;
    server_name ${PMA_HOST};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name ${PMA_HOST};
    ssl_certificate ${SSL_CRT};
    ssl_certificate_key ${SSL_KEY};
    location / {
        proxy_pass http://127.0.0.1:${PMA_PORT};
        include snippets/proxy_common.conf;
    }
}
NGINX

  ln -sf "/etc/nginx/sites-available/${GITLAB_HOST}.conf" "/etc/nginx/sites-enabled/${GITLAB_HOST}.conf"
  ln -sf "/etc/nginx/sites-available/${PMA_HOST}.conf" "/etc/nginx/sites-enabled/${PMA_HOST}.conf"

  nginx -t
  systemctl reload nginx
  log "Nginx configured for https://${GITLAB_HOST} and https://${PMA_HOST}"
}

ensure_mysql_password() {
  if [[ -z "${MYSQL_ROOT_PASSWORD}" ]]; then
    mkdir -p "${STACK_DIR}"
    if [[ -s "${STACK_DIR}/mysql_root_password.txt" ]]; then
      MYSQL_ROOT_PASSWORD="$(cat "${STACK_DIR}/mysql_root_password.txt")"
    else
      MYSQL_ROOT_PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)"
      echo "${MYSQL_ROOT_PASSWORD}" > "${STACK_DIR}/mysql_root_password.txt"
      chmod 600 "${STACK_DIR}/mysql_root_password.txt"
      warn "Generated MySQL root password saved to ${STACK_DIR}/mysql_root_password.txt"
    fi
  fi
}

deploy_mysql() {
  ensure_docker_installed
  ensure_mysql_password
  log "Deploying MySQL 8 ..."
  if docker ps -a --format '{{.Names}}' | grep -qx "${MYSQL_CONT}"; then
    warn "Container ${MYSQL_CONT} already exists; (re)starting and ensuring network ..."
    docker start "${MYSQL_CONT}" >/dev/null 2>&1 || true
    docker network connect "${NET_NAME}" "${MYSQL_CONT}" 2>/dev/null || true
  else
    docker run -d --name "${MYSQL_CONT}" \
      --network "${NET_NAME}" \
      -e MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}" \
      -v mysql8_data:/var/lib/mysql \
      -p ${MYSQL_PORT}:3306 \
      --restart unless-stopped \
      "${MYSQL_IMAGE}" \
      --default-authentication-plugin=mysql_native_password
  fi
  log "MySQL ready on host port ${MYSQL_PORT}."
}

deploy_pma() {
  ensure_docker_installed
  log "Deploying phpMyAdmin ..."
  if docker ps -a --format '{{.Names}}' | grep -qx "${PMA_CONT}"; then
    warn "Container ${PMA_CONT} already exists; (re)starting and ensuring network ..."
    docker start "${PMA_CONT}" >/dev/null 2>&1 || true
    docker network connect "${NET_NAME}" "${PMA_CONT}" 2>/dev/null || true
  else
    docker run -d --name "${PMA_CONT}" \
      --network "${NET_NAME}" \
      -e PMA_HOST="${MYSQL_CONT}" \
      -e PMA_ABSOLUTE_URI="https://${PMA_HOST}/" \
      -p ${PMA_PORT}:80 \
      --restart unless-stopped \
      "${PMA_IMAGE}"
  fi
  log "phpMyAdmin proxied at https://${PMA_HOST}"
}

deploy_gitlab() {
  ensure_docker_installed
  log "Deploying GitLab CE (first boot can take a while) ..."
  if docker ps -a --format '{{.Names}}' | grep -qx "${GITLAB_CONT}"; then
    warn "Container ${GITLAB_CONT} already exists; (re)starting and ensuring network ..."
    docker start "${GITLAB_CONT}" >/dev/null 2>&1 || true
    docker network connect "${NET_NAME}" "${GITLAB_CONT}" 2>/dev/null || true
  else
    docker run -d --name "${GITLAB_CONT}" \
      --hostname "${GITLAB_HOST}" \
      --network "${NET_NAME}" \
      -p ${GITLAB_HTTP_PORT}:80 \
      -p ${GITLAB_SSH_PORT}:22 \
      -v gitlab_config:/etc/gitlab \
      -v gitlab_logs:/var/log/gitlab \
      -v gitlab_data:/var/opt/gitlab \
      -e GITLAB_OMNIBUS_CONFIG="external_url 'https://${GITLAB_HOST}';
nginx['listen_port']=80;
nginx['listen_https']=false;" \
      --restart unless-stopped \
      "${GITLAB_IMAGE}"
  fi
  log "GitLab proxied at https://${GITLAB_HOST} (container HTTP on 127.0.0.1:${GITLAB_HTTP_PORT}, SSH on ${GITLAB_SSH_PORT})."
}

# ----------------- Execution (ordered) -----------------
if $DO_PACKAGES; then
  # First: Docker + Nginx
  install_docker_and_nginx
  # Then: AFTER Docker, the Ansible + pip stack you specified
  setup_ansible_and_python_stack
fi

if $DO_CERTS;    then generate_certs; fi
if $DO_NGINX;    then configure_nginx; fi
if $DO_MYSQL;    then deploy_mysql; fi
if $DO_PMA;      then deploy_pma; fi
if $DO_GITLAB;   then deploy_gitlab; fi

# If user asked only for the Ansible/PIP tasks, still keep your order (after Docker)
if $DO_ANSIBLE_COLLECTION || $DO_PIP_MODULES; then
  setup_ansible_and_python_stack
fi

log "Done."
