#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

API_DIR="${BOXION_API_DIR:-/var/www/boxion-api}"
install -m 0644 "$REPO_DIR/server/web/index.html" "$API_DIR/index.html"

# S'assurer que le dossier des secrets existe
install -d -m 0755 /etc/boxion

# Générer/mettre à jour la Basic Auth si absente, sans utilisateur 'admin' ou si le mot de passe n'a pas été conservé
HT="/etc/nginx/.htpasswd-boxion"
ADMIN_PASS_FILE="/etc/boxion/admin-password.txt"
if [[ ! -f "$HT" ]] || ! grep -qE '^admin:' "$HT" 2>/dev/null || [[ ! -f "$ADMIN_PASS_FILE" ]]; then
  admin_password="$(openssl rand -base64 16)"
  ht_hash="$(openssl passwd -apr1 "$admin_password")"
  touch "$HT"
  sed -i '/^admin:/d' "$HT" 2>/dev/null || true
  echo "admin:$ht_hash" >> "$HT"
  echo "$admin_password" > "$ADMIN_PASS_FILE"
  chmod 600 "$ADMIN_PASS_FILE"
fi

# Ne pas chown le HOME de l'utilisateur
if [[ "$API_DIR" == /var/www/* ]]; then
  chown www-data:www-data "$API_DIR/index.html"
fi

systemctl reload nginx || true

log_success "Dashboard déployé (Basic Auth vérifiée)"
