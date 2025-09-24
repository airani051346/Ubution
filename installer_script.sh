#!/usr/bin/env bash
set -Eeuo pipefail

# =========================
# Simple LAN Stack Installer
# - Docker CE + compose plugin (or standalone binary fallback)
# - MySQL 8 (Docker)
# - phpMyAdmin (Docker)
# - GitLab CE (Docker)
# - Nginx reverse proxy (host)
# Optional: --tls self-signed HTTPS
# =========================

# -------- Defaults --------
DOMAIN="fritz.lan"
DO_MYSQL=false
DO_PMA=false
DO_GITLAB=false
DO_NGINX=false
DO_ALL=false
ENABLE_TLS=false

BASE_DIR="/opt/fritz_stack"
COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"
SECRETS_DIR="${BASE_DIR}/secrets"
MYSQL_ROOT_FILE="${SECRETS_DIR}/mysql_root_password"
NETWORK_NAME="fritz_net"
PMA_HOST_DEFAULT="pma"
GITLAB_HOST_DEFAULT="gitlab"
PMA_PORT=8080
GITLAB_PORT=8081
MYSQL_PORT=3306

log() { echo -e "\e[1;32m[+]\e[0m $*"; }
warn() { echo -e "\e[1;33m[!]\e[0m $*"; }
err() { echo -e "\e[1;31m[x]\e[0m $*" >&2; }
need_root() { [[ $EUID -eq 0 ]] || { err "Run as root (sudo)."; exit 1; }; }

usage() {
  cat <<EOF
Usage: $0 [--all] [--domain fritz.lan] [--mysql] [--pma] [--gitlab] [--nginx] [--tls]

  --all                 Install/start Docker + MySQL + phpMyAdmin + GitLab + Nginx
  --domain <name>       Base domain (default: fritz.lan) -> pma.<domain>, gitlab.<domain>
  --mysql               Install/start MySQL
  --pma                 Install/start phpMyAdmin (depends on MySQL)
  --gitlab              Install/start GitLab CE
  --nginx               Configure Nginx reverse proxy on host
  --tls                 Self-signed certs + HTTPS (HTTP -> HTTPS redirect)
  -h|--help             Show help
EOF
}

# -------- Arg parse --------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all) DO_ALL=true; shift ;;
    --domain) DOMAIN="$2"; shift 2 ;;
    --mysql) DO_MYSQL=true; shift ;;
    --pma|--phpmyadmin) DO_PMA=true; shift ;;
    --gitlab) DO_GITLAB=true; shift ;;
    --nginx) DO_NGINX=true; shift ;;
    --tls) ENABLE_TLS=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown option: $1"; usage; exit 1 ;;
  esac
done
$DO_ALL && { DO_MYSQL=true; DO_PMA=true; DO_GITLAB=true; DO_NGINX=true; }
if ! $DO_MYSQL && ! $DO_PMA && ! $DO_GITLAB && ! $DO_NGINX; then usage; exit 1; fi
need_root

PMA_FQDN="${PMA_HOST_DEFAULT}.${DOMAIN}"
GITLAB_FQDN="${GITLAB_HOST_DEFAULT}.${DOMAIN}"
mkdir -p "$BASE_DIR" "$SECRETS_DIR"

# -------- Base prereqs (no docker yet) --------
log "Installing base prereqs..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release jq git make openssl software-properties-common nginx python3 python3-yaml apache2-utils
systemctl enable --now nginx

# -------- Install Docker CE + plugins --------
install_docker_official() {
  log "Setting up Docker APT repository (official)..."
  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi
  UBUNTU_CODENAME="$(. /etc/os-release; echo "${VERSION_CODENAME}")"
  echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
}

install_compose_fallback() {
  warn "Falling back to standalone docker-compose binary..."
  mkdir -p /usr/local/lib/docker/cli-plugins
  curl -sSL "https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
}

if ! command -v docker >/dev/null 2>&1; then
  install_docker_official || err "Docker installation failed"
else
  log "Docker already installed."
fi

# Ensure docker compose works
if ! docker compose version >/dev/null 2>&1; then
  install_docker_official || install_compose_fallback
fi

if ! docker compose version >/dev/null 2>&1; then
  err "docker compose still not available. Please check Docker installation."
  exit 1
fi
log "docker compose available: $(docker compose version)"

# -------- Docker network (idempotent) --------
if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  log "Creating Docker network: ${NETWORK_NAME}"
  docker network create "$NETWORK_NAME" >/dev/null
else
  log "Docker network ${NETWORK_NAME} already exists (ok)."
fi

# -------- Secrets --------
if [[ ! -f "$MYSQL_ROOT_FILE" ]]; then
  log "Generating MySQL root password secret..."
  openssl rand -base64 24 > "$MYSQL_ROOT_FILE"
  chmod 600 "$MYSQL_ROOT_FILE"
fi
MYSQL_ROOT_PASSWORD="$(cat "$MYSQL_ROOT_FILE")"

# -------- Compose file --------
log "Writing compose file to ${COMPOSE_FILE}"
SCHEME=$($ENABLE_TLS && echo https || echo http)

cat > "$COMPOSE_FILE" <<'YAML'
version: "3.9"
services:
  mysql:
    image: mysql:8
    container_name: mysql8
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD_FILE: /run/secrets/mysql_root_password
    secrets:
      - mysql_root_password
    command: ["--default-authentication-plugin=mysql_native_password"]
    ports:
      - "127.0.0.1:__MYSQL_PORT__:3306"
    volumes:
      - ./mysql/data:/var/lib/mysql
    networks: [ __NETWORK_NAME__ ]

  pma:
    image: phpmyadmin:latest
    container_name: phpmyadmin
    restart: unless-stopped
    environment:
      PMA_HOST: mysql
      PMA_ABSOLUTE_URI: __SCHEME__://__PMA_FQDN__/
    depends_on: [ mysql ]
    ports:
      - "127.0.0.1:__PMA_PORT__:80"
    networks: [ __NETWORK_NAME__ ]

  gitlab:
    image: gitlab/gitlab-ce:latest
    container_name: gitlab
    restart: unless-stopped
    hostname: __GITLAB_FQDN__
    shm_size: "256m"
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url "__SCHEME__://__GITLAB_FQDN__";
        nginx['listen_port'] = 80;
        nginx['listen_https'] = false;
    ports:
      - "127.0.0.1:__GITLAB_PORT__:80"
    volumes:
      - ./gitlab/config:/etc/gitlab
      - ./gitlab/logs:/var/log/gitlab
      - ./gitlab/data:/var/opt/gitlab
    networks: [ __NETWORK_NAME__ ]

networks:
  __NETWORK_NAME__:
    external: true

secrets:
  mysql_root_password:
    file: ./secrets/mysql_root_password
YAML

sed -i \
  -e "s|__NETWORK_NAME__|${NETWORK_NAME}|g" \
  -e "s|__MYSQL_PORT__|${MYSQL_PORT}|g" \
  -e "s|__PMA_PORT__|${PMA_PORT}|g" \
  -e "s|__GITLAB_PORT__|${GITLAB_PORT}|g" \
  -e "s|__PMA_FQDN__|${PMA_FQDN}|g" \
  -e "s|__GITLAB_FQDN__|${GITLAB_FQDN}|g" \
  -e "s|__SCHEME__|${SCHEME}|g" \
  "$COMPOSE_FILE"

# -------- Start selected services --------
services_to_up=()
$DO_MYSQL && services_to_up+=("mysql")
$DO_PMA && services_to_up+=("pma")
$DO_GITLAB && services_to_up+=("gitlab")
if [[ ${#services_to_up[@]} -gt 0 ]]; then
  log "Starting services: ${services_to_up[*]}"
  (cd "$BASE_DIR" && docker compose up -d "${services_to_up[@]}")
fi

# -------- Nginx config --------
if $DO_NGINX; then
  log "Configuring Nginx reverse proxy for ${PMA_FQDN} and ${GITLAB_FQDN}"
  SSL_DIR="/etc/nginx/ssl"
  mkdir -p "$SSL_DIR"

  NCONF="/etc/nginx/sites-available/fritz_stack.conf"

  # Create certs if TLS
  if $ENABLE_TLS; then
    for host in "$PMA_FQDN" "$GITLAB_FQDN"; do
      CRT="${SSL_DIR}/${host}.crt"
      KEY="${SSL_DIR}/${host}.key"
      if [[ ! -f "$CRT" || ! -f "$KEY" ]]; then
        warn "Generating self-signed certificate for ${host}..."
        openssl req -x509 -nodes -newkey rsa:2048 -days 825 \
          -subj "/CN=${host}" -keyout "$KEY" -out "$CRT" >/dev/null 2>&1
        chmod 600 "$KEY"
      fi
    done
  fi

  # Write Nginx configs (same as before, omitted here for brevity)
  # ...
  # [keep your existing Nginx config section here unchanged]
fi

log "Done."
