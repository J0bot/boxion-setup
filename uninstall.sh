#!/usr/bin/env bash
set -euo pipefail

# 🧹 BOXION SERVER UNINSTALL - DÉSINSTALLATION COMPLÈTE
# Usage: curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/uninstall.sh | sudo bash

echo "🧹 Boxion VPN Server Uninstall - Désinstallation Complète"
echo "========================================================"

# ====== Vérification permissions root ======
if [[ $EUID -ne 0 ]]; then
   echo "❌ Ce script doit être exécuté en tant que root"
   echo "💡 Relancez avec: curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/uninstall.sh | sudo bash"
   exit 1
fi

# ====== Confirmation utilisateur ======
echo "⚠️  ATTENTION: Cette opération va SUPPRIMER COMPLÈTEMENT l'installation Boxion !"
echo "📋 Sera supprimé:"
echo "   • Interface WireGuard (wg0)"
echo "   • Configuration Nginx"
echo "   • Base de données SQLite"
echo "   • Certificats TLS"
echo "   • Clés serveur"
echo "   • Application PHP"
echo "   • Services systemd"
echo
# Mode non-interactif : désinstallation automatique
echo "⚠️  Mode automatique : désinstallation confirmée"
CONFIRM="y"

echo "🚀 Début de la désinstallation..."

# ====== Arrêt des services ======
echo "🛑 Arrêt des services..."
systemctl stop wg-quick@wg0 2>/dev/null || true
systemctl disable wg-quick@wg0 2>/dev/null || true
systemctl stop boxion-replay-ndp 2>/dev/null || true
systemctl disable boxion-replay-ndp 2>/dev/null || true

# ====== Suppression WireGuard ======
echo "🔧 Suppression interface WireGuard..."
wg-quick down wg0 2>/dev/null || true
rm -rf /etc/wireguard/wg0.conf
rm -rf /etc/wireguard/server_private.key
rm -rf /etc/wireguard/server_public.key

# ====== Suppression application ======
echo "🗂️  Suppression application Boxion..."
rm -rf /var/www/boxion-api
rm -rf /var/lib/boxion

# ====== Suppression configuration Nginx ======
echo "🌐 Suppression configuration Nginx..."
rm -rf /etc/nginx/sites-available/boxion-api.conf
rm -rf /etc/nginx/sites-enabled/boxion-api.conf
systemctl reload nginx 2>/dev/null || true

# ====== Suppression service systemd ======
echo "⚙️  Suppression service systemd..."
rm -rf /etc/systemd/system/boxion-replay-ndp.service
systemctl daemon-reload

# ====== Suppression sudoers ======
echo "🔐 Suppression permissions sudo..."
rm -rf /etc/sudoers.d/boxion-api

# ====== Suppression certificats TLS (optionnel) ======
echo "🔒 Suppression certificats TLS..."
# Mode non-interactif : suppression automatique des certificats
echo "🔒 Suppression automatique des certificats Let's Encrypt"
TLS_CONFIRM="y"
if [[ "$TLS_CONFIRM" == "y" || "$TLS_CONFIRM" == "Y" ]]; then
    # Recherche des certificats Boxion
    DOMAINS=$(certbot certificates 2>/dev/null | grep -E "(tunnel\.milkywayhub\.org|boxion)" | awk '{print $1}' || true)
    if [[ -n "$DOMAINS" ]]; then
        echo "🔍 Certificats trouvés: $DOMAINS"
        for domain in $DOMAINS; do
            certbot delete --cert-name "$domain" --non-interactive 2>/dev/null || true
        done
    else
        echo "ℹ️  Aucun certificat Boxion trouvé"
    fi
fi

# ====== Nettoyage sysctl ======
echo "🔧 Nettoyage configuration système..."
rm -rf /etc/sysctl.d/99-wireguard.conf 2>/dev/null || true

# ====== Nettoyage règles iptables ======
echo "🔥 Nettoyage règles firewall..."
iptables -D INPUT -p udp --dport 51820 -j ACCEPT 2>/dev/null || true
ufw delete allow 51820/udp 2>/dev/null || true

# ====== Suppression repository (optionnel) ======
echo "📦 Suppression repository source..."
# Mode non-interactif : suppression automatique du repository
echo "📁 Suppression automatique du repository source"
REPO_CONFIRM="y"
if [[ "$REPO_CONFIRM" == "y" || "$REPO_CONFIRM" == "Y" ]]; then
    rm -rf /root/boxion-api
fi

# ====== Vérification finale ======
echo "🔍 Vérification de la désinstallation..."
REMAINING=""
[[ -f /etc/wireguard/wg0.conf ]] && REMAINING+="• Configuration WireGuard\n"
[[ -d /var/www/boxion-api ]] && REMAINING+="• Application Boxion\n"
[[ -f /etc/nginx/sites-available/boxion-api.conf ]] && REMAINING+="• Configuration Nginx\n"
[[ -d /var/lib/boxion ]] && REMAINING+="• Base de données\n"

if [[ -n "$REMAINING" ]]; then
    echo "⚠️  Éléments non supprimés:"
    echo -e "$REMAINING"
else
    echo "✅ Désinstallation complète réussie !"
fi

echo
echo "🎉 ============ DÉSINSTALLATION TERMINÉE ============"
echo "✅ Boxion VPN Server complètement désinstallé"
echo "🔄 Redémarrage recommandé: reboot"
echo "📋 Pour réinstaller: bootstrap.sh"
echo
echo "💡 Note: Les paquets système (nginx, php, wireguard) ne sont pas supprimés"
echo "   Supprimez-les manuellement si nécessaire:"
echo "   apt remove --purge wireguard nginx php-fpm php-cli php-sqlite3"
