#!/usr/bin/env bash

# 📦 Module System - Installation paquets et configuration système
# Extrait du monolithe setup.sh pour une approche modulaire

set -euo pipefail

# Source du logging
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../logging/logger.sh"

MODULE_NAME="SYSTEM"
log_info "$MODULE_NAME" "Début installation module système"

# ====== INSTALLATION DES PAQUETS ======

install_packages() {
    log_step "$MODULE_NAME" "Installation des paquets système" "1/4"
    
    # Configuration pour éviter les prompts interactifs
    export DEBIAN_FRONTEND=noninteractive
    log_debug "$MODULE_NAME" "DEBIAN_FRONTEND=noninteractive configuré"
    
    # Mise à jour des sources
    log_info "$MODULE_NAME" "Mise à jour des sources de paquets..."
    if ! apt-get update -qq 2>/tmp/apt-update.log; then
        log_error_context "$MODULE_NAME" "Échec mise à jour sources" "$(cat /tmp/apt-update.log)"
        return 1
    fi
    log_success "$MODULE_NAME" "Sources de paquets mises à jour"
    
    # Liste des paquets requis
    local packages=(
        "wireguard"         # WireGuard VPN
        "iptables"          # Firewall rules
        "php-fpm"           # PHP FastCGI Process Manager
        "php-cli"           # PHP Command Line Interface
        "php-sqlite3"       # PHP SQLite3 extension
        "nginx"             # Web server
        "jq"                # JSON processor
        "sqlite3"           # SQLite database
        "openssl"           # Cryptographic toolkit
        "curl"              # HTTP client
    )
    
    log_info "$MODULE_NAME" "Installation des paquets: ${packages[*]}"
    
    # Installation avec gestion d'erreur détaillée
    local failed_packages=()
    for package in "${packages[@]}"; do
        log_debug "$MODULE_NAME" "Installation: $package"
        if ! apt-get install -y "$package" 2>/tmp/apt-install-$package.log; then
            failed_packages+=("$package")
            log_error "$MODULE_NAME" "Échec installation: $package"
            log_debug "$MODULE_NAME" "Logs: $(head -3 /tmp/apt-install-$package.log)"
        else
            log_debug "$MODULE_NAME" "✅ $package installé"
        fi
    done
    
    # Vérification des échecs
    if [[ ${#failed_packages[@]} -gt 0 ]]; then
        log_fatal "$MODULE_NAME" "Paquets non installés: ${failed_packages[*]}"
    fi
    
    log_success "$MODULE_NAME" "Tous les paquets installés avec succès"
    
    # Nettoyage des logs temporaires
    rm -f /tmp/apt-*.log
}

# ====== CONFIGURATION SYSTÈME ======

configure_sysctl() {
    log_step "$MODULE_NAME" "Configuration noyau (sysctl)" "2/4"
    
    local sysctl_file="/etc/sysctl.d/99-boxion-tunnel.conf"
    
    log_info "$MODULE_NAME" "Création de la configuration sysctl: $sysctl_file"
    
    cat > "$sysctl_file" << 'EOF'
# Configuration réseau pour Boxion Tunnel VPN
# Activation du forwarding IPv4/IPv6 et NDP proxy

# IPv4 forwarding (routage)
net.ipv4.ip_forward = 1

# IPv6 forwarding (routage)
net.ipv6.conf.all.forwarding = 1

# NDP proxy pour le routage IPv6
net.ipv6.conf.all.proxy_ndp = 1

# Optimisations réseau pour VPN
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Sécurité réseau de base
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
EOF
    
    if [[ ! -f "$sysctl_file" ]]; then
        log_fatal "$MODULE_NAME" "Échec création fichier sysctl: $sysctl_file"
    fi
    
    log_debug "$MODULE_NAME" "Configuration sysctl créée ($(wc -l < "$sysctl_file") lignes)"
    
    # Application de la configuration
    log_info "$MODULE_NAME" "Application de la configuration sysctl..."
    if sysctl -p "$sysctl_file" >/dev/null 2>/tmp/sysctl-error.log; then
        log_success "$MODULE_NAME" "Configuration sysctl appliquée"
    else
        log_error_context "$MODULE_NAME" "Échec application sysctl" "$(cat /tmp/sysctl-error.log)"
        rm -f /tmp/sysctl-error.log
        return 1
    fi
    
    rm -f /tmp/sysctl-error.log
}

# ====== CONFIGURATION FIREWALL ======

configure_firewall() {
    log_step "$MODULE_NAME" "Configuration firewall" "3/4"
    
    local port="${PORT:-51820}"
    log_info "$MODULE_NAME" "Configuration firewall pour port UDP/$port"
    
    # Configuration UFW (si disponible)
    if command -v ufw >/dev/null 2>&1; then
        log_debug "$MODULE_NAME" "Configuration UFW détectée"
        if ufw allow "$port/udp" >/dev/null 2>&1; then
            log_debug "$MODULE_NAME" "Règle UFW ajoutée: $port/udp"
        else
            log_warn "$MODULE_NAME" "Échec configuration UFW - continuons avec iptables"
        fi
    fi
    
    # Configuration iptables directe
    log_debug "$MODULE_NAME" "Configuration iptables pour UDP/$port"
    
    # Vérification si règle existe déjà
    if ! iptables -C INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null; then
        if iptables -A INPUT -p udp --dport "$port" -j ACCEPT 2>/tmp/iptables-error.log; then
            log_success "$MODULE_NAME" "Règle iptables ajoutée: UDP/$port"
        else
            log_error_context "$MODULE_NAME" "Échec règle iptables" "$(cat /tmp/iptables-error.log)"
            rm -f /tmp/iptables-error.log
            return 1
        fi
    else
        log_debug "$MODULE_NAME" "Règle iptables déjà présente: UDP/$port"
    fi
    
    # Règles IPv6 (ip6tables)
    if command -v ip6tables >/dev/null 2>&1; then
        if ! ip6tables -C INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null; then
            if ip6tables -A INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null; then
                log_debug "$MODULE_NAME" "Règle ip6tables ajoutée: UDP/$port"
            else
                log_warn "$MODULE_NAME" "Échec règle ip6tables - IPv6 peut ne pas fonctionner"
            fi
        fi
    fi
    
    log_success "$MODULE_NAME" "Configuration firewall terminée"
}

# ====== CRÉATION DES RÉPERTOIRES SYSTÈME ======

create_system_directories() {
    log_step "$MODULE_NAME" "Création répertoires système" "4/4"
    
    local directories=(
        "/etc/wireguard:700"
        "/var/lib/boxion:755"
        "/var/log/boxion:750"
        "/tmp/boxion-logs:755"
    )
    
    for dir_spec in "${directories[@]}"; do
        IFS=':' read -r dir_path dir_mode <<< "$dir_spec"
        
        log_debug "$MODULE_NAME" "Création: $dir_path (mode: $dir_mode)"
        
        if ! mkdir -p "$dir_path" 2>/dev/null; then
            log_fatal "$MODULE_NAME" "Impossible de créer: $dir_path"
        fi
        
        if ! chmod "$dir_mode" "$dir_path" 2>/dev/null; then
            log_error "$MODULE_NAME" "Impossible de définir permissions $dir_mode pour: $dir_path"
        fi
        
        log_debug "$MODULE_NAME" "✅ $dir_path créé ($(stat -c '%a' "$dir_path"))"
    done
    
    # Vérification critique
    for critical_dir in "/etc/wireguard" "/var/lib/boxion"; do
        if [[ ! -d "$critical_dir" ]]; then
            log_fatal "$MODULE_NAME" "Répertoire critique manquant: $critical_dir"
        fi
        if [[ ! -w "$critical_dir" ]]; then
            log_fatal "$MODULE_NAME" "Répertoire critique non writable: $critical_dir"
        fi
    done
    
    log_success "$MODULE_NAME" "Tous les répertoires système créés"
}

# ====== VALIDATION POST-INSTALLATION ======

validate_system_setup() {
    log_info "$MODULE_NAME" "Validation de l'installation système"
    
    # Vérification services essentiels
    local services=("nginx" "php8.2-fpm" "systemd-resolved")
    for service in "${services[@]}"; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            log_debug "$MODULE_NAME" "✅ Service actif: $service"
        else
            # Démarrage si inactif
            if systemctl start "$service" 2>/dev/null; then
                log_info "$MODULE_NAME" "Service démarré: $service"
            else
                log_warn "$MODULE_NAME" "Service inactif: $service"
            fi
        fi
    done
    
    # Vérification PHP
    if php -v >/dev/null 2>&1; then
        local php_version=$(php -r "echo PHP_VERSION;")
        log_success "$MODULE_NAME" "PHP fonctionnel: $php_version"
    else
        log_fatal "$MODULE_NAME" "PHP non fonctionnel"
    fi
    
    # Vérification SQLite
    if sqlite3 -version >/dev/null 2>&1; then
        local sqlite_version=$(sqlite3 -version | awk '{print $1}')
        log_success "$MODULE_NAME" "SQLite fonctionnel: $sqlite_version"
    else
        log_fatal "$MODULE_NAME" "SQLite non fonctionnel"
    fi
    
    log_success "$MODULE_NAME" "Validation système complète"
}

# ====== MAIN MODULE ======

main() {
    log_info "$MODULE_NAME" "=== INSTALLATION MODULE SYSTÈME ==="
    
    # Vérification privilèges root
    if [[ $UID -ne 0 ]]; then
        log_fatal "$MODULE_NAME" "Privilèges root requis"
    fi
    
    # Séquence d'installation
    install_packages
    configure_sysctl
    configure_firewall
    create_system_directories
    validate_system_setup
    
    log_success "$MODULE_NAME" "Module système installé avec succès!"
    return 0
}

# Exécution si appelé directement
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
