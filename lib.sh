#!/usr/bin/env bash
set -euo pipefail

# ========== Globals ==========
DOMAIN="${DOMAIN:-fritz.box}"
SERVER_IP="$(hostname -I | awk '{print $1}')"
SERVER_IP="${SERVER_IP:-127.0.0.1}"

CERT_DIR=/etc/ssl/certs
KEY_DIR=/etc/ssl/private
NGINX_SITES=/etc/nginx/sites-available
NGINX_ENABLED=/etc/nginx/sites-enabled

# ========== Functions ==========
log(){ echo -e "\033[1;32m[+] $*\033[0m"; }
warn(){ echo -e "\033[1;33m[!] $*\033[0m"; }
die(){ echo -e "\033[1;31m[x] $*\033[0m"; exit 1; }
need_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run as root (sudo)."; }

ensure_pkg(){ dpkg -s "$1" >/dev/null 2>&1 || apt-get install -y "$1"; }

gen_cert(){
  local host="$1" crt="$2" key="$3"
  if [[ -f "$crt" && -f "$key" ]]; then
    log "Certificate already exists for $host"
    return
  fi
  log "Generating self-signed certificate for $host"
  install -d -m 0755 "$CERT_DIR" "$KEY_DIR"
  openssl req -x509 -nodes -newkey rsa:4096 -sha256 -days 825 \
    -keyout "$key" -out "$crt" \
    -subj "/CN=${host}" \
    -addext "subjectAltName=DNS:${host},IP:${SERVER_IP}"
  chmod 600 "$key"
}

nginx_reload(){ nginx -t && (systemctl reload nginx || systemctl restart nginx); }
