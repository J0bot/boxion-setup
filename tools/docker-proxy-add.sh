#!/usr/bin/env bash
set -euo pipefail
# Add/Update a domain mapping for IPv4->IPv6 proxy (Docker Nginx)
# - HTTP (Host) -> ./data/nginx-maps/http.map (default upstream [IPv6]:80)
# - TLS  (SNI)  -> ./data/nginx-maps/tls.map  (default upstream [IPv6]:443)
# Usage: ./tools/docker-proxy-add.sh <domain> <ipv6> [http_port] [tls_port]
# Notes:
# - <ipv6> may be with or without brackets; may not include prefix length.
# - Does NOT edit DNS. Create A (to VPS IPv4) and AAAA (to client IPv6) manually.
# - Requires the proxy container name 'boxion-proxy' (from docker-compose.yml)

here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"

domain="${1-}"; ip6raw="${2-}"; http_port="${3-80}"; tls_port="${4-443}"
if [[ -z "$domain" || -z "$ip6raw" ]]; then
  echo "Usage: $0 <domain> <ipv6> [http_port] [tls_port]" >&2
  exit 2
fi

# Sanitize domain
if ! [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "Invalid domain: $domain" >&2
  exit 2
fi

# Sanitize IPv6: strip brackets and prefix
ip6="$ip6raw"
ip6="${ip6#[}"; ip6="${ip6%]}"; ip6="${ip6%%/*}"
if [[ "$ip6" != *:* ]]; then
  echo "Not an IPv6 address: $ip6raw" >&2
  exit 2
fi

up_http="[${ip6}]:${http_port}"
up_tls="[${ip6}]:${tls_port}"

MAP_DIR="./data/nginx-maps"
HTTP_MAP="$MAP_DIR/http.map"
TLS_MAP="$MAP_DIR/tls.map"
mkdir -p "$MAP_DIR"
[[ -f "$HTTP_MAP" ]] || echo "# domain  upstream" > "$HTTP_MAP"
[[ -f "$TLS_MAP"  ]] || echo "# domain  upstream" > "$TLS_MAP"

# Idempotent replace-or-append
awk -v d="$domain" 'BEGIN{printed=0} {if($1==d){next} print} END{ }' "$HTTP_MAP" > "$HTTP_MAP.tmp" && mv "$HTTP_MAP.tmp" "$HTTP_MAP"
echo -e "${domain}\t${up_http};" >> "$HTTP_MAP"

awk -v d="$domain" 'BEGIN{printed=0} {if($1==d){next} print} END{ }' "$TLS_MAP" > "$TLS_MAP.tmp" && mv "$TLS_MAP.tmp" "$TLS_MAP"
echo -e "${domain}\t${up_tls};" >> "$TLS_MAP"

# Reload proxy container
if docker compose ps proxy >/dev/null 2>&1; then
  docker compose exec -T proxy nginx -t >/dev/null
  docker compose exec -T proxy nginx -s reload || docker compose restart proxy
  echo "Mapped $domain -> HTTP $up_http, TLS $up_tls"
else
  echo "Proxy not running yet. Start with: tools/docker-up.sh" >&2
fi
