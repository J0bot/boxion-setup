#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

export DEBIAN_FRONTEND=noninteractive

log_info "Mise à jour des paquets..."
apt-get update -qq

log_info "Installation des dépendances..."
apt-get install -y \
  wireguard nginx php-fpm php-sqlite3 php-json php-curl \
  sqlite3 iptables ndppd openssl curl procps \
  certbot python3-certbot-nginx jq >/dev/null

log_success "Paquets installés"

# Démarrage des services web
systemctl enable --now nginx >/dev/null 2>&1 || true

# Trouver et démarrer php-fpm (versionnée sur Debian)
php_fpm_unit="$(systemctl list-unit-files | awk '/php.*-fpm\.service/{print $1; exit}')"
if [[ -n "$php_fpm_unit" ]]; then
  systemctl enable --now "$php_fpm_unit" >/dev/null 2>&1 || true
else
  # Fallback commun
  systemctl enable --now php-fpm >/dev/null 2>&1 || true
fi
