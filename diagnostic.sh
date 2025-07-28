#!/usr/bin/env bash
set -euo pipefail

# 🔍 BOXION SERVER DIAGNOSTIC - DIAGNOSTIC COMPLET
# Usage: curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/diagnostic.sh | sudo bash

echo "🔍 Boxion VPN Server Diagnostic - Analyse Complète"
echo "==============================================="

# ====== Vérification permissions root ======
if [[ $EUID -ne 0 ]]; then
   echo "❌ Ce script doit être exécuté en tant que root"
   echo "💡 Relancez avec: curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/diagnostic.sh | sudo bash"
   exit 1
fi

echo "🚀 Début du diagnostic..."
echo

# ====== 1. Vérification Services ======
echo "🔧 === SERVICES ==="
echo -n "WireGuard wg0: "
if systemctl is-active --quiet wg-quick@wg0; then
    echo "✅ ACTIF"
    wg show wg0 | head -3
else
    echo "❌ INACTIF"
    systemctl status wg-quick@wg0 --no-pager -l || true
fi

echo -n "Nginx: "
if systemctl is-active --quiet nginx; then
    echo "✅ ACTIF"
else
    echo "❌ INACTIF"
    systemctl status nginx --no-pager -l || true
fi

echo -n "PHP-FPM: "
if systemctl is-active --quiet php*-fpm; then
    echo "✅ ACTIF"
else
    echo "❌ INACTIF"
    systemctl status php*-fpm --no-pager -l || true
fi

echo

# ====== 2. Vérification Ports ======
echo "📡 === PORTS ==="
echo "Ports en écoute:"
ss -tlnp | grep -E ":(80|443|51820)\s" || echo "⚠️  Aucun port standard détecté"

echo -n "Port 80 (HTTP): "
if ss -tln | grep -q ":80 "; then
    echo "✅ OUVERT"
else
    echo "❌ FERMÉ"
fi

echo -n "Port 51820 (WireGuard): "
if ss -uln | grep -q ":51820 "; then
    echo "✅ OUVERT"
else
    echo "❌ FERMÉ"
fi

echo

# ====== 3. Vérification Configuration ======
echo "⚙️  === CONFIGURATION ==="
echo -n "Config WireGuard: "
if [[ -f /etc/wireguard/wg0.conf ]]; then
    echo "✅ TROUVÉE"
    echo "Interface: $(grep Address /etc/wireguard/wg0.conf | cut -d= -f2 | tr -d ' ')"
else
    echo "❌ MANQUANTE"
fi

echo -n "Application Boxion: "
if [[ -d /var/www/boxion-api ]]; then
    echo "✅ TROUVÉE"
else
    echo "❌ MANQUANTE"
fi

echo -n "Base de données: "
if [[ -f /var/lib/boxion/boxion.db ]]; then
    echo "✅ TROUVÉE"
    PEERS=$(sqlite3 /var/lib/boxion/boxion.db "SELECT COUNT(*) FROM peers;" 2>/dev/null || echo "ERROR")
    echo "Peers enregistrés: $PEERS"
else
    echo "❌ MANQUANTE"
fi

echo -n "Config Nginx: "
if [[ -f /etc/nginx/sites-enabled/boxion-api.conf ]]; then
    echo "✅ TROUVÉE"
    DOMAIN=$(grep server_name /etc/nginx/sites-enabled/boxion-api.conf | awk '{print $2}' | tr -d ';')
    echo "Domaine configuré: $DOMAIN"
else
    echo "❌ MANQUANTE"
fi

echo

# ====== 4. Test API Local ======
echo "🌐 === TEST API ==="

# Initialisation sécurisée des variables critiques
TOKEN=""
DOMAIN=""

if [[ -f /var/www/boxion-api/.env ]]; then
    TOKEN=$(grep API_TOKEN /var/www/boxion-api/.env | cut -d= -f2 | tr -d '"' 2>/dev/null || echo "")
    DOMAIN=$(grep ENDPOINT_DOMAIN /var/www/boxion-api/.env | cut -d= -f2 | tr -d '"' 2>/dev/null || echo "")
    
    if [[ -n "$TOKEN" && -n "$DOMAIN" ]]; then
        echo "Token trouvé: ${TOKEN:0:8}..."
        echo "Domaine: $DOMAIN"
    else
        echo "⚠️  Variables .env incomplètes (TOKEN ou DOMAIN manquant)"
        TOKEN=""
        DOMAIN=""
    fi
else
    echo "❌ Fichier .env manquant - tests API ignorés"
fi
    
    echo -n "Test API local (HTTP): "
    if curl -s -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
       -d '{"name":"test-diagnostic","pubkey":"test123456789test123456789test1234567890123="}' \
       http://localhost/api/peers >/dev/null 2>&1; then
        echo "✅ SUCCÈS"
    else
        echo "❌ ÉCHEC"
        echo "Détails erreur:"
        curl -v -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
             -d '{"name":"test-diagnostic","pubkey":"test123456789test123456789test1234567890123="}' \
             http://localhost/api/peers 2>&1 | head -10
    fi
    
    # Tests externes uniquement si variables valides
    if [[ -n "$TOKEN" && -n "$DOMAIN" && "$DOMAIN" != "localhost" ]]; then
        echo -n "Test API externe (HTTP): "
        if curl -s --max-time 10 -H "Authorization: Bearer $TOKEN" \
           "http://$DOMAIN/api/peers" >/dev/null 2>&1; then
            echo "✅ ACCESSIBLE"
        else
            echo "❌ INACCESSIBLE"
        fi
        
        echo -n "Test API externe (HTTPS): "
        if curl -s --max-time 10 -H "Authorization: Bearer $TOKEN" \
           "https://$DOMAIN/api/peers" >/dev/null 2>&1; then
            echo "✅ ACCESSIBLE"
        else
            echo "❌ INACCESSIBLE"
        fi
    elif [[ -z "$TOKEN" || -z "$DOMAIN" ]]; then
        echo "⚠️  Tests API externes ignorés (variables manquantes)"
    fi
else
    echo "❌ Fichier .env manquant"
fi

echo

# ====== 5. Test DNS ======
echo "🔍 === DNS & CONNECTIVITÉ ==="
if [[ -n "${DOMAIN:-}" ]]; then
    echo -n "Résolution DNS $DOMAIN: "
    if nslookup "$DOMAIN" >/dev/null 2>&1; then
        IP=$(nslookup "$DOMAIN" | grep -A1 "Name:" | tail -1 | awk '{print $2}' | head -1)
        echo "✅ RÉSOLU ($IP)"
        
        # Vérifier si IP correspond à l'interface locale
        LOCAL_IP=$(ip route get 8.8.8.8 | awk '{print $7; exit}')
        if [[ "$IP" == "$LOCAL_IP" ]]; then
            echo "✅ DNS pointe vers cette machine"
        else
            echo "⚠️  DNS pointe vers $IP, cette machine: $LOCAL_IP"
        fi
    else
        echo "❌ NON RÉSOLU"
    fi
fi

echo

# ====== 6. Logs Récents ======
echo "📋 === LOGS RÉCENTS ==="
echo "Nginx errors (5 dernières):"
tail -5 /var/log/nginx/error.log 2>/dev/null || echo "Pas de logs d'erreur Nginx"

echo
echo "PHP-FPM errors (5 dernières):"
journalctl -u php*-fpm --no-pager -n 5 2>/dev/null || echo "Pas de logs PHP-FPM"

echo

# ====== 7. Recommandations ======
echo "💡 === RECOMMANDATIONS ==="

# Check si ports ouverts
if ! ss -tln | grep -q ":80 "; then
    echo "⚠️  Ouvrez le port 80 sur votre firewall/cloud"
fi

if ! ss -uln | grep -q ":51820 "; then
    echo "⚠️  Redémarrez WireGuard: systemctl restart wg-quick@wg0"
fi

if [[ -n "${DOMAIN:-}" ]] && ! nslookup "$DOMAIN" >/dev/null 2>&1; then
    echo "⚠️  Configurez le DNS pour $DOMAIN vers cette machine"
fi

echo
echo "🎯 === COMMANDES DE TEST CLIENT ==="
if [[ -f /var/www/boxion-api/.env ]]; then
    TOKEN=$(grep API_TOKEN /var/www/boxion-api/.env | cut -d= -f2 | tr -d '"')
    DOMAIN=$(grep ENDPOINT_DOMAIN /var/www/boxion-api/.env | cut -d= -f2 | tr -d '"')
    
    echo "Test manuel depuis un client:"
    echo "curl -H \"Authorization: Bearer $TOKEN\" http://$DOMAIN/api/peers"
    echo
    echo "Commande client Boxion:"
    echo "TOKEN='$TOKEN' DOMAIN='$DOMAIN' bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/bootstrap_client.sh)\""
fi

echo
echo "🎉 === DIAGNOSTIC TERMINÉ ==="
echo "📞 Si problème persiste, partagez ce diagnostic complet"
