#!/usr/bin/env bash
set -euo pipefail
# Persist and apply IPv6 routed-prefix preference for wg0
# - Adds PostUp/PostDown to /etc/wireguard/wg0.conf to prefer wg0 for the /64
# - Applies the route immediately
# Idempotent.

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

WGCONF="/etc/wireguard/wg0.conf"
if [[ ! -f "$WGCONF" ]]; then
  echo "WireGuard config not found: $WGCONF" >&2
  exit 1
fi

# Extract server WG IPv6 and derive prefix
WG_ADDR_LINE=$(grep -E '^\s*Address\s*=\s*' "$WGCONF" | head -n1 | cut -d= -f2- | tr -d ' ')
if [[ -z "$WG_ADDR_LINE" ]]; then
  echo "Could not find Address= in $WGCONF" >&2
  exit 1
fi
WG_ADDR_V6=${WG_ADDR_LINE%%,*}
WG_ADDR_V6=${WG_ADDR_V6%%/*}     # drop /64
BASE=${WG_ADDR_V6%::*}           # trim to base (without ::1)
PREFIX="${BASE}::/64"

# Ensure PostUp/PostDown lines exist
POSTUP="PostUp = ip -6 route replace ${PREFIX} dev %i metric 50"
POSTDOWN="PostDown = ip -6 route del ${PREFIX} dev %i || true"
if ! grep -qF "$POSTUP" "$WGCONF"; then
  echo "$POSTUP" >>"$WGCONF"
fi
if ! grep -qF "$POSTDOWN" "$WGCONF"; then
  echo "$POSTDOWN" >>"$WGCONF"
fi

# Apply route immediately
ip -6 route replace "$PREFIX" dev wg0 metric 50

# Restart wg-quick to apply PostUp rules (no-op if already correct)
systemctl restart wg-quick@wg0 || true

# Show resulting routes touching the prefix
ip -6 route | grep -E "(^| )${BASE}::/(64|128)" || true

echo "Done. ${PREFIX} now prefers wg0 (metric 50)."
