#!/usr/bin/env bash
set -euo pipefail

# 🚀 BOXION FULL AUTO BOOTSTRAP - MODE SERVEUR
# Usage: curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/bootstrap.sh | bash
# Ou avec paramètres: DOMAIN="ton.domaine" EMAIL="toi@domaine" bash bootstrap.sh

echo "🚀 Boxion VPN Server Bootstrap - Mode Full Auto"
echo "=============================================="

# ====== Initialisation des variables ======
DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"

# ====== Détection/Demande des paramètres ======
read -p "🌐 Nom de domaine [tunnel.milkywayhub.org]: " DOMAIN_INPUT
DOMAIN="${DOMAIN_INPUT:-tunnel.milkywayhub.org}"

if [[ "$DOMAIN" == "tunnel.milkywayhub.org" ]]; then
  echo "⚠️  Vous utilisez le domaine par défaut. Assurez-vous qu'il pointe vers ce serveur !"
fi

read -p "📧 Email pour Let's Encrypt [admin@${DOMAIN}]: " EMAIL_INPUT
EMAIL="${EMAIL_INPUT:-admin@${DOMAIN}}"

echo "🔍 Auto-détection des paramètres réseau..."

# ====== Auto-détection réseau ======
WAN_IF=$(ip r | awk '/default/ {print $5; exit}')
echo "📡 Interface WAN détectée: $WAN_IF"

# Auto-détection du préfixe IPv6 /64
V6=$(ip -6 addr show dev "$WAN_IF" scope global | awk '/inet6/ && !/temporary/ {print $2; exit}' | cut -d/ -f1)
if [[ -n "$V6" ]]; then
  PREFIX=$(printf "%s:%s:%s:%s" $(echo "$V6" | awk -F: '{print $1,$2,$3,$4}'))
  echo "🌐 Préfixe IPv6 détecté: ${PREFIX}::/64"
else
  echo "⚠️  Aucune IPv6 globale détectée sur $WAN_IF"
  read -p "🌐 Entrez votre préfixe IPv6 /64 (ex: 2a0c:xxxx:xxxx:abcd): " PREFIX_INPUT
  PREFIX="${PREFIX_INPUT:-2a0c:xxxx:xxxx:abcd}"
fi

# ====== Génération token sécurisé ======
echo "🔐 Génération du token API sécurisé..."
TOKEN=$(openssl rand -hex 32)

# ====== Installation dépendances ======
echo "📦 Installation des dépendances..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y git jq curl openssl

# ====== Clone/Update repo ======
REPO_DIR="/root/boxion-api"
if [[ -d "$REPO_DIR" ]]; then
  echo "🔄 Mise à jour du repository existant..."
  cd "$REPO_DIR"
  git pull
else
  echo "📥 Clonage du repository..."
  git clone https://github.com/J0bot/boxion-setup.git "$REPO_DIR"
  cd "$REPO_DIR"
fi

# ====== Installation serveur ======
echo "⚙️  Installation du serveur Boxion..."
chmod +x setup.sh
./setup.sh --domain "$DOMAIN" --token "$TOKEN" --prefix "$PREFIX" --port 51820 --wan-if "$WAN_IF"

# ====== Configuration TLS ======
echo "🔒 Configuration TLS avec Let's Encrypt..."
apt-get install -y certbot python3-certbot-nginx >/dev/null 2>&1 || true
# Test de connectivité avant TLS
echo "🔍 Test de connectivité DNS pour $DOMAIN..."
if ! nslookup "$DOMAIN" >/dev/null 2>&1; then
  echo "⚠️  Attention: DNS pour $DOMAIN non résolu. TLS peut échouer."
fi

if certbot --nginx -d "$DOMAIN" --redirect -n --agree-tos -m "$EMAIL" 2>/dev/null; then
  echo "✅ TLS configuré avec succès"
  CLIENT_URL="https://$DOMAIN"
else
  echo "⚠️  TLS échoué, utilisation HTTP"
  echo "💡 Pour réparer plus tard: certbot --nginx -d $DOMAIN"
  CLIENT_URL="http://$DOMAIN"
fi

# ====== Génération commande client ======
CLIENT_CMD="TOKEN='$TOKEN' DOMAIN='$DOMAIN' bash -c '
set -e
apt-get update -qq && apt-get install -y wireguard-tools jq curl
curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/bootstrap_client.sh | bash
'"

# ====== Affichage final ======
echo
echo "🎉 ============ BOXION SERVER READY ============"
echo "🌐 Domaine: $DOMAIN"
echo "🔐 API Token: $TOKEN"
echo "📡 API URL: ${CLIENT_URL}/api/peers"
echo "🔧 Interface: $WAN_IF"
echo "🌐 Préfixe IPv6: ${PREFIX}::/64"
echo
echo "📋 COMMANDE CLIENT (Boxion) - Copiez-collez:"
echo "=============================================="
echo "$CLIENT_CMD"
echo
echo "✅ Le serveur est prêt ! Les clients peuvent maintenant se connecter."
echo "📊 Vérification: systemctl status wg-quick@wg0"
echo "🔍 Logs API: tail -f /var/log/nginx/error.log"
