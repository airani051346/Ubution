#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
need_root

AWX_HOST="awx.${DOMAIN}"
AWX_NS="awx"
AWX_NODEPORT=30090
AWX_OP_DIR="/opt/awx-operator"
K3S_KUBECONFIG="/etc/rancher/k3s/k3s.yaml"

install_k3s(){
  if systemctl is-active --quiet k3s; then log "k3s already installed"; return; fi
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik" sh -
  systemctl enable --now k3s
}

log "Installing AWX via AWX Operator..."
install_k3s
export KUBECONFIG="${K3S_KUBECONFIG}"

mkdir -p "$AWX_OP_DIR"
cd "$AWX_OP_DIR"

# Get latest operator release
TAG="$(curl -fsSL https://api.github.com/repos/ansible/awx-operator/releases/latest | jq -r .tag_name 2>/dev/null || true)"
[[ -n "${TAG:-}" && "$TAG" != "null" ]] || TAG="2.7.2"
log "Using AWX Operator tag ${TAG}"

# Base kustomization.yaml
cat > kustomization.yaml <<YAML
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - github.com/ansible/awx-operator/config/default?ref=${TAG}
images:
  - name: quay.io/ansible/awx-operator
    newTag: ${TAG}
namespace: ${AWX_NS}
YAML

kubectl create namespace "${AWX_NS}" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -k .
kubectl -n "${AWX_NS}" rollout status deploy/awx-operator-controller-manager --timeout=300s || true

# AWX manifest
cat > "${AWX_OP_DIR}/awx.yml" <<YAML
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx
spec:
  service_type: NodePort
  nodeport_port: ${AWX_NODEPORT}
YAML

if ! grep -q "awx.yml" kustomization.yaml; then
  printf "\nresources:\n  - awx.yml\n" >> kustomization.yaml
fi

kubectl apply -k .
kubectl -n "${AWX_NS}" wait --for=condition=available deploy/awx --timeout=900s || true

# Nginx proxy with SSL
gen_cert "$AWX_HOST" "${CERT_DIR}/awx.crt" "${KEY_DIR}/awx.key"
cat > "${NGINX_SITES}/awx.conf" <<EOF
server { listen 80; server_name ${AWX_HOST}; return 301 https://\$host\$request_uri; }
server {
  listen 443 ssl http2;
  server_name ${AWX_HOST};
  ssl_certificate ${CERT_DIR}/awx.crt;
  ssl_certificate_key ${KEY_DIR}/awx.key;

  client_max_body_size 0;
  proxy_read_timeout 3600;
  proxy_http_version 1.1;

  location /websocket {
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_pass http://127.0.0.1:${AWX_NODEPORT};
  }
  location / {
    proxy_set_header Host              \$host;
    proxy_set_header X-Real-IP         \$remote_addr;
    proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_pass http://127.0.0.1:${AWX_NODEPORT};
  }
}
EOF

ln -sf "${NGINX_SITES}/awx.conf" "${NGINX_ENABLED}/awx.conf"
nginx_reload

log "AWX installed and proxied."
echo "URL: https://${AWX_HOST}"
echo "Admin password (run on host):"
echo "  KUBECONFIG=${K3S_KUBECONFIG} kubectl -n ${AWX_NS} get secret awx-admin-password -o jsonpath='{.data.password}' | base64 --decode"
