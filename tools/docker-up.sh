#!/usr/bin/env bash
set -euo pipefail

# Bring up Boxion in Docker (proxy + api), creating shared network for Caddy if missing.
# - Requires: docker and docker compose plugin
# - Creates external network 'boxion-edge' used to interconnect with your Caddy stack
# - Does NOT touch DNS

here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 1; }; }
need docker

# Create external network if absent (to let Caddy run in a separate compose on same L2)
if ! docker network inspect boxion-edge >/dev/null 2>&1; then
  echo "+ Creating external network 'boxion-edge'"
  docker network create boxion-edge >/dev/null
fi

if ! docker network inspect boxion >/dev/null 2>&1; then
  echo "+ Creating external network 'boxion'"
  docker network create boxion >/dev/null
fi

# Build and start
echo "+ Building images"
docker compose build --pull

echo "+ Starting services"
docker compose up -d

echo "\nDone. Next:"
echo "- Run tools/docker-proxy-add.sh <domain> <ipv6> [http_port] [tls_port] to map hosts"
echo "- Run your Caddy as a separate stack, joined to network 'boxion-edge' and reachable as container name 'caddy' on 8080/8443"
