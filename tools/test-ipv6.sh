#!/usr/bin/env bash
set -euo pipefail
# Test basique IPv6 (VPS ou client)
# Usage: ./tools/test-ipv6.sh [host]

HOST="${1:-}"

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
  run "curl -6 -I -m 5 http://$HOST"
  run "curl -6 -I -m 5 https://$HOST"
fi
