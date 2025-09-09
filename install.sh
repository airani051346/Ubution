#!/usr/bin/env bash
set -euo pipefail

### ===== Config (override via env before running) =====
# GitLab (host apps)
GITLAB_HTTP_BACKEND_PORT="${GITLAB_HTTP_BACKEND_PORT:-8080}"  # GitLab Omnibus internal HTTP (127.0.0.1)
GITLAB_TLS_PORT="${GITLAB_TLS_PORT:-4443}"

# MySQL (host apps)
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-ChangeMe_MySQL!123}"
MYSQL_APP_DB="${MYSQL_APP_DB:-appdb}"
MYSQL_APP_USER="${MYSQL_APP_USER:-appuser}"
MYSQL_APP_PASS="${MYSQL_APP_PASS:-ChangeMe_App!123}"

# Data viewer (host app)
DATAVIEWER_DIR="/opt/data-viewer"
DATAVIEWER_BIND_IP="127.0.0.1"
DATAVIEWER_BIND_PORT="${DATAVIEWER_BIND_PORT:-8002}"
DATAVIEWER_TLS_PORT="${DATAVIEWER_TLS_PORT:-4445}"

# phpMyAdmin (host app via Nginx+PHP-FPM)
PHPMYADMIN_TLS_PORT="${PHPMYADMIN_TLS_PORT:-4444}"

# AWX (only component in Docker)
AWX_DIR="/opt/awx-docker"
AWX_WEB_PORT_INTERNAL="${AWX_WEB_PORT_INTERNAL:-8052}"  # inside docker bind on 127.0.0.1:8052
AWX_TLS_PORT="${AWX_TLS_PORT:-4446}"
AWX_ADMIN_USER="${AWX_ADMIN_USER:-admin}"
AWX_ADMIN_PASS="${AWX_ADMIN_PASS:-ChangeMe_AWX!123}"
AWX_POSTGRES_USER="${AWX_POSTGRES_USER:-awx}"
AWX_POSTGRES_PASS="${AWX_POSTGRES_PASS:-AwxDbPass!123}"
AWX_POSTGRES_DB="${AWX_POSTGRES_DB:-awx}"

# TLS
TLS_CN="${TLS_CN:-}"   # default set to host IP later

### ===== Helpers =====
say(){ echo -e "\e[1;32m[+]\e[0m $*"; }
warn(){ echo -e "\e[1;33m[!]\e[0m $*"; }
die(){ echo -e "\e[1;31m[x]\e[0m $*"; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1; }

host_ip() {
  local ip
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')" || true
  [[ -z "$ip" ]] && ip="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')" || true
  [[ -z "$ip" ]] && ip="127.0.0.1"
  echo "$ip"
}

trap 'warn "Something failed. Fix the error above, then re-run — the script is mostly idempotent."' ERR

### ===== System prep =====
say "Installing base packages…"
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https \
  software-properties-common git jq ufw \
  nginx openssl \
  mysql-server \
  php-fpm php-mysql php-zip php-gd php-curl php-mbstring php-xml php-bcmath php-intl php-cli php-json php-common \
  debconf-utils

# Detect PHP-FPM socket
PHPFPM_SOCK="$(ls /run/php/php*-fpm.sock 2>/dev/null | head -n1 || true)"
if [[ -z "$PHPFPM_SOCK" ]]; then
  # Fallback: try service restart and check again
  sudo systemctl restart php*-fpm || true
  PHPFPM_SOCK="$(ls /run/php/php*-fpm.sock 2>/dev/null | head -n1 || true)"
fi
[[ -z "$PHPFPM_SOCK" ]] && die "Could not find PHP-FPM socket under /run/php. Is php-fpm installed?"

### ===== Install GitLab CE (Omnibus) =====
say "Installing GitLab CE (Omnibus)…"
if ! dpkg -l | grep -q '^ii\s\+gitlab-ce\s'; then
  # Add official GitLab CE repo (packages.gitlab.com)
  curl -fsSL https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | sudo bash
  # Precreate config directory to drop gitlab.rb before first reconfigure
  sudo mkdir -p /etc/gitlab
fi

HOST_IP="$(host_ip)"
: "${TLS_CN:=$HOST_IP}"

# Configure GitLab to listen on localhost:${GITLAB_HTTP_BACKEND_PORT} and generate HTTPS links at :4443
sudo tee /etc/gitlab/gitlab.rb >/dev/null <<EOF
external_url "https://${HOST_IP}:${GITLAB_TLS_PORT}"
nginx['listen_https'] = false
nginx['listen_port']  = ${GITLAB_HTTP_BACKEND_PORT}
nginx['listen_addresses'] = ["127.0.0.1"]
letsencrypt['enable'] = false
gitlab_rails['gitlab_https'] = true
gitlab_rails['trusted_proxies'] = ['127.0.0.1']
# Keep SSH on default host port 22 unless you prefer another; GitLab will advertise the correct port if changed:
# gitlab_rails['gitlab_shell_ssh_port'] = 22
EOF

# Install/ensure package present then reconfigure
sudo apt-get install -y gitlab-ce
sudo gitlab-ctl reconfigure

### ===== MySQL server config + users =====
say "Configuring MySQL server…"
# Ensure MySQL binds on all interfaces (so remote is possible)
sudo sed -i 's/^\s*bind-address\s*=.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf || true

sudo systemctl enable --now mysql

# Secure and create users/db (idempotent)
MYSQL_SECURE_SQL=$(cat <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
CREATE DATABASE IF NOT EXISTS \`${MYSQL_APP_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${MYSQL_APP_USER}'@'%' IDENTIFIED BY '${MYSQL_APP_PASS}';
GRANT ALL PRIVILEGES ON \`${MYSQL_APP_DB}\`.* TO '${MYSQL_APP_USER}'@'%';
FLUSH PRIVILEGES;
SQL
)
sudo mysql -e "$MYSQL_SECURE_SQL" || true
sudo systemctl restart mysql

### ===== phpMyAdmin (host) =====
say "Installing phpMyAdmin…"
# Preseed debconf to avoid Apache auto-config
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect" | sudo debconf-set-selections
echo "phpmyadmin phpmyadmin/dbconfig-install boolean false"    | sudo debconf-set-selections
sudo apt-get install -y phpmyadmin

# Nginx server for phpMyAdmin over TLS :4444
sudo tee /etc/nginx/sites-available/phpmyadmin.conf >/dev/null <<EOF
server {
    listen ${PHPMYADMIN_TLS_PORT} ssl;
    server_name _;

    ssl_certificate     /etc/nginx/selfsigned/fullchain.crt;
    ssl_certificate_key /etc/nginx/selfsigned/privkey.key;

    root /usr/share/phpmyadmin;
    index index.php index.html;

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHPFPM_SOCK};
    }

    location / {
        try_files \$uri /index.php?\$query_string;
    }
}
EOF

### ===== Data Viewer (host) =====
say "Installing data-viewer (Flask) as a systemd service…"
sudo apt-get install -y python3-venv python3-pip
sudo mkdir -p "$DATAVIEWER_DIR"
sudo chown -R "$USER":"$USER" "$DATAVIEWER_DIR"

cat > "${DATAVIEWER_DIR}/app.py" <<'EOF'
import os, pymysql
from flask import Flask, render_template_string

DB_HOST=os.getenv("DB_HOST","127.0.0.1")
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
    app.run()
EOF

python3 -m venv "${DATAVIEWER_DIR}/venv"
"${DATAVIEWER_DIR}/venv/bin/pip" install --no-cache-dir flask pymysql gunicorn

# Systemd service (Gunicorn bound to 127.0.0.1:8002)
sudo tee /etc/systemd/system/data-viewer.service >/dev/null <<EOF
[Unit]
Description=Data Viewer Flask App
After=network.target

[Service]
User=${USER}
WorkingDirectory=${DATAVIEWER_DIR}
Environment=DB_HOST=127.0.0.1
Environment=DB_NAME=${MYSQL_APP_DB}
Environment=DB_USER=${MYSQL_APP_USER}
Environment=DB_PASS=${MYSQL_APP_PASS}
ExecStart=${DATAVIEWER_DIR}/venv/bin/gunicorn -b ${DATAVIEWER_BIND_IP}:${DATAVIEWER_BIND_PORT} app:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now data-viewer

# Nginx server for data-viewer :4445
sudo tee /etc/nginx/sites-available/data-viewer.conf >/dev/null <<EOF
server {
    listen ${DATAVIEWER_TLS_PORT} ssl;
    server_name _;

    ssl_certificate     /etc/nginx/selfsigned/fullchain.crt;
    ssl_certificate_key /etc/nginx/selfsigned/privkey.key;

    location / {
        proxy_pass http://${DATAVIEWER_BIND_IP}:${DATAVIEWER_BIND_PORT};
        proxy_set_header Host \$host:\$server_port;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
EOF

### ===== Docker (AWX only) =====
say "Installing Docker Engine (for AWX only)…"
if ! need docker; then
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release; echo $VERSION_CODENAME) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  sudo usermod -aG docker "$USER" || true
fi

say "Preparing AWX docker-compose…"
sudo mkdir -p "$AWX_DIR"
sudo chown -R "$USER":"$USER" "$AWX_DIR"

cat > "${AWX_DIR}/docker-compose.yml" <<EOF
services:
  postgres:
    image: postgres:13
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${AWX_POSTGRES_DB}
      POSTGRES_USER: ${AWX_POSTGRES_USER}
      POSTGRES_PASSWORD: ${AWX_POSTGRES_PASS}
    volumes:
      - ./pgdata:/var/lib/postgresql/data

  redis:
    image: redis:6-alpine
    restart: unless-stopped

  awx:
    image: quay.io/ansible/awx:latest
    depends_on:
      - postgres
      - redis
    restart: unless-stopped
    environment:
      SECRET_KEY: "$(openssl rand -hex 32)"
      DATABASE_USER: ${AWX_POSTGRES_USER}
      DATABASE_PASSWORD: ${AWX_POSTGRES_PASS}
      DATABASE_NAME: ${AWX_POSTGRES_DB}
      DATABASE_HOST: postgres
      REDIS_HOST: redis
      AWX_ADMIN_USER: ${AWX_ADMIN_USER}
      AWX_ADMIN_PASSWORD: ${AWX_ADMIN_PASS}
      AWX_ALLOWED_HOSTS: "*"
    ports:
      - "127.0.0.1:${AWX_WEB_PORT_INTERNAL}:8052"
    volumes:
      - ./awx_projects:/var/lib/awx/projects
EOF

# Bring up AWX stack
( cd "$AWX_DIR" && sudo docker compose up -d )

### ===== Nginx TLS (self-signed) and proxy for GitLab & AWX =====
say "Configuring Nginx TLS reverse proxy…"
sudo mkdir -p /etc/nginx/selfsigned
if [[ ! -f /etc/nginx/selfsigned/privkey.key ]]; then
  sudo openssl req -x509 -nodes -newkey rsa:4096 -days 365 \
    -keyout /etc/nginx/selfsigned/privkey.key \
    -out /etc/nginx/selfsigned/fullchain.crt \
    -subj "/CN=${TLS_CN}" >/dev/null 2>&1
fi

# GitLab proxy :4443 -> 127.0.0.1:${GITLAB_HTTP_BACKEND_PORT}
sudo tee /etc/nginx/sites-available/gitlab_proxy.conf >/dev/null <<EOF
server {
    listen ${GITLAB_TLS_PORT} ssl;
    server_name _;

    ssl_certificate     /etc/nginx/selfsigned/fullchain.crt;
    ssl_certificate_key /etc/nginx/selfsigned/privkey.key;

    location / {
        proxy_pass http://127.0.0.1:${GITLAB_HTTP_BACKEND_PORT};
        proxy_set_header Host              \$host:\$server_port;
        proxy_set_header X-Forwarded-Host  \$host:\$server_port;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Ssl   on;
        proxy_set_header X-Forwarded-Port  \$server_port;
        client_max_body_size 0;
        proxy_read_timeout 300s;
    }
}
EOF

# AWX proxy :4446 -> 127.0.0.1:${AWX_WEB_PORT_INTERNAL}
sudo tee /etc/nginx/sites-available/awx_proxy.conf >/dev/null <<EOF
server {
    listen ${AWX_TLS_PORT} ssl;
    server_name _;

    ssl_certificate     /etc/nginx/selfsigned/fullchain.crt;
    ssl_certificate_key /etc/nginx/selfsigned/privkey.key;

    location / {
        proxy_pass http://127.0.0.1:${AWX_WEB_PORT_INTERNAL};
        proxy_set_header Host \$host:\$server_port;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

# Enable Nginx sites
sudo ln -sf /etc/nginx/sites-available/gitlab_proxy.conf   /etc/nginx/sites-enabled/gitlab_proxy.conf
sudo ln -sf /etc/nginx/sites-available/awx_proxy.conf      /etc/nginx/sites-enabled/awx_proxy.conf
sudo ln -sf /etc/nginx/sites-available/phpmyadmin.conf     /etc/nginx/sites-enabled/phpmyadmin.conf
sudo ln -sf /etc/nginx/sites-available/data-viewer.conf    /etc/nginx/sites-enabled/data-viewer.conf
# default site can stay or be disabled:
sudo rm -f /etc/nginx/sites-enabled/default || true

sudo nginx -t
sudo systemctl enable --now nginx

### ===== Firewall (optional: open TLS ports) =====
if need ufw; then
  sudo ufw allow "${GITLAB_TLS_PORT}/tcp" || true
  sudo ufw allow "${PHPMYADMIN_TLS_PORT}/tcp" || true
  sudo ufw allow "${DATAVIEWER_TLS_PORT}/tcp" || true
  sudo ufw allow "${AWX_TLS_PORT}/tcp" || true
fi

### ===== Wait for services and show credentials =====
say "Waiting for GitLab web to respond on https://${HOST_IP}:${GITLAB_TLS_PORT}…"
for _ in {1..120}; do
  if curl -skf "https://${HOST_IP}:${GITLAB_TLS_PORT}/users/sign_in" >/dev/null 2>&1; then
    say "GitLab is up."
    break
  fi
  sleep 3
done

# Read GitLab initial root password (best-effort)
GITLAB_INITIAL_PW="(not yet available)"
if [[ -f /etc/gitlab/initial_root_password ]]; then
  GITLAB_INITIAL_PW="$(grep 'Password:' /etc/gitlab/initial_root_password | awk '{print $2}')" || true
fi
[[ -z "${GITLAB_INITIAL_PW}" ]] && GITLAB_INITIAL_PW="(expired or not found; set via: sudo gitlab-rake \"gitlab:password:reset[root]\")"

say "Done! Endpoints (self-signed TLS; accept the warning):"
cat <<EOF

GitLab:
  URL:  https://${HOST_IP}:${GITLAB_TLS_PORT}
  Initial root password: ${GITLAB_INITIAL_PW}

phpMyAdmin:
  URL:  https://${HOST_IP}:${PHPMYADMIN_TLS_PORT}
  Login: root / ${MYSQL_ROOT_PASSWORD}
  (Remote root is enabled; MySQL listening 0.0.0.0:3306)

Data Viewer:
  URL:  https://${HOST_IP}:${DATAVIEWER_TLS_PORT}
  After first open, visit /init once to create demo table.

AWX:
  URL:  https://${HOST_IP}:${AWX_TLS_PORT}
  Login: ${AWX_ADMIN_USER} / ${AWX_ADMIN_PASS}

Files/dirs:
  AWX docker-compose:   ${AWX_DIR}
  Data viewer app:      ${DATAVIEWER_DIR}
  Nginx sites:          /etc/nginx/sites-available/*.conf
  GitLab config:        /etc/gitlab/gitlab.rb
  phpMyAdmin root:      /usr/share/phpmyadmin
EOF
