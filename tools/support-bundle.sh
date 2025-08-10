#!/usr/bin/env bash
set -euo pipefail
# Boxion - Support Bundle (VPS)
# Collecte des diagnostics en un tar.gz partageable
# Usage: ./tools/support-bundle.sh [BASE_URL] [MASTER_TOKEN]
# - BASE_URL (optionnel): ex https://tunnel.milkywayhub.org
# - MASTER_TOKEN (optionnel): token maître pour /api/status

BASE_URL="${1:-${BOXION_API_URL:-}}"
TOKEN="${2:-${BOXION_API_TOKEN:-}}"
TS=$(date +%Y%m%d-%H%M%S)
OUTDIR="/tmp/boxion-support-${TS}"
mkdir -p "$OUTDIR"

redact() { sed -E 's/([A-Fa-f0-9]{16,})/[redacted]/g; s/(API_TOKEN=).*/\1[redacted]/; s/(password|passwd|secret)\s*=\s*[^;\n]*/\1=[redacted]/Ig'; }

save_cmd() {
  local name="$1"; shift
  { echo "$ $*"; eval "$*" 2>&1 || true; } | tee "${OUTDIR}/${name}.txt" >/dev/null
}

# 1) Diag helper
if [[ -x /usr/local/sbin/boxion-diag ]]; then
  /usr/local/sbin/boxion-diag >"${OUTDIR}/diag.txt" 2>&1 || true
fi

# 2) Réseau et WireGuard
save_cmd ip-addr 'ip -6 addr show'
save_cmd ip-route 'ip -6 route show'
save_cmd wg 'wg show'

# 3) ndppd / sysctl / firewall
save_cmd ndppd 'systemctl status ndppd'
save_cmd ndppd-log 'journalctl -u ndppd -n 200 --no-pager'
save_cmd sysctl 'sysctl net.ipv6.conf.all.forwarding net.ipv6.conf.all.proxy_ndp'
save_cmd ip6tables 'ip6tables -S'

# 4) Nginx / PHP
save_cmd nginx-test 'nginx -t'
nginx -T 2>&1 | redact >"${OUTDIR}/nginx-full.txt" || true
save_cmd php-fpm 'php-fpm -v || php -v'

# 5) Config Boxion
if [[ -f /etc/boxion/boxion.env ]]; then
  redact < /etc/boxion/boxion.env >"${OUTDIR}/boxion.env.txt"
fi

# 6) DB (résumé)
if [[ -f /var/lib/boxion/peers.db ]]; then
  {
    echo '== peers (count, preview) =='
    sqlite3 /var/lib/boxion/peers.db 'SELECT COUNT(*) FROM peers;' 2>&1 || true
    sqlite3 /var/lib/boxion/peers.db "SELECT id,name,substr(public_key,1,6)||'...' as pubk, ipv6_address FROM peers ORDER BY id DESC LIMIT 20;" 2>&1 || true
    echo
    echo '== otps (count only) =='
    sqlite3 /var/lib/boxion/peers.db 'SELECT COUNT(*) FROM otps;' 2>&1 || true
  } >"${OUTDIR}/db-summary.txt" || true
fi

# 7) API status (si URL+TOKEN)
if [[ -n "${BASE_URL}" && -n "${TOKEN}" ]]; then
  curl -fsS -H "Authorization: Bearer ${TOKEN}" -H 'Accept: application/json' \
    -X GET "${BASE_URL%/}/api/status" | tee "${OUTDIR}/api-status.json" >/dev/null || true
fi

# 8) Version / env
{
  echo "date: $(date -Is)"
  echo "uname:"; uname -a
  echo
  echo "Debian:"; (lsb_release -a 2>/dev/null || cat /etc/debian_version 2>/dev/null || true)
} >"${OUTDIR}/system.txt"

# Archive
TAR="${OUTDIR}.tar.gz"
(
  cd "/tmp"
  tar -czf "${TAR}" "$(basename "$OUTDIR")"
)

echo "\nBundle créé: ${TAR}"
echo "Partagez ce fichier pour analyse (contient des infos réseau et config, secrets redacted)."
