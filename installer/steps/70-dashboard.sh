#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

API_DIR="${BOXION_API_DIR:-/var/www/boxion-api}"
install -m 0644 "$REPO_DIR/server/web/index.html" "$API_DIR/index.html"

# Générer Basic Auth seulement si absente
if [[ ! -f /etc/nginx/.htpasswd-boxion ]]; then
  admin_password="$(openssl rand -base64 16)"
  ht_hash="$(openssl passwd -apr1 "$admin_password")"
  echo "admin:$ht_hash" > /etc/nginx/.htpasswd-boxion
  install -d -m 0755 /etc/boxion
  echo "$admin_password" > /etc/boxion/admin-password.txt
  chmod 600 /etc/boxion/admin-password.txt
fi

# Ne pas chown le HOME de l'utilisateur
if [[ "$API_DIR" == /var/www/* ]]; then
  chown www-data:www-data "$API_DIR/index.html"
fi

systemctl reload nginx || true

log_success "Dashboard déployé (Basic Auth vérifiée)"
