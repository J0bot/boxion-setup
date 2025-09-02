#!/usr/bin/env bash
set -euo pipefail
# Open minimal IPv6 forwarding for Boxion when nftables is active (or ip6tables fallback)
# - Allows forwarding between he-ipv6 <-> wg0 (both directions)
# - Allows ICMPv6 in INPUT (PMTUD, Echo)
# - Ensures IPv6 forwarding sysctl
# Idempotent best-effort.

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

HE_IF="${HE_IF:-}"
WG_IF="${WG_IF:-wg0}"

# Detect HE interface
if [[ -z "$HE_IF" ]]; then
  if ip link show he-ipv6 >/dev/null 2>&1; then
    HE_IF="he-ipv6"
  else
    # Fallback to default v6 route dev
    HE_IF=$(ip -6 route show default 2>/dev/null | awk '/default/ {print $5; exit}')
    HE_IF="${HE_IF:-$(ip -6 -o addr show scope global | awk '{print $2}' | head -n1)}"
  fi
fi

if [[ -z "${HE_IF:-}" || -z "${WG_IF:-}" ]]; then
  echo "Cannot detect interfaces (HE_IF=$HE_IF WG_IF=$WG_IF)" >&2
  exit 1
fi

echo "Using HE_IF=$HE_IF WG_IF=$WG_IF"

# Sysctls
sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null

if command -v nft >/dev/null 2>&1 && nft list ruleset >/dev/null 2>&1; then
  echo "Configuring nftables rules..."
  RS=$(nft list ruleset)
  add_rule(){ local rule="$1"; local grep_pat="$2"; echo "$RS" | grep -qE "$grep_pat" || nft add rule inet filter $rule; }
  # Forward allow between interfaces
  add_rule "forward iifname \"$HE_IF\" oifname \"$WG_IF\" accept" "forward .* iifname \\"$HE_IF\" .* oifname \\"$WG_IF\" .* accept"
  add_rule "forward iifname \"$WG_IF\" oifname \"$HE_IF\" accept" "forward .* iifname \\"$WG_IF\" .* oifname \\"$HE_IF\" .* accept"
  # ICMPv6 in INPUT
  add_rule "input ip6 nexthdr icmpv6 accept" "input .* ip6 .* nexthdr icmpv6 .* accept"
  echo "nftables updated."
else
  echo "Configuring ip6tables rules..."
  cmd(){ ip6tables "$@" 2>/dev/null || true; }
  # Forward rules (server wg0 PostUp already adds wg0<->any, but ensure HE_IF too)
  cmd -C FORWARD -i "$HE_IF" -o "$WG_IF" -j ACCEPT || cmd -I FORWARD -i "$HE_IF" -o "$WG_IF" -j ACCEPT
  cmd -C FORWARD -i "$WG_IF" -o "$HE_IF" -j ACCEPT || cmd -I FORWARD -i "$WG_IF" -o "$HE_IF" -j ACCEPT
  # ICMPv6 INPUT
  cmd -C INPUT -p icmpv6 -j ACCEPT || cmd -I INPUT -p icmpv6 -j ACCEPT
  echo "ip6tables updated."
fi

echo "Done. Verify with tools/server-check-forward.sh"
