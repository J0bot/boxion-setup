#!/usr/bin/env bash

# 🚀 Orchestrateur Principal Boxion - Installation Modulaire
# Remplace le monolithe setup.sh par une approche modulaire avec logging détaillé

set -euo pipefail

# Configuration globale
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MODULES_DIR="$PROJECT_ROOT/modules"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Source du système de logging
source "$MODULES_DIR/logging/logger.sh"

# Variables globales d'installation
INSTALLATION_ID="$(date +%Y%m%d_%H%M%S)_$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 8)"
ROLLBACK_DIR="/tmp/boxion-rollback-$INSTALLATION_ID"

# État de l'installation pour rollback
INSTALLATION_STATE=()
INSTALLED_MODULES=()

# ====== GESTION DES PARAMÈTRES ======

show_help() {
    cat << EOF
🚀 Boxion VPN Server - Installation Modulaire

USAGE:
    $0 [OPTIONS] [MODULES...]

OPTIONS:
    --domain DOMAIN         Domaine du serveur (ex: tunnel.milkywayhub.org)
    --token TOKEN          Token API (généré automatiquement si omis)
    --prefix PREFIX        Préfixe IPv6 /64 (ex: 2a0c:xxxx:xxxx:abcd)
    --port PORT            Port WireGuard (défaut: 51820)
    --wan-if INTERFACE     Interface WAN (auto-détectée si omise)
    --log-level LEVEL      Niveau de log (DEBUG|INFO|WARN|ERROR|FATAL)
    --module MODULE        Installer uniquement un module spécifique
    --validate-only        Valider la configuration sans installer
    --rollback ID          Rollback d'une installation précédente
    --dry-run              Simuler l'installation sans modifications
    --help                 Afficher cette aide

MODULES DISPONIBLES:
    system                 Configuration système de base
    wireguard             Configuration WireGuard
    api                   API REST pour gestion des peers
    dashboard             Dashboard web d'administration
    all                   Tous les modules (défaut)

EXEMPLES:
    # Installation complète automatique
    $0 --domain tunnel.example.com

    # Installation avec debug détaillé
    $0 --domain tunnel.example.com --log-level DEBUG

    # Installation uniquement du module API
    $0 --domain tunnel.example.com --module api

    # Validation de configuration sans installation
    $0 --domain tunnel.example.com --validate-only

    # Rollback d'une installation
    $0 --rollback 20250127_213045_abc12345

EOF
}

# Paramètres par défaut
DOMAIN=""
API_TOKEN=""
IPV6_PREFIX=""
PORT="51820"
WAN_IF=""
MODULES_TO_INSTALL=("all")
VALIDATE_ONLY=false
DRY_RUN=false
ROLLBACK_ID=""

# Parse des arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --domain)
                DOMAIN="$2"; shift 2;;
            --token)
                API_TOKEN="$2"; shift 2;;
            --prefix)
                IPV6_PREFIX="$2"; shift 2;;
            --port)
                PORT="$2"; shift 2;;
            --wan-if)
                WAN_IF="$2"; shift 2;;
            --log-level)
                LOG_LEVEL="$2"; shift 2;;
            --module)
                MODULES_TO_INSTALL=("$2"); shift 2;;
            --validate-only)
                VALIDATE_ONLY=true; shift;;
            --rollback)
                ROLLBACK_ID="$2"; shift 2;;
            --dry-run)
                DRY_RUN=true; shift;;
            --help|-h)
                show_help; exit 0;;
            *)
                log_error "MAIN" "Paramètre inconnu: $1"
                show_help
                exit 1;;
        esac
    done
}

# ====== GESTION D'ÉTAT ET ROLLBACK ======

save_installation_state() {
    local module="$1"
    local action="$2"
    local details="$3"
    
    mkdir -p "$ROLLBACK_DIR"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $module $action $details" >> "$ROLLBACK_DIR/installation.log"
    INSTALLATION_STATE+=("$module:$action:$details")
    
    log_debug "STATE" "État sauvegardé: $module -> $action ($details)"
}

# ====== VALIDATION DE CONFIGURATION ======

validate_prerequisites() {
    log_step "VALIDATION" "Prérequis système" "1/5"
    
    # Vérification root
    validate_or_fatal "VALIDATION" "[[ \$UID -eq 0 ]]" "Installation requiert les privilèges root"
    log_success "VALIDATION" "Privilèges root validés"
    
    # Vérification OS
    if [[ -f /etc/debian_version ]]; then
        log_success "VALIDATION" "OS Debian/Ubuntu détecté"
    else
        log_warn "VALIDATION" "OS non testé - continuer avec précaution"
    fi
    
    # Vérification espace disque
    local available_space=$(df /var | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 1048576 ]]; then # 1GB en KB
        log_warn "VALIDATION" "Espace disque faible: ${available_space}KB disponible"
    else
        log_success "VALIDATION" "Espace disque suffisant: ${available_space}KB"
    fi
    
    save_installation_state "VALIDATION" "COMPLETED" "prerequisites_ok"
}

validate_network() {
    log_step "VALIDATION" "Configuration réseau" "2/5"
    
    # Auto-détection interface WAN si non spécifiée
    if [[ -z "$WAN_IF" ]]; then
        WAN_IF=$(ip r | awk '/default/ {print $5; exit}' 2>/dev/null || true)
        if [[ -z "$WAN_IF" ]]; then
            # Fallback: première interface avec IPv4 globale
            WAN_IF=$(ip -4 addr show scope global | awk -F': ' '/^[0-9]+:/ && !/lo:/ {print $2; exit}')
        fi
        log_info "VALIDATION" "Interface WAN auto-détectée: $WAN_IF"
    fi
    
    validate_or_fatal "VALIDATION" "[[ -n \$WAN_IF ]]" "Interface WAN non détectée - spécifiez --wan-if"
    
    # Validation interface existe
    validate_or_fatal "VALIDATION" "ip link show \$WAN_IF >/dev/null 2>&1" "Interface $WAN_IF introuvable"
    log_success "VALIDATION" "Interface WAN validée: $WAN_IF"
    
    # Auto-détection préfixe IPv6 si non spécifié
    if [[ -z "$IPV6_PREFIX" ]]; then
        local detected_v6=$(ip -6 addr show dev "$WAN_IF" scope global | awk '/inet6/ && !/temporary/ {print $2; exit}' | cut -d/ -f1)
        if [[ -n "$detected_v6" ]]; then
            IPV6_PREFIX=$(printf "%s:%s:%s:%s" $(echo "$detected_v6" | awk -F: '{print $1,$2,$3,$4}'))
            log_info "VALIDATION" "Préfixe IPv6 auto-détecté: ${IPV6_PREFIX}::/64"
        fi
    fi
    
    save_installation_state "VALIDATION" "COMPLETED" "network_ok"
}

validate_ports() {
    log_step "VALIDATION" "Disponibilité des ports" "3/5"
    
    # Vérification port WireGuard
    if ss -ulpn | grep -q ":$PORT " 2>/dev/null; then
        log_fatal "VALIDATION" "Port UDP/$PORT déjà utilisé"
    fi
    log_success "VALIDATION" "Port UDP/$PORT disponible"
    
    # Vérification ports web (80, 443)
    for port in 80 443; do
        if ss -tlpn | grep -q ":$port " 2>/dev/null; then
            log_warn "VALIDATION" "Port TCP/$port déjà utilisé - nginx peut échouer"
        else
            log_success "VALIDATION" "Port TCP/$port disponible"
        fi
    done
    
    save_installation_state "VALIDATION" "COMPLETED" "ports_ok"
}

validate_configuration() {
    log_step "VALIDATION" "Configuration complète" "4/5"
    
    # Validation domaine
    validate_or_fatal "VALIDATION" "[[ -n \$DOMAIN ]]" "Domaine requis (--domain)"
    log_success "VALIDATION" "Domaine: $DOMAIN"
    
    # Génération token si manquant
    if [[ -z "$API_TOKEN" ]]; then
        if command -v openssl >/dev/null 2>&1; then
            API_TOKEN=$(openssl rand -hex 32)
            log_info "VALIDATION" "Token API généré automatiquement"
        else
            log_fatal "VALIDATION" "openssl requis pour générer le token API"
        fi
    fi
    log_debug "VALIDATION" "Token API configuré (${#API_TOKEN} caractères)"
    
    # Validation préfixe IPv6
    if [[ -n "$IPV6_PREFIX" ]]; then
        if [[ "$IPV6_PREFIX" =~ ^[0-9a-f:]+$ ]]; then
            log_success "VALIDATION" "Préfixe IPv6: ${IPV6_PREFIX}::/64"
        else
            log_fatal "VALIDATION" "Format de préfixe IPv6 invalide: $IPV6_PREFIX"
        fi
    else
        log_warn "VALIDATION" "Aucun préfixe IPv6 détecté - configuration manuelle requise"
    fi
    
    save_installation_state "VALIDATION" "COMPLETED" "config_ok"
}

# ====== INSTALLATION MODULAIRE ======

install_module() {
    local module_name="$1"
    local module_dir="$MODULES_DIR/$module_name"
    
    if [[ ! -d "$module_dir" ]]; then
        log_error "MODULE" "Module '$module_name' introuvable: $module_dir"
        return 1
    fi
    
    log_step "MODULE" "Installation du module $module_name"
    
    # Exécution de l'installateur du module
    local installer="$module_dir/install.sh"
    if [[ -f "$installer" ]]; then
        log_info "$module_name" "Exécution de l'installateur"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "$module_name" "[DRY-RUN] Simulation de l'installation"
        else
            # Export des variables pour les modules
            export DOMAIN API_TOKEN IPV6_PREFIX PORT WAN_IF PROJECT_ROOT
            
            if bash "$installer"; then
                log_success "$module_name" "Module installé avec succès"
                INSTALLED_MODULES+=("$module_name")
                save_installation_state "$module_name" "INSTALLED" "success"
            else
                log_error "$module_name" "Échec de l'installation du module"
                save_installation_state "$module_name" "FAILED" "installer_error"
                return 1
            fi
        fi
    else
        log_warn "$module_name" "Aucun installateur trouvé - module ignoré"
        save_installation_state "$module_name" "SKIPPED" "no_installer"
    fi
}

# ====== ROLLBACK ======

perform_rollback() {
    local rollback_id="$1"
    local rollback_dir="/tmp/boxion-rollback-$rollback_id"
    
    if [[ ! -d "$rollback_dir" ]]; then
        log_fatal "ROLLBACK" "Répertoire de rollback introuvable: $rollback_dir"
    fi
    
    log_info "ROLLBACK" "Début du rollback: $rollback_id"
    
    # TODO: Implémenter le rollback effectif
    log_warn "ROLLBACK" "Rollback automatique non encore implémenté"
    log_info "ROLLBACK" "Logs disponibles dans: $rollback_dir"
}

# ====== MAIN ======

main() {
    echo "🚀 Boxion VPN Server - Installation Modulaire"
    echo "============================================="
    echo "Installation ID: $INSTALLATION_ID"
    echo
    
    # Parse des arguments
    parse_arguments "$@"
    
    # Configuration du logging
    export LOG_LEVEL
    init_logging
    log_info "MAIN" "Début de l'installation - ID: $INSTALLATION_ID"
    
    # Gestion du rollback
    if [[ -n "$ROLLBACK_ID" ]]; then
        perform_rollback "$ROLLBACK_ID"
        return $?
    fi
    
    # Validation complète
    log_info "MAIN" "Phase de validation"
    validate_prerequisites
    validate_network
    validate_ports
    validate_configuration
    
    # Mode validation uniquement
    if [[ "$VALIDATE_ONLY" == "true" ]]; then
        log_success "MAIN" "Validation terminée - aucune installation effectuée"
        return 0
    fi
    
    # Installation des modules
    log_info "MAIN" "Phase d'installation"
    
    if [[ "${MODULES_TO_INSTALL[0]}" == "all" ]]; then
        MODULES_TO_INSTALL=("system" "wireguard" "api" "dashboard")
    fi
    
    local total_modules=${#MODULES_TO_INSTALL[@]}
    local current_module=0
    
    for module in "${MODULES_TO_INSTALL[@]}"; do
        ((current_module++))
        log_info "MAIN" "Module $current_module/$total_modules: $module"
        
        if install_module "$module"; then
            show_progress "$current_module" "$total_modules"
        else
            log_error "MAIN" "Échec installation module: $module"
            log_info "MAIN" "Rollback disponible avec: $0 --rollback $INSTALLATION_ID"
            return 1
        fi
    done
    
    # Finalisation
    log_success "MAIN" "Installation complétée avec succès!"
    log_info "MAIN" "Modules installés: ${INSTALLED_MODULES[*]}"
    log_info "MAIN" "Logs disponibles: $LOG_FILE"
    log_info "MAIN" "Rollback disponible: $0 --rollback $INSTALLATION_ID"
    
    return 0
}

# Exécution si script appelé directement
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
