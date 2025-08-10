#!/usr/bin/env bash
set -euo pipefail
# Boxion server reset helper: uninstall then reinstall
# Usage:
#   sudo BOXION_DOMAIN=tunnel.milkywayhub.org BOXION_LE_EMAIL=admin@example.com tools/server-reset.sh
# If env vars are missing, the script will only uninstall and print reinstall hints.

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

read -r -p "This will UNINSTALL current Boxion server and optionally reinstall. Continue? [y/N] " ans
ans=${ans:-N}
if [[ ! "$ans" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

bash "$SCRIPT_DIR/server-uninstall.sh"

echo "Uninstall complete."

if [[ -n "${BOXION_DOMAIN:-}" && -n "${BOXION_LE_EMAIL:-}" ]]; then
  echo "Reinstalling with domain=$BOXION_DOMAIN email=$BOXION_LE_EMAIL ..."
  BOXION_DOMAIN="$BOXION_DOMAIN" BOXION_LE_EMAIL="$BOXION_LE_EMAIL" bash "$REPO_DIR/installer/install.sh"
  echo "Reinstall done."
else
  cat <<EOF
To reinstall now, run:
  sudo BOXION_DOMAIN=your.domain.tld BOXION_LE_EMAIL=you@example.com bash installer/install.sh
EOF
fi

# Optional: ensure NDP if needed
echo "If external IPv6 reachability is not immediate, you can run:"
echo "  sudo bash tools/server-ndp-ensure.sh"
