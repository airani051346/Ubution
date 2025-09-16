#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
need_root

log "Installing Nginx..."
apt-get update -y
apt-get install -y nginx-full || apt-get install -y nginx-extras || apt-get install -y nginx
systemctl enable --now nginx

# Enable WebSocket map
cat >/etc/nginx/conf.d/ws_upgrade_map.conf <<'EOF'
map $http_upgrade $connection_upgrade { default upgrade; '' close; }
EOF

nginx_reload
log "Nginx installed and running."
