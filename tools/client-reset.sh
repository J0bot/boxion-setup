#!/usr/bin/env bash
set -euo pipefail
# Boxion client reset helper: uninstall then reinstall
# Usage examples:
#   sudo tools/client-reset.sh                       # interactive reinstall
#   sudo BOXION_SERVER_URL=https://tunnel.example BOXION_API_TOKEN=... \
#        BOXION_NAME=mybox tools/client-reset.sh     # unattended reinstall

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

read -r -p "This will UNINSTALL current Boxion client config and reinstall. Continue? [y/N] " ans
ans=${ans:-N}
if [[ ! "$ans" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

bash "$SCRIPT_DIR/client-uninstall.sh"

echo "Uninstall complete."

echo "Reinstalling client..."
# Pass through env if provided; client-setup.sh supports interactive mode otherwise
bash "$REPO_DIR/client-setup.sh" || true

echo "Client reset done."
