#!/usr/bin/env bash
set -euo pipefail
# Boxion server uninstaller (safe): stop services and remove Boxion-specific configs.
# Creates a backup in /root/boxion-backup-<timestamp>.tar.gz

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

read -r -p "This will stop WireGuard (wg0), disable ndppd, and remove Boxion nginx/vpn configs. Continue? [y/N] " ans
ans=${ans:-N}
if [[ ! "$ans" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

TS=$(date +%Y%m%d%H%M%S)
BK="/root/boxion-backup-${TS}.tar.gz"

# Collect paths if exist
paths=()
[[ -f /etc/wireguard/wg0.conf ]] && paths+=(/etc/wireguard/wg0.conf)
[[ -d /etc/wireguard/peers ]] && paths+=(/etc/wireguard/peers)
[[ -f /etc/ndppd.conf ]] && paths+=(/etc/ndppd.conf)
[[ -f /etc/sysctl.d/99-boxion-ipv6.conf ]] && paths+=(/etc/sysctl.d/99-boxion-ipv6.conf)
[[ -d /etc/boxion ]] && paths+=(/etc/boxion)
[[ -f /etc/nginx/sites-available/boxion.conf ]] && paths+=(/etc/nginx/sites-available/boxion.conf)
[[ -f /etc/nginx/sites-enabled/boxion.conf ]] && paths+=(/etc/nginx/sites-enabled/boxion.conf)
[[ -f /etc/nginx/sites-available/boxion-api ]] && paths+=(/etc/nginx/sites-available/boxion-api)
[[ -f /etc/nginx/sites-enabled/boxion-api ]] && paths+=(/etc/nginx/sites-enabled/boxion-api)
[[ -f /etc/nginx/sites-available/boxion-api.conf ]] && paths+=(/etc/nginx/sites-available/boxion-api.conf)
[[ -f /etc/nginx/sites-enabled/boxion-api.conf ]] && paths+=(/etc/nginx/sites-enabled/boxion-api.conf)
[[ -f /etc/nginx/conf.d/boxion-rate.conf ]] && paths+=(/etc/nginx/conf.d/boxion-rate.conf)
[[ -f /etc/nginx/.htpasswd-boxion ]] && paths+=(/etc/nginx/.htpasswd-boxion)
[[ -d /var/www/boxion ]] && paths+=(/var/www/boxion)
[[ -d /var/www/boxion-api ]] && paths+=(/var/www/boxion-api)
[[ -d /var/lib/boxion ]] && paths+=(/var/lib/boxion)

if ((${#paths[@]})); then
  echo "Creating backup: $BK"
  tar -czf "$BK" "${paths[@]}" 2>/dev/null || true
else
  echo "No known Boxion files found to backup."
fi

# Stop services
# Try to compute prefix from wg0.conf before removing it
WGCONF="/etc/wireguard/wg0.conf"
PREFIX=""
if [[ -f "$WGCONF" ]]; then
  ADDR_LINE=$(grep -E '^\s*Address\s*=\s*' "$WGCONF" | head -n1 | awk -F= '{print $2}' | tr -d ' ' | cut -d, -f1)
  if [[ -n "$ADDR_LINE" ]]; then
    BASE_V6=${ADDR_LINE%%/*}
    BASE_TRIM=${BASE_V6%::*}
    PREFIX="${BASE_TRIM}::/64"
  fi
fi

systemctl stop wg-quick@wg0 2>/dev/null || true
systemctl disable wg-quick@wg0 2>/dev/null || true
systemctl stop ndppd 2>/dev/null || true
systemctl disable ndppd 2>/dev/null || true

# Remove configs
rm -f /etc/wireguard/wg0.conf
rm -rf /etc/wireguard/peers 2>/dev/null || true
rm -f /etc/ndppd.conf
rm -f /etc/sysctl.d/99-boxion-ipv6.conf && sysctl --system >/dev/null || true

# Remove nginx vhosts and related files
for f in boxion.conf boxion-api boxion-api.conf; do
  rm -f "/etc/nginx/sites-enabled/${f}" "/etc/nginx/sites-available/${f}" 2>/dev/null || true
done
rm -f /etc/nginx/conf.d/boxion-rate.conf 2>/dev/null || true
rm -f /etc/nginx/.htpasswd-boxion 2>/dev/null || true

# Remove app dir if ours
if [[ -d /var/www/boxion ]]; then
  rm -rf /var/www/boxion
fi

# Reload services
if command -v nginx >/dev/null 2>&1; then
  systemctl reload nginx 2>/dev/null || true
fi

# Flush route we might have added
if [[ -n "$PREFIX" ]]; then
  ip -6 route del "$PREFIX" dev wg0 2>/dev/null || true
fi

# Remove app/data dirs and sudoers if present
rm -rf /var/www/boxion /var/www/boxion-api /var/lib/boxion /etc/boxion 2>/dev/null || true
rm -f /etc/sudoers.d/boxion 2>/dev/null || true

echo "Boxion server components removed. Backup: $BK"
