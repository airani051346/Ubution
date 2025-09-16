#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

usage(){
  cat <<EOF
Usage: $0 [options]

Options:
  --nginx          Install Nginx
  --mysql [pass]   Install MySQL (root/admin password via arg or default)
  --phpmyadmin     Install phpMyAdmin (proxied by Nginx)
  --gitlab         Install GitLab CE (proxied by Nginx)
  --awx            Install AWX (via k3s + operator, proxied by Nginx)
  --status         Show overall homelab status
  --all            Install everything (nginx → mysql → phpmyadmin → gitlab → awx)

Examples:
  $0 --mysql MySecret123!
  $0 --nginx --phpmyadmin
  $0 --all
EOF
}

need_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "[x] Run as root (sudo)."; exit 1; }; }
need_root

if [[ $# -eq 0 ]]; then usage; exit 0; fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --nginx)        sudo "${DIR}/install_nginx.sh" ;;
    --mysql)        shift; sudo "${DIR}/install_mysql.sh" "${1:-rootpass123!}" ;;
    --phpmyadmin)   sudo "${DIR}/install_phpmyadmin.sh" ;;
    --gitlab)       sudo "${DIR}/install_gitlab.sh" ;;
    --awx)          sudo "${DIR}/install_awx.sh" ;;
    --status)       sudo "${DIR}/status.sh" ;;
    --all)
      sudo "${DIR}/install_nginx.sh"
      sudo "${DIR}/install_mysql.sh" "rootpass123!"
      sudo "${DIR}/install_phpmyadmin.sh"
      sudo "${DIR}/install_gitlab.sh"
      sudo "${DIR}/install_awx.sh"
      sudo "${DIR}/show_status.sh"
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[x] Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done
