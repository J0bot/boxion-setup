#!/usr/bin/env bash
set -euo pipefail

# 🗑️ BOXION CLIENT UNINSTALL - DÉSINSTALLATION COMPLÈTE
# Usage: curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/uninstall_client.sh | bash

echo "🗑️ Boxion VPN Client Uninstall - Désinstallation Complète"
echo "========================================================"

# ====== Détection OS ======
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
else
    echo "❌ OS non supporté: $OSTYPE"
    echo "💡 Désinstallation manuelle requise"
    exit 1
fi

echo "🔍 OS détecté: $OS"

# ====== Confirmation utilisateur ======
echo "⚠️  ATTENTION: Cette opération va SUPPRIMER COMPLÈTEMENT l'installation Boxion Client !"
echo "📋 Sera supprimé:"
echo "   • Configuration WireGuard"
echo "   • Clés privées/publiques"
echo "   • Scripts de connexion"
echo "   • Services systemd (Linux)"
echo
read -p "❓ Confirmez la désinstallation complète [y/N]: " CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "❌ Désinstallation annulée"
    exit 0
fi

echo "🚀 Début de la désinstallation..."

# ====== Arrêt connexion ======
echo "🛑 Arrêt de la connexion Boxion..."
if [[ "$OS" == "linux" ]]; then
    sudo systemctl stop wg-quick@boxion 2>/dev/null || true
    sudo systemctl disable wg-quick@boxion 2>/dev/null || true
    sudo wg-quick down boxion 2>/dev/null || true
elif [[ "$OS" == "macos" ]]; then
    sudo launchctl unload /Library/LaunchDaemons/com.boxion.wg.plist 2>/dev/null || true
    sudo wg-quick down boxion 2>/dev/null || true
fi

# ====== Suppression configuration ======
echo "🔧 Suppression configuration WireGuard..."
sudo rm -rf /etc/wireguard/boxion.conf
sudo rm -rf /etc/wireguard/boxion_private.key
sudo rm -rf /etc/wireguard/boxion_public.key

# ====== Suppression scripts (Linux) ======
if [[ "$OS" == "linux" ]]; then
    echo "📜 Suppression scripts Linux..."
    sudo rm -rf /usr/local/bin/boxion-connect
    sudo rm -rf /usr/local/bin/boxion-disconnect
    sudo rm -rf /usr/local/bin/boxion-status
fi

# ====== Suppression LaunchDaemon (macOS) ======
if [[ "$OS" == "macos" ]]; then
    echo "🍎 Suppression LaunchDaemon macOS..."
    sudo rm -rf /Library/LaunchDaemons/com.boxion.wg.plist
fi

# ====== Suppression données utilisateur ======
echo "🗂️  Suppression données utilisateur..."
rm -rf ~/.boxion 2>/dev/null || true
rm -rf ~/boxion-setup 2>/dev/null || true

# ====== Nettoyage DNS (si configuré) ======
echo "🌐 Nettoyage configuration DNS..."
if [[ "$OS" == "linux" ]]; then
    # Restaurer resolv.conf original si backup existe
    if [[ -f /etc/resolv.conf.boxion-backup ]]; then
        sudo mv /etc/resolv.conf.boxion-backup /etc/resolv.conf 2>/dev/null || true
    fi
elif [[ "$OS" == "macos" ]]; then
    # Supprimer DNS personalisation sur macOS
    sudo networksetup -setdnsservers "Wi-Fi" "Empty" 2>/dev/null || true
    sudo networksetup -setdnsservers "Ethernet" "Empty" 2>/dev/null || true
fi

# ====== Nettoyage routes ======
echo "🛣️  Nettoyage routes réseau..."
if [[ "$OS" == "linux" ]]; then
    # Supprimer routes Boxion spécifiques
    sudo ip route del 0.0.0.0/1 2>/dev/null || true
    sudo ip route del 128.0.0.0/1 2>/dev/null || true
    sudo ip -6 route del ::/1 2>/dev/null || true
    sudo ip -6 route del 8000::/1 2>/dev/null || true
elif [[ "$OS" == "macos" ]]; then
    # Supprimer routes macOS
    sudo route delete 0.0.0.0/1 2>/dev/null || true
    sudo route delete 128.0.0.0/1 2>/dev/null || true
fi

# ====== Vérification finale ======
echo "🔍 Vérification de la désinstallation..."
REMAINING=""
[[ -f /etc/wireguard/boxion.conf ]] && REMAINING+="• Configuration WireGuard\n"
[[ -f /usr/local/bin/boxion-connect ]] && REMAINING+="• Scripts Boxion\n"
[[ -d ~/.boxion ]] && REMAINING+="• Données utilisateur\n"

if [[ -n "$REMAINING" ]]; then
    echo "⚠️  Éléments non supprimés:"
    echo -e "$REMAINING"
    echo "💡 Suppression manuelle requise"
else
    echo "✅ Désinstallation complète réussie !"
fi

echo
echo "🎉 ============ DÉSINSTALLATION TERMINÉE ============"
echo "✅ Boxion VPN Client complètement désinstallé"
echo "🔄 Redémarrage réseau recommandé:"
if [[ "$OS" == "linux" ]]; then
    echo "   sudo systemctl restart NetworkManager"
elif [[ "$OS" == "macos" ]]; then
    echo "   sudo dscacheutil -flushcache"
fi
echo "📋 Pour réinstaller: bootstrap_client.sh"
echo
echo "💡 Note: WireGuard système n'est pas désinstallé"
if [[ "$OS" == "linux" ]]; then
    echo "   Supprimez-le manuellement si nécessaire:"
    echo "   sudo apt remove --purge wireguard"
elif [[ "$OS" == "macos" ]]; then
    echo "   Supprimez-le manuellement si nécessaire:"
    echo "   brew uninstall wireguard-go wireguard-tools"
fi
