#!/usr/bin/env bash

# 🚀 BOXION VPN SERVER - INSTALLATION SIMPLE ET SÉCURISÉE
# Installation complète d'un serveur tunnel IPv6 via WireGuard
# Simple, sécurisé, fonctionnel !

set -euo pipefail

# ========================================
# 🎯 CONFIGURATION & VARIABLES
# ========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
        "sqlite3"
        "iptables"
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
    local server_private_key
    server_private_key=$(wg genkey)
    local server_public_key
    server_public_key=$(echo "$server_private_key" | wg pubkey)
    
    # Détection de l'interface réseau principale
    local interface
    interface=$(ip route get 8.8.8.8 | awk 'NR==1 {print $5}')
    
    # Détection du préfixe IPv6
    local ipv6_prefix
    ipv6_prefix=$(ip -6 addr show "$interface" | grep "inet6.*global" | head -1 | awk '{print $2}' | cut -d'/' -f1)
    
    if [[ -z "$ipv6_prefix" ]]; then
        log_error "Impossible de détecter le préfixe IPv6"
        exit 1
    fi
    
    # Configuration WireGuard
    cat > "$WG_CONFIG" << EOF
[Interface]
PrivateKey = $server_private_key
Address = ${ipv6_prefix%:*}:1::1/112
ListenPort = 51820
SaveConfig = false

# Règles de routage IPv6
PostUp = ip6tables -A FORWARD -i wg0 -j ACCEPT
PostUp = ip6tables -A FORWARD -o wg0 -j ACCEPT
PostUp = ip6tables -t nat -A POSTROUTING -o $interface -j MASQUERADE
PostDown = ip6tables -D FORWARD -i wg0 -j ACCEPT
PostDown = ip6tables -D FORWARD -o wg0 -j ACCEPT
PostDown = ip6tables -t nat -D POSTROUTING -o $interface -j MASQUERADE

EOF
    
    # Activation du service
    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0
    
    # Sauvegarde des variables pour l'API
    echo "SERVER_PUBLIC_KEY=$server_public_key" > /tmp/boxion-config.env
    echo "IPV6_PREFIX=${ipv6_prefix%:*}:1::" >> /tmp/boxion-config.env
    echo "INTERFACE=$interface" >> /tmp/boxion-config.env
    
    log_success "WireGuard configuré (Clé publique: ${server_public_key:0:20}...)"
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
IPV6_PREFIX=$IPV6_PREFIX
INTERFACE=$INTERFACE
EOF
    
    # Permissions sécurisées
    chown www-data:www-data "$API_DIR/.env"
    chmod 600 "$API_DIR/.env"
    
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
    $headers = getallheaders();
    $token = $headers['Authorization'] ?? '';
    
    if (!str_starts_with($token, 'Bearer ')) {
        jsonResponse(['error' => 'Token manquant'], 401);
    }
    
    $provided_token = substr($token, 7);
    if (!hash_equals($env['API_TOKEN'], $provided_token)) {
        jsonResponse(['error' => 'Token invalide'], 403);
    }
}

function getNextIPv6($prefix) {
    global $env;
    
    // Connexion à la base
    $db = new PDO('sqlite:' . $env['DB_PATH']);
    $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    
    // Recherche du prochain ID disponible
    $stmt = $db->query("SELECT MAX(id) as max_id FROM peers");
    $result = $stmt->fetch();
    $next_id = ($result['max_id'] ?? 0) + 1;
    
    // Génération de l'adresse IPv6
    return $prefix . sprintf('%x', $next_id) . '/112';
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
    $ipv6_address = getNextIPv6($env['IPV6_PREFIX']);
    
    // Insertion du nouveau peer
    $stmt = $db->prepare("INSERT INTO peers (name, public_key, ipv6_address) VALUES (?, ?, ?)");
    $stmt->execute([$name, $public_key, $ipv6_address]);
    
    // Ajout à la configuration WireGuard
    $wg_config = "\n[Peer]\nPublicKey = $public_key\nAllowedIPs = $ipv6_address\n";
    file_put_contents('/etc/wireguard/wg0.conf', $wg_config, FILE_APPEND | LOCK_EX);
    
    // Rechargement de WireGuard
    exec('wg syncconf wg0 <(wg-quick strip wg0)');
    
    // Réponse avec la configuration client
    jsonResponse([
        'success' => true,
        'config' => [
            'interface' => [
                'PrivateKey' => '[VOTRE_CLE_PRIVEE]',
                'Address' => $ipv6_address
            ],
            'peer' => [
                'PublicKey' => $env['SERVER_PUBLIC_KEY'],
                'Endpoint' => $_SERVER['SERVER_NAME'] . ':51820',
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
    location /api/ {
        try_files \$uri \$uri/ =404;
        location ~ \.php$ {
            include snippets/fastcgi-php.conf;
            fastcgi_pass unix:/var/run/php/php-fpm.sock;
        }
    }
    
    # Interface web simple
    location / {
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
    
    echo ""
    log_info "Pour connecter une Boxion, utilisez le script client avec ce token"
    
    # Nettoyage des fichiers temporaires
    rm -f /tmp/boxion-config.env
}

# Exécution du script principal
main "$@"
