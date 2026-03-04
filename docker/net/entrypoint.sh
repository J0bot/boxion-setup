#!/usr/bin/env bash
set -euo pipefail

BOXION_ENV="/etc/boxion/boxion.env"
WG_CONF="/etc/wireguard/wg0.conf"
WG_IF="wg0"
NDPD_CONF="/etc/ndppd.conf"
TEMPLATE_DIR="/opt/boxion"

mkdir -p /etc/boxion /etc/wireguard /var/lib/boxion

get_env(){
  local key="$1"
  if [[ -f "$BOXION_ENV" ]]; then
    # shellcheck disable=SC2162
    while IFS='=' read k v; do
      [[ -z "${k:-}" || "${k:0:1}" == "#" ]] && continue
      if [[ "$k" == "$key" ]]; then echo "$v"; return 0; fi
    done < "$BOXION_ENV"
  fi
  return 1
}

set_env(){
  local key="$1" val="$2"
  touch "$BOXION_ENV"
  if grep -q "^${key}=" "$BOXION_ENV" 2>/dev/null; then
    sed -i "s|^${key}=.*$|${key}=${val}|" "$BOXION_ENV"
  else
    echo "${key}=${val}" >> "$BOXION_ENV"
  fi
}

log(){ echo "[net] $*"; }

# Detect interface if not provided
INTERFACE="${BOXION_INTERFACE:-}"
if [[ -z "$INTERFACE" ]]; then
  INTERFACE=$(ip -6 route show default 2>/dev/null | awk '/^default/ {for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}') || true
fi
if [[ -z "$INTERFACE" ]]; then
  INTERFACE=$(ip route get 8.8.8.8 2>/dev/null | awk 'NR==1{print $5}') || true
fi
if [[ -z "$INTERFACE" ]]; then
  INTERFACE="eth0"
fi
set_env INTERFACE "$INTERFACE"

# Determine IPv6 prefix base
IPV6_PREFIX_BASE="${BOXION_IPV6_PREFIX_BASE:-}"
if [[ -z "$IPV6_PREFIX_BASE" ]]; then
  # try from env file
  IPV6_PREFIX_BASE="$(get_env IPV6_PREFIX_BASE || true)"
fi
if [[ -z "$IPV6_PREFIX_BASE" ]]; then
  route_prefix=$(ip -6 route show dev "$INTERFACE" 2>/dev/null | awk '/proto (ra|kernel)/ && $1 ~ /\/[0-9]+/ && $1 !~ /^fe80:/ && $1 !~ /^fc/ && $1 !~ /^fd/ && $1 !~ /^ff/ {print $1; exit}')
  if [[ -z "$route_prefix" ]]; then
    route_prefix=$(ip -6 route show dev "$INTERFACE" 2>/dev/null | awk '$1 ~ /\/[0-9]+/ && $1 !~ /^fe80:/ && $1 !~ /^fc/ && $1 !~ /^fd/ && $1 !~ /^ff/ {print $1; exit}')
  fi
  if [[ -z "$route_prefix" ]]; then
    route_prefix=$(ip -6 addr show dev "$INTERFACE" scope global 2>/dev/null | awk '/inet6 /{print $2; exit}')
  fi
  if [[ -n "$route_prefix" ]]; then
    prefix_base="${route_prefix%/*}"
    prefix_trim="${prefix_base%%::}"
    IPV6_PREFIX_BASE="${prefix_trim}::"
  fi
fi
if [[ -z "$IPV6_PREFIX_BASE" ]]; then
  log "Aucun préfixe IPv6 détecté automatiquement. Vous pouvez définir BOXION_IPV6_PREFIX_BASE=2xxx:...::"
else
  set_env IPV6_PREFIX_BASE "$IPV6_PREFIX_BASE"
fi

# Sysctls for IPv6 forwarding and NDP proxy
sysctl -w net.ipv6.conf.all.forwarding=1 || true
sysctl -w net.ipv6.conf.all.proxy_ndp=1 || true
sysctl -w net.ipv6.conf."${INTERFACE}".proxy_ndp=1 || true

# WireGuard setup
if [[ ! -f "$WG_CONF" ]]; then
  log "Génération config WireGuard..."
  tmp_priv=$(wg genkey)
  tmp_pub=$(echo "$tmp_priv" | wg pubkey)
  set_env SERVER_PUBLIC_KEY "$tmp_pub"
  prefix_trim="${IPV6_PREFIX_BASE%%::}"
  SERVER_WG_ADDRESS="${prefix_trim}::1/64"
  sed -e "s|\${SERVER_WG_ADDRESS}|$SERVER_WG_ADDRESS|g" \
      -e "s|\${INTERFACE}|$INTERFACE|g" \
      -e "s|\${SERVER_PRIVATE_KEY}|$tmp_priv|g" \
      -e "s|\${IPV6_PREFIX_BASE_TRIM}|$prefix_trim|g" \
      "$TEMPLATE_DIR/wg0.conf.tmpl" > "$WG_CONF"
  chmod 600 "$WG_CONF"
fi

# Bring up WireGuard
if ! ip link show "$WG_IF" >/dev/null 2>&1; then
  log "Activation de wg0..."
  wg-quick up "$WG_IF"
fi

set_env ENDPOINT_PORT 51820

# ndppd configuration unless skipped
if [[ "${BOXION_SKIP_NDPD:-0}" != "1" ]]; then
  prefix_trim="${IPV6_PREFIX_BASE%%::}"
  sed -e "s|\${INTERFACE}|$INTERFACE|g" \
      -e "s|\${IPV6_PREFIX_BASE_TRIM}|$prefix_trim|g" \
      "$TEMPLATE_DIR/ndppd.conf.tmpl" > "$NDPD_CONF"
  log "Démarrage ndppd..."
  exec ndppd -d -c "$NDPD_CONF"
else
  log "ndppd désactivé (BOXION_SKIP_NDPD=1). Container en veille."
  exec tail -f /dev/null
fi
