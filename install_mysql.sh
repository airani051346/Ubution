#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
need_root

ROOT_PASS="${1:-rootpass123!}"
MYSQL_SSL_DIR="/etc/mysql/ssl"

log "Installing MySQL..."
apt-get update -y
ensure_pkg mysql-server

mkdir -p "$MYSQL_SSL_DIR"; chmod 700 "$MYSQL_SSL_DIR"

# Generate CA + server cert
if [[ ! -s "$MYSQL_SSL_DIR/ca.pem" ]]; then
  openssl genrsa -out "$MYSQL_SSL_DIR/ca-key.pem" 4096
  openssl req -x509 -new -nodes -key "$MYSQL_SSL_DIR/ca-key.pem" -days 1825 \
    -out "$MYSQL_SSL_DIR/ca.pem" -subj "/CN=Homelab MySQL CA"
  openssl genrsa -out "$MYSQL_SSL_DIR/server-key.pem" 4096
  openssl req -new -key "$MYSQL_SSL_DIR/server-key.pem" -out "$MYSQL_SSL_DIR/server.csr" -subj "/CN=$(hostname -f)"
  cat > "$MYSQL_SSL_DIR/server-ext.cnf" <<EOF
subjectAltName=DNS:$(hostname -f),IP:${SERVER_IP}
extendedKeyUsage=serverAuth
EOF
  openssl x509 -req -in "$MYSQL_SSL_DIR/server.csr" -CA "$MYSQL_SSL_DIR/ca.pem" -CAkey "$MYSQL_SSL_DIR/ca-key.pem" \
    -CAcreateserial -out "$MYSQL_SSL_DIR/server-cert.pem" -days 825 -sha256 -extfile "$MYSQL_SSL_DIR/server-ext.cnf"
fi

# Fix ownership/permissions
chown mysql:mysql "$MYSQL_SSL_DIR"/{server-cert.pem,server-key.pem,ca.pem}
chmod 644 "$MYSQL_SSL_DIR"/{server-cert.pem,ca.pem}
chmod 600 "$MYSQL_SSL_DIR"/server-key.pem

# Configure MySQL
cat > /etc/mysql/mysql.conf.d/zz-homelab.cnf <<EOF
[mysqld]
bind-address = 0.0.0.0
ssl-ca   = ${MYSQL_SSL_DIR}/ca.pem
ssl-cert = ${MYSQL_SSL_DIR}/server-cert.pem
ssl-key  = ${MYSQL_SSL_DIR}/server-key.pem
EOF

systemctl restart mysql

mysql --protocol=socket -uroot <<SQL || true
ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${ROOT_PASS}';
CREATE USER IF NOT EXISTS 'admin'@'%' IDENTIFIED BY '${ROOT_PASS}';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%' WITH GRANT OPTION;
ALTER USER 'admin'@'%' REQUIRE SSL;
FLUSH PRIVILEGES;
SQL

log "MySQL ready."
echo "Root password: ${ROOT_PASS}"
echo "Admin user: admin / ${ROOT_PASS} (SSL required)"
