#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

log_info "Détection interface et préfixe IPv6..."
# 1) Permettre forçage par variable d'env
interface="${BOXION_INTERFACE:-}"
if [[ -z "$interface" ]]; then
  # 2) Tenter avec la route IPv6 par défaut
  interface="$(ip -6 route show default 2>/dev/null | awk '/^default/ {for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}')"
fi
if [[ -z "$interface" ]]; then
  # 3) Fallback: même interface que la route IPv4
  interface="$(ip route get 8.8.8.8 | awk 'NR==1 {print $5}')"
fi
if [[ -z "$interface" ]]; then
  log_error "Impossible de détecter une interface réseau"; exit 1
fi

# Chercher un /64 appris (RA) ou kernel sur cette interface
route_prefix="$(ip -6 route show dev "$interface" 2>/dev/null | awk '/proto (ra|kernel)/ && $1 ~ /\/[0-9]+/ {print $1; exit}')"
if [[ -z "$route_prefix" ]]; then
  route_prefix="$(ip -6 route show dev "$interface" 2>/dev/null | awk '$1 ~ /\/[0-9]+/ {print $1; exit}')"
fi
if [[ -z "$route_prefix" ]]; then
  # Dernier recours: n'importe quel /64 global présent
  route_prefix="$(ip -6 route show 2>/dev/null | awk '/proto (ra|kernel)/ && $1 ~ /::\/[0-9]+/ {print $1; exit}')"
fi
if [[ -z "$route_prefix" ]]; then
  log_error "Impossible de détecter un préfixe IPv6 (interface: $interface)"; exit 1
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
