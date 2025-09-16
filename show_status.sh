#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

echo "===== HOMELAB STATUS ====="
echo "Server IP: ${SERVER_IP}"
echo "Domain:    ${DOMAIN}"
echo

systemctl is-active --quiet nginx && echo "Nginx ✅" || echo "Nginx ❌"
systemctl is-active --quiet mysql && echo "MySQL ✅" || echo "MySQL ❌"
[[ -d /opt/phpMyAdmin ]] && echo "phpMyAdmin ✅ → https://pma.${DOMAIN}" || echo "phpMyAdmin ❌"
dpkg -s gitlab-ce >/dev/null 2>&1 && echo "GitLab ✅ → https://gitlab.${DOMAIN}" || echo "GitLab ❌"
systemctl is-active --quiet k3s && echo "AWX ✅ → https://awx.${DOMAIN}" || echo "AWX ❌"
