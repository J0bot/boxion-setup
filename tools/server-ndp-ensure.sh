#!/usr/bin/env bash
set -euo pipefail
# Ensure NDP proxy is active so external hosts can reach client IPv6s in the /64
# - Detect upstream interface
# - Ensure sysctls (forwarding + proxy_ndp)
# - Create /etc/ndppd.conf to proxy ${PREFIX} on the upstream interface
# - Enable & restart ndppd
# Idempotent; run as root.

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

# Derive prefix from wg0 Address
WGCONF="/etc/wireguard/wg0.conf"
if [[ ! -f "$WGCONF" ]]; then
  echo "WireGuard config not found: $WGCONF" >&2
  exit 1
fi
ADDR=$(grep -E '^\s*Address\s*=\s*' "$WGCONF" | head -n1 | awk -F= '{print $2}' | tr -d ' ' | cut -d, -f1)
if [[ -z "$ADDR" ]]; then
  echo "Failed to parse Address= from $WGCONF" >&2
  exit 1
fi
BASE_V6=${ADDR%%/*}
BASE_TRIM=${BASE_V6%::*}
PREFIX="${BASE_TRIM}::/64"

# Detect external interface (first default v6 route dev)
EXT_IF=$(ip -6 route show default 2>/dev/null | awk '/default/ {print $5; exit}')
if [[ -z "${EXT_IF:-}" ]]; then
  # Fallback: pick first non-loopback with a global v6
  EXT_IF=$(ip -6 -o addr show scope global | awk '{print $2}' | head -n1 || true)
fi
if [[ -z "${EXT_IF:-}" ]]; then
  echo "Cannot detect upstream interface (default v6 route)." >&2
  exit 1
fi

# Sysctls
sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null
sysctl -w net.ipv6.conf.all.proxy_ndp=1 >/dev/null
sysctl -w net.ipv6.conf.${EXT_IF}.proxy_ndp=1 >/dev/null || true

# Persist sysctls
SYSCTL_FILE="/etc/sysctl.d/99-boxion-ipv6.conf"
cat >"$SYSCTL_FILE" <<EOF
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.all.proxy_ndp=1
net.ipv6.conf.${EXT_IF}.proxy_ndp=1
EOF
sysctl --system >/dev/null || true

# ndppd install
if ! command -v ndppd >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq && apt-get install -y ndppd >/dev/null
fi

# ndppd config
mkdir -p /etc
cat >/etc/ndppd.conf <<EOF
proxy ${EXT_IF} {
    rule ${BASE_TRIM}::/64 {
        auto
    }
}
EOF

systemctl enable ndppd >/dev/null 2>&1 || true
systemctl restart ndppd || true

# Helpful info
echo "Upstream IF: $EXT_IF"
echo "Proxied prefix: $PREFIX"

# Show neighbor proxy settings
ip -6 neigh show proxy || true
systemctl --no-pager -l status ndppd || true

echo "NDP proxy ensured. External IPv6 hosts should now reach addresses in $PREFIX."
