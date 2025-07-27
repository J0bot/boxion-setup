#!/usr/bin/env bash
set -euo pipefail

# 🩺 BOXION CLIENT DIAGNOSTIC - ANALYSE AUTOMATIQUE
# Usage: curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/diagnostic_client.sh | bash

echo "🩺 Boxion VPN Client Diagnostic - Analyse Automatique"
echo "===================================================="

# ====== Détection OS ======
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
else
    echo "❌ OS non supporté: $OSTYPE"
    exit 1
fi

echo "🔍 OS détecté: $OS"
echo

# ====== Variables de diagnostic ======
ERRORS=0
WARNINGS=0

log_error() {
    echo "❌ ERREUR: $1"
    ((ERRORS++))
}

log_warning() {
    echo "⚠️  ATTENTION: $1"
    ((WARNINGS++))
}

log_success() {
    echo "✅ OK: $1"
}

log_info() {
    echo "ℹ️  INFO: $1"
}

# ====== Test 1: WireGuard installé ======
echo "🔍 === TEST 1: Installation WireGuard ==="
if command -v wg >/dev/null 2>&1; then
    WG_VERSION=$(wg --version 2>/dev/null | head -n1)
    log_success "WireGuard installé: $WG_VERSION"
else
    log_error "WireGuard non installé"
    echo "💡 Installation:"
    if [[ "$OS" == "linux" ]]; then
        echo "   sudo apt update && sudo apt install -y wireguard"
    elif [[ "$OS" == "macos" ]]; then
        echo "   brew install wireguard-go wireguard-tools"
    fi
fi
echo

# ====== Test 2: Configuration Boxion ======
echo "🔍 === TEST 2: Configuration Boxion ==="
BOXION_CONF="/etc/wireguard/boxion.conf"
if [[ -f "$BOXION_CONF" ]]; then
    log_success "Configuration trouvée: $BOXION_CONF"
    
    # Vérifier le contenu
    if grep -q "PrivateKey" "$BOXION_CONF" 2>/dev/null; then
        log_success "Clé privée configurée"
    else
        log_error "Clé privée manquante dans la configuration"
    fi
    
    if grep -q "PublicKey" "$BOXION_CONF" 2>/dev/null; then
        log_success "Clé publique serveur configurée"
    else
        log_error "Clé publique serveur manquante"
    fi
    
    if grep -q "Endpoint" "$BOXION_CONF" 2>/dev/null; then
        ENDPOINT=$(grep "Endpoint" "$BOXION_CONF" | cut -d'=' -f2 | tr -d ' ')
        log_success "Endpoint configuré: $ENDPOINT"
    else
        log_error "Endpoint serveur manquant"
    fi
    
    if grep -q "Address" "$BOXION_CONF" 2>/dev/null; then
        ADDRESS=$(grep "Address" "$BOXION_CONF" | cut -d'=' -f2 | tr -d ' ')
        log_success "Adresse IPv6 attribuée: $ADDRESS"
    else
        log_error "Adresse IPv6 non configurée"
    fi
else
    log_error "Configuration Boxion introuvable: $BOXION_CONF"
    echo "💡 Réinstallez avec: bootstrap_client.sh"
fi
echo

# ====== Test 3: Statut connexion ======
echo "🔍 === TEST 3: Statut Connexion ==="
if [[ "$OS" == "linux" ]]; then
    if systemctl is-active wg-quick@boxion >/dev/null 2>&1; then
        log_success "Service WireGuard actif"
        
        # Test interface réseau
        if ip link show boxion >/dev/null 2>&1; then
            log_success "Interface boxion active"
            
            # Stats interface
            WG_STATS=$(wg show boxion 2>/dev/null || echo "")
            if [[ -n "$WG_STATS" ]]; then
                echo "📊 Statistiques WireGuard:"
                echo "$WG_STATS" | sed 's/^/   /'
            fi
        else
            log_error "Interface boxion introuvable"
        fi
    else
        log_warning "Service WireGuard inactif"
        echo "💡 Démarrer avec: sudo systemctl start wg-quick@boxion"
    fi
elif [[ "$OS" == "macos" ]]; then
    if pgrep -f "wg-quick.*boxion" >/dev/null 2>&1; then
        log_success "Processus WireGuard actif"
    else
        log_warning "WireGuard non actif"
        echo "💡 Démarrer avec: sudo wg-quick up boxion"
    fi
fi
echo

# ====== Test 4: Connectivité réseau ======
echo "🔍 === TEST 4: Tests Connectivité ==="

# Test résolveur DNS
if [[ -f "$BOXION_CONF" ]] && grep -q "DNS" "$BOXION_CONF" 2>/dev/null; then
    DNS_SERVER=$(grep "DNS" "$BOXION_CONF" | cut -d'=' -f2 | tr -d ' ' | cut -d',' -f1)
    log_info "DNS configuré: $DNS_SERVER"
    
    # Test ping DNS
    if ping -c 1 -W 3 "$DNS_SERVER" >/dev/null 2>&1; then
        log_success "DNS serveur accessible"
    else
        log_warning "DNS serveur inaccessible: $DNS_SERVER"
    fi
else
    log_warning "DNS non configuré dans Boxion"
fi

# Test endpoint serveur
if [[ -f "$BOXION_CONF" ]] && grep -q "Endpoint" "$BOXION_CONF" 2>/dev/null; then
    ENDPOINT=$(grep "Endpoint" "$BOXION_CONF" | cut -d'=' -f2 | tr -d ' ')
    SERVER_IP=$(echo "$ENDPOINT" | cut -d':' -f1)
    SERVER_PORT=$(echo "$ENDPOINT" | cut -d':' -f2)
    
    log_info "Test connexion serveur: $SERVER_IP:$SERVER_PORT"
    
    # Test ping serveur
    if ping -c 1 -W 3 "$SERVER_IP" >/dev/null 2>&1; then
        log_success "Serveur ping accessible"
    else
        log_warning "Serveur ping inaccessible: $SERVER_IP"
    fi
    
    # Test port UDP (difficile à tester directement)
    if command -v nc >/dev/null 2>&1; then
        if timeout 3 nc -u -z "$SERVER_IP" "$SERVER_PORT" 2>/dev/null; then
            log_success "Port UDP $SERVER_PORT accessible"
        else
            log_warning "Port UDP $SERVER_PORT inaccessible (ou firewall)"
        fi
    fi
fi

# Test connectivité internet via VPN
if ip link show boxion >/dev/null 2>&1 || pgrep -f "wg-quick.*boxion" >/dev/null 2>&1; then
    log_info "Test connectivité internet via VPN..."
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        log_success "Internet accessible via VPN"
    else
        log_error "Internet inaccessible via VPN"
        echo "💡 Vérifiez les routes et le DNS"
    fi
else
    log_info "VPN inactif - test connectivité normale..."
    if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        log_success "Internet accessible (sans VPN)"
    else
        log_error "Aucune connectivité internet"
    fi
fi
echo

# ====== Test 5: Configuration système ======
echo "🔍 === TEST 5: Configuration Système ==="

# Test permissions
if [[ -f "$BOXION_CONF" ]]; then
    CONF_PERMS=$(stat -c "%a" "$BOXION_CONF" 2>/dev/null || stat -f "%A" "$BOXION_CONF" 2>/dev/null)
    if [[ "$CONF_PERMS" == "600" ]] || [[ "$CONF_PERMS" == "400" ]]; then
        log_success "Permissions configuration sécurisées: $CONF_PERMS"
    else
        log_warning "Permissions configuration faibles: $CONF_PERMS"
        echo "💡 Corriger avec: sudo chmod 600 $BOXION_CONF"
    fi
fi

# Test forwarding IP (Linux)
if [[ "$OS" == "linux" ]]; then
    IP_FORWARD=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
    if [[ "$IP_FORWARD" == "1" ]]; then
        log_success "IP forwarding activé"
    else
        log_info "IP forwarding désactivé (normal pour client)"
    fi
fi

# Test espace disque
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
if [[ "$DISK_USAGE" -lt 90 ]]; then
    log_success "Espace disque OK: ${DISK_USAGE}% utilisé"
else
    log_warning "Espace disque faible: ${DISK_USAGE}% utilisé"
fi
echo

# ====== Test 6: Logs et diagnostics ======
echo "🔍 === TEST 6: Logs Système ==="

if [[ "$OS" == "linux" ]]; then
    # Logs systemd récents
    log_info "Derniers logs WireGuard:"
    if systemctl status wg-quick@boxion --no-pager -n 5 2>/dev/null | grep -E "(Active|Main PID|Loaded)" | sed 's/^/   /'; then
        echo
    fi
    
    # Logs journalctl
    if journalctl -u wg-quick@boxion --no-pager -n 3 --since "1 hour ago" 2>/dev/null | tail -n 3 | sed 's/^/   /'; then
        echo
    fi
elif [[ "$OS" == "macos" ]]; then
    # Logs système macOS
    log_info "Derniers logs système (recherche WireGuard):"
    if log show --predicate 'process == "wg-quick"' --info --last 1h 2>/dev/null | tail -n 3 | sed 's/^/   /'; then
        echo
    fi
fi

# ====== Résumé final ======
echo "🔍 === RÉSUMÉ DIAGNOSTIC ==="
echo "📊 Erreurs: $ERRORS"
echo "📊 Avertissements: $WARNINGS"
echo

if [[ $ERRORS -eq 0 ]] && [[ $WARNINGS -eq 0 ]]; then
    echo "🎉 ✅ DIAGNOSTIC PARFAIT - Boxion Client fonctionne correctement !"
elif [[ $ERRORS -eq 0 ]]; then
    echo "😊 ✅ DIAGNOSTIC OK - Quelques optimisations possibles"
elif [[ $ERRORS -lt 3 ]]; then
    echo "😐 ⚠️  DIAGNOSTIC MOYEN - Problèmes mineurs à corriger"
else
    echo "😞 ❌ DIAGNOSTIC CRITIQUE - Réinstallation recommandée"
    echo "💡 Commande de réinstallation:"
    echo "   curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/bootstrap_client.sh | bash"
fi

echo
echo "🛠️  === COMMANDES UTILES ==="
echo "• Statut:     sudo systemctl status wg-quick@boxion"
echo "• Démarrer:   sudo systemctl start wg-quick@boxion" 
echo "• Arrêter:    sudo systemctl stop wg-quick@boxion"
echo "• Logs:       journalctl -u wg-quick@boxion -f"
echo "• Stats:      sudo wg show boxion"
echo "• Config:     sudo cat /etc/wireguard/boxion.conf"
echo "• Ping test:  ping 8.8.8.8 # (avec VPN actif)"
echo
echo "📋 Pour support: partagez ce rapport avec les détails du problème"
