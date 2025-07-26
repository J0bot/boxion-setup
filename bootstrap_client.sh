#!/usr/bin/env bash
set -euo pipefail

# 🚀 BOXION FULL AUTO BOOTSTRAP - MODE CLIENT
# Usage: TOKEN='your_token' DOMAIN='your.domain' bash -c "$(curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/bootstrap_client.sh)"

echo "🚀 Boxion VPN Client Bootstrap - Mode Full Auto"
echo "=============================================="

# ====== Vérification/Demande des paramètres ======
if [[ -z "${TOKEN:-}" ]]; then
  echo "🔐 Token API requis pour la connexion"
  read -p "Entrez votre token API: " TOKEN
fi

if [[ -z "${DOMAIN:-}" ]]; then
  read -p "🌐 Domaine du serveur [tunnel.milkywayhub.org]: " DOMAIN_INPUT
  DOMAIN="${DOMAIN_INPUT:-tunnel.milkywayhub.org}"
fi

echo "🔍 Connexion à: $DOMAIN"
echo "🔐 Token: ${TOKEN:0:8}..." # Affiche seulement les 8 premiers caractères

# ====== Installation dépendances ======
echo "📦 Installation WireGuard et dépendances..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y wireguard-tools jq curl

# ====== Configuration WireGuard ======
WG_IF=wg0
WG_DIR=/etc/wireguard
NAME="${HOSTNAME:-boxion}-$(date +%s)"

echo "⚙️  Configuration WireGuard..."
mkdir -p "$WG_DIR"
chmod 700 "$WG_DIR"

# Génération des clés si absentes
if [[ ! -f "$WG_DIR/client_private.key" ]]; then
  echo "🔑 Génération des clés WireGuard..."
  umask 077
  wg genkey | tee "$WG_DIR/client_private.key" | wg pubkey > "$WG_DIR/client_public.key"
fi

PUB=$(cat "$WG_DIR/client_public.key")
PRIV=$(cat "$WG_DIR/client_private.key")

# ====== Détection du protocole (HTTPS/HTTP) ======
if curl -fsSL --max-time 5 "https://$DOMAIN" >/dev/null 2>&1; then
  API_URL="https://$DOMAIN/api/peers"
  echo "🔒 Utilisation HTTPS"
else
  API_URL="http://$DOMAIN/api/peers"
  echo "⚠️  Utilisation HTTP (pas de TLS)"
fi

# ====== Enregistrement auprès de l'API ======
echo "📡 Enregistrement auprès du serveur..."
resp=$(curl -fsSL \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$NAME\",\"pubkey\":\"$PUB\"}" \
  "$API_URL")

# Vérification de la réponse
conf=$(echo "$resp" | jq -r '.wg_conf' 2>/dev/null || echo "null")
if [[ "$conf" == "null" || -z "$conf" ]]; then
  echo "❌ Erreur API: $resp"
  exit 1
fi

ip6=$(echo "$resp" | jq -r '.ip6' 2>/dev/null || echo "unknown")
echo "✅ IP assignée: $ip6"

# ====== Création de la configuration WireGuard ======
printf "[Interface]\nPrivateKey = %s\n%s" "$PRIV" "$(echo "$conf" | sed '1d')" > "$WG_DIR/$WG_IF.conf"
chmod 600 "$WG_DIR/$WG_IF.conf"

# ====== Démarrage WireGuard ======
echo "🚀 Démarrage de WireGuard..."
systemctl enable wg-quick@$WG_IF 2>/dev/null || true
systemctl restart wg-quick@$WG_IF

# ====== Vérification ======
sleep 2
if systemctl is-active --quiet wg-quick@$WG_IF; then
  echo "✅ WireGuard démarré avec succès"
  echo "📊 Status:"
  wg show $WG_IF | head -12 || true
  
  # Test de connectivité IPv6
  echo "🔍 Test de connectivité IPv6..."
  if ping -6 -c1 -W3 2606:4700:4700::1111 >/dev/null 2>&1; then
    echo "✅ Connectivité IPv6 OK"
  else
    echo "⚠️  Connectivité IPv6 limitée (normal si pas de routage global)"
  fi
else
  echo "❌ Erreur lors du démarrage de WireGuard"
  systemctl status wg-quick@$WG_IF || true
  exit 1
fi

echo
echo "🎉 ============ BOXION CLIENT READY ============"
echo "🔗 Client: $NAME"
echo "🌐 IP IPv6: $ip6"
echo "📡 Serveur: $DOMAIN"
echo "⚙️  Interface: $WG_IF"
echo
echo "✅ Le client est connecté au VPN Boxion !"
echo "🔍 Vérification: wg show $WG_IF"
echo "🌐 Test IPv6: ping -6 -c3 ipv6.google.com"
