#!/usr/bin/env bash
set -euo pipefail
# Enable IPv4->IPv6 proxying on the VPS using Nginx
# - Adds a stream (L4) listener on 443 with SNI-based routing (no TLS termination)
# - Adds an HTTP (L7) listener on 80 with Host-based routing
# - Uses two map files:
#     /etc/nginx/boxion/tls.map   (domain -> [ipv6]:443)
#     /etc/nginx/boxion/http.map  (domain -> [ipv6]:80)
# - Safe/idempotent. Does NOT edit DNS.
# After running, use tools/server-proxy-add.sh to add domains.

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

mkdir -p /etc/nginx/boxion /etc/nginx/streams.d
# Create maps if missing (do not truncate if present)
[[ -f /etc/nginx/boxion/tls.map ]]  || echo "# domain  upstream" > /etc/nginx/boxion/tls.map
[[ -f /etc/nginx/boxion/http.map ]] || echo "# domain  upstream" > /etc/nginx/boxion/http.map

# Create stream aggregator file (top-level, not inside http)
STREAM_FILE="/etc/nginx/boxion-stream.conf"
if [[ ! -f "$STREAM_FILE" ]]; then
  cat >"$STREAM_FILE" <<'EOF'
# Boxion L4 TLS passthrough by SNI
stream {
    map $ssl_preread_server_name $boxion_sni_upstream {
        include /etc/nginx/boxion/tls.map;
        default 127.0.0.1:44444;
    }

    server {
        listen 0.0.0.0:443 reuseport;
        proxy_pass $boxion_sni_upstream;
        ssl_preread on;
        proxy_connect_timeout 5s;
        proxy_timeout 600s;
    }
}
EOF
fi

# Ensure nginx.conf includes the stream file at top-level
NGINX_CONF="/etc/nginx/nginx.conf"
if ! grep -qF "/etc/nginx/boxion-stream.conf" "$NGINX_CONF"; then
  cp -a "$NGINX_CONF" "${NGINX_CONF}.bak-boxion-`date +%s`"
  printf "\n# Boxion stream include\ninclude /etc/nginx/boxion-stream.conf;\n" >> "$NGINX_CONF"
  echo "Injected include into $NGINX_CONF (backup created)."
fi

# Create HTTP Host-based proxy config inside http {}
HTTP_CONF="/etc/nginx/conf.d/boxion-http-proxy.conf"
if [[ ! -f "$HTTP_CONF" ]]; then
  cat >"$HTTP_CONF" <<'EOF'
# Boxion HTTP Host proxy (port 80)
# Requires this file to be included inside http {} (Debian default)
map $host $boxion_http_upstream {
    include /etc/nginx/boxion/http.map;
    default 127.0.0.1:18080;
}

server {
    listen 0.0.0.0:80;
    access_log off;
    location / {
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 3s;
        proxy_read_timeout 60s;
        proxy_pass http://$boxion_http_upstream;
    }
}
EOF
fi

echo "Nginx proxy scaffolding installed. Now add domains with tools/server-proxy-add.sh."

# Test & reload nginx if available
if command -v nginx >/dev/null 2>&1; then
  if nginx -t; then
    systemctl reload nginx || systemctl restart nginx || true
  else
    echo "nginx -t failed; please fix configuration before reload." >&2
  fi
else
  echo "nginx not installed yet. Install with: apt-get update && apt-get install -y nginx" >&2
fi
