#!/usr/bin/env bash

# 📝 Système de Logging Modulaire Boxion
# Niveaux : DEBUG, INFO, WARN, ERROR, FATAL

# Configuration globale
LOG_DIR="${LOG_DIR:-/tmp/boxion-logs}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/boxion.log}"
ENABLE_COLORS="${ENABLE_COLORS:-true}"

# Codes couleurs
if [[ "$ENABLE_COLORS" == "true" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
else
    RED='' GREEN='' YELLOW='' BLUE='' PURPLE='' CYAN='' NC=''
fi

# Niveaux de priorité (pour filtrage)
declare -A LOG_PRIORITIES=(
    ["DEBUG"]=0
    ["INFO"]=1
    ["WARN"]=2
    ["ERROR"]=3
    ["FATAL"]=4
)

# Initialisation du système de logs
init_logging() {
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    
    if [[ ! -w "$LOG_DIR" ]]; then
        echo "⚠️  Warning: Cannot write to log directory $LOG_DIR" >&2
        LOG_FILE="/tmp/boxion-fallback.log"
    fi
    
    echo "🔍 [$(date '+%Y-%m-%d %H:%M:%S')] [SYSTEM] [INFO] Logging initialized - File: $LOG_FILE, Level: $LOG_LEVEL" | tee -a "$LOG_FILE" 2>/dev/null || true
}

# Fonction de logging principale
log() {
    local level="$1"
    local module="${2:-SYSTEM}"
    local message="$3"
    
    # Validation des paramètres
    if [[ -z "$level" || -z "$message" ]]; then
        echo "❌ log() usage: log LEVEL MODULE MESSAGE" >&2
        return 1
    fi
    
    # Vérification niveau de priorité
    local current_priority=${LOG_PRIORITIES[$LOG_LEVEL]:-1}
    local message_priority=${LOG_PRIORITIES[$level]:-0}
    
    if [[ $message_priority -lt $current_priority ]]; then
        return 0  # Message filtré
    fi
    
    # Format du timestamp
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Couleurs par niveau
    local color=""
    case "$level" in
        "DEBUG") color="$CYAN" ;;
        "INFO")  color="$GREEN" ;;
        "WARN")  color="$YELLOW" ;;
        "ERROR") color="$RED" ;;
        "FATAL") color="$PURPLE" ;;
    esac
    
    # Format final du message
    local log_message="[$timestamp] [$module] [$level] $message"
    local colored_message="${color}[$timestamp] [$module] [$level] $message${NC}"
    
    # Écriture console (avec couleurs)
    echo -e "$colored_message"
    
    # Écriture fichier (sans couleurs)
    echo "$log_message" >> "$LOG_FILE" 2>/dev/null || true
    
    # Si FATAL, on arrête le script
    if [[ "$level" == "FATAL" ]]; then
        echo -e "${RED}💀 FATAL ERROR - Installation stopped${NC}"
        exit 1
    fi
}

# Fonctions de logging spécialisées
log_debug() { log "DEBUG" "$1" "$2"; }
log_info() { log "INFO" "$1" "$2"; }
log_warn() { log "WARN" "$1" "$2"; }
log_error() { log "ERROR" "$1" "$2"; }
log_fatal() { log "FATAL" "$1" "$2"; }

# Fonction d'étape avec progress
log_step() {
    local module="$1"
    local step="$2"
    local total="${3:-unknown}"
    
    if [[ "$total" != "unknown" ]]; then
        log_info "$module" "📋 Step $step/$total: Starting"
    else
        log_info "$module" "📋 $step: Starting"
    fi
}

# Fonction de succès
log_success() {
    local module="$1"
    local message="$2"
    log_info "$module" "✅ $message"
}

# Fonction d'erreur avec contexte
log_error_context() {
    local module="$1"
    local message="$2"
    local context="$3"
    
    log_error "$module" "$message"
    if [[ -n "$context" ]]; then
        log_debug "$module" "Context: $context"
    fi
}

# Fonction de validation avec logging
validate_or_fatal() {
    local module="$1"
    local condition="$2"
    local error_message="$3"
    
    if ! eval "$condition"; then
        log_fatal "$module" "$error_message"
    fi
}

# Progress bar simple
show_progress() {
    local current="$1"
    local total="$2"
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "\r${GREEN}["
    printf "%*s" $filled | tr ' ' '='
    printf "%*s" $empty | tr ' ' '-'
    printf "] %d%% (%d/%d)${NC}" $percentage $current $total
    
    if [[ $current -eq $total ]]; then
        echo  # Nouvelle ligne à la fin
    fi
}

# Affichage des logs en temps réel (pour debug)
tail_logs() {
    if [[ -f "$LOG_FILE" ]]; then
        echo "📋 Displaying logs from: $LOG_FILE"
        echo "📋 Press Ctrl+C to stop"
        tail -f "$LOG_FILE"
    else
        echo "❌ Log file not found: $LOG_FILE"
        return 1
    fi
}

# Export des fonctions pour usage global
export -f log log_debug log_info log_warn log_error log_fatal
export -f log_step log_success log_error_context validate_or_fatal
export -f show_progress tail_logs init_logging

# Auto-initialisation si sourcé
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    init_logging
fi
