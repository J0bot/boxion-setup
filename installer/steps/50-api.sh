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

# Token API
api_token_current="$(get_env_var API_TOKEN || true)"
if [[ -z "${api_token_current:-}" ]]; then
  api_token="$(openssl rand -hex 32)"
  set_env_var API_TOKEN "$api_token"
fi
set_env_var ENDPOINT_PORT 51820

chown -R www-data:www-data "$API_DIR"

log_success "API déployée"
