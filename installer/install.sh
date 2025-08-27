#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_root

BOXION_DOMAIN="${BOXION_DOMAIN:-}"
BOXION_LE_EMAIL="${BOXION_LE_EMAIL:-}"

# Avoid pager interference in scripts
export SYSTEMD_PAGER=cat
export PAGER=cat

# Parse minimal flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) BOXION_DOMAIN="$2"; shift 2;;
    --email) BOXION_LE_EMAIL="$2"; shift 2;;
    *) shift;;
  esac
done

export REPO_DIR BOXION_DOMAIN BOXION_LE_EMAIL

log_info "Démarrage installation modulaire Boxion"

STEPS=(
  "00-prereqs.sh"
  "10-packages.sh"
  "15-he-tunnel.sh"
  "20-network.sh"
  "30-wireguard.sh"
  "40-database.sh"
  "50-api.sh"
  "60-nginx.sh"
  "65-tls.sh"
  "70-dashboard.sh"
)

for step in "${STEPS[@]}"; do
  log_info "Exécution étape: $step"
  bash "$SCRIPT_DIR/steps/$step"
  log_success "Étape terminée: $step"
  echo ""
done

# Affichage infos
IPV4_ADDR="$(hostname -I | awk '{print $1}')"
if [[ -n "${BOXION_DOMAIN:-}" ]]; then
  API_URL="https://${BOXION_DOMAIN}/api/"
  DASH_URL="https://${BOXION_DOMAIN}/"
else
  API_URL="http://${IPV4_ADDR}/api/"
  DASH_URL="http://${IPV4_ADDR}/"
fi

log_success "Installation terminée"
log_info "API: $API_URL"
log_info "Dashboard: $DASH_URL"

API_TOKEN_VAL="$(get_env_var API_TOKEN || true)"
if [[ -n "${API_TOKEN_VAL:-}" ]]; then
  log_warning "Token API (secret): $API_TOKEN_VAL"
fi

if [[ -f /etc/boxion/admin-password.txt ]]; then
  log_warning "Admin (Basic Auth): admin: $(cat /etc/boxion/admin-password.txt)"
fi
