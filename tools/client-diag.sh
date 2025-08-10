#!/usr/bin/env bash
set -euo pipefail
# Boxion - Diagnostic CLI (Client)
# Usage: ./tools/client-diag.sh [host_or_domain]

HOST="${1:-}"
IFACE="boxion"
SUDO=${SUDO:-sudo}

section(){ echo "=== $1 ==="; }

section SYSTEM
uname -a || true
if command -v lsb_release >/dev/null 2>&1; then lsb_release -a 2>/dev/null || true; fi

echo
section INTERFACE
ip -6 addr show dev "$IFACE" || echo "Interface $IFACE introuvable"
ip -6 route show dev "$IFACE" || true

echo
section WIREGUARD
if command -v wg >/dev/null 2>&1; then
  ${SUDO} wg show "$IFACE" 2>/dev/null || ${SUDO} wg show 2>/dev/null || true
else
  echo "wg non installé"
fi

echo
section CONFIG
CONF="/etc/wireguard/${IFACE}.conf"
if [[ -f "$CONF" ]]; then
  echo "Fichier: $CONF"
  grep -E '^(Address|Endpoint|AllowedIPs)\s*=\s*' "$CONF" || true
else
  echo "Configuration introuvable ($CONF)"
fi

echo
section CONNECTIVITE
ping6 -c 1 -w 3 google.com 2>&1 || true
curl -6 -I -m 5 https://ipv6.google.com 2>&1 || true

if [[ -n "$HOST" ]]; then
  echo
  section "TEST CIBLE: $HOST"
  dig +short AAAA "$HOST" 2>&1 || true
  ping6 -c 1 -w 3 "$HOST" 2>&1 || true
  curl -6 -I -m 5 "http://$HOST" 2>&1 || true
  curl -6 -I -m 5 "https://$HOST" 2>&1 || true
fi
