#!/usr/bin/env bash
set -euo pipefail
# Boxion - API Status Fetcher
# Usage: ./tools/api-status.sh https://tunnel.example.org <TOKEN>
# Or with env: BOXION_API_URL, BOXION_API_TOKEN

URL="${1:-${BOXION_API_URL:-}}"
TOKEN="${2:-${BOXION_API_TOKEN:-}}"

if [[ -z "${URL}" || -z "${TOKEN}" ]]; then
  echo "Usage: $0 <BASE_URL> <TOKEN>" >&2
  echo "Example: $0 https://tunnel.milkywayhub.org $(openssl rand -hex 16)" >&2
  exit 2
fi

API="${URL%/}/api/status"

if command -v jq >/dev/null 2>&1; then
  curl -fsS -H "Authorization: Bearer ${TOKEN}" -H 'Accept: application/json' \
    -X GET "${API}" | jq -r .
else
  curl -fsS -H "Authorization: Bearer ${TOKEN}" -H 'Accept: application/json' \
    -X GET "${API}"
fi
