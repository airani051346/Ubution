#!/usr/bin/env bash
set -Eeuo pipefail

# Simple Docker + k3s menu with robust pickers
K3S_KUBECONFIG=${K3S_KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
AWX_NAMESPACE=${AWX_NAMESPACE:-awx}
AWX_NAME=${AWX_NAME:-awx}
COMPOSE_DIR=${COMPOSE_DIR:-/opt/stack/compose}
GITLAB_HTTP_PORT=${GITLAB_HTTP_PORT:-8929}
PMA_BIND_PORT=${PMA_BIND_PORT:-9001}
AWX_NODEPORT=${AWX_NODEPORT:-30090}
export KUBECONFIG="$K3S_KUBECONFIG"

say()   { echo -e "[+] $*"; }
warn()  { echo -e "[!] $*" >&2; }
press() { read -rp $'\nPress ENTER to continue...'; }

# ask "Prompt: " varname
ask() {
  local __prompt="$1"; local -n __out="$2"
  read -rp "$__prompt" __out
}

# ---- Robust pickers (numbered) ----
pick_running_container() {
  mapfile -t rows < <(docker ps --format '{{.Names}}|{{.Image}}|{{.Status}}|{{.Ports}}')
  if ((${#rows[@]}==0)); then warn "No running containers"; return 1; fi
  echo "N  NAME                      IMAGE                 STATUS                   PORTS"
  echo "--------------------------------------------------------------------------------------"
  local i=1
  for r in "${rows[@]}"; do
    IFS='|' read -r nm img st pr <<<"$r"
    printf "%-2s %-25s %-20s %-23s %s\n" "$i" "$nm" "${img:0:20}" "${st:0:23}" "${pr:0:60}"
    ((i++))
  done
  local pick=""
  ask $'\nChoose number: ' pick
  [[ "$pick" =~ ^[0-9]+$ ]] || { warn "Not a number"; return 1; }
  (( pick>=1 && pick<=${#rows[@]} )) || { warn "Out of range"; return 1; }
  IFS='|' read -r nm _ _ _ <<<"${rows[pick-1]}"
  printf '%s\n' "$nm"
}

pick_pod() {
  local ns="${1:-$AWX_NAMESPACE}"
  mapfile -t pods < <(kubectl -n "$ns" get pods -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.status.phase}{"|"}{.status.podIP}{"\n"}{end}')
  if ((${#pods[@]}==0)); then warn "No pods in $ns"; return 1; fi
  echo "N  POD NAME                                   PHASE     POD IP"
  echo "-------------------------------------------------------------------"
  local i=1
  for p in "${pods[@]}"; do
    IFS='|' read -r name phase ip <<<"$p"
    printf "%-2s %-40s %-9s %s\n" "$i" "$name" "$phase" "$ip"
    ((i++))
  done
  local pick=""
  ask $'\nChoose number: ' pick
  [[ "$pick" =~ ^[0-9]+$ ]] || { warn "Not a number"; return 1; }
  (( pick>=1 && pick<=${#pods[@]} )) || { warn "Out of range"; return 1; }
  IFS='|' read -r name _ _ <<<"${pods[pick-1]}"
  printf '%s\n' "$name"
}

# ---- Actions (resolve to IDs before acting) ----
docker_logs_follow() {
  local name; name=$(pick_running_container) || return 1
  local cid; cid=$(docker ps -q --filter "name=^${name}$")
  [[ -n "${cid:-}" ]] || { warn "Container not found: $name"; return 1; }
  # Use ID to avoid any name oddities; show last 200 lines then follow
  docker logs --tail 200 -f "$cid"
}

docker_exec_bash() {
  local name; name=$(pick_running_container) || return 1
  local cid; cid=$(docker ps -q --filter "name=^${name}$")
  [[ -n "${cid:-}" ]] || { warn "Container not found: $name"; return 1; }
  docker exec -it "$cid" /bin/bash || docker exec -it "$cid" /bin/sh
}

docker_restart() {
  local name; name=$(pick_running_container) || return 1
  local cid; cid=$(docker ps -q --filter "name=^${name}$")
  [[ -n "${cid:-}" ]] || { warn "Container not found: $name"; return 1; }
  docker restart "$cid"
}

awx_web_pod() {
  kubectl -n "$AWX_NAMESPACE" get pods \
    -l "app.kubernetes.io/instance=${AWX_NAME},app.kubernetes.io/component=web" \
    -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null | awk '{print $1}'
}

decode_secret_value() {
  local ns="$1" name="$2" key="$3"
  kubectl -n "$ns" get secret "$name" -o jsonpath="{.data.$key}" 2>/dev/null | base64 -d || true
}

docker_menu() {
  PS3=$'\nDocker > Choose an action: '
  select opt in \
    "List containers" \
    "Logs (follow) – pick by number" \
    "Exec shell (/bin/bash) – pick by number" \
    "Restart container – pick by number" \
    "docker compose up -d" \
    "docker compose down" \
    "System df (space usage)" \
    "Back"; do
    case "$REPLY" in
      1) clear; docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'; press ;;
      2) clear; docker_logs_follow ;;
      3) clear; docker_exec_bash; press ;;
      4) clear; docker_restart; press ;;
      5) clear; (cd "$COMPOSE_DIR" && docker compose up -d); press ;;
      6) clear; (cd "$COMPOSE_DIR" && docker compose down); press ;;
      7) clear; docker system df; press ;;
      8) break ;;
      *) warn "Invalid";;
    esac
  done
}

k8s_menu() {
  PS3=$'\nKubernetes > Choose an action: '
  select opt in \
    "Get nodes" \
    "Get pods (all namespaces)" \
    "Get services (all namespaces)" \
    "Describe a pod (pick in current ns)" \
    "Logs (follow) a pod (pick in current ns)" \
    "Exec shell into a pod (pick in current ns)" \
    "AWX: show pods/services" \
    "AWX: tail awx-web logs" \
    "AWX: show admin password" \
    "CoreDNS: show NodeHosts" \
    "Back"; do
    case "$REPLY" in
      1) clear; kubectl get nodes -o wide; press ;;
      2) clear; kubectl get pods -A -o wide; press ;;
      3) clear; kubectl get svc -A -o wide; press ;;
      4) clear; local pod; pod=$(pick_pod "$AWX_NAMESPACE") || true; [[ -n "${pod:-}" ]] && kubectl -n "$AWX_NAMESPACE" describe pod "$pod"; press ;;
      5) clear; local pod; pod=$(pick_pod "$AWX_NAMESPACE") || true; [[ -n "${pod:-}" ]] && kubectl -n "$AWX_NAMESPACE" logs -f "$pod" ;;
      6) clear; local pod; pod=$(pick_pod "$AWX_NAMESPACE") || true; [[ -n "${pod:-}" ]] && (kubectl -n "$AWX_NAMESPACE" exec -it "$pod" -- /bin/bash || kubectl -n "$AWX_NAMESPACE" exec -it "$pod" -- /bin/sh); press ;;
      7) clear; kubectl -n "$AWX_NAMESPACE" get pods -o wide; echo; kubectl -n "$AWX_NAMESPACE" get svc -o wide; press ;;
      8) clear; local pod; pod=$(awx_web_pod); [[ -n "${pod:-}" ]] && kubectl -n "$AWX_NAMESPACE" logs -f "$pod" || warn "awx-web not running";;
      9) clear; local pw; pw=$(decode_secret_value "$AWX_NAMESPACE" "${AWX_NAME}-admin-password" "password"); [[ -n "$pw" ]] && echo "AWX admin password: $pw" || warn "Secret not ready"; press ;;
      10) clear; kubectl -n kube-system get cm coredns -o jsonpath='{.data.NodeHosts}'; echo; press ;;
      11) break ;;
      *) warn "Invalid";;
    esac
  done
}

host_menu() {
  PS3=$'\nHost/Proxy > Choose an action: '
  select opt in \
    "Nginx test & reload" \
    "Listening ports" \
    "Curl local backends (GitLab/AWX/pma)" \
    "Systemctl status (docker/k3s/nginx)" \
    "Disk usage" \
    "Back"; do
    case "$REPLY" in
      1) clear; nginx -t && systemctl reload nginx && say "Nginx reloaded"; press ;;
      2) clear; ss -tulpn | sort -k5; press ;;
      3) clear; echo "GitLab:"; curl -sS --max-time 5 "http://127.0.0.1:${GITLAB_HTTP_PORT}/users/sign_in" | head -n 5 || true
         echo "---- AWX:"; curl -sS --max-time 5 "http://127.0.0.1:${AWX_NODEPORT}/api/v2/ping/" || curl -sS "http://127.0.0.1:${AWX_NODEPORT}/" | head -n 5 || true
         echo "---- phpMyAdmin:"; curl -sS --max-time 5 "http://127.0.0.1:${PMA_BIND_PORT}/" | head -n 5 || true
         press ;;
      4) clear; systemctl -q is-active docker && systemctl status docker --no-pager || warn "docker inactive"
         echo "----"; systemctl -q is-active k3s && systemctl status k3s --no-pager || warn "k3s inactive"
         echo "----"; systemctl -q is-active nginx && systemctl status nginx --no-pager || warn "nginx inactive"
         press ;;
      5) clear; df -h; press ;;
      6) break ;;
      *) warn "Invalid";;
    esac
  done
}

main_menu() {
  trap 'echo; say "Bye!"; exit 0' INT
  while true; do
    clear
    echo "=============================================="
    echo " Manage Apps – Docker + k3s quick ops"
    echo " KUBECONFIG: $KUBECONFIG"
    echo " Namespace : $AWX_NAMESPACE   AWX: $AWX_NAME"
    echo " Compose   : $COMPOSE_DIR"
    echo "=============================================="
    echo " 1) Docker"
    echo " 2) Kubernetes"
    echo " 3) Host / Proxy"
    echo " 4) Quit"
    read -rp "Choose: " choice
    case "$choice" in
      1) docker_menu ;;
      2) k8s_menu ;;
      3) host_menu ;;
      4) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

main_menu
