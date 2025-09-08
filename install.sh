#!/usr/bin/env bash
set -euo pipefail

### ========= Config (override via env as needed) =========
AWX_NAMESPACE="${AWX_NAMESPACE:-awx}"
AWX_NAME="${AWX_NAME:-awx}"
AWX_NODEPORT="${AWX_NODEPORT:-30080}"                 # AWX HTTP -> http://<host>:30080 (proxied by Nginx :4446)
AWX_ADMIN_USER="${AWX_ADMIN_USER:-admin}"
AWX_ADMIN_PASS="${AWX_ADMIN_PASS:-ChangeMe_AWX!123}"

# GitLab host ports (host:container)
GITLAB_HTTP_PORT="${GITLAB_HTTP_PORT:-8080}"
GITLAB_HTTPS_PORT="${GITLAB_HTTPS_PORT:-8443}"        # container HTTPS (unused; we terminate at Nginx)
GITLAB_SSH_PORT="${GITLAB_SSH_PORT:-2222}"

# MySQL + phpMyAdmin + demo app
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-ChangeMe_MySQL!123}"
MYSQL_DB="${MYSQL_DB:-appdb}"
MYSQL_USER="${MYSQL_USER:-appuser}"
MYSQL_PASS="${MYSQL_PASS:-ChangeMe_App!123}"
PHPMYADMIN_PORT="${PHPMYADMIN_PORT:-8081}"            # container HTTP (proxied to Nginx :4444)
DATAVIEWER_PORT="${DATAVIEWER_PORT:-8082}"            # container HTTP (proxied to Nginx :4445)"

# HTTPS reverse proxy (self-signed cert, multiple TLS ports)
TLS_GITLAB_PORT="${TLS_GITLAB_PORT:-4443}"
TLS_PHPMYADMIN_PORT="${TLS_PHPMYADMIN_PORT:-4444}"
TLS_APP_PORT="${TLS_APP_PORT:-4445}"
TLS_AWX_PORT="${TLS_AWX_PORT:-4446}"
TLS_CN="${TLS_CN:-$(hostname -f)}"                    # Common Name for cert

# Paths
BASE_DIR="/opt/stack"
COMPOSE_DIR="${BASE_DIR}/compose"
GITLAB_DIR="${COMPOSE_DIR}/gitlab"
MYSQL_DIR="${COMPOSE_DIR}/mysql"
PHPMYADMIN_DIR="${COMPOSE_DIR}/phpmyadmin"
DATAVIEWER_DIR="${COMPOSE_DIR}/data-viewer"
NGINX_DIR="${COMPOSE_DIR}/nginx"
K8S_DIR="${BASE_DIR}/k8s"

### ========= Helpers =========
need_cmd() { command -v "$1" >/dev/null 2>&1; }
say() { echo -e "\e[1;32m[+]\e[0m $*"; }
warn() { echo -e "\e[1;33m[!]\e[0m $*"; }
die() { echo -e "\e[1;31m[x]\e[0m $*"; exit 1; }

require_ubuntu() {
  if ! [ -f /etc/os-release ]; then die "Unsupported OS (no /etc/os-release)"; fi
  . /etc/os-release
  if [[ "${ID}" != "ubuntu" ]]; then
    warn "This script targets Ubuntu. Detected: ${PRETTY_NAME}"
  fi
}

sudo_test() {
  if ! sudo -n true 2>/dev/null; then
    say "Requesting sudo privileges once…"
    sudo -v
  fi
}

# Docker wrapper that falls back to sudo if the current session isn't in the docker group yet
docker_exec() {
  if docker info >/dev/null 2>&1; then
    docker "$@"
  elif sudo -n docker info >/dev/null 2>&1; then
    sudo docker "$@"
  else
    echo "[x] Docker not accessible (group not active yet). Open a new shell or re-run with sudo:"
    echo "    sudo docker $*"
    return 1
  fi
}

trap 'warn "Something failed. Fix the issue and re-run—script is mostly idempotent."' ERR

### ========= System prep =========
system_prep() {
  say "Updating apt and installing base tools…"
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https jq git openssl

  # Docker Engine + compose plugin
  if ! need_cmd docker; then
    say "Installing Docker Engine…"
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu $(. /etc/os-release; echo $VERSION_CODENAME) stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo usermod -aG docker "$USER" || true
  else
    say "Docker already installed."
  fi

  # Compose plugin sanity
  docker_exec compose version >/dev/null 2>&1 || sudo apt-get install -y docker-compose-plugin

  # Helm
  if ! need_cmd helm; then
    say "Installing Helm…"
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  else
    say "Helm already installed."
  fi

  # k3s (Kubernetes)
  if ! systemctl is-active --quiet k3s; then
    say "Installing k3s (lightweight Kubernetes)…"
    curl -sfL https://get.k3s.io | sudo INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -
  else
    say "k3s already running."
  fi

  # Ensure kubectl exists (k3s provides one)
  need_cmd kubectl || sudo ln -sf /usr/local/bin/kubectl /usr/bin/kubectl || true

  # Create directories with sudo; hand over to current user
  sudo mkdir -p "${GITLAB_DIR}" "${MYSQL_DIR}/data" "${MYSQL_DIR}/init" "${PHPMYADMIN_DIR}" "${DATAVIEWER_DIR}" "${NGINX_DIR}/certs" "${K8S_DIR}"
  sudo chown -R "$USER":"$USER" "${BASE_DIR}"
}

### ========= k3s readiness =========
wait_for_k3s() {
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  say "Waiting for k3s API to be ready…"
  for i in {1..120}; do
    if kubectl get --raw=/readyz 2>/dev/null | grep -q ok; then
      say "k3s API is ready."
      kubectl get nodes -o wide || true
      return 0
    fi
    sleep 2
  done
  die "k3s API not ready after ~4 minutes."
}

### ========= AWX via Operator on k3s =========
deploy_awx() {
  say "Setting up AWX Operator via Helm (namespace: ${AWX_NAMESPACE})…"
  helm repo add awx-operator https://ansible-community.github.io/awx-operator-helm >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1

  # Install/upgrade operator
  helm upgrade --install ansible-awx-operator awx-operator/awx-operator \
    -n "${AWX_NAMESPACE}" --create-namespace

  # Admin password secret
  cat > "${K8S_DIR}/awx-admin-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${AWX_NAME}-admin-password
  namespace: ${AWX_NAMESPACE}
type: Opaque
stringData:
  password: "${AWX_ADMIN_PASS}"
EOF
  kubectl apply -f "${K8S_DIR}/awx-admin-secret.yaml"

  # AWX Custom Resource (NodePort for web UI)
  cat > "${K8S_DIR}/awx.yaml" <<EOF
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: ${AWX_NAME}
  namespace: ${AWX_NAMESPACE}
spec:
  admin_user: ${AWX_ADMIN_USER}
  admin_password_secret: ${AWX_NAME}-admin-password
  service_type: NodePort
  nodeport_port: ${AWX_NODEPORT}
  ingress_type: none
EOF
  kubectl apply -f "${K8S_DIR}/awx.yaml"

  say "Waiting for AWX components (operator + instance)…"
  kubectl -n "${AWX_NAMESPACE}" rollout status deployment/awx-operator-controller-manager --timeout=300s || true

  # Best-effort: wait for the AWX service to appear
  for i in {1..120}; do
    if kubectl -n "${AWX_NAMESPACE}" get svc "${AWX_NAME}-service" >/dev/null 2>&1; then
      say "AWX service detected."
      break
    fi
    sleep 5
  done
}

### ========= Docker Compose stack: GitLab + MySQL + phpMyAdmin + demo app + Nginx TLS =========
write_compose() {
  say "Writing docker-compose.yml, app files, MySQL init and Nginx TLS config…"

  # docker-compose
  cat > "${COMPOSE_DIR}/docker-compose.yml" <<'EOF'
services:
  gitlab:
    image: gitlab/gitlab-ce:latest
    restart: unless-stopped
    hostname: gitlab.local
    ports:
      - "${GITLAB_HTTP_PORT}:80"
      - "${GITLAB_HTTPS_PORT}:443"
      - "${GITLAB_SSH_PORT}:22"
    volumes:
      - ./gitlab/config:/etc/gitlab
      - ./gitlab/logs:/var/log/gitlab
      - ./gitlab/data:/var/opt/gitlab
    shm_size: '1g'

  mysql:
    image: mysql:8.4
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: "${MYSQL_ROOT_PASSWORD}"
      MYSQL_DATABASE: "${MYSQL_DB}"
      MYSQL_USER: "${MYSQL_USER}"
      MYSQL_PASSWORD: "${MYSQL_PASS}"
    command: --default-authentication-plugin=mysql_native_password --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci
    volumes:
      - ./mysql/data:/var/lib/mysql
      - ./mysql/init:/docker-entrypoint-initdb.d
    ports:
      - "3306:3306"

  phpmyadmin:
    image: phpmyadmin:latest
    restart: unless-stopped
    depends_on:
      - mysql
    environment:
      PMA_HOST: mysql
      PMA_ABSOLUTE_URI: "https://localhost:${TLS_PHPMYADMIN_PORT}/"
    ports:
      - "${PHPMYADMIN_PORT}:80"

  data-viewer:
    build:
      context: ./data-viewer
    restart: unless-stopped
    depends_on:
      - mysql
    environment:
      DB_HOST: mysql
      DB_NAME: "${MYSQL_DB}"
      DB_USER: "${MYSQL_USER}"
      DB_PASS: "${MYSQL_PASS}"
    ports:
      - "${DATAVIEWER_PORT}:8080"

  # Single Nginx reverse proxy with self-signed cert, publishing multiple HTTPS ports.
  # Uses host network so it can reach localhost:<ports> and bind :4443-:4446.
  nginx:
    image: nginx:alpine
    restart: unless-stopped
    network_mode: "host"
    depends_on:
      - gitlab
      - phpmyadmin
      - data-viewer
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/certs:/etc/nginx/certs:ro
EOF

  # .env
  cat > "${COMPOSE_DIR}/.env" <<EOF
GITLAB_HTTP_PORT=${GITLAB_HTTP_PORT}
GITLAB_HTTPS_PORT=${GITLAB_HTTPS_PORT}
GITLAB_SSH_PORT=${GITLAB_SSH_PORT}

MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
MYSQL_DB=${MYSQL_DB}
MYSQL_USER=${MYSQL_USER}
MYSQL_PASS=${MYSQL_PASS}

PHPMYADMIN_PORT=${PHPMYADMIN_PORT}
DATAVIEWER_PORT=${DATAVIEWER_PORT}

TLS_GITLAB_PORT=${TLS_GITLAB_PORT}
TLS_PHPMYADMIN_PORT=${TLS_PHPMYADMIN_PORT}
TLS_APP_PORT=${TLS_APP_PORT}
TLS_AWX_PORT=${TLS_AWX_PORT}
EOF

  # GitLab config: set external_url to HTTP (behind proxy); we pass X-Forwarded-Proto https from Nginx.
  mkdir -p "${GITLAB_DIR}/config"
  cat > "${GITLAB_DIR}/config/gitlab.rb" <<EOF
external_url "http://localhost:${GITLAB_HTTP_PORT}"
nginx['listen_https'] = false
nginx['listen_port'] = 80
gitlab_rails['gitlab_shell_ssh_port'] = ${GITLAB_SSH_PORT}
letsencrypt['enable'] = false
# Trust X-Forwarded-Proto from proxy
nginx['proxy_set_headers'] = { 'X-Forwarded-Proto' => 'https', 'X-Forwarded-Ssl' => 'on' }
EOF

  # MySQL init to allow remote root login (and via phpMyAdmin)
  cat > "${MYSQL_DIR}/init/01-remote-root.sql" <<EOF
-- Create root@'%' if needed and ensure password + full privileges
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
ALTER USER 'root'@'%' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

  # Flask demo app
  cat > "${DATAVIEWER_DIR}/app.py" <<'EOF'
import os, pymysql
from flask import Flask, render_template_string

DB_HOST=os.getenv("DB_HOST","mysql")
DB_NAME=os.getenv("DB_NAME","appdb")
DB_USER=os.getenv("DB_USER","appuser")
DB_PASS=os.getenv("DB_PASS","password")

tmpl = """
<!doctype html>
<title>Data Viewer</title>
<h1>MySQL: {{ db }}</h1>
<p><a href="/init">[Init demo table]</a></p>
<h2>Tables</h2>
<ul>
{% for t in tables %}
  <li>{{ t }}</li>
{% endfor %}
</ul>
<h2>demo_items (first 100)</h2>
<table border="1" cellpadding="6" cellspacing="0">
  <tr><th>id</th><th>name</th><th>created_at</th></tr>
  {% for r in rows %}
    <tr><td>{{ r[0] }}</td><td>{{ r[1] }}</td><td>{{ r[2] }}</td></tr>
  {% endfor %}
</table>
"""

def db():
    return pymysql.connect(host=DB_HOST, user=DB_USER, password=DB_PASS, database=DB_NAME, cursorclass=pymysql.cursors.Cursor)

app = Flask(__name__)

@app.get("/")
def index():
    with db() as conn:
        with conn.cursor() as cur:
            cur.execute("SHOW TABLES;")
            tables = [r[0] for r in cur.fetchall()]
            try:
                cur.execute("SELECT id,name,created_at FROM demo_items ORDER BY id DESC LIMIT 100;")
                rows = cur.fetchall()
            except Exception:
                rows = []
    return render_template_string(tmpl, db=DB_NAME, tables=tables, rows=rows)

@app.get("/init")
def init():
    with db() as conn:
        with conn.cursor() as cur:
            cur.execute("""
            CREATE TABLE IF NOT EXISTS demo_items(
              id INT AUTO_INCREMENT PRIMARY KEY,
              name VARCHAR(255) NOT NULL,
              created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
            """)
            cur.execute("INSERT INTO demo_items(name) VALUES ('hello'),('world'),('from data-viewer');")
        conn.commit()
    return "Initialized. <a href='/'>Back</a>"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
EOF

  cat > "${DATAVIEWER_DIR}/requirements.txt" <<'EOF'
flask
pymysql
EOF

  cat > "${DATAVIEWER_DIR}/Dockerfile" <<'EOF'
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 8080
CMD ["python", "app.py"]
EOF

  # Nginx TLS: one self-signed cert used for all listeners
  mkdir -p "${NGINX_DIR}/certs"
  openssl req -x509 -nodes -newkey rsa:4096 -days 365 \
    -keyout "${NGINX_DIR}/certs/selfsigned.key" \
    -out "${NGINX_DIR}/certs/selfsigned.crt" \
    -subj "/CN=${TLS_CN}" >/dev/null 2>&1

  # Nginx config: four HTTPS servers on different ports proxying to local HTTP ports
  cat > "${NGINX_DIR}/nginx.conf" <<EOF
events {}
http {
  ssl_session_cache shared:SSL:10m;
  ssl_session_timeout 10m;

  map \$http_upgrade \$connection_upgrade { default upgrade; '' close; }

  # Common proxy settings
  proxy_headers_hash_max_size 512;
  proxy_headers_hash_bucket_size 64;

  # GitLab (HTTPS :${TLS_GITLAB_PORT} -> http://127.0.0.1:${GITLAB_HTTP_PORT})
  server {
    listen ${TLS_GITLAB_PORT} ssl;
    server_name _;

    ssl_certificate     /etc/nginx/certs/selfsigned.crt;
    ssl_certificate_key /etc/nginx/certs/selfsigned.key;

    location / {
      proxy_pass http://127.0.0.1:${GITLAB_HTTP_PORT};
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto https;
      proxy_set_header X-Forwarded-Ssl on;
      client_max_body_size 0;
      proxy_read_timeout 300s;
    }
  }

  # phpMyAdmin (HTTPS :${TLS_PHPMYADMIN_PORT} -> http://127.0.0.1:${PHPMYADMIN_PORT})
  server {
    listen ${TLS_PHPMYADMIN_PORT} ssl;
    server_name _;

    ssl_certificate     /etc/nginx/certs/selfsigned.crt;
    ssl_certificate_key /etc/nginx/certs/selfsigned.key;

    location / {
      proxy_pass http://127.0.0.1:${PHPMYADMIN_PORT};
      proxy_set_header Host \$host;
      proxy_set_header X-Forwarded-Proto https;
    }
  }

  # Data Viewer (HTTPS :${TLS_APP_PORT} -> http://127.0.0.1:${DATAVIEWER_PORT})
  server {
    listen ${TLS_APP_PORT} ssl;
    server_name _;

    ssl_certificate     /etc/nginx/certs/selfsigned.crt;
    ssl_certificate_key /etc/nginx/certs/selfsigned.key;

    location / {
      proxy_pass http://127.0.0.1:${DATAVIEWER_PORT};
      proxy_set_header Host \$host;
      proxy_set_header X-Forwarded-Proto https;
    }
  }

  # AWX (HTTPS :${TLS_AWX_PORT} -> http://127.0.0.1:${AWX_NODEPORT})
  server {
    listen ${TLS_AWX_PORT} ssl;
    server_name _;

    ssl_certificate     /etc/nginx/certs/selfsigned.crt;
    ssl_certificate_key /etc/nginx/certs/selfsigned.key;

    location / {
      proxy_pass http://127.0.0.1:${AWX_NODEPORT};
      proxy_set_header Host \$host;
      proxy_set_header X-Forwarded-Proto https;
      proxy_read_timeout 300s;
    }
  }
}
EOF
}

bring_up_compose() {
  say "Starting Docker services (GitLab, MySQL, phpMyAdmin, data-viewer, Nginx TLS)…"
  pushd "${COMPOSE_DIR}" >/dev/null
  docker_exec compose build --no-cache data-viewer
  docker_exec compose up -d
  popd >/dev/null
}

### ========= Post-install info =========
print_info() {
  # Try to pick a sensible IP to show
  HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
  if [[ -z "${HOST_IP}" ]]; then
    HOST_IP="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
  fi
  [[ -z "${HOST_IP}" ]] && HOST_IP="localhost"

  # GitLab initial password (best-effort)
  local GITLAB_PW="(not found yet)"
  if docker_exec ps --format '{{.Names}}\t{{.Image}}' | grep -q 'compose-gitlab-1'; then
    set +e
    GITLAB_PW="$(docker_exec exec -i compose-gitlab-1 sh -lc "grep 'Password:' /etc/gitlab/initial_root_password 2>/dev/null | awk '{print \$2}'")"
    [[ -z "${GITLAB_PW}" ]] && GITLAB_PW="(expired or not yet created; reset with: sudo docker exec -it compose-gitlab-1 gitlab-rake \"gitlab:password:reset[root]\")"
    set -e
  fi

  say "Done! Endpoints (HTTPS via self-signed cert):"
  cat <<EOF

GitLab:
  URL:  https://${HOST_IP}:${TLS_GITLAB_PORT}
  SSH:  ssh -p ${GITLAB_SSH_PORT} git@${HOST_IP}
  Initial root password: ${GITLAB_PW}

phpMyAdmin:
  URL:  https://${HOST_IP}:${TLS_PHPMYADMIN_PORT}
  MySQL root login is enabled remotely (root / ${MYSQL_ROOT_PASSWORD})

Data Viewer (demo web app on MySQL):
  URL:  https://${HOST_IP}:${TLS_APP_PORT}
  Visit /init once to create a demo table.

AWX:
  URL:  https://${HOST_IP}:${TLS_AWX_PORT}
  User: ${AWX_ADMIN_USER}
  Pass: (what you set) or fetch with:
        kubectl get secret -n ${AWX_NAMESPACE} ${AWX_NAME}-admin-password -o jsonpath="{.data.password}" | base64 --decode; echo

Files live under:
  ${COMPOSE_DIR}
  ${K8S_DIR}

Note: Browser will warn about the self-signed certificate (expected). Proceed/accept to continue.
If you were just added to the 'docker' group, open a new terminal or run 'newgrp docker' to use Docker without sudo.
EOF
}

### ========= Run all =========
main() {
  require_ubuntu
  sudo_test
  system_prep
  wait_for_k3s
  deploy_awx
  write_compose
  bring_up_compose
  print_info
}

main "$@"
