#!/usr/bin/env bash
set -euo pipefail
WG_IF=wg0; WG_DIR=/etc/wireguard
API="https://tunnel.milkywayhub.org/api/peers"
TOKEN="PLACE_YOUR_TOKEN"
NAME="${HOSTNAME:-boxion}-$(date +%s)"

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
