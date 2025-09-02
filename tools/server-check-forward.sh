#!/usr/bin/env bash
set -euo pipefail
# Inspect IPv6 forwarding path for Boxion (HE 6in4 + wg0)
# Usage: sudo ./tools/server-check-forward.sh

section(){ echo; echo "=== $1 ==="; }

section "SYSTEM"
uname -a || true

section "SYSCTL"
sysctl net.ipv6.conf.all.forwarding net.ipv6.conf.default.forwarding 2>/dev/null || true

section "INTERFACES"
ip -br link show | awk '{print $1, $2}'

section "ADDRESSES"
ip -6 addr show dev he-ipv6 2>/dev/null || echo "(no he-ipv6)"
ip -6 addr show dev wg0 2>/dev/null || echo "(no wg0)"

section "ROUTES"
ip -6 route show | egrep 'default|/64|/128' || true

section "WIREGUARD"
wg show 2>/dev/null || true

section "NDPPD"
systemctl is-active ndppd 2>/dev/null || true
journalctl -u ndppd -n 20 --no-pager 2>/dev/null || true

section "FIREWALL (nftables)"
if command -v nft >/dev/null 2>&1; then
  nft list ruleset 2>/dev/null | sed -n '1,200p' || true
else
  echo "nft not installed"
fi

section "FIREWALL (ip6tables)"
if command -v ip6tables >/dev/null 2>&1; then
  ip6tables -S | sed -n '1,200p' || true
else
  echo "ip6tables not installed"
fi

section "SUGGESTIONS"
cat <<'EOF'
- Ensure cloud Security Groups allow IPv4 protocol 41 (HE 6in4) inbound to the VPS IPv4.
- Ensure UDP/51820 inbound (WireGuard), and ICMPv6 inbound for PMTUD and Echo.
- Ensure route for the routed /64 points to wg0 (wg0.conf PostUp handles this).
- If nftables drops FORWARD by default, run tools/server-allow-forward.sh to allow he-ipv6<->wg0 and ICMPv6.
EOF
