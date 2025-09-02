#!/usr/bin/env bash
set -euo pipefail
# Add/Update a domain mapping for IPv4->IPv6 proxy (Nginx)
# - HTTP (Host) -> /etc/nginx/boxion/http.map (default upstream [IPv6]:80)
# - TLS  (SNI)  -> /etc/nginx/boxion/tls.map  (default upstream [IPv6]:443)
# Usage: sudo ./tools/server-proxy-add.sh <domain> <ipv6> [http_port] [tls_port]
# Notes:
# - <ipv6> may be with or without brackets; may not include prefix length.
# - Does not edit DNS. Create A (to VPS IPv4) and AAAA (to client IPv6) manually.

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

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

HTTP_MAP="/etc/nginx/boxion/http.map"
TLS_MAP="/etc/nginx/boxion/tls.map"
mkdir -p /etc/nginx/boxion
[[ -f "$HTTP_MAP" ]] || echo "# domain  upstream" > "$HTTP_MAP"
[[ -f "$TLS_MAP"  ]] || echo "# domain  upstream" > "$TLS_MAP"

# Idempotent replace-or-append
tmp=$(mktemp)
sed -E "/^[[:space:]]*${domain}[[:space:]]/d" "$HTTP_MAP" > "$tmp" && mv "$tmp" "$HTTP_MAP"
echo -e "${domain}\t${up_http};" >> "$HTTP_MAP"

tmp=$(mktemp)
sed -E "/^[[:space:]]*${domain}[[:space:]]/d" "$TLS_MAP" > "$tmp" && mv "$tmp" "$TLS_MAP"
echo -e "${domain}\t${up_tls};" >> "$TLS_MAP"

# Test & reload nginx
if nginx -t; then
  systemctl reload nginx || systemctl restart nginx || true
  echo "Mapped $domain -> HTTP $up_http, TLS $up_tls"
else
  echo "nginx -t failed; not reloaded." >&2
  exit 1
fi
