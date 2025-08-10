#!/usr/bin/env bash
set -euo pipefail
# Boxion - Diagnostic CLI (VPS)
# Usage: ./tools/diag.sh

SUDO=${SUDO:-sudo}
if [[ -x /usr/local/sbin/boxion-diag ]]; then
  exec ${SUDO} /usr/local/sbin/boxion-diag
fi

iface="${1:-$(ip route get 8.8.8.8 2>/dev/null | awk 'NR==1{print $5}')}"

section(){ echo "=== $1 ==="; }

section SYSTEM
uname -a || true

echo
section ENV
echo "INTERFACE=$iface"

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
section "PING6/CURL"
ping6 -c 1 -w 3 google.com 2>&1 || true
curl -6 -I -m 5 https://ipv6.google.com 2>&1 || true
