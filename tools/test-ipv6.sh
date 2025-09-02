#!/usr/bin/env bash
set -euo pipefail
# Test basique IPv6 (VPS ou client ou n'importe quel Linux)
# Usage: ./tools/test-ipv6.sh [host]

HOST="${1:-}"
IS_IPV6=0
if [[ -n "$HOST" && "$HOST" == *:* ]]; then IS_IPV6=1; fi
CHOST="$HOST"
if [[ -n "$HOST" && $IS_IPV6 -eq 1 && "$HOST" != "["* && "$HOST" != *"]" ]]; then CHOST="[$HOST]"; fi

run(){ echo "$ $*"; eval "$*" || true; echo; }

echo "=== TEST IPV6 GENERIQUE ==="
run "ping6 -c 1 -w 3 google.com"
run "curl -6 -I -m 5 https://ipv6.google.com"

if [[ -n "$HOST" ]]; then
  echo "=== TEST CIBLE ($HOST) ==="
  if command -v dig >/dev/null 2>&1; then
    run "dig +short AAAA $HOST"
  else
    run "getent ahostsv6 $HOST | awk '{print $1}' | sort -u"
  fi
  run "ping6 -c 1 -w 3 $HOST"
  # MTU/PMTUD probes
  run "ping6 -M do -s 1200 -c 1 -w 3 $HOST"
  run "ping6 -M do -s 1400 -c 1 -w 3 $HOST"
  run "ping6 -M do -s 1472 -c 1 -w 3 $HOST"
  run "curl -6 -I -m 5 http://$CHOST"
  run "curl -6 -I -m 5 https://$CHOST"
fi
