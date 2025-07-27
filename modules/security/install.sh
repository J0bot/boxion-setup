#!/usr/bin/env bash

# 🔒 Module Security - Configuration sudoers et sécurité
# Gestion des permissions pour scripts système

set -euo pipefail

# Source du logging
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../logging/logger.sh"

MODULE_NAME="SECURITY"
log_info "$MODULE_NAME" "Début installation module Security"

# Variables globales
SUDOERS_FILE="/etc/sudoers.d/boxion-api"
BIN_DIR="${APP_ROOT:-/var/www/boxion-api}/bin"

# ====== GÉNÉRATION SUDOERS ======

generate_sudoers_config() {
    log_step "$MODULE_NAME" "Configuration sudoers" "1/2"
    
    local wan_if="${WAN_IF:-eth0}"
    local wg_if="${WG_IF:-wg0}"
    
    log_info "$MODULE_NAME" "Génération: $SUDOERS_FILE"
    
    cat > "$SUDOERS_FILE" << EOF
# Sudoers Boxion Tunnel VPN - Permissions limitées
# Permet à www-data d'exécuter uniquement les scripts WireGuard
# Générée automatiquement le $(date)

# Variables d'environnement sécurisées
Defaults env_keep += "WG_IF WAN_IF"

# Permissions www-data pour gestion WireGuard
www-data ALL=(root) NOPASSWD: $BIN_DIR/wg_add_peer.sh
www-data ALL=(root) NOPASSWD: $BIN_DIR/wg_del_peer.sh
www-data ALL=(root) NOPASSWD: $BIN_DIR/replay_ndp.sh

# Commandes WireGuard directes (backup)
www-data ALL=(root) NOPASSWD: /usr/bin/wg set $wg_if peer *
www-data ALL=(root) NOPASSWD: /usr/bin/wg show $wg_if
www-data ALL=(root) NOPASSWD: /sbin/ip -6 neigh add proxy * dev $wan_if
www-data ALL=(root) NOPASSWD: /sbin/ip -6 neigh del proxy * dev $wan_if

# SÉCURITÉ: Interdiction explicite d'autres commandes système
www-data ALL=(root) !ALL, /bin/false
EOF

    # Validation syntaxe sudoers
    if ! visudo -c -f "$SUDOERS_FILE" 2>/tmp/sudoers-check.log; then
        log_error_context "$MODULE_NAME" "Configuration sudoers invalide" "$(cat /tmp/sudoers-check.log)"
        rm -f /tmp/sudoers-check.log "$SUDOERS_FILE"
        return 1
    fi
    
    # Permissions sécurisées
    chmod 440 "$SUDOERS_FILE"
    chown root:root "$SUDOERS_FILE"
    
    log_success "$MODULE_NAME" "Configuration sudoers validée et appliquée"
    rm -f /tmp/sudoers-check.log
}

# ====== CONFIGURATION SYSTEMD ======

configure_systemd_service() {
    log_step "$MODULE_NAME" "Service systemd replay-ndp" "2/2"
    
    local service_file="/etc/systemd/system/boxion-replay-ndp.service"
    
    log_info "$MODULE_NAME" "Génération: $service_file"
    
    cat > "$service_file" << EOF
[Unit]
Description=Boxion Tunnel - Replay NDP et restauration peers WireGuard
After=network.target wg-quick@${WG_IF:-wg0}.service
Wants=wg-quick@${WG_IF:-wg0}.service

[Service]
Type=oneshot
ExecStart=$BIN_DIR/replay_ndp.sh
Environment=WG_IF=${WG_IF:-wg0}
Environment=WAN_IF=${WAN_IF:-eth0}
User=root
Group=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Activation du service
    if ! systemctl daemon-reload 2>/dev/null; then
        log_warn "$MODULE_NAME" "Impossible de recharger systemd"
    fi
    
    if ! systemctl enable boxion-replay-ndp.service 2>/dev/null; then
        log_warn "$MODULE_NAME" "Impossible d'activer le service replay-ndp"
    else
        log_debug "$MODULE_NAME" "Service replay-ndp activé au boot"
    fi
    
    log_success "$MODULE_NAME" "Service systemd configuré"
}

# ====== MAIN MODULE ======

main() {
    log_info "$MODULE_NAME" "=== INSTALLATION MODULE SECURITY ==="
    
    # Vérification privilèges root
    if [[ $UID -ne 0 ]]; then
        log_fatal "$MODULE_NAME" "Privilèges root requis"
    fi
    
    # Validation prérequis
    validate_or_fatal "$MODULE_NAME" "[[ -d \$BIN_DIR ]]" "Répertoire bin/ requis: $BIN_DIR"
    
    # Séquence d'installation
    generate_sudoers_config
    configure_systemd_service
    
    log_success "$MODULE_NAME" "Module Security installé avec succès!"
    return 0
}

# Exécution si appelé directement
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
