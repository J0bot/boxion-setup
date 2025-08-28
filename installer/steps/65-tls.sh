#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

if [[ -z "${BOXION_DOMAIN:-}" || -z "${BOXION_LE_EMAIL:-}" ]]; then
  log_warning "TLS ignoré (BOXION_DOMAIN ou BOXION_LE_EMAIL manquant)"
  exit 0
fi

log_info "Vérification DNS AAAA pour ${BOXION_DOMAIN}..."
# Collect local IPv6 (global) without prefix
mapfile -t LOCAL_V6 < <(ip -6 addr show scope global 2>/dev/null | awk '/inet6 /{print $2}' | sed 's|/.*||' | sort -u)

# Resolve domain AAAA via getent (no dependency on dig)
mapfile -t DNS_V6 < <(getent ahosts "$BOXION_DOMAIN" 2>/dev/null | awk '{print $1}' | awk '/:/' | sort -u)

if [[ ${#DNS_V6[@]} -eq 0 ]]; then
  log_warning "Aucun AAAA résolu pour ${BOXION_DOMAIN}. TLS reporté."
  exit 0
fi

match=false
for ip in "${DNS_V6[@]}"; do
  for lip in "${LOCAL_V6[@]}"; do
    if [[ "$ip" == "$lip" ]]; then match=true; break 2; fi
  done
done

if [[ "$match" != true ]]; then
  log_warning "Le AAAA de ${BOXION_DOMAIN} (${DNS_V6[*]}) ne pointe pas sur cette machine (${LOCAL_V6[*]}). TLS reporté."
  exit 0
fi

log_info "Obtention certificat Let's Encrypt pour $BOXION_DOMAIN"
if certbot --nginx -d "$BOXION_DOMAIN" -m "$BOXION_LE_EMAIL" --agree-tos --redirect --non-interactive; then
  log_success "TLS activé pour $BOXION_DOMAIN"
else
  log_warning "Échec certbot; vérifier DNS et accès HTTP"
fi
