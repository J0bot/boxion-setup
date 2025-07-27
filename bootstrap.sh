#!/usr/bin/env bash
set -euo pipefail

# 🚀 BOXION FULL AUTO BOOTSTRAP - MODE SERVEUR
# Usage: curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/bootstrap.sh | bash
# Ou avec paramètres: DOMAIN="ton.domaine" EMAIL="toi@domaine" bash bootstrap.sh

echo "🚀 Boxion VPN Server Bootstrap - Mode Full Auto"
echo "=============================================="

# ====== Vérification permissions root ======
if [[ $EUID -ne 0 ]]; then
   echo "❌ Ce script doit être exécuté en tant que root"
   echo "💡 Relancez avec: curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/bootstrap.sh | sudo bash"
   exit 1
fi

# ====== Initialisation des variables ======
DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"
INCLUDE_LEGAL="${INCLUDE_LEGAL:-}"

# ====== Détection/Demande des paramètres ======
echo "🌐 Configuration du domaine pour l'API Boxion"
echo "Options disponibles:"
echo "  1. Votre propre domaine (ex: vpn.mondomaine.com)"
echo "  2. Adresse IP publique de ce serveur (pour tests)"
echo "  3. Domaine par défaut (tunnel.milkywayhub.org)"
echo

read -p "🌐 Nom de domaine ou IP [tunnel.milkywayhub.org]: " DOMAIN_INPUT
DOMAIN="${DOMAIN_INPUT:-tunnel.milkywayhub.org}"

# Vérification et conseils selon le type de domaine
if [[ "$DOMAIN" == "tunnel.milkywayhub.org" ]]; then
  echo "ℹ️  Domaine par défaut: $DOMAIN"
  echo "    → Assurez-vous que ce domaine pointe vers ce serveur"
  echo "    → Configurez un enregistrement DNS A/AAAA si nécessaire"
elif [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ℹ️  Mode IP détecté: $DOMAIN"
  echo "    → Parfait pour les tests, pas besoin de DNS"
  echo "    → Les certificats TLS ne fonctionneront pas"
else
  echo "✅ Domaine personnalisé: $DOMAIN"
  echo "    → Assurez-vous que ce domaine pointe vers ce serveur"
  echo "    → Vérifiez avec: nslookup $DOMAIN"
fi
echo

read -p "📧 Email pour Let's Encrypt [admin@${DOMAIN}]: " EMAIL_INPUT
EMAIL="${EMAIL_INPUT:-admin@${DOMAIN}}"

echo
echo "🏢 === PERSONNALISATION DASHBOARD ==="
read -p "🏢 Nom de votre entreprise [Gasser IT Services]: " COMPANY_INPUT
COMPANY_NAME="${COMPANY_INPUT:-Gasser IT Services}"

read -p "⚖️  Inclure les pages légales (confidentialité, mentions) ? [o/N]: " LEGAL_INPUT
INCLUDE_LEGAL="${LEGAL_INPUT:-n}"
if [[ "$INCLUDE_LEGAL" =~ ^[Oo]([Uu][Ii])?$ ]]; then
    INCLUDE_LEGAL="true"
else
    INCLUDE_LEGAL="false"
fi

echo
echo "🔐 === CREDENTIALS ADMIN ==="
read -p "👤 Nom d'utilisateur admin [admin]: " ADMIN_USER_INPUT
ADMIN_USERNAME="${ADMIN_USER_INPUT:-admin}"

read -p "🔑 Mot de passe admin (laissez vide pour génération automatique): " ADMIN_PASS_INPUT
if [[ -n "$ADMIN_PASS_INPUT" ]]; then
    ADMIN_PASSWORD="$ADMIN_PASS_INPUT"
else
    ADMIN_PASSWORD=""
fi

echo "🔍 Auto-détection des paramètres réseau..."

# ====== Sélection interface réseau ======
echo "📡 Interfaces réseau disponibles:"
echo

# Lister toutes les interfaces avec leurs adresses
interfaces=()
while IFS= read -r line; do
    if [[ $line =~ ^[0-9]+: ]]; then
        iface=$(echo "$line" | awk -F': ' '{print $2}' | awk '{print $1}')
        if [[ "$iface" != "lo" ]]; then
            ipv4=$(ip -4 addr show dev "$iface" 2>/dev/null | awk '/inet / && !/127.0.0.1/ {print $2; exit}' | cut -d/ -f1)
            ipv6=$(ip -6 addr show dev "$iface" scope global 2>/dev/null | awk '/inet6/ && !/temporary/ {print $2; exit}' | cut -d/ -f1)
            
            interfaces+=("$iface")
            printf "  %s) %s" "${#interfaces[@]}" "$iface"
            [[ -n "$ipv4" ]] && printf " - IPv4: %s" "$ipv4"
            [[ -n "$ipv6" ]] && printf " - IPv6: %s" "$ipv6"
            echo
        fi
    fi
done < <(ip link show)

echo
echo "  0) Auto-détection (recommandé)"
echo
read -p "📡 Choisissez l'interface WAN [0]: " IFACE_CHOICE
IFACE_CHOICE="${IFACE_CHOICE:-0}"

# Traitement du choix
if [[ "$IFACE_CHOICE" == "0" ]] || [[ -z "$IFACE_CHOICE" ]]; then
    # Auto-détection: préférer une interface avec IPv6 globale
    WAN_IF_CANDIDATES=$(ip r | awk '/default/ {print $5}')
    WAN_IF=""
    V6=""
    
    for iface in $WAN_IF_CANDIDATES; do
        ipv6_addr=$(ip -6 addr show dev "$iface" scope global | awk '/inet6/ && !/temporary/ {print $2; exit}' | cut -d/ -f1)
        if [[ -n "$ipv6_addr" ]]; then
            WAN_IF="$iface"
            V6="$ipv6_addr"
            echo "📡 Interface WAN auto-détectée: $WAN_IF (avec IPv6)"
            break
        fi
    done
    
    # Si aucune interface avec IPv6, prendre la première par défaut
    if [[ -z "$WAN_IF" ]]; then
        WAN_IF=$(ip r | awk '/default/ {print $5; exit}')
        echo "📡 Interface WAN auto-détectée: $WAN_IF (sans IPv6)"
    fi
elif [[ "$IFACE_CHOICE" =~ ^[0-9]+$ ]] && [[ "$IFACE_CHOICE" -ge 1 ]] && [[ "$IFACE_CHOICE" -le "${#interfaces[@]}" ]]; then
    # Choix manuel valide
    WAN_IF="${interfaces[$((IFACE_CHOICE-1))]}"
    V6=$(ip -6 addr show dev "$WAN_IF" scope global | awk '/inet6/ && !/temporary/ {print $2; exit}' | cut -d/ -f1)
    echo "📡 Interface WAN sélectionnée: $WAN_IF"
else
    echo "⚠️  Choix invalide, utilisation de l'auto-détection"
    WAN_IF=$(ip r | awk '/default/ {print $5; exit}')
    echo "📡 Interface WAN par défaut: $WAN_IF"
fi

# Auto-détection du préfixe IPv6 /64
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

# Export des variables de personnalisation pour setup.sh
export COMPANY_NAME="$COMPANY_NAME"
export INCLUDE_LEGAL="$INCLUDE_LEGAL"
export ADMIN_USERNAME="$ADMIN_USERNAME"
export ADMIN_PASSWORD="$ADMIN_PASSWORD"

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
echo "📝 Token complet: $TOKEN"
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
