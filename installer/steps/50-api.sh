#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

API_DIR="/var/www/boxion-api"
ensure_dir "$API_DIR/api"
ensure_dir "$API_DIR/admin"

log_info "Déploiement des fichiers API..."
install -m 0644 "$REPO_DIR/server/api/index.php" "$API_DIR/api/index.php"
install -m 0644 "$REPO_DIR/server/admin/index.php" "$API_DIR/admin/index.php"
install -m 0644 "$REPO_DIR/server/web/index.html" "$API_DIR/index.html"
install -m 0644 "$REPO_DIR/server/admin/status.php" "$API_DIR/admin/status.php"
install -m 0644 "$REPO_DIR/server/admin/probe.php" "$API_DIR/admin/probe.php"

# Helper root pour appliquer les peers WG (idempotent + runtime)
cat > /usr/local/sbin/boxion-wg-apply <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

WG_IF="wg0"
WG_CONF="/etc/wireguard/wg0.conf"
LOCK_FILE="/run/boxion-wg.lock"

usage() { echo "Usage: $0 add-peer <pubkey> <ipv6/128>" >&2; }

cmd="${1:-}"; shift || true
case "$cmd" in
  add-peer)
    pubkey="${1:-}"; ipv6="${2:-}"
    if [[ -z "$pubkey" || -z "$ipv6" ]]; then usage; exit 2; fi
    if ! [[ "$pubkey" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then echo "Invalid pubkey" >&2; exit 2; fi
    if ! echo "$ipv6" | grep -Eq '^[0-9a-fA-F:]+/128$'; then echo "Invalid IPv6" >&2; exit 2; fi

    # Lock to avoid concurrent writes
    exec 9>"$LOCK_FILE" || true
    flock 9 || true

    # Ensure interface is up
    if ! ip link show "$WG_IF" >/dev/null 2>&1; then
      systemctl start "wg-quick@${WG_IF}" >/dev/null 2>&1 || true
    fi

    # Apply to runtime (creates peer if missing, updates allowed-ips otherwise)
    wg set "$WG_IF" peer "$pubkey" allowed-ips "$ipv6"

    # Persist in config if not already present
    umask 077
    if ! grep -q "^PublicKey = ${pubkey}$" "$WG_CONF" 2>/dev/null; then
      {
        printf "\n[Peer]\n"
        printf "PublicKey = %s\n" "$pubkey"
        printf "AllowedIPs = %s\n" "$ipv6"
      } >> "$WG_CONF"
    fi
    ;;
  *) usage; exit 2;;
esac
EOF
chmod 750 /usr/local/sbin/boxion-wg-apply
chown root:root /usr/local/sbin/boxion-wg-apply

echo "www-data ALL=(root) NOPASSWD: /usr/local/sbin/boxion-wg-apply" > /etc/sudoers.d/boxion-wg
chmod 440 /etc/sudoers.d/boxion-wg

# Helper root de diagnostic (lecture seule)
cat > /usr/local/sbin/boxion-diag <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

section(){ echo "=== $1 ==="; }

# Charger env
declare -A ENV
if [[ -f /etc/boxion/boxion.env ]]; then
  while IFS='=' read -r k v; do
    [[ -z "${k:-}" || "${k:0:1}" == "#" ]] && continue
    ENV[$k]="${v}"
  done < /etc/boxion/boxion.env
fi
iface="${ENV[INTERFACE]:-$(ip route get 8.8.8.8 2>/dev/null | awk 'NR==1{print $5}') }"
prefix="${ENV[IPV6_PREFIX_BASE]:-}"

section SYSTEM
uname -a || true
echo

section ENV
echo "INTERFACE=$iface"
echo "IPV6_PREFIX_BASE=$prefix"
echo

section SYSCTL
sysctl net.ipv6.conf.all.forwarding net.ipv6.conf.all.proxy_ndp "net.ipv6.conf.${iface}.proxy_ndp" 2>/dev/null || true
echo

section ADDRESSES
ip -6 addr show dev "$iface" || true
ip -6 addr show dev wg0 || true
echo

section ROUTES
ip -6 route show || true
echo

section "NDP PROXY"
ip -6 neigh show proxy dev "$iface" 2>/dev/null || true
systemctl is-active ndppd || true
journalctl -u ndppd -n 20 --no-pager 2>/dev/null || true
echo

section WIREGUARD
wg show 2>/dev/null || true
echo

section "FIREWALL (ip6tables FORWARD)"
ip6tables -S FORWARD 2>/dev/null || true
if command -v nft >/dev/null 2>&1; then
  echo
  echo "--- nftables (summary) ---"
  nft list ruleset 2>/dev/null | sed -n '1,200p' || true
fi
echo

section NGINX
nginx -t 2>&1 || true
ls -l /etc/nginx/sites-enabled/boxion-api 2>/dev/null || true
echo

section API
printf "PHP-FPM: "; php-fpm -v 2>/dev/null | head -n1 || true
ls -l /var/www/boxion-api 2>/dev/null || true
echo

section "PING6/CURL"
ping6 -c 1 -w 3 google.com 2>&1 || true
curl -6 -I -m 5 https://ipv6.google.com 2>&1 || true
EOF
chmod 750 /usr/local/sbin/boxion-diag
chown root:root /usr/local/sbin/boxion-diag

echo "www-data ALL=(root) NOPASSWD: /usr/local/sbin/boxion-diag" > /etc/sudoers.d/boxion-diag
chmod 440 /etc/sudoers.d/boxion-diag

# Token API
api_token_current="$(get_env_var API_TOKEN || true)"
if [[ -z "${api_token_current:-}" ]]; then
  api_token="$(openssl rand -hex 32)"
  set_env_var API_TOKEN "$api_token"
fi
set_env_var ENDPOINT_PORT 51820

chown -R www-data:www-data "$API_DIR"

log_success "API déployée"
