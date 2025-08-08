#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_root

log_info "Vérification des prérequis..."
if ! command -v apt-get >/dev/null 2>&1; then
  log_error "apt-get requis (Debian/Ubuntu)"; exit 1
fi
if ! ip -6 addr show | grep -q "inet6.*global"; then
  log_error "Aucune IPv6 globale détectée sur ce VPS"; exit 1
fi

ensure_dir /etc/boxion
ensure_dir /var/lib/boxion
ensure_dir /var/www/boxion-api
# Répertoires et permissions
chown root:www-data /etc/boxion 2>/dev/null || true
chmod 750 /etc/boxion 2>/dev/null || true
chmod 755 /var/www/boxion-api

log_success "Prérequis OK"
