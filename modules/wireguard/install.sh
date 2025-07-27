#!/usr/bin/env bash

# 🔒 Module WireGuard - Configuration VPN serveur
# Extrait du monolithe setup.sh pour une approche modulaire

set -euo pipefail

# Source du logging
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../logging/logger.sh"

MODULE_NAME="WIREGUARD"
log_info "$MODULE_NAME" "Début installation module WireGuard"

# Variables globales du module
WG_IF="${WG_IF:-wg0}"
WG_CONFIG_DIR="/etc/wireguard"
WG_CONFIG_FILE="$WG_CONFIG_DIR/${WG_IF}.conf"
SERVER_KEYS_DIR="$WG_CONFIG_DIR/keys"

# ====== VALIDATION DES PARAMÈTRES ======

validate_parameters() {
    log_step "$MODULE_NAME" "Validation des paramètres" "1/6"
    
    # Validation domaine
    validate_or_fatal "$MODULE_NAME" "[[ -n \$DOMAIN ]]" "Domaine requis (variable DOMAIN)"
    log_debug "$MODULE_NAME" "Domaine: $DOMAIN"
    
    # Validation préfixe IPv6
    validate_or_fatal "$MODULE_NAME" "[[ -n \$IPV6_PREFIX ]]" "Préfixe IPv6 requis (variable IPV6_PREFIX)"
    if [[ ! "$IPV6_PREFIX" =~ ^[0-9a-f:]+$ ]]; then
        log_fatal "$MODULE_NAME" "Format préfixe IPv6 invalide: $IPV6_PREFIX"
    fi
    log_debug "$MODULE_NAME" "Préfixe IPv6: ${IPV6_PREFIX}::/64"
    
    # Validation port
    local port="${PORT:-51820}"
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ $port -lt 1 || $port -gt 65535 ]]; then
        log_fatal "$MODULE_NAME" "Port invalide: $port"
    fi
    log_debug "$MODULE_NAME" "Port WireGuard: $port"
    
    # Validation interface WAN
    validate_or_fatal "$MODULE_NAME" "[[ -n \$WAN_IF ]]" "Interface WAN requise (variable WAN_IF)"
    validate_or_fatal "$MODULE_NAME" "ip link show \$WAN_IF >/dev/null 2>&1" "Interface WAN introuvable: $WAN_IF"
    log_debug "$MODULE_NAME" "Interface WAN: $WAN_IF"
    
    log_success "$MODULE_NAME" "Paramètres validés"
}

# ====== GÉNÉRATION DES CLÉS ======

generate_server_keys() {
    log_step "$MODULE_NAME" "Génération des clés serveur" "2/6"
    
    # Création répertoire sécurisé pour les clés
    if ! mkdir -p "$SERVER_KEYS_DIR" 2>/dev/null; then
        log_fatal "$MODULE_NAME" "Impossible de créer: $SERVER_KEYS_DIR"
    fi
    chmod 700 "$SERVER_KEYS_DIR"
    log_debug "$MODULE_NAME" "Répertoire clés créé: $SERVER_KEYS_DIR"
    
    # Fichiers de clés
    local private_key_file="$SERVER_KEYS_DIR/server_private.key"
    local public_key_file="$SERVER_KEYS_DIR/server_public.key"
    local legacy_public_file="$WG_CONFIG_DIR/server_public.key"  # Compatibilité
    
    # Génération uniquement si les clés n'existent pas
    if [[ -f "$private_key_file" && -f "$public_key_file" ]]; then
        log_info "$MODULE_NAME" "Clés serveur existantes détectées - réutilisation"
        SV_PRIV=$(cat "$private_key_file")
        SV_PUB=$(cat "$public_key_file")
        log_debug "$MODULE_NAME" "Clés chargées depuis: $SERVER_KEYS_DIR"
    else
        log_info "$MODULE_NAME" "Génération de nouvelles clés serveur..."
        
        # Sécurisation umask pour génération clés
        local old_umask=$(umask)
        umask 077
        
        # Génération clé privée
        log_debug "$MODULE_NAME" "Génération clé privée..."
        if ! SV_PRIV=$(wg genkey); then
            log_fatal "$MODULE_NAME" "Échec génération clé privée"
        fi
        
        # Génération clé publique
        log_debug "$MODULE_NAME" "Génération clé publique..."
        if ! SV_PUB=$(echo "$SV_PRIV" | wg pubkey); then
            log_fatal "$MODULE_NAME" "Échec génération clé publique"
        fi
        
        # Sauvegarde sécurisée
        if ! echo "$SV_PRIV" > "$private_key_file"; then
            log_fatal "$MODULE_NAME" "Impossible de sauvegarder clé privée"
        fi
        
        if ! echo "$SV_PUB" > "$public_key_file"; then
            log_fatal "$MODULE_NAME" "Impossible de sauvegarder clé publique"
        fi
        
        # Compatibilité avec ancien système
        echo "$SV_PUB" > "$legacy_public_file"
        
        # Permissions restrictives
        chmod 600 "$private_key_file"
        chmod 644 "$public_key_file" "$legacy_public_file"
        
        # Restauration umask
        umask "$old_umask"
        
        log_success "$MODULE_NAME" "Nouvelles clés générées et sauvegardées"
        log_debug "$MODULE_NAME" "Clé publique: ${SV_PUB:0:20}..."
    fi
    
    # Export des variables pour autres étapes
    export SV_PRIV SV_PUB
}

# ====== GÉNÉRATION DE LA CONFIGURATION ======

generate_wireguard_config() {
    log_step "$MODULE_NAME" "Génération configuration WireGuard" "3/6"
    
    local port="${PORT:-51820}"
    log_info "$MODULE_NAME" "Configuration pour interface $WG_IF (port $port)"
    
    # Génération de la configuration optimisée Debian 12
    log_debug "$MODULE_NAME" "Écriture: $WG_CONFIG_FILE"
    
    cat > "$WG_CONFIG_FILE" << EOF
# Configuration WireGuard Serveur - Boxion Tunnel VPN
# Générée automatiquement le $(date)
# Interface: $WG_IF, Port: $port, Domaine: $DOMAIN

[Interface]
# Clé privée serveur (gardée secrète)
PrivateKey = $SV_PRIV

# Adresse IPv6 serveur (::1 = gateway du réseau)
Address = ${IPV6_PREFIX}::1/64

# Port d'écoute UDP
ListenPort = $port

# SÉCURITÉ: SaveConfig désactivé (gestion via API uniquement)
SaveConfig = false

# PostUp: Configuration réseau automatique au démarrage
PostUp = sysctl -w net.ipv6.conf.all.forwarding=1
PostUp = sysctl -w net.ipv6.conf.$WAN_IF.proxy_ndp=1
PostUp = ip6tables -I FORWARD -i %i -j ACCEPT || true
PostUp = ip6tables -I FORWARD -o %i -j ACCEPT || true

# PreDown: Nettoyage règles au shutdown
PreDown = ip6tables -D FORWARD -i %i -j ACCEPT || true
PreDown = ip6tables -D FORWARD -o %i -j ACCEPT || true

# Les peers seront ajoutés dynamiquement via l'API
# Configuration peer management: API REST + SQLite + scripts sudo

EOF

    # Validation fichier généré
    if [[ ! -f "$WG_CONFIG_FILE" ]]; then
        log_fatal "$MODULE_NAME" "Configuration non créée: $WG_CONFIG_FILE"
    fi
    
    # Vérification syntaxe
    local config_lines=$(wc -l < "$WG_CONFIG_FILE")
    if [[ $config_lines -lt 10 ]]; then
        log_fatal "$MODULE_NAME" "Configuration trop courte ($config_lines lignes) - génération échouée"
    fi
    
    # Permissions sécurisées
    chmod 600 "$WG_CONFIG_FILE"
    chown root:root "$WG_CONFIG_FILE"
    
    log_success "$MODULE_NAME" "Configuration générée ($config_lines lignes)"
    log_debug "$MODULE_NAME" "Interface: $WG_IF → ${IPV6_PREFIX}::1/64"
}

# ====== ACTIVATION DU SERVICE ======

enable_wireguard_service() {
    log_step "$MODULE_NAME" "Activation service WireGuard" "4/6"
    
    local service_name="wg-quick@$WG_IF"
    log_info "$MODULE_NAME" "Configuration du service: $service_name"
    
    # Validation de la configuration avant activation
    log_debug "$MODULE_NAME" "Validation syntaxe configuration..."
    if ! wg-quick strip "$WG_IF" >/dev/null 2>/tmp/wg-validation.log; then
        log_error_context "$MODULE_NAME" "Configuration WireGuard invalide" "$(cat /tmp/wg-validation.log)"
        rm -f /tmp/wg-validation.log
        return 1
    fi
    log_debug "$MODULE_NAME" "Configuration validée"
    
    # Arrêt du service s'il est déjà actif (pour reconfiguration)
    if systemctl is-active "$service_name" >/dev/null 2>&1; then
        log_info "$MODULE_NAME" "Service déjà actif - redémarrage..."
        if ! systemctl stop "$service_name" 2>/tmp/systemctl-stop.log; then
            log_error_context "$MODULE_NAME" "Échec arrêt service" "$(cat /tmp/systemctl-stop.log)"
        fi
        sleep 2  # Attente pour libération interface
    fi
    
    # Activation du service
    log_info "$MODULE_NAME" "Démarrage du service WireGuard..."
    if ! systemctl start "$service_name" 2>/tmp/systemctl-start.log; then
        log_error_context "$MODULE_NAME" "Échec démarrage service" "$(cat /tmp/systemctl-start.log)"
        
        # Debug supplémentaire
        log_debug "$MODULE_NAME" "Statut interface avant échec:"
        ip link show "$WG_IF" 2>/dev/null | head -1 || log_debug "$MODULE_NAME" "Interface $WG_IF inexistante"
        
        rm -f /tmp/systemctl-*.log
        return 1
    fi
    
    # Activation au boot
    if ! systemctl enable "$service_name" 2>/dev/null; then
        log_warn "$MODULE_NAME" "Impossible d'activer au boot - service fonctionnel"
    else
        log_debug "$MODULE_NAME" "Service activé au boot"
    fi
    
    # Attente stabilisation
    sleep 3
    
    # Validation du service actif
    if ! systemctl is-active "$service_name" >/dev/null 2>&1; then
        log_fatal "$MODULE_NAME" "Service non actif après démarrage"
    fi
    
    log_success "$MODULE_NAME" "Service WireGuard actif"
    
    # Nettoyage logs temporaires
    rm -f /tmp/systemctl-*.log /tmp/wg-validation.log
}

# ====== VALIDATION DE L'INTERFACE ======

validate_wireguard_interface() {
    log_step "$MODULE_NAME" "Validation interface WireGuard" "5/6"
    
    # Vérification existence interface
    if ! ip link show "$WG_IF" >/dev/null 2>&1; then
        log_fatal "$MODULE_NAME" "Interface $WG_IF non créée"
    fi
    log_debug "$MODULE_NAME" "Interface $WG_IF détectée"
    
    # Vérification configuration active
    if ! wg show "$WG_IF" >/dev/null 2>&1; then
        log_fatal "$MODULE_NAME" "Configuration WireGuard non active sur $WG_IF"
    fi
    
    # Récupération informations interface
    local interface_info=$(wg show "$WG_IF" 2>/dev/null)
    local listening_port=$(echo "$interface_info" | grep "listening port:" | awk '{print $3}')
    local public_key=$(echo "$interface_info" | grep "public key:" | awk '{print $3}')
    
    # Validation port d'écoute
    local expected_port="${PORT:-51820}"
    if [[ "$listening_port" != "$expected_port" ]]; then
        log_error "$MODULE_NAME" "Port incorrect: $listening_port (attendu: $expected_port)"
        return 1
    fi
    log_debug "$MODULE_NAME" "Port d'écoute: $listening_port"
    
    # Validation clé publique
    if [[ -z "$public_key" ]]; then
        log_error "$MODULE_NAME" "Clé publique non détectée sur l'interface"
        return 1
    fi
    
    if [[ "$public_key" != "$SV_PUB" ]]; then
        log_error "$MODULE_NAME" "Clé publique différente de celle générée"
        return 1
    fi
    log_debug "$MODULE_NAME" "Clé publique: ${public_key:0:20}..."
    
    # Vérification adresse IPv6
    local ipv6_addr=$(ip -6 addr show "$WG_IF" | grep "inet6" | grep -v "fe80" | awk '{print $2}')
    local expected_addr="${IPV6_PREFIX}::1/64"
    
    if [[ "$ipv6_addr" != "$expected_addr" ]]; then
        log_warn "$MODULE_NAME" "Adresse IPv6 différente: $ipv6_addr (attendue: $expected_addr)"
    else
        log_debug "$MODULE_NAME" "Adresse IPv6: $ipv6_addr"
    fi
    
    log_success "$MODULE_NAME" "Interface WireGuard validée"
}

# ====== TEST DE CONNECTIVITÉ ======

test_wireguard_connectivity() {
    log_step "$MODULE_NAME" "Tests de connectivité" "6/6"
    
    # Test ping local sur l'interface
    local gateway_ip="${IPV6_PREFIX}::1"
    log_debug "$MODULE_NAME" "Test ping local: $gateway_ip"
    
    if ping6 -c 1 -W 2 "$gateway_ip" >/dev/null 2>&1; then
        log_success "$MODULE_NAME" "Ping local IPv6 réussi"
    else
        log_warn "$MODULE_NAME" "Ping local IPv6 échoué - peut être normal"
    fi
    
    # Test résolution DNS (si disponible)
    if command -v nslookup >/dev/null 2>&1; then
        log_debug "$MODULE_NAME" "Test résolution DNS..."
        if nslookup "$DOMAIN" >/dev/null 2>&1; then
            log_debug "$MODULE_NAME" "Résolution DNS fonctionnelle: $DOMAIN"
        else
            log_warn "$MODULE_NAME" "Résolution DNS échouée: $DOMAIN"
        fi
    fi
    
    # Statistiques finales
    local peer_count=$(wg show "$WG_IF" peers | wc -l)
    log_info "$MODULE_NAME" "Interface configurée - $peer_count peer(s) connecté(s)"
    
    log_success "$MODULE_NAME" "Tests de connectivité terminés"
}

# ====== AFFICHAGE DES INFORMATIONS ======

display_wireguard_info() {
    log_info "$MODULE_NAME" "=== INFORMATIONS WIREGUARD ==="
    log_info "$MODULE_NAME" "Interface: $WG_IF"
    log_info "$MODULE_NAME" "Port: ${PORT:-51820}"
    log_info "$MODULE_NAME" "Domaine: $DOMAIN"
    log_info "$MODULE_NAME" "IPv6 Gateway: ${IPV6_PREFIX}::1/64"
    log_info "$MODULE_NAME" "Clé publique: $SV_PUB"
    log_info "$MODULE_NAME" "Service: $(systemctl is-active "wg-quick@$WG_IF")"
    
    # Export des variables importantes pour autres modules
    echo "export SV_PUB='$SV_PUB'" > /tmp/boxion-wireguard-vars.sh
    echo "export WG_IF='$WG_IF'" >> /tmp/boxion-wireguard-vars.sh
    echo "export IPV6_PREFIX='$IPV6_PREFIX'" >> /tmp/boxion-wireguard-vars.sh
    
    log_debug "$MODULE_NAME" "Variables exportées: /tmp/boxion-wireguard-vars.sh"
}

# ====== MAIN MODULE ======

main() {
    log_info "$MODULE_NAME" "=== INSTALLATION MODULE WIREGUARD ==="
    
    # Vérification privilèges root
    if [[ $UID -ne 0 ]]; then
        log_fatal "$MODULE_NAME" "Privilèges root requis"
    fi
    
    # Séquence d'installation WireGuard
    validate_parameters
    generate_server_keys
    generate_wireguard_config
    enable_wireguard_service
    validate_wireguard_interface
    test_wireguard_connectivity
    display_wireguard_info
    
    log_success "$MODULE_NAME" "Module WireGuard installé avec succès!"
    return 0
}

# Exécution si appelé directement
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
