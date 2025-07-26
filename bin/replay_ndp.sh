#!/usr/bin/env bash
set -euo pipefail
WG_IF="${WG_IF:-wg0}"
WAN_IF="${WAN_IF:-eth0}"
DB="/var/lib/boxion/boxion.db"
[ -f "$DB" ] || exit 0
while IFS='|' read -r pub ip6; do
  [ -n "$pub" ] || continue
  wg set "$WG_IF" peer "$pub" allowed-ips "${ip6}/128" 2>/dev/null || true
  ip -6 neigh add proxy "$ip6" dev "$WAN_IF" 2>/dev/null || true
done < <(sqlite3 "$DB" "select pubkey||'|'||ip6 from peers;")
