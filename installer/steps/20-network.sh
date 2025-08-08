#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

log_info "Détection interface et préfixe IPv6..."
interface="$(ip route get 8.8.8.8 | awk 'NR==1 {print $5}')"
route_prefix="$(ip -6 route show dev "$interface" | awk '/proto kernel/ && $1 ~ /\/[0-9]+/ {print $1; exit}')"
if [[ -z "$route_prefix" ]]; then
  route_prefix="$(ip -6 route show dev "$interface" | awk '/\/[0-9]+/ {print $1; exit}')"
fi
if [[ -z "$route_prefix" ]]; then
  log_error "Impossible de détecter un préfixe IPv6 sur $interface"; exit 1
fi
prefix_base="${route_prefix%/*}"
# Trim trailing '::'
prefix_trim="${prefix_base%%::}"
IPV6_PREFIX_BASE="$prefix_trim::"

set_env_var INTERFACE "$interface"
set_env_var IPV6_PREFIX_BASE "$IPV6_PREFIX_BASE"

log_info "Écriture sysctl..."
sed "s|\${INTERFACE}|$interface|g" "$REPO_DIR/server/system/sysctl.d/99-boxion.conf" > /etc/sysctl.d/99-boxion.conf
sysctl -p /etc/sysctl.d/99-boxion.conf || true

log_info "Écriture ndppd.conf..."
sed -e "s|\${INTERFACE}|$interface|g" \
    -e "s|\${IPV6_PREFIX_BASE_TRIM}|$prefix_trim|g" \
    "$REPO_DIR/server/system/ndppd.conf.tmpl" > /etc/ndppd.conf
systemctl enable ndppd >/dev/null 2>&1 || true
systemctl restart ndppd || true

log_success "Réseau IPv6 configuré (proxy NDP)"
