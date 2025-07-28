#!/usr/bin/env bash
set -euo pipefail

# ====== GESTION DE SIGNAUX POUR CLEANUP ======
cleanup() {
    local exit_code=$?
    echo
    echo "🧹 Nettoyage en cours..."
    
    # Suppression fichiers temporaires
    rm -f /tmp/boxion-*-vars.sh 2>/dev/null || true
    rm -f /tmp/php-syntax.log 2>/dev/null || true
    rm -f /tmp/nginx-test.log 2>/dev/null || true
    
    # Arrêt services si partiellement configurés
    systemctl stop nginx 2>/dev/null || true
    systemctl stop wg-quick@wg0 2>/dev/null || true
    
    if [[ $exit_code -ne 0 ]]; then
        echo "❌ Installation interrompue ou échouée"
        echo "📋 Consultez les logs pour plus de détails"
        echo "🔄 Vous pouvez relancer le script après correction"
    fi
    
    exit $exit_code
}

# Installation des traps pour tous les signaux critiques
trap cleanup EXIT
trap cleanup INT
trap cleanup TERM
trap cleanup HUP

# ====== PROTECTION CONTRE EXÉCUTIONS CONCURRENTES ======
LOCK_FILE="/var/lock/boxion-bootstrap.lock"
FLOCK_FD=200

# Tentative de verrouillage exclusif
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "❌ ERREUR: Une autre installation Boxion est déjà en cours"
    echo "🔒 Fichier de verrouillage: $LOCK_FILE"
    echo "⏳ Attendez la fin de l'installation en cours ou supprimez le fichier si bloqué"
    exit 1
fi

echo "🔒 Verrouillage acquisition réussi - installation sécurisée"

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
COMPANY_NAME="${COMPANY_NAME:-}"
ADMIN_USERNAME="${ADMIN_USERNAME:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"

# ====== Détection du mode d'exécution ======
INTERACTIVE_MODE=false
if [[ -t 0 ]] && [[ "${FORCE_NON_INTERACTIVE:-}" != "true" ]]; then
    INTERACTIVE_MODE=true
    echo "🎛️  Mode interactif détecté"
else
    echo "🤖 Mode non-interactif (curl | bash)"
fi

# ====== Configuration du domaine ======
echo "🌐 Configuration du domaine pour l'API Boxion"
if [[ "$INTERACTIVE_MODE" == "true" ]] && [[ -z "$DOMAIN" ]]; then
    echo "Options disponibles:"
    echo "  1. Votre propre domaine (ex: vpn.mondomaine.com)"
    echo "  2. Adresse IP publique de ce serveur (pour tests)" 
    echo "  3. Domaine par défaut (tunnel.milkywayhub.org)"
    echo
    read -p "🌐 Nom de domaine ou IP [tunnel.milkywayhub.org]: " DOMAIN_INPUT
    
    # Validation format domaine/IP
    if [[ -n "$DOMAIN_INPUT" ]]; then
        if [[ ! "$DOMAIN_INPUT" =~ ^[a-zA-Z0-9.-]+$ ]]; then
            echo "❌ ERREUR: Format domaine invalide (caractères autorisés: a-z, 0-9, ., -)"
            exit 1
        fi
        if [[ ${#DOMAIN_INPUT} -gt 253 ]]; then
            echo "❌ ERREUR: Domaine trop long (max 253 caractères)"
            exit 1
        fi
        DOMAIN="$DOMAIN_INPUT"
    else
        DOMAIN="tunnel.milkywayhub.org"
    fi
    echo "🌐 Domaine sélectionné: $DOMAIN"
elif [[ -z "$DOMAIN" ]]; then
    DOMAIN="tunnel.milkywayhub.org"
    echo "🌐 Domaine par défaut utilisé: $DOMAIN"
else
    echo "🌐 Domaine configuré: $DOMAIN"
fi

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

# Configuration email
if [[ "$INTERACTIVE_MODE" == "true" ]] && [[ -z "$EMAIL" ]]; then
    read -p "📧 Email pour Let's Encrypt [admin@${DOMAIN}]: " EMAIL_INPUT
    EMAIL="${EMAIL_INPUT:-admin@${DOMAIN}}"
    echo "📧 Email configuré: $EMAIL"
elif [[ -z "$EMAIL" ]]; then
    EMAIL="admin@${DOMAIN}"
    echo "📧 Email par défaut utilisé: $EMAIL"
else
    echo "📧 Email configuré: $EMAIL"
fi

echo
echo "🏢 === PERSONNALISATION DASHBOARD ==="
# Configuration dashboard
if [[ "$INTERACTIVE_MODE" == "true" ]] && [[ -z "$COMPANY_NAME" ]]; then
    read -p "🏢 Nom de votre entreprise [Gasser IT Services]: " COMPANY_INPUT
    COMPANY_NAME="${COMPANY_INPUT:-Gasser IT Services}"
elif [[ -z "$COMPANY_NAME" ]]; then
    COMPANY_NAME="Gasser IT Services"
fi
echo "🏢 Entreprise configurée: $COMPANY_NAME"

# Pages légales
if [[ "$INTERACTIVE_MODE" == "true" ]] && [[ -z "$INCLUDE_LEGAL" ]]; then
    read -p "⚖️  Inclure les pages légales (confidentialité, mentions) ? [o/N]: " LEGAL_INPUT
    INCLUDE_LEGAL="${LEGAL_INPUT:-n}"
    if [[ "$INCLUDE_LEGAL" =~ ^[Oo]([Uu][Ii])?$ ]]; then
        INCLUDE_LEGAL="true"
    else
        INCLUDE_LEGAL="false"
    fi
elif [[ -z "$INCLUDE_LEGAL" ]]; then
    INCLUDE_LEGAL="false"
fi
echo "⚖️  Pages légales: $INCLUDE_LEGAL"

echo
echo "🔐 === CREDENTIALS ADMIN ==="
# Configuration admin
if [[ "$INTERACTIVE_MODE" == "true" ]] && [[ -z "$ADMIN_USERNAME" ]]; then
    read -p "👤 Nom d'utilisateur admin [admin]: " ADMIN_USER_INPUT
    
    # Validation nom utilisateur admin
    if [[ -n "$ADMIN_USER_INPUT" ]]; then
        if [[ ! "$ADMIN_USER_INPUT" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            echo "❌ ERREUR: Nom utilisateur invalide (caractères autorisés: a-z, 0-9, _, -)"
            exit 1
        fi
        if [[ ${#ADMIN_USER_INPUT} -lt 2 || ${#ADMIN_USER_INPUT} -gt 32 ]]; then
            echo "❌ ERREUR: Nom utilisateur doit faire entre 2 et 32 caractères"
            exit 1
        fi
        ADMIN_USERNAME="$ADMIN_USER_INPUT"
    else
        ADMIN_USERNAME="admin"
    fi
elif [[ -z "$ADMIN_USERNAME" ]]; then
    ADMIN_USERNAME="admin"
fi
echo "👤 Utilisateur admin: $ADMIN_USERNAME"

# Mot de passe admin
if [[ "$INTERACTIVE_MODE" == "true" ]] && [[ -z "$ADMIN_PASSWORD" ]]; then
    read -p "🔑 Mot de passe admin (laissez vide pour génération automatique): " ADMIN_PASS_INPUT
    if [[ -n "$ADMIN_PASS_INPUT" ]]; then
        # Validation sécurité mot de passe
        if [[ ${#ADMIN_PASS_INPUT} -lt 8 ]]; then
            echo "❌ ERREUR: Mot de passe trop court (minimum 8 caractères)"
            exit 1
        fi
        if [[ ! "$ADMIN_PASS_INPUT" =~ [A-Z] ]] || [[ ! "$ADMIN_PASS_INPUT" =~ [a-z] ]] || [[ ! "$ADMIN_PASS_INPUT" =~ [0-9] ]]; then
            echo "❌ ERREUR: Mot de passe doit contenir au moins 1 majuscule, 1 minuscule et 1 chiffre"
            exit 1
        fi
        ADMIN_PASSWORD="$ADMIN_PASS_INPUT"
        echo "🔑 Mot de passe admin: [personnalisé]"
    else
        ADMIN_PASSWORD=""
        echo "🔑 Mot de passe admin: [génération automatique]"
    fi
elif [[ -z "$ADMIN_PASSWORD" ]]; then
    ADMIN_PASSWORD=""
    echo "🔑 Mot de passe admin: [génération automatique]"
else
    echo "🔑 Mot de passe admin: [configuré]"
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
# Auto-sélection de l'interface (non-interactif)
IFACE_CHOICE="0"
echo "📡 Auto-détection activée (mode non-interactif)"

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
# Récupération de l'IPv6 globale sur l'interface WAN
V6=$(ip -6 addr show dev "$WAN_IF" scope global 2>/dev/null | awk '/inet6/ && !/temporary/ {print $2; exit}' | cut -d/ -f1)

if [[ -n "$V6" ]]; then
  PREFIX=$(printf "%s:%s:%s:%s" $(echo "$V6" | awk -F: '{print $1,$2,$3,$4}'))
  echo "🌐 Préfixe IPv6 détecté: ${PREFIX}::/64"
else
  echo "⚠️  Aucune IPv6 globale détectée sur $WAN_IF"
  echo "🌐 Utilisation du préfixe par défaut (mode non-interactif)"
  PREFIX="2a0c:xxxx:xxxx:abcd"
  echo "🌐 Préfixe IPv6 par défaut: ${PREFIX}::/64"
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
  if ! cd "$REPO_DIR"; then
    echo "❌ ERREUR: Impossible d'accéder au répertoire $REPO_DIR"
    exit 1
  fi
  git pull
else
  echo "📥 Clonage du repository..."
  if ! git clone https://github.com/J0bot/boxion-setup.git "$REPO_DIR"; then
    echo "❌ ERREUR: Échec clonage repository"
    exit 1
  fi
  if ! cd "$REPO_DIR"; then
    echo "❌ ERREUR: Impossible d'accéder au répertoire cloné $REPO_DIR"
    exit 1
  fi
fi

# ====== Installation serveur modulaire ======
echo "⚙️  Installation du serveur Boxion (architecture modulaire)..."
chmod +x install/provisioner.sh

# Export des variables de personnalisation pour les modules
export COMPANY_NAME="$COMPANY_NAME"
export INCLUDE_LEGAL="$INCLUDE_LEGAL"
export ADMIN_USERNAME="$ADMIN_USERNAME"
export ADMIN_PASSWORD="$ADMIN_PASSWORD"
export DOMAIN="$DOMAIN"
export API_TOKEN="$TOKEN"
export IPV6_PREFIX="$PREFIX"
export PORT="51820"
export WAN_IF="$WAN_IF"

./install/provisioner.sh

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
