#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Optional Hurricane Electric (HE) 6in4 setup
# Goal: if the VPS does not have a native routed /64, offer to configure HE tunnel
# This step is safe to run multiple times; it will overwrite the systemd unit/env if needed.

prompt_yes_no() {
  local prompt="$1" default="$2" ans
  echo -n "$prompt [$default]: "
  read -r ans || true
  ans="${ans:-$default}"
  [[ "$ans" =~ ^[Yy]$ ]]
}

# Detect if a global prefix likely exists (heuristic)
interface_default="$(ip -6 route show default 2>/dev/null | awk '/^default/ {for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}')"
route_prefix=""
if [[ -n "${interface_default:-}" ]]; then
  route_prefix="$(ip -6 route show dev "$interface_default" 2>/dev/null | awk '/proto (ra|kernel)/ && $1 ~ /\/[0-9]+/ && $1 !~ /^fe80:/ && $1 !~ /^fc/ && $1 !~ /^fd/ && $1 !~ /^ff/ {print $1; exit}')"
fi

log_info "Configuration optionnelle du tunnel Hurricane Electric (6in4)"

# Ask if user already has a native /64 routed
use_native=false
if [[ -n "${route_prefix:-}" ]]; then
  if prompt_yes_no "Un préfixe IPv6 global a été détecté ($route_prefix). Utiliser ce /64 natif ?" "Y"; then
    use_native=true
  fi
else
  if prompt_yes_no "Votre VPS a-t-il un /64 IPv6 routé nativement ?" "n"; then
    use_native=true
  fi
fi

if $use_native; then
  log_info "Mode IPv6: natif (/64 du provider). Aucune configuration HE."
  set_env_var BOXION_HE_ENABLED 0
  # Ne pas forcer la base ici; l'étape 20-network la détectera.
  exit 0
fi

# Propose HE 6in4
if ! prompt_yes_no "Souhaitez-vous configurer un tunnel Hurricane Electric (6in4) maintenant ?" "Y"; then
  log_warning "Aucun /64 configuré. Vous pouvez relancer plus tard avec BOXION_IPV6_PREFIX_BASE=... ou re-exécuter l'installeur."
  exit 0
fi

log_info "Si vous n'avez pas encore de tunnel: créez-le sur https://tunnelbroker.net/ (choisir le POP le plus proche)."

# Collect HE parameters
# Local IPv4 autodetection
MY_V4="$(ip -4 route get 1.1.1.1 2>/dev/null | awk 'NR==1{for(i=1;i<=NF;i++){if($i=="src"){print $(i+1); exit}}}')"
MY_V4="${MY_V4:-$(hostname -I | awk '{print $1}') }"
read -r -p "IPv4 publique locale (endpoint) [$MY_V4]: " inp; MY_V4="${inp:-$MY_V4}"

read -r -p "HE Server IPv4 (depuis TunnelBroker, ex: 216.66.80.98): " HE_SERVER_V4
while [[ -z "$HE_SERVER_V4" ]]; do read -r -p "HE Server IPv4: " HE_SERVER_V4; done

read -r -p "IPv6 client P2P du tunnel (ex: 2001:470:xxxx:yyyy::2/64): " HE_TUN_CLIENT6
while [[ -z "$HE_TUN_CLIENT6" ]]; do read -r -p "IPv6 client P2P (/64): " HE_TUN_CLIENT6; done

# Derive server side from client if possible
HE_TUN_SERVER6=""
base_no_pref="${HE_TUN_CLIENT6%%/*}"
if [[ "$base_no_pref" == *"::"* ]]; then
  HE_TUN_SERVER6="${base_no_pref%::*}::1"
fi
read -r -p "IPv6 serveur P2P [$HE_TUN_SERVER6]: " inp; HE_TUN_SERVER6="${inp:-$HE_TUN_SERVER6}"

read -r -p "Routed /64 fourni par HE (ex: 2001:470:zzzz::/64): " HE_ROUTED64
while [[ -z "$HE_ROUTED64" ]]; do read -r -p "Routed /64: " HE_ROUTED64; done

# Default route via HE?
USE_HE_DEFAULT_ROUTE=false
if prompt_yes_no "Utiliser HE comme route IPv6 par défaut ?" "n"; then
  USE_HE_DEFAULT_ROUTE=true
fi

HE_TUN_MTU="1480"
read -r -p "MTU du tunnel [1480]: " inp; HE_TUN_MTU="${inp:-$HE_TUN_MTU}"

# Sanitize inputs
# - Ensure client is in form <ip>/64
# - Ensure server is a bare IPv6 address without prefix
client_no_pref="${HE_TUN_CLIENT6%%/*}"
HE_TUN_CLIENT6="${client_no_pref}/64"
srv_no_pref="${HE_TUN_SERVER6%%/*}"
HE_TUN_SERVER6="${srv_no_pref}"

# Persist environment for service
ensure_dir /etc/boxion
cat > /etc/boxion/he6in4.env <<EOF
MY_V4=$MY_V4
HE_SERVER_V4=$HE_SERVER_V4
HE_TUN_CLIENT6=$HE_TUN_CLIENT6
HE_TUN_SERVER6=$HE_TUN_SERVER6
HE_TUN_MTU=$HE_TUN_MTU
HE_ROUTED64=$HE_ROUTED64
USE_HE_DEFAULT_ROUTE=$([[ $USE_HE_DEFAULT_ROUTE == true ]] && echo 1 || echo 0)
EOF

# Create systemd unit
cat > /etc/systemd/system/he6in4.service <<'EOF'
[Unit]
Description=HE 6in4 tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
EnvironmentFile=/etc/boxion/he6in4.env
ExecStart=/bin/sh -c 'modprobe sit; ip tunnel add he-ipv6 mode sit remote "$HE_SERVER_V4" local "$MY_V4" ttl 255 || true; ip link set he-ipv6 mtu "$HE_TUN_MTU" up; ip -6 addr add "$HE_TUN_CLIENT6" dev he-ipv6 || true; if command -v iptables >/dev/null 2>&1; then iptables -C INPUT -p 41 -j ACCEPT 2>/dev/null || iptables -I INPUT -p 41 -j ACCEPT; fi; if [ "$USE_HE_DEFAULT_ROUTE" = "1" ]; then ip -6 route replace default via "$HE_TUN_SERVER6" dev he-ipv6 metric 10; fi'
ExecStop=/bin/sh -c 'ip -6 route del default dev he-ipv6 2>/dev/null || true; ip link set he-ipv6 down 2>/dev/null || true; ip tunnel del he-ipv6 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now he6in4 >/dev/null 2>&1 || true

# Best-effort local firewall (INPUT proto 41). Many systems have ACCEPT by default; if not, this helps.
if command -v iptables >/dev/null 2>&1; then
  if ! iptables -C INPUT -p 41 -j ACCEPT >/dev/null 2>&1; then
    iptables -I INPUT -p 41 -j ACCEPT || true
  fi
fi

# Set env for next steps (20-network will respect this override)
trim_routed="${HE_ROUTED64%/*}"; trim_routed="${trim_routed%%::}"
set_env_var BOXION_HE_ENABLED 1
set_env_var BOXION_SKIP_NDPD 1
set_env_var IPV6_PREFIX_BASE "${trim_routed}::"

log_success "Tunnel HE configuré. Préfixe pour Boxion: ${trim_routed}::/64"
log_info "Vérification rapide: ping6 -c1 $HE_TUN_SERVER6"
