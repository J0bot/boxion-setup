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

# Permettre le forçage du préfixe global (ex: 2a01:abcd:1234:5678::)
override_prefix="${BOXION_IPV6_PREFIX_BASE:-}"
# Si non fourni via l'environnement, tenter de lire depuis /etc/boxion/boxion.env
if [[ -z "$override_prefix" ]]; then
  env_override="$(get_env_var IPV6_PREFIX_BASE || true)"
  if [[ -n "${env_override:-}" ]]; then
    override_prefix="$env_override"
  fi
fi
if [[ -n "$override_prefix" ]]; then
  # Normaliser: enlever '::' final s'il existe puis réajouter '::'
  prefix_trim="${override_prefix%%::}"
  IPV6_PREFIX_BASE="$prefix_trim::"
  log_info "Préfixe IPv6 forcé: $IPV6_PREFIX_BASE"
else
  # Chercher un préfixe GLOBAL (exclure link-local fe80::/10, ULA fc00::/7, multicast ff00::/8)
  # 1) RA/kernel sur l'interface
  route_prefix="$(ip -6 route show dev "$interface" 2>/dev/null | awk '/proto (ra|kernel)/ && $1 ~ /\/[0-9]+/ && $1 !~ /^fe80:/ && $1 !~ /^fc/ && $1 !~ /^fd/ && $1 !~ /^ff/ {print $1; exit}')"
  # 2) Fallback: toute route globale sur l'interface
  if [[ -z "$route_prefix" ]]; then
    route_prefix="$(ip -6 route show dev "$interface" 2>/dev/null | awk '$1 ~ /\/[0-9]+/ && $1 !~ /^fe80:/ && $1 !~ /^fc/ && $1 !~ /^fd/ && $1 !~ /^ff/ {print $1; exit}')"
  fi
  # 3) Fallback: une adresse globale sur l'interface (inet6 scope global)
  if [[ -z "$route_prefix" ]]; then
    route_prefix="$(ip -6 addr show dev "$interface" scope global 2>/dev/null | awk '/inet6 /{print $2; exit}')"
  fi
  if [[ -z "$route_prefix" ]]; then
    log_error "Aucun préfixe IPv6 GLOBAL détecté (interface: $interface). Fournissez BOXION_IPV6_PREFIX_BASE=2xxx:yyyy:....:zzzz:: et relancez."; exit 1
  fi
  prefix_base="${route_prefix%/*}"
  # Trim trailing '::'
  prefix_trim="${prefix_base%%::}"
  IPV6_PREFIX_BASE="$prefix_trim::"
fi

set_env_var INTERFACE "$interface"
set_env_var IPV6_PREFIX_BASE "$IPV6_PREFIX_BASE"

log_info "Écriture sysctl..."
sed "s|\${INTERFACE}|$interface|g" "$REPO_DIR/server/system/sysctl.d/99-boxion.conf" > /etc/sysctl.d/99-boxion.conf
sysctl -p /etc/sysctl.d/99-boxion.conf || true

# NDP proxying: activer sauf si explicitement désactivé (HE 6in4 routed /64)
skip_ndp_val="${BOXION_SKIP_NDPD:-}"
if [[ -z "${skip_ndp_val:-}" ]]; then
  skip_ndp_val="$(get_env_var BOXION_SKIP_NDPD || true)"
fi
if [[ "${skip_ndp_val:-0}" = "1" ]]; then
  log_info "Mode HE détecté: ndppd désactivé (routed /64, pas de proxy NDP nécessaire)"
  # Assurer l'arrêt et la désactivation du service, même si installé via paquets
  systemctl disable --now ndppd >/dev/null 2>&1 || true
else
  log_info "Écriture ndppd.conf..."
  sed -e "s|\${INTERFACE}|$interface|g" \
      -e "s|\${IPV6_PREFIX_BASE_TRIM}|$prefix_trim|g" \
      "$REPO_DIR/server/system/ndppd.conf.tmpl" > /etc/ndppd.conf
  systemctl enable ndppd >/dev/null 2>&1 || true
  systemctl restart ndppd || true
fi

if [[ "${skip_ndp_val:-0}" = "1" ]]; then
  log_success "Réseau IPv6 configuré (HE 6in4)"
else
  log_success "Réseau IPv6 configuré (proxy NDP)"
fi
