#!/usr/bin/env bash
set -euo pipefail

### ========= Config (edit for prod) =========
AWX_NAMESPACE="awx"
AWX_NAME="awx"
AWX_NODEPORT=30080                     # AWX Web UI via http://<host>:30080
AWX_ADMIN_USER="admin"
AWX_ADMIN_PASS="${AWX_ADMIN_PASS:-ChangeMe_AWX!123}"   # can override via env

# GitLab ports (host:container)
GITLAB_HTTP_PORT=8080
GITLAB_HTTPS_PORT=8443
GITLAB_SSH_PORT=2222

# MySQL + phpMyAdmin + demo app
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-ChangeMe_MySQL!123}"
MYSQL_DB="appdb"
MYSQL_USER="appuser"
MYSQL_PASS="${MYSQL_PASS:-ChangeMe_App!123}"
PHPMYADMIN_PORT=8081
DATAVIEWER_PORT=8082

# Paths
BASE_DIR="/opt/stack"
COMPOSE_DIR="${BASE_DIR}/compose"
GITLAB_DIR="${COMPOSE_DIR}/gitlab"
MYSQL_DIR="${COMPOSE_DIR}/mysql"
PHPMYADMIN_DIR="${COMPOSE_DIR}/phpmyadmin"
DATAVIEWER_DIR="${COMPOSE_DIR}/data-viewer"
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

### ========= System prep =========
system_prep() {
  say "Updating apt and installing base tools…"
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https jq git

  # Docker Engine + compose plugin
  if ! need_cmd docker; then
    say "Installing Docker Engine…"
    # Docker repo
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

  # kubectl (k3s provides one)
  if ! need_cmd kubectl; then
    sudo ln -sf /usr/local/bin/kubectl /usr/bin/kubectl || true
  fi

  sudo mkdir -p "${GITLAB_DIR}" "${MYSQL_DIR}" "${PHPMYADMIN_DIR}" "${DATAVIEWER_DIR}" "${K8S_DIR}"
}

### ========= AWX via Operator on k3s =========
deploy_awx() {
  say "Setting up AWX Operator via Helm (namespace: ${AWX_NAMESPACE})…"
  helm repo add awx-operator https://ansible-community.github.io/awx-operator-helm >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1

  # Install/upgrade operator
  helm upgrade --install ansible-awx-operator awx-operator/awx-operator \
    -n "${AWX_NAMESPACE}" --create-namespace

  # Create admin password secret
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

  # AWX Custom Resource (NodePort)
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

  say "Waiting for AWX pods to become Ready (this can take a few minutes)…"
  kubectl -n "${AWX_NAMESPACE}" rollout status deployment/awx-operator-controller-manager --timeout=300s || true
  # Wait for AWX web to appear (best-effort)
  for i in {1..60}; do
    if kubectl -n "${AWX_NAMESPACE}" get svc "${AWX_NAME}-service" >/dev/null 2>&1; then break; fi
    sleep 5
  done
}

### ========= Docker Compose stack: GitLab + MySQL + phpMyAdmin + demo app =========
write_compose() {
  say "Writing docker-compose.yml and app files…"

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
    ports:
      - "3306:3306"

  phpmyadmin:
    image: phpmyadmin:latest
    restart: unless-stopped
    depends_on:
      - mysql
    environment:
      PMA_HOST: mysql
      PMA_ABSOLUTE_URI: "http://localhost:${PHPMYADMIN_PORT}/"
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
EOF

  # .env to feed compose interpolation
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
EOF

  # Minimal Flask app that shows tables and top 100 rows of a demo table
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
}

bring_up_compose() {
  say "Starting Docker services (GitLab, MySQL, phpMyAdmin, data-viewer)…"
  pushd "${COMPOSE_DIR}" >/dev/null
  docker compose build --no-cache data-viewer
  docker compose up -d
  popd >/dev/null
}

### ========= Post-install info =========
print_info() {
  HOST_IP=$(hostname -I | awk '{print $1}')
  say "Done! Endpoints:"
  cat <<EOF

AWX (NodePort):
  URL:  http://${HOST_IP}:${AWX_NODEPORT}
  User: ${AWX_ADMIN_USER}
  Pass: (what you set) or fetch with:
        kubectl get secret -n ${AWX_NAMESPACE} ${AWX_NAME}-admin-password -o jsonpath="{.data.password}" | base64 --decode; echo

GitLab CE:
  Web:  http://localhost:${GITLAB_HTTP_PORT}
  SSH:  ssh -p ${GITLAB_SSH_PORT} git@localhost
  Data: ${GITLAB_DIR}

MySQL:
  Host: localhost  Port: 3306
  DB:   ${MYSQL_DB}
  User: ${MYSQL_USER}
  Pass: ${MYSQL_PASS}
  Root: ${MYSQL_ROOT_PASSWORD}

phpMyAdmin:
  URL:  http://localhost:${PHPMYADMIN_PORT}
  Login with MySQL credentials above.

Data Viewer (demo web app on MySQL):
  URL:  http://localhost:${DATAVIEWER_PORT}
  Visit /init once to create a demo table.

Files live under: ${COMPOSE_DIR} and ${K8S_DIR}
EOF
}

### ========= Run all =========
main() {
  require_ubuntu
  sudo_test
  system_prep
  deploy_awx
  write_compose
  bring_up_compose
  print_info
  warn "If you were added to the 'docker' group just now, you may need to log out/in to use Docker without sudo."
}

main "$@"

