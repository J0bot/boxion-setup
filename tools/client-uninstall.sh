#!/usr/bin/env bash
set -euo pipefail
# Boxion client uninstaller (safe)
# Stops and disables wg-quick@boxion, removes /etc/wireguard/boxion.conf

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

read -r -p "This will stop and remove Boxion client config on this machine. Continue? [y/N] " ans
ans=${ans:-N}
if [[ ! "$ans" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

systemctl stop wg-quick@boxion 2>/dev/null || true
systemctl disable wg-quick@boxion 2>/dev/null || true

if [[ -f /etc/wireguard/boxion.conf ]]; then
  rm -f /etc/wireguard/boxion.conf
fi

# Optional: remove resolvconf entries created by wg-quick
# Nothing persistent is written by our script; wg-quick updates /etc/resolv.conf transiently.

echo "Boxion client removed. You can also 'apt-get purge wireguard' if you want to remove the package."
