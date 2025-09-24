#!/usr/bin/env bash
set -Eeuo pipefail

# =========================
# Simple LAN Stack Installer
# - Docker + compose plugin
# - MySQL 8 (Docker)
# - phpMyAdmin (Docker)
# - GitLab CE (Docker)
# - Nginx reverse proxy (host)
# HTTP by default; add --tls for self-signed HTTPS
# =========================

# -------- Defaults --------
DOMAIN="fritz.lan"
DO_MYSQL=false
DO_PMA=false
DO_GITLAB=false
DO_NGINX=false
DO_ALL=false
ENABLE_TLS=false

# Paths & names
BASE_DIR="/opt/fritz_stack"
COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"
SECRETS_DIR="${BASE_DIR}/secrets"
MYSQL_ROOT_FILE="${SECRETS_DIR}/mysql_root_password"
NETWORK_NAME="fritz_net"                  # stable name
PMA_HOST_DEFAULT="pma"
GITLAB_HOST_DEFAULT="gitlab"
PMA_PORT=8080       # host loopback -> pma container 80
GITLAB_PORT=8081    # host loopback -> gitlab container 80
MYSQL_PORT=3306     # host loopback -> mysql container 3306

# -------- Helpers --------
log() { echo -e "\e[1;32m[+]\e[0m $*"; }
warn() { echo -e "\e[1;33m[!]\e[0m $*"; }
err() { echo -e "\e[1;31m[x]\e[0m $*" >&2; }
need_root() { [[ $EUID -eq 0 ]] || { err "Run as root (sudo)."; exit 1; }; }

usage() {
  cat <<EOF
Usage: $0 [--all] [--domain fritz.lan] [--mysql] [--pma] [--gitlab] [--nginx] [--tls] [--help]

Options:
  --all                 Install/start Docker + MySQL + phpMyAdmin + GitLab + Nginx
  --domain <name>       Base domain (default: fritz.lan). Services become:
                        pma.<domain>, gitlab.<domain>
  --mysql               Install/start only MySQL (and Docker if needed)
  --pma                 Install/start only phpMyAdmin (depends on MySQL)
  --gitlab              Install/start only GitLab CE
  --nginx               Configure Nginx reverse proxy on host
  --tls                 Generate self-signed certs and serve HTTPS (redirect from HTTP)
  --help                Show this help

Examples:
  $0 --all --domain fritz.lan
  $0 --mysql --pma --nginx --domain mylab.lan
  $0 --gitlab --nginx --tls
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

if $DO_ALL; then
  DO_MYSQL=true
  DO_PMA=true
  DO_GITLAB=true
  DO_NGINX=true
fi

if ! $DO_MYSQL && ! $DO_PMA && ! $DO_GITLAB && ! $DO_NGINX; then
  usage; exit 1
fi

need_root

PMA_FQDN="${PMA_HOST_DEFAULT}.${DOMAIN}"
GITLAB_FQDN="${GITLAB_HOST_DEFAULT}.${DOMAIN}"
mkdir -p "$BASE_DIR" "$SECRETS_DIR"

# -------- Install base packages --------
log "Installing base packages (Docker, compose plugin, Nginx, tools)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
  apt-transport-https ca-certificates curl gnupg lsb-release jq git make openssl \
  docker.io docker-compose-plugin nginx

systemctl enable --now docker
systemctl enable --now nginx

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

# -------- Write docker-compose.yml --------
log "Writing compose file to ${COMPOSE_FILE}"
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
      PMA_ABSOLUTE_URI: __PMA_SCHEME__://__PMA_FQDN__/
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
        external_url "__GITLAB_SCHEME__://__GITLAB_FQDN__";
        nginx['listen_port'] = 80;
        nginx['listen_https'] = false;
        # Uncomment to enable SSH cloning via host port mapping later:
        # gitlab_rails['gitlab_shell_ssh_port'] = 2222;
    ports:
      - "127.0.0.1:__GITLAB_PORT__:80"
      # SSH (optional): - "0.0.0.0:2222:22"
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

# Replace placeholders
SCHEME_HTTP="http"
[[ "$ENABLE_TLS" == true ]] && SCHEME_HTTP="https"

sed -i \
  -e "s|__NETWORK_NAME__|${NETWORK_NAME}|g" \
  -e "s|__MYSQL_PORT__|${MYSQL_PORT}|g" \
  -e "s|__PMA_PORT__|${PMA_PORT}|g" \
  -e "s|__GITLAB_PORT__|${GITLAB_PORT}|g" \
  -e "s|__PMA_FQDN__|${PMA_FQDN}|g" \
  -e "s|__GITLAB_FQDN__|${GITLAB_FQDN}|g" \
  -e "s|__PMA_SCHEME__|${SCHEME_HTTP}|g" \
  -e "s|__GITLAB_SCHEME__|${SCHEME_HTTP}|g" \
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

  # Certificates (if --tls)
  if $ENABLE_TLS; then
    for host in "$PMA_FQDN" "$GITLAB_FQDN"; do
      CRT="${SSL_DIR}/${host}.crt"
      KEY="${SSL_DIR}/${host}.key"
      if [[ ! -f "$CRT" || ! -f "$KEY" ]]; then
        warn "Generating self-signed certificate for ${host}..."
        openssl req -x509 -nodes -newkey rsa:2048 -days 825 \
          -subj "/CN=${host}" \
          -keyout "$KEY" -out "$CRT" >/dev/null 2>&1
        chmod 600 "$KEY"
      else
        log "Found existing cert for ${host} (ok)."
      fi
    done
  fi

  NCONF="/etc/nginx/sites-available/fritz_stack.conf"
  cat > "$NCONF" <<NGINX
# Auto-generated by stack installer
# Access:
#   ${SCHEME_HTTP}://${PMA_FQDN}
#   ${SCHEME_HTTP}://${GITLAB_FQDN}

# ------- phpMyAdmin -------
server {
    listen 80;
    server_name ${PMA_FQDN};
$( $ENABLE_TLS && echo "    return 301 https://\$host\$request_uri;" )
$( !$ENABLE_TLS && echo "    location / { proxy_pass http://127.0.0.1:${PMA_PORT}; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto \$scheme; }" )
}
$( $ENABLE_TLS && cat <<'HTTPSPMA'
server {
    listen 443 ssl http2;
    server_name __PMA_FQDN__;

    ssl_certificate     /etc/nginx/ssl/__PMA_FQDN__.crt;
    ssl_certificate_key /etc/nginx/ssl/__PMA_FQDN__.key;

    client_max_body_size 64m;

    location / {
        proxy_pass http://127.0.0.1:__PMA_PORT__;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
HTTPSPMA
)

# ------- GitLab -------
server {
    listen 80;
    server_name ${GITLAB_FQDN};
$( $ENABLE_TLS && echo "    return 301 https://\$host\$request_uri;" )
$( !$ENABLE_TLS && echo "    location / { proxy_read_timeout 300; proxy_connect_timeout 300; proxy_pass http://127.0.0.1:${GITLAB_PORT}; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto \$scheme; }" )
}
$( $ENABLE_TLS && cat <<'HTTPSGL'
server {
    listen 443 ssl http2;
    server_name __GITLAB_FQDN__;

    ssl_certificate     /etc/nginx/ssl/__GITLAB_FQDN__.crt;
    ssl_certificate_key /etc/nginx/ssl/__GITLAB_FQDN__.key;

    client_max_body_size 512m;

    location / {
        proxy_read_timeout 300;
        proxy_connect_timeout 300;
        proxy_pass http://127.0.0.1:__GITLAB_PORT__;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
HTTPSGL
)
NGINX

  # Fill TLS placeholders if enabled
  if $ENABLE_TLS; then
    sed -i \
      -e "s|__PMA_FQDN__|${PMA_FQDN}|g" \
      -e "s|__GITLAB_FQDN__|${GITLAB_FQDN}|g" \
      -e "s|__PMA_PORT__|${PMA_PORT}|g" \
      -e "s|__GITLAB_PORT__|${GITLAB_PORT}|g" \
      "$NCONF"
  fi

  ln -sf "$NCONF" /etc/nginx/sites-enabled/fritz_stack.conf
  if [[ -f /etc/nginx/sites-enabled/default ]]; then
    rm -f /etc/nginx/sites-enabled/default
  fi

  log "Testing Nginx config..."
  nginx -t
  systemctl reload nginx
fi

log "Done."

# -------- Output summary --------
echo
echo "=============================================="
echo " Domain:         ${DOMAIN}"
echo " phpMyAdmin:     ${SCHEME_HTTP}://${PMA_FQDN}"
echo " GitLab:         ${SCHEME_HTTP}://${GITLAB_FQDN}"
echo " MySQL root pw:  $( [[ -t 1 ]] && echo "(stored in ${MYSQL_ROOT_FILE})" )"
echo " Compose file:   ${COMPOSE_FILE}"
echo " Docker network: ${NETWORK_NAME}"
$ENABLE_TLS && echo " TLS:            self-signed certs installed under /etc/nginx/ssl"
echo "=============================================="
echo
warn "Make sure DNS resolves ${PMA_FQDN} and ${GITLAB_FQDN} to this server.
For quick local testing on this host, add to /etc/hosts:
  127.0.0.1  ${PMA_FQDN} ${GITLAB_FQDN}"
