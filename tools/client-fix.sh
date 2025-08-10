#!/usr/bin/env bash
set -euo pipefail
# Boxion - Correctif client existant
# - Détecte support DNS (resolvconf/resolvectl)
# - Met à jour /etc/wireguard/boxion.conf (ajoute/supprime la ligne DNS)
# - (Re)démarre wg-quick@boxion
# - Valide la connectivité IPv6 sans dépendre du DNS

if [[ $EUID -ne 0 ]]; then
  echo "Ce script doit être exécuté en root (sudo)" >&2
  exit 1
fi

CFG="/etc/wireguard/boxion.conf"
if [[ ! -f "$CFG" ]]; then
  echo "Configuration introuvable: $CFG" >&2
  exit 1
fi

have_dns_mgr=false
if command -v resolvectl >/dev/null 2>&1 || \
   command -v systemd-resolve >/dev/null 2>&1 || \
   command -v resolvconf >/dev/null 2>&1; then
  have_dns_mgr=true
fi

if $have_dns_mgr; then
  # Assure une ligne DNS présente (Google v6) unique
  sed -i '/^DNS\s*=.*/d' "$CFG"
  echo "Ajout de la ligne DNS (gestionnaire détecté)"
  sed -i '/^Address\s*=.*/a DNS = 2001:4860:4860::8888, 2001:4860:4860::8844' "$CFG"
else
  # Supprime toute ligne DNS (évite l'appel à resolvconf)
  echo "Suppression des lignes DNS (aucun gestionnaire détecté)"
  sed -i '/^DNS\s*=.*/d' "$CFG"
fi

systemctl stop wg-quick@boxion >/dev/null 2>&1 || true
if systemctl start wg-quick@boxion; then
  echo "Tunnel démarré"
else
  echo "Échec au démarrage du tunnel" >&2
  journalctl -u wg-quick@boxion --no-pager -n 100 || true
  exit 1
fi

# Dérive l'IPv6 serveur (PREFIX::1) à partir de l'Address client
ADDR=$(grep -E '^\s*Address\s*=\s*' "$CFG" | head -n1 | cut -d= -f2- | tr -d ' ')
ADDR_NOPFX=${ADDR%%/*}
SV=""
if [[ "$ADDR_NOPFX" == *"::"* ]]; then
  SV="${ADDR_NOPFX%::*}::1"
fi

# Cible de test: priorité au serveur dérivé; override possible via BOXION_TEST_V6; fallback Cloudflare
TEST_FALLBACK="${BOXION_TEST_V6:-}"
if [[ -z "$TEST_FALLBACK" ]]; then
  TEST_FALLBACK="2606:4700:4700::1111"  # Cloudflare v6
fi
TARGET="${SV:-$TEST_FALLBACK}"
if ping6 -c1 "$TARGET" >/dev/null 2>&1; then
  echo "IPv6 OK (ping $TARGET)"
else
  echo "IPv6 non confirmée (ping $TARGET)" >&2
  exit 2
fi

wg show || true
ip -6 addr show dev boxion || true
