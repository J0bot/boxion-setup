#!/usr/bin/env bash
set -euo pipefail
# Remove a domain mapping for IPv4->IPv6 proxy (Nginx)
# Usage: sudo ./tools/server-proxy-remove.sh <domain>

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

domain="${1-}"
if [[ -z "$domain" ]]; then
  echo "Usage: $0 <domain>" >&2
  exit 2
fi

if ! [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "Invalid domain: $domain" >&2
  exit 2
fi

HTTP_MAP="/etc/nginx/boxion/http.map"
TLS_MAP="/etc/nginx/boxion/tls.map"

for f in "$HTTP_MAP" "$TLS_MAP"; do
  [[ -f "$f" ]] || continue
  tmp=$(mktemp)
  sed -E "/^[[:space:]]*${domain}[[:space:]]/d" "$f" > "$tmp" && mv "$tmp" "$f"
done

# Test & reload nginx
if nginx -t; then
  systemctl reload nginx || systemctl restart nginx || true
  echo "Removed mapping for $domain"
else
  echo "nginx -t failed; not reloaded." >&2
  exit 1
fi
