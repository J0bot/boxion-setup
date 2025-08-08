#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

WG_CONF="/etc/wireguard/wg0.conf"
API_DIR="/var/www/boxion-api"

interface="$(get_env_var INTERFACE)"
prefix_base="$(get_env_var IPV6_PREFIX_BASE)"
if [[ -z "${interface:-}" || -z "${prefix_base:-}" ]]; then
  log_error "Variables réseau manquantes (INTERFACE/IPV6_PREFIX_BASE)"; exit 1
fi
trim="${prefix_base%%::}"
SERVER_WG_ADDRESS="$trim::1/64"

log_info "Génération des clés WireGuard..."
server_private_key="$(wg genkey)"
server_public_key="$(echo "$server_private_key" | wg pubkey)"
set_env_var SERVER_PUBLIC_KEY "$server_public_key"

sed -e "s|\${SERVER_WG_ADDRESS}|$SERVER_WG_ADDRESS|g" \
    -e "s|\${INTERFACE}|$interface|g" \
    -e "s|\${SERVER_PRIVATE_KEY}|$server_private_key|g" \
    "$REPO_DIR/server/wireguard/wg0.conf.tmpl" > "$WG_CONF"

chmod 600 "$WG_CONF"
systemctl enable wg-quick@wg0 >/dev/null 2>&1 || true
systemctl restart wg-quick@wg0

log_success "WireGuard configuré (clé publique: ${server_public_key:0:20}...)"
