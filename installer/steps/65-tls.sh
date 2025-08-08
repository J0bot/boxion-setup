#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

if [[ -z "${BOXION_DOMAIN:-}" || -z "${BOXION_LE_EMAIL:-}" ]]; then
  log_warning "TLS ignoré (BOXION_DOMAIN ou BOXION_LE_EMAIL manquant)"
  exit 0
fi

log_info "Obtention certificat Let's Encrypt pour $BOXION_DOMAIN"
if certbot --nginx -d "$BOXION_DOMAIN" -m "$BOXION_LE_EMAIL" --agree-tos --redirect --non-interactive; then
  log_success "TLS activé pour $BOXION_DOMAIN"
else
  log_warning "Échec certbot; vérifier DNS et accès HTTP"
fi
