#!/usr/bin/env bash

# 🚀 BOXION CLIENT - CONNEXION SIMPLE AU TUNNEL IPv6
# Script ultra-simple pour connecter votre Boxion au tunnel et obtenir une IPv6 publique
# Simple, sécurisé, fonctionnel !

set -euo pipefail

# ========================================
# 🎯 CONFIGURATION & VARIABLES
# ========================================

# Couleurs pour les logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Variables par défaut
SERVER_URL=""
API_TOKEN=""
BOXION_NAME=""
DNS_LINE=""
SERVER_V6=""

# ========================================
# 🔍 VALIDATION PRÉALABLE
# ========================================

check_requirements() {
    log_info "Vérification des prérequis..."
    
    # Vérification root
    if [[ $EUID -ne 0 ]]; then
        log_error "Ce script doit être exécuté en tant que root"
        log_info "Utilisez: sudo $0"
        exit 1
    fi
    
    # Vérification WireGuard
    if ! command -v wg >/dev/null 2>&1; then
        log_info "Installation de WireGuard..."
        if command -v apt-get >/dev/null 2>&1; then
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq && apt-get install -y wireguard >/dev/null
        else
            log_error "Installation WireGuard requise (Debian/Ubuntu uniquement)"
            exit 1
        fi
    fi

    # Vérification jq (parsing JSON)
    if ! command -v jq >/dev/null 2>&1; then
        log_info "Installation de jq..."
        if command -v apt-get >/dev/null 2>&1; then
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq && apt-get install -y jq >/dev/null
        else
            log_error "jq requis pour parser la réponse JSON"
            exit 1
        fi
    fi
    
    log_success "Prérequis validés"
}

# ========================================
# 📝 CONFIGURATION INTERACTIVE
# ========================================

get_configuration() {
    log_info "Configuration de la connexion..."
    
    # Mode non-interactif (variables d'environnement)
    if [[ -n "${BOXION_SERVER_URL:-}" && -n "${BOXION_API_TOKEN:-}" ]]; then
        SERVER_URL="$BOXION_SERVER_URL"
        API_TOKEN="$BOXION_API_TOKEN"
        BOXION_NAME="${BOXION_NAME:-boxion-$(hostname)}"
        log_info "Configuration automatique détectée"
        return
    fi
    
    # Mode interactif
    echo ""
    echo "🔧 Configuration de votre Boxion"
    echo "================================"
    echo ""
    
    # Serveur tunnel
    while [[ -z "$SERVER_URL" ]]; do
        echo -n "🌐 URL du serveur tunnel (ex: https://tunnel.milkywayhub.org): "
        read -r SERVER_URL
        SERVER_URL="${SERVER_URL%/}" # Supprime le / final
        
        if [[ ! "$SERVER_URL" =~ ^https?:// ]]; then
            log_error "L'URL doit commencer par http:// ou https://"
            SERVER_URL=""
        fi
    done
    
    # Token API ou OTP (usage unique)
    while [[ -z "$API_TOKEN" ]]; do
        echo -n "🔑 Token API ou OTP (fourni par l'administrateur): "
        read -r API_TOKEN
        # OTP = 32 hex, API token = 64 hex (par défaut). On accepte >=32.
        if [[ ${#API_TOKEN} -lt 32 ]]; then
            log_error "Le token semble trop court (minimum 32 caractères)"
            API_TOKEN=""
        fi
    done
    
    # Nom de la Boxion
    echo -n "📛 Nom de votre Boxion [$(hostname)]: "
    read -r input_name
    BOXION_NAME="${input_name:-$(hostname)}"
    
    log_success "Configuration complétée"
}

# ========================================
# 🔐 GÉNÉRATION DES CLÉS WIREGUARD
# ========================================

generate_keys() {
    log_info "Génération des clés WireGuard..."
    
    # Génération des clés
    PRIVATE_KEY=$(wg genkey)
    PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)
    
    log_success "Clés générées (Publique: ${PUBLIC_KEY:0:20}...)"
}

# ========================================
# 📡 ENREGISTREMENT AUPRÈS DU SERVEUR
# ========================================

register_with_server() {
    log_info "Enregistrement auprès du serveur tunnel..."
    
    # Préparation de la requête
    local payload
    payload=$(cat << EOF
{
    "name": "$BOXION_NAME",
    "public_key": "$PUBLIC_KEY"
}
EOF
)
    
    # Appel à l'API
    local response
    local http_code
    
    response=$(curl -s -w "%{http_code}" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $API_TOKEN" \
        -d "$payload" \
        "$SERVER_URL/api/" \
        2>/dev/null)
    
    http_code="${response: -3}"
    response="${response%???}"
    
    # Vérification de la réponse
    case "$http_code" in
        200)
            log_success "Enregistrement réussi"
            ;;
        401|403)
            log_error "Token API invalide"
            log_info "Vérifiez votre token auprès de l'administrateur"
            exit 1
            ;;
        409)
            log_error "Cette clé publique est déjà enregistrée"
            log_info "Supprimez d'abord l'ancienne configuration"
            exit 1
            ;;
        *)
            log_error "Erreur serveur (Code: $http_code)"
            log_info "Réponse: $response"
            exit 1
            ;;
    esac
    
    # Extraction de la configuration (JSON)
    IPV6_ADDRESS=$(echo "$response" | jq -r '.Address // empty')
    SERVER_PUBLIC_KEY=$(echo "$response" | jq -r '.PublicKey // empty')
    SERVER_ENDPOINT=$(echo "$response" | jq -r '.Endpoint // empty')
    
    if [[ -z "$IPV6_ADDRESS" || -z "$SERVER_PUBLIC_KEY" || -z "$SERVER_ENDPOINT" ]]; then
        log_error "Réponse serveur invalide"
        exit 1
    fi
    
    log_success "Configuration reçue (IPv6: $IPV6_ADDRESS)"
}

# ========================================
# 🧭 PRÉPARATION DNS (resolvconf/resolvectl)
# ========================================

ensure_dns_support() {
    log_info "Détection du gestionnaire DNS pour WireGuard..."
    DNS_LINE=""

    if command -v resolvectl >/dev/null 2>&1 || \
       command -v systemd-resolve >/dev/null 2>&1 || \
       command -v resolvconf >/dev/null 2>&1; then
        # Un gestionnaire est présent, on peut définir DNS dans wg-quick
        DNS_LINE="DNS = 2001:4860:4860::8888, 2001:4860:4860::8844"
    else
        # Tentative d'installation silencieuse si possible
        if command -v apt-get >/dev/null 2>&1; then
            log_info "Installation de resolvconf pour gérer le DNS..."
            export DEBIAN_FRONTEND=noninteractive
            if apt-get update -qq && apt-get install -y resolvconf >/dev/null 2>&1; then
                DNS_LINE="DNS = 2001:4860:4860::8888, 2001:4860:4860::8844"
                log_success "resolvconf installé"
            elif apt-get install -y openresolv >/dev/null 2>&1; then
                DNS_LINE="DNS = 2001:4860:4860::8888, 2001:4860:4860::8844"
                log_success "openresolv installé"
            else
                log_warning "Impossible d'installer resolvconf; la ligne DNS sera omise"
            fi
        else
            log_warning "Aucun gestionnaire DNS détecté; la ligne DNS sera omise"
        fi
    fi
}

# ========================================
# ⚙️ CONFIGURATION WIREGUARD LOCAL
# ========================================

setup_local_wireguard() {
    log_info "Configuration WireGuard local..."
    
    # Création de la configuration
    local config_file="/etc/wireguard/boxion.conf"
    
    cat > "$config_file" << EOF
[Interface]
PrivateKey = $PRIVATE_KEY
Address = $IPV6_ADDRESS
$DNS_LINE

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_ENDPOINT
AllowedIPs = ::/0
PersistentKeepalive = 25
EOF
    
    # Permissions sécurisées
    chmod 600 "$config_file"
    
    # Activation du service
    systemctl enable wg-quick@boxion 2>/dev/null || true
    
    log_success "Configuration WireGuard créée"
}

# ========================================
# 🔎 DÉRIVATION DE L'IPv6 SERVEUR (wg0)
# ========================================

derive_server_ipv6() {
    # Ex: IPV6_ADDRESS = 2001:1600:16:10::103/128 -> SERVER_V6 = 2001:1600:16:10::1
    local addr_no_prefix="${IPV6_ADDRESS%%/*}"
    if [[ "$addr_no_prefix" == *"::"* ]]; then
        SERVER_V6="${addr_no_prefix%::*}::1"
    else
        SERVER_V6=""
    fi
}

# ========================================
# 🚀 ACTIVATION DE LA CONNEXION
# ========================================

start_connection() {
    log_info "Activation de la connexion tunnel..."
    
    # Arrêt de toute ancienne connexion
    systemctl stop wg-quick@boxion 2>/dev/null || true
    
    # Démarrage de la nouvelle connexion
    if systemctl start wg-quick@boxion; then
        log_success "Connexion tunnel active"
    else
        log_error "Échec d'activation de la connexion"
        log_info "Vérifiez les logs: journalctl -u wg-quick@boxion"
        exit 1
    fi
    
    # Vérification de la connectivité IPv6 (sans dépendre du DNS)
    sleep 3
    local target="${SERVER_V6:-}"
    if [[ -z "$target" ]]; then
        target="2001:4860:4860::8888"  # Fallback: Google Public DNS v6
    fi
    if ping6 -c 1 "$target" >/dev/null 2>&1; then
        log_success "Connectivité IPv6 validée (ping $target)"
    else
        log_warning "IPv6 non confirmée (ping $target). Vérifiez pare-feu et réseau, cela peut être normal."
    fi
}

# ========================================
# 📊 AFFICHAGE DES INFORMATIONS
# ========================================

show_status() {
    echo ""
    echo "🎉 BOXION CONNECTÉE AVEC SUCCÈS !"
    echo "================================="
    echo ""
    log_success "Nom: $BOXION_NAME"
    log_success "IPv6 publique: $IPV6_ADDRESS"
    log_success "Serveur tunnel: $SERVER_ENDPOINT"
    echo ""
    log_info "Commandes utiles:"
    echo "  • Statut: systemctl status wg-quick@boxion"
    echo "  • Arrêt: systemctl stop wg-quick@boxion"
    echo "  • Redémarrage: systemctl restart wg-quick@boxion"
    echo "  • Configuration: cat /etc/wireguard/boxion.conf"
    echo ""
    log_info "Votre Boxion a maintenant une IPv6 publique accessible depuis Internet !"
}

# ========================================
# 🚀 FONCTION PRINCIPALE
# ========================================

main() {
    echo "🚀 Installation Boxion Client - Version Simple"
    echo "=============================================="
    echo ""
    
    check_requirements
    get_configuration
    generate_keys
    register_with_server
    ensure_dns_support
    derive_server_ipv6
    setup_local_wireguard
    start_connection
    show_status
}

# Gestion de l'interruption propre
cleanup() {
    log_warning "Interruption détectée - nettoyage..."
    exit 1
}
trap cleanup SIGINT SIGTERM

# Exécution du script principal
main "$@"
