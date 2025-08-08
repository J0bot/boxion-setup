#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

API_DIR="/var/www/boxion-api"
install -m 0644 "$REPO_DIR/server/web/index.html" "$API_DIR/index.html"

admin_password="$(openssl rand -base64 16)"
ht_hash="$(openssl passwd -apr1 "$admin_password")"
echo "admin:$ht_hash" > /etc/nginx/.htpasswd-boxion

echo "$admin_password" > /etc/boxion/admin-password.txt
chmod 600 /etc/boxion/admin-password.txt
chown www-data:www-data "$API_DIR/index.html"

systemctl reload nginx || true

log_success "Dashboard déployé (Basic Auth générée)"
