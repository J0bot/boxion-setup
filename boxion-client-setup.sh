#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Boxion VPN Client Setup"
echo "========================"

# ====== Configuration ======
WG_IF=wg0
WG_DIR=/etc/wireguard
DOMAIN="${DOMAIN:-}"
TOKEN="${TOKEN:-}"
NAME="${HOSTNAME:-boxion}-$(date +%s)"

# ====== Mode interactif si paramètres manquants ======
if [[ -z "${DOMAIN}" ]]; then
  echo "🌐 Configuration du serveur"
  read -p "Domaine du serveur [tunnel.milkywayhub.org]: " DOMAIN_INPUT
  DOMAIN="${DOMAIN_INPUT:-tunnel.milkywayhub.org}"
fi

if [[ -z "${TOKEN}" ]] || [[ "${TOKEN}" == "PLACE_YOUR_TOKEN" ]]; then
  echo "🔐 Configuration du token API"
  echo "Obtenez votre token depuis l'administrateur du serveur $DOMAIN"
  read -p "Token API: " TOKEN
fi

# Détection du protocole et construction de l'URL API
echo "🔍 Connexion à: $DOMAIN"
if curl -fsSL --max-time 5 "https://$DOMAIN" >/dev/null 2>&1; then
  API="https://$DOMAIN/api/peers"
  echo "🔒 Utilisation HTTPS"
else
  API="http://$DOMAIN/api/peers"
  echo "⚠️  Utilisation HTTP (pas de TLS)"
fi

echo "🔐 Token: ${TOKEN:0:8}..." # Affiche seulement les 8 premiers caractères

apt-get update -qq
apt-get install -y wireguard-tools jq

mkdir -p "$WG_DIR"; chmod 700 "$WG_DIR"
if [[ ! -f "$WG_DIR/client_private.key" ]]; then
  umask 077
  wg genkey | tee "$WG_DIR/client_private.key" | wg pubkey > "$WG_DIR/client_public.key"
fi
PUB=$(cat "$WG_DIR/client_public.key")
PRIV=$(cat "$WG_DIR/client_private.key")

resp=$(curl -fsSL -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"name\":\"$NAME\",\"pubkey\":\"$PUB\"}" "$API")
conf=$(echo "$resp" | jq -r '.wg_conf')
[[ "$conf" == "null" || -z "$conf" ]] && { echo "API error: $resp"; exit 1; }

# injecte la clé privée
printf "[Interface]\nPrivateKey = %s\n%s" "$PRIV" "$(echo "$conf" | sed '1d')" > "$WG_DIR/$WG_IF.conf"
chmod 600 "$WG_DIR/$WG_IF.conf"

systemctl enable wg-quick@$WG_IF
systemctl restart wg-quick@$WG_IF
echo "UP ✓  $(wg show $WG_IF | sed -n '1,12p')"
