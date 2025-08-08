#!/usr/bin/env bash

# ⚠️ DEPRECATION: ce script est remplacé par l'installateur modulaire.
# Utilisez désormais: sudo bash installer/install.sh [--domain mon.domaine] [--email admin@mail]
# Le script legacy s'arrête ici pour éviter des installations incohérentes.
echo "[Boxion] Ce script est déprécié. Utilisez: sudo bash installer/install.sh --domain tunnel.milkywayhub.org --email toi@mail.tld" >&2
exit 1

# 🚀 BOXION VPN SERVER - INSTALLATION SIMPLE ET SÉCURISÉE
# Installation complète d'un serveur tunnel IPv6 via WireGuard
# Simple, sécurisé, fonctionnel !

set -euo pipefail

# ========================================
# 🎯 CONFIGURATION & VARIABLES
# ========================================

# Script directory (compatible avec curl | bash)
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR="/tmp"
fi
API_DIR="/var/www/boxion-api"
WG_CONFIG="/etc/wireguard/wg0.conf"
DB_FILE="/var/lib/boxion/peers.db"

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

# Gestion de l'interruption propre
cleanup() {
    log_warning "Interruption détectée - nettoyage en cours..."
    exit 1
}
trap cleanup SIGINT SIGTERM

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
    
    # Vérification Debian/Ubuntu
    if ! command -v apt-get >/dev/null 2>&1; then
        log_error "Ce script nécessite apt-get (Debian/Ubuntu)"
        exit 1
    fi
    
    # Vérification IPv6
    if ! ip -6 addr show | grep -q "inet6.*global"; then
        log_error "Aucune adresse IPv6 globale détectée"
        log_info "Configurez IPv6 sur votre VPS avant d'installer"
        exit 1
    fi
    
    log_success "Prérequis validés"
}

# ========================================
# 📦 INSTALLATION DES PAQUETS
# ========================================

install_packages() {
    log_info "Installation des paquets requis..."
    
    # Configuration non-interactive
    export DEBIAN_FRONTEND=noninteractive
    
    # Mise à jour des sources
    if ! apt-get update -qq; then
        log_error "Échec de la mise à jour des sources"
        exit 1
    fi
    
    # Installation des paquets essentiels
    local packages=(
        "wireguard"
        "nginx"
        "php-fpm"
        "php-sqlite3"
        "php-json"
        "php-curl"
        "sqlite3"
        "iptables"
        "ndppd"
        "openssl"
        "curl"
    )
    
    for package in "${packages[@]}"; do
        log_info "Installation: $package"
        if ! apt-get install -y "$package" >/dev/null 2>&1; then
            log_error "Échec installation: $package"
            exit 1
        fi
    done
    
    log_success "Paquets installés avec succès"
}

# ========================================
# 🔧 CONFIGURATION WIREGUARD
# ========================================

setup_wireguard() {
    log_info "Configuration WireGuard..."
    
    # Génération de la clé privée du serveur
    log_info "Génération des clés WireGuard..."
    local server_private_key
    if ! server_private_key=$(wg genkey); then
        log_error "Échec génération clé privée WireGuard"
        exit 1
    fi
    
    local server_public_key
    if ! server_public_key=$(echo "$server_private_key" | wg pubkey); then
        log_error "Échec génération clé publique WireGuard"
        exit 1
    fi
    log_success "Clés WireGuard générées"
    
    # Détection de l'interface réseau principale
    log_info "Détection de l'interface réseau..."
    local interface
    if ! interface=$(ip route get 8.8.8.8 | awk 'NR==1 {print $5}'); then
        log_error "Échec détection interface réseau"
        exit 1
    fi
    log_success "Interface détectée: $interface"
    
    # Détection du préfixe IPv6 (préférence route kernel sur l'interface)
    log_info "Détection du préfixe IPv6..."
    local route_prefix
    route_prefix=$(ip -6 route show dev "$interface" | awk '/proto kernel/ && $1 ~ /\/[0-9]+/ {print $1; exit}')
    if [[ -z "$route_prefix" ]]; then
        route_prefix=$(ip -6 route show dev "$interface" | awk '/\/[0-9]+/ {print $1; exit}')
    fi
    if [[ -z "$route_prefix" ]]; then
        log_error "Impossible de détecter le préfixe IPv6 sur $interface"
        ip -6 addr show dev "$interface" || true
        ip -6 route show dev "$interface" || true
        exit 1
    fi
    local prefix_base="${route_prefix%/*}"
    local prefix_len="${route_prefix##*/}"
    log_success "Préfixe IPv6 détecté: $prefix_base/$prefix_len"
    
    # Configuration WireGuard
    log_info "Création du fichier de configuration WireGuard..."
    if ! cat > "$WG_CONFIG" << EOF
[Interface]
PrivateKey = $server_private_key
Address = ${prefix_base%::}::1/64
ListenPort = 51820
SaveConfig = false

# Règles de routage IPv6 (pas de NAT66 par défaut)
PostUp = ip6tables -A FORWARD -i wg0 -j ACCEPT
PostUp = ip6tables -A FORWARD -o wg0 -j ACCEPT
PostDown = ip6tables -D FORWARD -i wg0 -j ACCEPT
PostDown = ip6tables -D FORWARD -o wg0 -j ACCEPT

EOF
    then
        log_error "Échec création fichier $WG_CONFIG"
        exit 1
    fi
    log_success "Fichier WireGuard créé: $WG_CONFIG"

    # Activer le forwarding IPv6 et le proxy NDP
    log_info "Activation du forwarding IPv6 et proxy NDP..."
    cat > /etc/sysctl.d/99-boxion.conf << EOF
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1
net.ipv6.conf.all.accept_ra=2
net.ipv6.conf.default.accept_ra=2
net.ipv6.conf.all.proxy_ndp=1
net.ipv6.conf.$interface.proxy_ndp=1
EOF
    sysctl -p /etc/sysctl.d/99-boxion.conf || true

    # Configuration ndppd (proxy NDP) pour le préfixe détecté
    log_info "Configuration ndppd pour $prefix_base/64..."
    cat > /etc/ndppd.conf << EOF
proxy $interface {
    rule ${prefix_base%::}::/64 {
        auto
    }
}
EOF
    systemctl enable ndppd >/dev/null 2>&1 || true
    systemctl restart ndppd || true
    
    # Activation du service
    log_info "Activation du service WireGuard..."
    if ! systemctl enable wg-quick@wg0; then
        log_error "Échec activation service wg-quick@wg0"
        exit 1
    fi
    log_success "Service wg-quick@wg0 activé"
    
    log_info "Démarrage du service WireGuard..."
    if ! systemctl start wg-quick@wg0; then
        log_error "Échec démarrage service wg-quick@wg0"
        systemctl status wg-quick@wg0 || true
        exit 1
    fi
    log_success "Service WireGuard démarré"
    
    # Sauvegarde des variables pour l'API
    log_info "Sauvegarde des variables de configuration..."
    if ! {
        echo "SERVER_PUBLIC_KEY=$server_public_key" > /tmp/boxion-config.env
        echo "IPV6_PREFIX_BASE=${prefix_base%::}::" >> /tmp/boxion-config.env
        echo "INTERFACE=$interface" >> /tmp/boxion-config.env
    }; then
        log_error "Échec sauvegarde variables configuration"
        exit 1
    fi
    log_success "Variables sauvegardées dans /tmp/boxion-config.env"
    
    log_success "WireGuard configuré (Clé publique: ${server_public_key:0:20}...)"
    log_info "Fonction setup_wireguard terminée avec succès"
}

# ========================================
# 🗄️ CONFIGURATION BASE DE DONNÉES
# ========================================

setup_database() {
    log_info "Configuration de la base de données..."
    
    # Création du répertoire
    mkdir -p "$(dirname "$DB_FILE")"
    
    # Création de la base SQLite
    sqlite3 "$DB_FILE" << 'EOF'
CREATE TABLE IF NOT EXISTS peers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    public_key TEXT UNIQUE NOT NULL,
    ipv6_address TEXT UNIQUE NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_seen DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_peers_public_key ON peers(public_key);
CREATE INDEX IF NOT EXISTS idx_peers_ipv6 ON peers(ipv6_address);
EOF
    
    # Permissions sécurisées
    chown www-data:www-data "$DB_FILE"
    chmod 640 "$DB_FILE"
    
    log_success "Base de données configurée"
}

# ========================================
# 🌐 CONFIGURATION API PHP
# ========================================

setup_api() {
    log_info "Configuration de l'API PHP..."
    
    # Création du répertoire API
    mkdir -p "$API_DIR/api"
    
    # Génération du token API sécurisé
    local api_token
    api_token=$(openssl rand -hex 32)
    
    # Lecture des variables WireGuard
    source /tmp/boxion-config.env
    
    # Création du fichier .env
    cat > "$API_DIR/.env" << EOF
# Configuration Boxion API
DB_PATH=$DB_FILE
API_TOKEN=$api_token
SERVER_PUBLIC_KEY=$SERVER_PUBLIC_KEY
IPV6_PREFIX_BASE=$IPV6_PREFIX_BASE
INTERFACE=$INTERFACE
ENDPOINT_PORT=51820
EOF
    
    # Permissions sécurisées
    chown www-data:www-data "$API_DIR/.env"
    chmod 600 "$API_DIR/.env"
    
    # Création du helper root pour appliquer la config WireGuard
    cat > /usr/local/sbin/boxion-wg-apply << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

WG_CONF="/etc/wireguard/wg0.conf"

cmd="${1:-}"
case "$cmd" in
  add-peer)
    pubkey="${2:-}"
    ipv6="${3:-}"
    if [[ -z "$pubkey" || -z "$ipv6" ]]; then
      echo "Usage: $0 add-peer <pubkey> <ipv6/128>" >&2; exit 2
    fi
    if ! [[ "$pubkey" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
      echo "Invalid pubkey" >&2; exit 2
    fi
    if ! echo "$ipv6" | grep -Eq '^[0-9a-fA-F:]+/128$'; then
      echo "Invalid IPv6" >&2; exit 2
    fi
    umask 077
    {
      printf "\n[Peer]\n"
      printf "PublicKey = %s\n" "$pubkey"
      printf "AllowedIPs = %s\n" "$ipv6"
    } >> "$WG_CONF"
    tmp="/run/wg0.stripped.conf"
    wg-quick strip wg0 > "$tmp"
    wg syncconf wg0 "$tmp"
    rm -f "$tmp"
    ;;
  *)
    echo "Usage: $0 add-peer <pubkey> <ipv6/128>" >&2
    exit 2
    ;;
esac
EOF
    chmod 750 /usr/local/sbin/boxion-wg-apply
    chown root:root /usr/local/sbin/boxion-wg-apply
    echo "www-data ALL=(root) NOPASSWD: /usr/local/sbin/boxion-wg-apply" > /etc/sudoers.d/boxion-wg
    chmod 440 /etc/sudoers.d/boxion-wg

    # Génération Basic Auth admin pour le dashboard
    local admin_password
    admin_password=$(openssl rand -base64 16)
    local ht_hash
    ht_hash=$(openssl passwd -apr1 "$admin_password")
    echo "admin:$ht_hash" > /etc/nginx/.htpasswd-boxion
    echo "$admin_password" > /tmp/boxion-admin.txt
    
    # Création de l'API principale
    cat > "$API_DIR/api/index.php" << 'EOF'
<?php
// 🚀 Boxion API - Simple et sécurisée
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

// Chargement de la configuration
$env = [];
if (file_exists(__DIR__ . '/../.env')) {
    $lines = file(__DIR__ . '/../.env', FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        if (strpos($line, '=') !== false && !str_starts_with(trim($line), '#')) {
            [$key, $value] = explode('=', $line, 2);
            $env[trim($key)] = trim($value);
        }
    }
}

function jsonResponse($data, $status = 200) {
    http_response_code($status);
    echo json_encode($data);
    exit;
}

function validateToken() {
    global $env;
    $headers = function_exists('getallheaders') ? getallheaders() : [];
    $token = $headers['Authorization'] ?? '';
    
    if (!str_starts_with($token, 'Bearer ')) {
        jsonResponse(['error' => 'Token manquant'], 401);
    }
    
    $provided_token = substr($token, 7);
    if (!hash_equals($env['API_TOKEN'] ?? '', $provided_token)) {
        jsonResponse(['error' => 'Token invalide'], 403);
    }
}

function getNextIPv6($prefixBase) {
    global $env;
    // Connexion à la base
    $db = new PDO('sqlite:' . ($env['DB_PATH'] ?? ''));
    $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    // Recherche du prochain ID disponible
    $stmt = $db->query("SELECT MAX(id) as max_id FROM peers");
    $result = $stmt->fetch();
    $next_id = ($result['max_id'] ?? 0) + 1;
    // Décaler pour éviter ::1 (serveur)
    $offset = 0x100; // commence à ::100
    $hext = dechex($next_id + $offset);
    return $prefixBase . $hext . '/128';
}

// Gestion des requêtes
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    exit; // Gestion CORS preflight
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    jsonResponse(['error' => 'Méthode non autorisée'], 405);
}

// Validation du token
validateToken();

// Décodage de la requête
$input = json_decode(file_get_contents('php://input'), true);
if (!$input) {
    jsonResponse(['error' => 'JSON invalide'], 400);
}

// Validation des données
if (empty($input['name']) || empty($input['public_key'])) {
    jsonResponse(['error' => 'Nom et clé publique requis'], 400);
}

$name = trim($input['name']);
$public_key = trim($input['public_key']);

// Validation de la clé publique WireGuard
if (!preg_match('/^[A-Za-z0-9+\/]{43}=$/', $public_key)) {
    jsonResponse(['error' => 'Format de clé publique invalide'], 400);
}

try {
    // Connexion à la base
    $db = new PDO('sqlite:' . $env['DB_PATH']);
    $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    
    // Vérification que la clé n'existe pas déjà
    $stmt = $db->prepare("SELECT COUNT(*) FROM peers WHERE public_key = ?");
    $stmt->execute([$public_key]);
    if ($stmt->fetchColumn() > 0) {
        jsonResponse(['error' => 'Clé publique déjà enregistrée'], 409);
    }
    
    // Attribution de l'adresse IPv6
    $ipv6_address = getNextIPv6($env['IPV6_PREFIX_BASE']);
    
    // Insertion du nouveau peer
    $stmt = $db->prepare("INSERT INTO peers (name, public_key, ipv6_address) VALUES (?, ?, ?)");
    $stmt->execute([$name, $public_key, $ipv6_address]);

    // Ajout à la config WireGuard via helper root
    $cmd = 'sudo /usr/local/sbin/boxion-wg-apply add-peer ' 
        . escapeshellarg($public_key) . ' ' . escapeshellarg($ipv6_address);
    exec($cmd, $out, $rc);
    if ($rc !== 0) {
        jsonResponse(['error' => 'Échec application config WG'], 500);
    }

    $host = $_SERVER['HTTP_HOST'] ?? ($_SERVER['SERVER_NAME'] ?? 'localhost');
    $host = preg_replace('/:.*/', '', $host);
    $endpoint = $host . ':' . ($env['ENDPOINT_PORT'] ?? '51820');
    jsonResponse([
        'success' => true,
        // Compat top-level pour scripts simples
        'Address' => $ipv6_address,
        'PublicKey' => $env['SERVER_PUBLIC_KEY'],
        'Endpoint' => $endpoint,
        'config' => [
            'interface' => [
                'PrivateKey' => '[VOTRE_CLE_PRIVEE]',
                'Address' => $ipv6_address
            ],
            'peer' => [
                'PublicKey' => $env['SERVER_PUBLIC_KEY'],
                'Endpoint' => $endpoint,
                'AllowedIPs' => '::/0'
            ]
        ]
    ]);
    
} catch (Exception $e) {
    error_log("Erreur API Boxion: " . $e->getMessage());
    jsonResponse(['error' => 'Erreur interne du serveur'], 500);
}
EOF
    # Permissions
    chown -R www-data:www-data "$API_DIR"
    
    log_success "API configurée (Token: ${api_token:0:20}...)"
    echo "$api_token" > /tmp/boxion-token.txt
}

# ========================================
# 🌐 CONFIGURATION NGINX
# ========================================

setup_nginx() {
    log_info "Configuration Nginx..."
    # Détection du socket PHP-FPM
    local php_fpm_sock=""
    if [[ -S /run/php/php-fpm.sock ]]; then
        php_fpm_sock="/run/php/php-fpm.sock"
    else
        local php_version
        php_version=$(php-fpm -v 2>/dev/null | awk '/PHP/{print $2}' | cut -d. -f1,2 || true)
        if [[ -n "$php_version" && -S "/run/php/php${php_version}-fpm.sock" ]]; then
            php_fpm_sock="/run/php/php${php_version}-fpm.sock"
        else
            php_fpm_sock="$(ls /run/php/php*-fpm.sock 2>/dev/null | head -n1 || true)"
        fi
    fi
    if [[ -z "$php_fpm_sock" ]]; then
        php_fpm_sock="/run/php/php-fpm.sock"
    fi

    # Configuration du site
    cat > "/etc/nginx/sites-available/boxion-api" << EOF
server {
    listen 80;
    listen [::]:80;
    server_name _;
    
    root $API_DIR;
    index index.php;
    
    # Logs
    access_log /var/log/nginx/boxion-access.log;
    error_log /var/log/nginx/boxion-error.log;
    
    # API endpoint
    location = /api { return 301 /api/; }
    location /api/ {
        index index.php;
        try_files \$uri /api/index.php;
    }
    location ~ ^/api/.*\.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$php_fpm_sock;
    }
    
    # Interface web simple
    location / {
        auth_basic "Boxion Admin";
        auth_basic_user_file /etc/nginx/.htpasswd-boxion;
        try_files \$uri \$uri/ /index.html;
    }
    
    # Sécurité
    location ~ /\.env {
        deny all;
    }
}
EOF
    
    # Activation du site
    ln -sf /etc/nginx/sites-available/boxion-api /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # Test et rechargement
    nginx -t && systemctl reload nginx
    
    log_success "Nginx configuré"
}

# ========================================
# 🎨 CRÉATION DASHBOARD SIMPLE
# ========================================

setup_dashboard() {
    log_info "Création du dashboard web..."
    
    # Page d'accueil simple
    cat > "$API_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Boxion VPN Tunnel</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 40px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; margin-bottom: 30px; }
        .status { padding: 15px; background: #e8f5e8; border-radius: 5px; margin: 20px 0; }
        .code { background: #f8f8f8; padding: 15px; border-radius: 5px; font-family: monospace; margin: 10px 0; }
        .btn { background: #3498db; color: white; padding: 10px 20px; border: none; border-radius: 5px; cursor: pointer; }
        .btn:hover { background: #2980b9; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Boxion VPN Tunnel</h1>
        
        <div class="status">
            ✅ Serveur tunnel opérationnel<br>
            🌐 Distribue des adresses IPv6 publiques via WireGuard
        </div>
        
        <h2>📱 Connexion d'une Boxion</h2>
        <p>Pour connecter votre Boxion à ce tunnel et obtenir une IPv6 publique :</p>
        
        <div class="code">
curl -sSL https://raw.githubusercontent.com/USER/boxion-setup/main/boxion-client-setup.sh | bash
        </div>
        
        <h2>🔧 Administration</h2>
        <p>Ce serveur fournit une API pour la gestion automatisée des peers WireGuard.</p>
        
        <button class="btn" onclick="showStats()">📊 Statistiques</button>
        
        <div id="stats" style="display:none; margin-top: 20px;">
            <h3>Statistiques du tunnel</h3>
            <div class="code" id="stats-content">Chargement...</div>
        </div>
    </div>
    
    <script>
        function showStats() {
            document.getElementById('stats').style.display = 'block';
            // Ici on pourrait ajouter un appel AJAX pour récupérer les stats
            document.getElementById('stats-content').textContent = 'Fonctionnalité à venir...';
        }
    </script>
</body>
</html>
EOF
    
    chown www-data:www-data "$API_DIR/index.html"
    
    log_success "Dashboard créé"
}

# ========================================
# 🚀 FONCTION PRINCIPALE
# ========================================

main() {
    echo "🚀 Installation Boxion VPN Server - Version Simple"
    echo "=================================================="
    echo ""
    
    check_requirements
    install_packages
    setup_wireguard
    setup_database
    setup_api
    setup_nginx
    setup_dashboard
    
    echo ""
    echo "🎉 INSTALLATION TERMINÉE AVEC SUCCÈS !"
    echo "======================================"
    echo ""
    log_success "Serveur tunnel opérationnel"
    log_info "API disponible sur: http://$(hostname -I | awk '{print $1}')/api/"
    log_info "Dashboard: http://$(hostname -I | awk '{print $1}')/"
    
    if [[ -f /tmp/boxion-token.txt ]]; then
        echo ""
        log_warning "🔑 TOKEN API (à garder secret):"
        echo "$(cat /tmp/boxion-token.txt)"
        rm -f /tmp/boxion-token.txt
    fi
    
    if [[ -f /tmp/boxion-admin.txt ]]; then
        echo ""
        log_warning "🔐 Identifiants Dashboard (HTTP Basic Auth):"
        echo "admin: $(cat /tmp/boxion-admin.txt)"
        rm -f /tmp/boxion-admin.txt
    fi
    
    echo ""
    log_info "Pour connecter une Boxion, utilisez le script client avec ce token"
    
    # Nettoyage des fichiers temporaires
    rm -f /tmp/boxion-config.env
}

# Exécution du script principal
main "$@"
