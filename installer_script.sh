#!/usr/bin/env bash
set -Eeuo pipefail

# -------- Defaults --------
DOMAIN="fritz.lan"
DO_MYSQL=false
DO_PMA=false
DO_GITLAB=false
DO_NGINX=false
DO_ALL=false
ENABLE_TLS=false

DEFAULT_MYSQL_ROOT_PASSWORD="ChangeMeStrong123"
MYSQL_ROOT_PASSWORD_ARG=""
FORCE_REINIT_MYSQL=false

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
    --mysql-root-password) MYSQL_ROOT_PASSWORD_ARG="$2"; shift 2 ;;
    --force-reinit-mysql) FORCE_REINIT_MYSQL=true; shift ;;
    --pma|--phpmyadmin) DO_PMA=true; shift ;;
    --gitlab) DO_GITLAB=true; shift ;;
    --nginx) DO_NGINX=true; shift ;;
    --tls) ENABLE_TLS=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown option: $1"; usage; exit 1 ;;
  esac
done
$DO_ALL && { DO_MYSQL=true; DO_PMA=true; DO_GITLAB=true; DO_NGINX=true; ENABLE_TLS=true; }
if ! $DO_MYSQL && ! $DO_PMA && ! $DO_GITLAB && ! $DO_NGINX; then usage; exit 1; fi
need_root

PMA_FQDN="${PMA_HOST_DEFAULT}.${DOMAIN}"
GITLAB_FQDN="${GITLAB_HOST_DEFAULT}.${DOMAIN}"
mkdir -p "$BASE_DIR" "$SECRETS_DIR"

# -------- Base prereqs --------
log "Installing base prereqs..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release jq git make openssl software-properties-common nginx python3 python3-yaml apache2-utils
systemctl enable --now nginx

# -------- Install Docker CE + compose plugin --------
log "Ensuring official Docker CE is installed..."
# Remove Ubuntu's docker.io if present
if dpkg -l | grep -q docker.io; then
  warn "Removing conflicting docker.io package..."
  apt-get remove -y docker.io
fi

# Setup Docker repo if not yet added
if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  UBUNTU_CODENAME="$(. /etc/os-release; echo "${VERSION_CODENAME}")"
  echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
fi

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

# Sanity check
docker compose version >/dev/null 2>&1 || { err "docker compose not available"; exit 1; }
log "docker compose available: $(docker compose version)"

# -------- Docker network (idempotent) --------
if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  log "Creating Docker network: ${NETWORK_NAME}"
  docker network create "$NETWORK_NAME" >/dev/null
else
  log "Docker network ${NETWORK_NAME} already exists (ok)."
fi

# -------- Secrets --------
mkdir -p "$(dirname "$MYSQL_ROOT_FILE")"

if [[ -n "$MYSQL_ROOT_PASSWORD_ARG" ]]; then
  # Overwrite secret file even if it exists
  printf '%s' "$MYSQL_ROOT_PASSWORD_ARG" > "$MYSQL_ROOT_FILE"
  chmod 600 "$MYSQL_ROOT_FILE"
  log "MySQL root password set from --mysql-root-password (secret overwritten)."
else
  if [[ ! -f "$MYSQL_ROOT_FILE" ]]; then
    # Write default only if no secret exists yet
    printf '%s' "$DEFAULT_MYSQL_ROOT_PASSWORD" > "$MYSQL_ROOT_FILE"
    chmod 600 "$MYSQL_ROOT_FILE"
    log "MySQL root password set to default (${DEFAULT_MYSQL_ROOT_PASSWORD})."
  else
    log "Using existing MySQL root password secret."
  fi
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
# -------- Nginx config --------
if $DO_NGINX; then
  log "Configuring Nginx reverse proxy for ${PMA_FQDN} and ${GITLAB_FQDN}"
  SSL_DIR="/etc/nginx/ssl"
  mkdir -p "$SSL_DIR"

  NCONF="/etc/nginx/sites-available/fritz_stack.conf"

  # Create self-signed certs if TLS enabled
  if $ENABLE_TLS; then
    for host in "$PMA_FQDN" "$GITLAB_FQDN"; do
      CRT="${SSL_DIR}/${host}.crt"
      KEY="${SSL_DIR}/${host}.key"
      if [[ ! -f "$CRT" || ! -f "$KEY" ]]; then
        warn "Generating self-signed certificate for ${host}..."
        openssl req -x509 -nodes -newkey rsa:2048 -days 825 -subj "/CN=${host}" -keyout "$KEY" -out "$CRT" >/dev/null 2>&1
        chmod 600 "$KEY"
      fi
    done
  fi

  SCHEME=$($ENABLE_TLS && echo https || echo http)

  # Always write HTTP blocks (if TLS, they just redirect)
  cat > "$NCONF" <<NGINX
# Auto-generated by stack installer
# Access:
#   ${SCHEME}://${PMA_FQDN}
#   ${SCHEME}://${GITLAB_FQDN}

server {
    listen 80;
    server_name ${PMA_FQDN};
$( $ENABLE_TLS && echo "    return 301 https://\$host\$request_uri;" || echo "    location / { proxy_pass http://127.0.0.1:${PMA_PORT}; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto \$scheme; }" )
}

server {
    listen 80;
    server_name ${GITLAB_FQDN};
$( $ENABLE_TLS && echo "    return 301 https://\$host\$request_uri;" || echo "    location / { proxy_read_timeout 300; proxy_connect_timeout 300; proxy_pass http://127.0.0.1:${GITLAB_PORT}; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto \$scheme; }" )
}
NGINX

  # If TLS enabled, add HTTPS blocks
  if $ENABLE_TLS; then
    cat >> "$NCONF" <<NGINX
server {
    listen 443 ssl http2;
    server_name ${PMA_FQDN};
    ssl_certificate     /etc/nginx/ssl/${PMA_FQDN}.crt;
    ssl_certificate_key /etc/nginx/ssl/${PMA_FQDN}.key;
    client_max_body_size 64m;
    location / {
        proxy_pass http://127.0.0.1:${PMA_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

server {
    listen 443 ssl http2;
    server_name ${GITLAB_FQDN};
    ssl_certificate     /etc/nginx/ssl/${GITLAB_FQDN}.crt;
    ssl_certificate_key /etc/nginx/ssl/${GITLAB_FQDN}.key;
    client_max_body_size 512m;
    location / {
        proxy_read_timeout 300;
        proxy_connect_timeout 300;
        proxy_pass http://127.0.0.1:${GITLAB_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX
  fi

  # Enable site + disable default
  ln -sf "$NCONF" /etc/nginx/sites-enabled/fritz_stack.conf
  [[ -f /etc/nginx/sites-enabled/default ]] && rm -f /etc/nginx/sites-enabled/default

  log "Testing Nginx config..."
  nginx -t
  systemctl reload nginx
fi


log "Done."
echo
echo "=============================================="
echo " Domain:         ${DOMAIN}"
echo " phpMyAdmin:     ${SCHEME}://${PMA_FQDN}"
echo " GitLab:         ${SCHEME}://${GITLAB_FQDN}"
echo " MySQL root pw:  (stored in ${MYSQL_ROOT_FILE})"
echo " Compose file:   ${COMPOSE_FILE}"
echo " Docker network: ${NETWORK_NAME}"
$ENABLE_TLS && echo " TLS:            self-signed certs installed under /etc/nginx/ssl"
echo "=============================================="
