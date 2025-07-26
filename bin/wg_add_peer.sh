#!/usr/bin/env bash
set -euo pipefail
WG_IF="${WG_IF:-wg0}"
WAN_IF="${WAN_IF:-eth0}"
PUB="$1"; IP6="$2"
wg set "$WG_IF" peer "$PUB" allowed-ips "${IP6}/128"
ip -6 neigh add proxy "$IP6" dev "$WAN_IF" 2>/dev/null || true
