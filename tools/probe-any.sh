#!/usr/bin/env bash
set -euo pipefail
# Probe IPv6 reachability from ANY Linux machine
# Usage: ./tools/probe-any.sh <host-or-ipv6>
# - Resolves AAAA, pings (with different sizes), traceroute6, curl -6 HTTP/HTTPS

if [[ ${1-} == "" ]]; then
  echo "Usage: $0 <host-or-ipv6>" >&2
  exit 2
fi

HOST="$1"
IS_IPV6=0
if [[ "$HOST" == *:* ]]; then IS_IPV6=1; fi
CURL_HOST="$HOST"
if [[ $IS_IPV6 -eq 1 && "$HOST" != "["* && "$HOST" != *"]" ]]; then CURL_HOST="[$HOST]"; fi

run(){ echo; echo "$ $*"; eval "$*" || true; }

echo "=== General IPv6 sanity ==="
run "getent ahostsv6 google.com | head -n2"
run "ping6 -c1 -w3 google.com"
run "curl -6 -sS -m 5 -I https://ipv6.google.com || true"

echo
echo "=== Target: $HOST ==="
if command -v dig >/dev/null 2>&1; then
  run "dig +short AAAA $HOST"
else
  run "getent ahostsv6 $HOST | awk '{print $1}' | sort -u"
fi

run "ping6 -c1 -w3 $HOST"
# MTU/PMTUD probes (1280 is IPv6 minimum MTU)
run "ping6 -M do -s 1200 -c1 -w3 $HOST"
run "ping6 -M do -s 1400 -c1 -w3 $HOST"
run "ping6 -M do -s 1472 -c1 -w3 $HOST"

# Traceroute / MTR
if command -v traceroute >/dev/null 2>&1; then
  run "traceroute -6 -n -w2 -q1 $HOST | sed -n '1,30p'"
fi
if command -v mtr >/dev/null 2>&1; then
  run "mtr -6 -c 20 -r -n $HOST"
fi

# HTTP(S) over IPv6 literal or host
run "curl -6 -sS -m 5 -I http://$CURL_HOST || true"
run "curl -6 -sS -m 5 -I https://$CURL_HOST || true"

echo
cat <<'EOF'
Hints:
- If ping from your PC fails but works from the server, inbound IPv6 to the VPS may be blocked by cloud Security Groups or nftables FORWARD policy.
- If large ping sizes fail while 1200 works, you likely have a PMTUD/MTU issue on the HE 6in4 path; ensure ICMPv6 type 2 (Packet Too Big) is allowed.
- For servers using nftables, allow forwarding he-ipv6 <-> wg0 and ICMPv6. See tools/server-allow-forward.sh.
EOF
