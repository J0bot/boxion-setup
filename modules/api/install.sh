#!/usr/bin/env bash

# 🔌 Module API - Installation API REST et authentification
# Extrait du monolithe setup.sh pour une approche modulaire

set -euo pipefail

# Source du logging
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../logging/logger.sh"

MODULE_NAME="API"
log_info "$MODULE_NAME" "Début installation module API"

# Variables globales du module
APP_ROOT="/var/www/boxion-api"
API_DIR="$APP_ROOT/api"
BIN_DIR="$APP_ROOT/bin"
SQL_DIR="$APP_ROOT/sql"
DB_PATH="/var/lib/boxion/boxion.db"
POOL_BITS="${POOL_BITS:-16}"
DNS_V6="${DNS_V6:-2606:4700:4700::1111}"

# ====== CRÉATION DE LA STRUCTURE API ======

create_api_structure() {
    log_step "$MODULE_NAME" "Création structure API" "1/6"
    
    # Création des répertoires avec gestion d'erreur
    local directories=(
        "$APP_ROOT"
        "$API_DIR"
        "$BIN_DIR"
        "$SQL_DIR"
        "$APP_ROOT/nginx"
        "$APP_ROOT/systemd"
        "$APP_ROOT/sudoers"
    )
    
    for dir in "${directories[@]}"; do
        log_debug "$MODULE_NAME" "Création: $dir"
        if ! mkdir -p "$dir" 2>/dev/null; then
            log_fatal "$MODULE_NAME" "Impossible de créer: $dir"
        fi
    done
    
    # Permissions sécurisées
    if ! chown -R www-data:www-data "$APP_ROOT" 2>/dev/null; then
        log_fatal "$MODULE_NAME" "Impossible de définir permissions: $APP_ROOT"
    fi
    
    log_success "$MODULE_NAME" "Structure API créée: $APP_ROOT"
}

# ====== GÉNÉRATION DES SCRIPTS BIN ======

generate_bin_scripts() {
    log_step "$MODULE_NAME" "Génération scripts système" "2/6"
    
    local wan_if="${WAN_IF:-eth0}"
    local wg_if="${WG_IF:-wg0}"
    
    # Script wg_add_peer.sh
    log_debug "$MODULE_NAME" "Création: $BIN_DIR/wg_add_peer.sh"
    cat > "$BIN_DIR/wg_add_peer.sh" << 'EOF'
#!/usr/bin/env bash
# Script sécurisé d'ajout de peer WireGuard
set -euo pipefail

# Variables d'environnement (définies par sudoers)
WG_IF="${WG_IF:-wg0}"
WAN_IF="${WAN_IF:-eth0}"

# Validation des paramètres
PUB="$1"
IP6="$2"

if [[ -z "$PUB" || -z "$IP6" ]]; then
    echo "Usage: $0 PUBLIC_KEY IPV6_ADDRESS" >&2
    exit 1
fi

# Validation format clé publique WireGuard (base64, 44 caractères)
if [[ ! "$PUB" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
    echo "Erreur: Format de clé publique invalide" >&2
    exit 1
fi

# Validation format IPv6
if [[ ! "$IP6" =~ ^[0-9a-f:]+$ ]]; then
    echo "Erreur: Format IPv6 invalide" >&2
    exit 1
fi

# Ajout du peer à WireGuard
wg set "$WG_IF" peer "$PUB" allowed-ips "${IP6}/128"

# Configuration NDP proxy pour routage IPv6
ip -6 neigh add proxy "$IP6" dev "$WAN_IF" 2>/dev/null || true

echo "Peer ajouté: $PUB -> $IP6"
EOF

    # Script wg_del_peer.sh
    log_debug "$MODULE_NAME" "Création: $BIN_DIR/wg_del_peer.sh"
    cat > "$BIN_DIR/wg_del_peer.sh" << 'EOF'
#!/usr/bin/env bash
# Script sécurisé de suppression de peer WireGuard
set -euo pipefail

# Variables d'environnement
WG_IF="${WG_IF:-wg0}"
WAN_IF="${WAN_IF:-eth0}"

# Validation des paramètres
PUB="$1"
IP6="$2"

if [[ -z "$PUB" || -z "$IP6" ]]; then
    echo "Usage: $0 PUBLIC_KEY IPV6_ADDRESS" >&2
    exit 1
fi

# Suppression du peer WireGuard
wg set "$WG_IF" peer "$PUB" remove 2>/dev/null || true

# Suppression NDP proxy
ip -6 neigh del proxy "$IP6" dev "$WAN_IF" 2>/dev/null || true

echo "Peer supprimé: $PUB -> $IP6"
EOF

    # Script replay_ndp.sh
    log_debug "$MODULE_NAME" "Création: $BIN_DIR/replay_ndp.sh"
    cat > "$BIN_DIR/replay_ndp.sh" << 'EOF'
#!/usr/bin/env bash
# Script de restauration des peers WireGuard au boot
set -euo pipefail

WG_IF="${WG_IF:-wg0}"
WAN_IF="${WAN_IF:-eth0}"
DB="/var/lib/boxion/boxion.db"

# Vérification existence base de données
if [[ ! -f "$DB" ]]; then
    echo "Base de données introuvable: $DB" >&2
    exit 0
fi

# Attente interface WireGuard (max 30s)
for i in {1..30}; do
    if ip link show "$WG_IF" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

if ! ip link show "$WG_IF" >/dev/null 2>&1; then
    echo "Interface $WG_IF indisponible après 30s" >&2
    exit 1
fi

echo "Restauration des peers WireGuard..."

# Restauration des peers depuis la base de données
while IFS='|' read -r pub ip6; do
    [[ -n "$pub" ]] || continue
    
    # Réajout du peer
    wg set "$WG_IF" peer "$pub" allowed-ips "${ip6}/128" 2>/dev/null || true
    
    # Réajout NDP proxy
    ip -6 neigh add proxy "$ip6" dev "$WAN_IF" 2>/dev/null || true
    
    echo "Peer restauré: $pub -> $ip6"
done < <(sqlite3 "$DB" "SELECT pubkey||'|'||ipv6 FROM peers;" 2>/dev/null)

echo "Restauration terminée"
EOF

    # Permissions d'exécution
    chmod +x "$BIN_DIR"/*.sh
    chown root:root "$BIN_DIR"/*.sh
    
    log_success "$MODULE_NAME" "Scripts système générés (3 scripts)"
}

# ====== INITIALISATION BASE DE DONNÉES ======

initialize_database() {
    log_step "$MODULE_NAME" "Initialisation base de données" "3/6"
    
    # Script SQL d'initialisation
    log_debug "$MODULE_NAME" "Création: $SQL_DIR/init.sql"
    cat > "$SQL_DIR/init.sql" << 'EOF'
-- Base de données Boxion Tunnel VPN
-- Gestion des peers WireGuard avec attribution IPv6 automatique

PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;

-- Table des peers connectés
CREATE TABLE IF NOT EXISTS peers (
    name TEXT PRIMARY KEY CHECK(name != ''),
    pubkey TEXT UNIQUE NOT NULL CHECK(length(pubkey) = 44),
    ipv6 TEXT UNIQUE NOT NULL CHECK(ipv6 LIKE '%:%'),
    created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
);

-- Index pour optimiser les requêtes
CREATE INDEX IF NOT EXISTS idx_peers_created_at ON peers(created_at);
CREATE INDEX IF NOT EXISTS idx_peers_ipv6 ON peers(ipv6);

-- Table de métadonnées pour allocation des IDs
CREATE TABLE IF NOT EXISTS meta (
    k TEXT PRIMARY KEY,
    v TEXT NOT NULL
);

-- Initialisation du compteur d'ID (peer ID = 1, 2, 3...)
INSERT OR IGNORE INTO meta(k,v) VALUES('last_id','1');

-- Table de logs pour audit (optionnelle)
CREATE TABLE IF NOT EXISTS audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
    action TEXT NOT NULL,
    peer_name TEXT,
    details TEXT
);

CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON audit_log(timestamp);
EOF

    # Initialisation de la base
    local db_dir=$(dirname "$DB_PATH")
    if ! mkdir -p "$db_dir" 2>/dev/null; then
        log_fatal "$MODULE_NAME" "Impossible de créer: $db_dir"
    fi
    
    log_info "$MODULE_NAME" "Initialisation base SQLite: $DB_PATH"
    
    # Fichier temporaire sécurisé
    local temp_log
    temp_log=$(mktemp) || {
        log_error "$MODULE_NAME" "Impossible de créer fichier temporaire"
        return 1
    }
    
    if ! sqlite3 "$DB_PATH" < "$SQL_DIR/init.sql" 2>"$temp_log"; then
        log_error_context "$MODULE_NAME" "Échec initialisation base" "$(cat "$temp_log")"
        rm -f "$temp_log"
        return 1
    fi
    
    rm -f "$temp_log"
    
    # Permissions pour accès web
    chown www-data:www-data "$DB_PATH"
    chmod 664 "$DB_PATH"
    
    # Validation
    local table_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';")
    log_debug "$MODULE_NAME" "Base initialisée: $table_count tables créées"
    
    log_success "$MODULE_NAME" "Base de données initialisée"
    rm -f /tmp/sqlite-init.log
}

# ====== CONFIGURATION ENVIRONNEMENT ======

generate_env_config() {
    log_step "$MODULE_NAME" "Configuration environnement" "4/6"
    
    local env_file="$APP_ROOT/.env"
    local wan_if="${WAN_IF:-eth0}"
    local wg_if="${WG_IF:-wg0}"
    local port="${PORT:-51820}"
    
    # Chargement des variables WireGuard
    if [[ -f /tmp/boxion-wireguard-vars.sh ]]; then
        source /tmp/boxion-wireguard-vars.sh
        log_debug "$MODULE_NAME" "Variables WireGuard chargées"
    else
        log_warn "$MODULE_NAME" "Variables WireGuard non trouvées - utilisation des valeurs par défaut"
        SV_PUB="${SV_PUB:-}"
    fi
    
    log_info "$MODULE_NAME" "Génération: $env_file"
    cat > "$env_file" << EOF
# Configuration Boxion Tunnel VPN API
# Générée automatiquement le $(date)

# Configuration WireGuard
WG_IF=$wg_if
WAN_IF=$wan_if

# Configuration réseau
ENDPOINT_DOMAIN=$DOMAIN
ENDPOINT_PORT=$port
SERVER_PUBLIC_KEY=$SV_PUB

# Configuration IPv6
IPV6_PREFIX=$IPV6_PREFIX
POOL_BITS=$POOL_BITS

# Sécurité API
API_TOKEN=$API_TOKEN

# Base de données
DB_PATH=$DB_PATH

# Configuration système
APP_BIN=$BIN_DIR
DNS_V6=$DNS_V6

# Logs et debug
LOG_LEVEL=${LOG_LEVEL:-INFO}
DEBUG=${DEBUG:-false}
EOF

    # Permissions sécurisées (contient le token)
    chmod 600 "$env_file"
    chown www-data:www-data "$env_file"
    
    local config_lines=$(wc -l < "$env_file")
    log_success "$MODULE_NAME" "Configuration générée ($config_lines paramètres)"
}

# ====== GÉNÉRATION DE L'API REST ======

generate_api_endpoints() {
    log_step "$MODULE_NAME" "Génération API REST" "5/6"
    
    local api_file="$API_DIR/index.php"
    log_info "$MODULE_NAME" "Génération: $api_file"
    
    cat > "$api_file" << 'EOF'
<?php
/**
 * Boxion Tunnel VPN - API REST sécurisée
 * Gestion des peers WireGuard avec authentification Bearer token
 */

// Configuration sécurisée
ini_set('display_errors', 0);
error_reporting(0);
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET,POST,DELETE,OPTIONS');
header('Access-Control-Allow-Headers: Authorization,Content-Type');
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');

// Gestion CORS preflight
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// ====== FONCTIONS UTILITAIRES ======

function envv($k, $d = '') {
    static $E = null;
    if ($E === null) {
        $envFile = __DIR__ . '/../.env';
        if (!file_exists($envFile)) {
            error_log("Boxion API: .env file not found");
            return $d;
        }
        $E = parse_ini_file($envFile);
        if ($E === false) {
            error_log("Boxion API: Failed to parse .env file");
            return $d;
        }
    }
    return $E[$k] ?? $d;
}

function abort($code, $msg) {
    http_response_code($code);
    echo json_encode(['error' => $msg, 'timestamp' => time()]);
    error_log("Boxion API [$code]: $msg");
    exit;
}

function auth() {
    $h = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if (!preg_match('/Bearer\s+(.+)/i', $h, $m)) {
        abort(401, 'no_token');
    }
    
    $token = trim($m[1]);
    $expectedToken = envv('API_TOKEN');
    
    if (empty($expectedToken)) {
        error_log("Boxion API: No API_TOKEN configured");
        abort(500, 'server_config_error');
    }
    
    if (!hash_equals($expectedToken, $token)) {
        abort(401, 'invalid_token');
    }
}

function db() {
    static $pdo = null;
    if ($pdo === null) {
        $dbPath = envv('DB_PATH', '/var/lib/boxion/boxion.db');
        
        if (!file_exists($dbPath)) {
            abort(500, 'database_not_found');
        }
        
        try {
            $pdo = new PDO("sqlite:$dbPath");
            $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
            $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
        } catch (PDOException $e) {
            error_log("Boxion API DB error: " . $e->getMessage());
            abort(500, 'database_error');
        }
    }
    return $pdo;
}

// ====== GESTION DES IPv6 ======

function next_ip6() {
    $prefix = envv('IPV6_PREFIX');
    $bits = (int)envv('POOL_BITS', 16);
    
    if (empty($prefix)) {
        abort(500, 'no_ipv6_prefix');
    }
    
    $db = db();
    $max = (1 << $bits) - 1;
    
    $db->beginTransaction();
    
    try {
        // Récupération atomique du dernier ID
        $stmt = $db->query("SELECT v FROM meta WHERE k='last_id'");
        $lastId = (int)$stmt->fetchColumn();
        
        if ($lastId > $max) {
            abort(409, 'pool_exhausted');
        }
        
        // Incrémentation atomique
        $db->exec("UPDATE meta SET v='" . ($lastId + 1) . "' WHERE k='last_id'");
        $db->commit();
        
        // Composition de l'adresse IPv6: prefix::id
        $hex = strtoupper(str_pad(dechex($lastId), 4, '0', STR_PAD_LEFT));
        return $prefix . '::' . $hex;
        
    } catch (Exception $e) {
        $db->rollback();
        error_log("Boxion API next_ip6 error: " . $e->getMessage());
        abort(500, 'ip6_allocation_failed');
    }
}

// ====== VALIDATION ======

function valid_name($s) {
    return preg_match('/^[a-zA-Z0-9._-]{1,32}$/', $s);
}

function valid_pub($s) {
    // Clé WireGuard: 44 caractères base64
    if (!preg_match('#^[A-Za-z0-9+/]{43}=$#', $s)) {
        return false;
    }
    
    // Validation décodage base64
    $decoded = base64_decode($s, true);
    if ($decoded === false || strlen($decoded) !== 32) {
        return false;
    }
    
    // Anti-clé faible (tout zéros)
    if ($decoded === str_repeat("\0", 32)) {
        return false;
    }
    
    return true;
}

// ====== AUTHENTIFICATION ======
auth();

$method = $_SERVER['REQUEST_METHOD'];
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);

// ====== ENDPOINT: POST /api/peers ======
if ($method === 'POST' && preg_match('#^/api/peers$#', $path)) {
    $input = json_decode(file_get_contents('php://input'), true);
    
    if (!$input) {
        abort(400, 'invalid_json');
    }
    
    $name = $input['name'] ?? '';
    $pub = $input['pubkey'] ?? '';
    
    if (!valid_name($name)) {
        abort(400, 'invalid_name');
    }
    
    if (!valid_pub($pub)) {
        abort(400, 'invalid_pubkey');
    }
    
    $db = db();
    
    // Vérification peer existant (idempotent)
    $stmt = $db->prepare('SELECT ipv6 FROM peers WHERE name = ?');
    $stmt->execute([$name]);
    $existing = $stmt->fetch();
    
    if ($existing) {
        $ipv6 = $existing['ipv6'];
        error_log("Boxion API: Peer exists, returning config: $name -> $ipv6");
    } else {
        // Création nouveau peer
        $ipv6 = next_ip6();
        
        try {
            $stmt = $db->prepare('INSERT INTO peers(name,pubkey,ipv6,created_at) VALUES(?,?,?,?)');
            $stmt->execute([$name, $pub, $ipv6, time()]);
            
            // Ajout peer WireGuard via script sudo
            putenv('WG_IF=' . envv('WG_IF'));
            putenv('WAN_IF=' . envv('WAN_IF'));
            
            $addScript = escapeshellcmd(envv('APP_BIN') . '/wg_add_peer.sh');
            $cmd = "$addScript " . escapeshellarg($pub) . " " . escapeshellarg($ipv6) . " 2>&1";
            
            exec($cmd, $output, $returnCode);
            
            if ($returnCode !== 0) {
                // Rollback base de données
                $db->prepare('DELETE FROM peers WHERE name = ?')->execute([$name]);
                error_log("Boxion API: WireGuard add failed: " . implode("\n", $output));
                abort(500, 'wireguard_add_failed');
            }
            
            error_log("Boxion API: New peer created: $name -> $ipv6");
            
        } catch (PDOException $e) {
            error_log("Boxion API: Database error: " . $e->getMessage());
            abort(500, 'database_error');
        }
    }
    
    // Génération configuration client
    $wgConf = "[Interface]\n" .
              "Address = $ipv6/128\n" .
              "DNS = " . envv('DNS_V6') . "\n\n" .
              "[Peer]\n" .
              "PublicKey = " . envv('SERVER_PUBLIC_KEY') . "\n" .
              "Endpoint = " . envv('ENDPOINT_DOMAIN') . ":" . envv('ENDPOINT_PORT') . "\n" .
              "AllowedIPs = ::/0\n" .
              "PersistentKeepalive = 25\n";
    
    echo json_encode([
        'wg_conf' => $wgConf,
        'ipv6' => $ipv6,
        'success' => true
    ]);
    exit;
}

// ====== ENDPOINT: GET /api/peers/{name} ======
if ($method === 'GET' && preg_match('#^/api/peers/([a-zA-Z0-9._-]+)$#', $path, $matches)) {
    $name = $matches[1];
    
    $stmt = db()->prepare('SELECT ipv6,pubkey,created_at FROM peers WHERE name = ?');
    $stmt->execute([$name]);
    $peer = $stmt->fetch();
    
    if (!$peer) {
        abort(404, 'peer_not_found');
    }
    
    // Configuration client
    $wgConf = "[Interface]\n" .
              "Address = " . $peer['ipv6'] . "/128\n" .
              "DNS = " . envv('DNS_V6') . "\n\n" .
              "[Peer]\n" .
              "PublicKey = " . envv('SERVER_PUBLIC_KEY') . "\n" .
              "Endpoint = " . envv('ENDPOINT_DOMAIN') . ":" . envv('ENDPOINT_PORT') . "\n" .
              "AllowedIPs = ::/0\n" .
              "PersistentKeepalive = 25\n";
    
    echo json_encode([
        'wg_conf' => $wgConf,
        'ipv6' => $peer['ipv6'],
        'created_at' => $peer['created_at'],
        'success' => true
    ]);
    exit;
}

// ====== ENDPOINT: DELETE /api/peers/{name} ======
if ($method === 'DELETE' && preg_match('#^/api/peers/([a-zA-Z0-9._-]+)$#', $path, $matches)) {
    $name = $matches[1];
    
    $db = db();
    $stmt = $db->prepare('SELECT ipv6,pubkey FROM peers WHERE name = ?');
    $stmt->execute([$name]);
    $peer = $stmt->fetch();
    
    if (!$peer) {
        abort(404, 'peer_not_found');
    }
    
    // Suppression WireGuard via script sudo
    putenv('WG_IF=' . envv('WG_IF'));
    putenv('WAN_IF=' . envv('WAN_IF'));
    
    $delScript = escapeshellcmd(envv('APP_BIN') . '/wg_del_peer.sh');
    $cmd = "$delScript " . escapeshellarg($peer['pubkey']) . " " . escapeshellarg($peer['ipv6']) . " 2>&1";
    
    exec($cmd, $output, $returnCode);
    
    if ($returnCode !== 0) {
        error_log("Boxion API: WireGuard del failed: " . implode("\n", $output));
        abort(500, 'wireguard_del_failed');
    }
    
    // Suppression base de données
    $db->prepare('DELETE FROM peers WHERE name = ?')->execute([$name]);
    
    error_log("Boxion API: Peer deleted: $name");
    
    echo json_encode(['success' => true]);
    exit;
}

// ====== ENDPOINT: GET /api/status ======
if ($method === 'GET' && preg_match('#^/api/status$#', $path)) {
    $db = db();
    $peerCount = $db->query('SELECT COUNT(*) FROM peers')->fetchColumn();
    
    echo json_encode([
        'status' => 'active',
        'peer_count' => (int)$peerCount,
        'version' => '2.0-modular',
        'timestamp' => time()
    ]);
    exit;
}

// Route non trouvée
abort(404, 'route_not_found');
?>
EOF

    # Permissions sécurisées avec gestion d'erreur
    if ! chown -R www-data:www-data "$API_DIR" 2>/dev/null; then
        log_error "$MODULE_NAME" "Échec définition propriétaire: $API_DIR"
        return 1
    fi
    
    if ! chmod 644 "$api_file" 2>/dev/null; then
        log_error "$MODULE_NAME" "Échec définition permissions: $api_file"
        return 1
    fi
    
    # Validation syntaxe PHP avec fichier temporaire sécurisé
    local temp_php_log
    temp_php_log=$(mktemp) || {
        log_error "$MODULE_NAME" "Impossible de créer fichier temporaire"
        return 1
    }
    
    if ! php -l "$api_file" >/dev/null 2>"$temp_php_log"; then
        log_error_context "$MODULE_NAME" "Erreur syntaxe PHP" "$(cat "$temp_php_log")"
        rm -f "$temp_php_log"
        return 1
    fi
    
    rm -f "$temp_php_log"
    local api_lines=$(wc -l < "$api_file")
    log_success "$MODULE_NAME" "API REST générée ($api_lines lignes PHP)"
}

# ====== VALIDATION API ======

validate_api_setup() {
    log_step "$MODULE_NAME" "Validation installation API" "6/6"
    
    # Vérification fichiers critiques
    local critical_files=(
        "$API_DIR/index.php"
        "$APP_ROOT/.env"
        "$DB_PATH"
        "$BIN_DIR/wg_add_peer.sh"
        "$BIN_DIR/wg_del_peer.sh"
    )
    
    for file in "${critical_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_fatal "$MODULE_NAME" "Fichier critique manquant: $file"
        fi
        log_debug "$MODULE_NAME" "✅ $file présent"
    done
    
    # Test base de données
    if ! sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM peers;" >/dev/null 2>&1; then
        log_fatal "$MODULE_NAME" "Base de données non fonctionnelle"
    fi
    log_debug "$MODULE_NAME" "Base de données fonctionnelle"
    
    # Test API basique (syntaxe)
    if ! php -f "$API_DIR/index.php" 2>/dev/null; then
        log_warn "$MODULE_NAME" "Test API échoué - vérifiez la configuration web"
    else
        log_debug "$MODULE_NAME" "API PHP basique fonctionnelle"
    fi
    
    log_success "$MODULE_NAME" "Validation API complète"
}

# ====== MAIN MODULE ======

main() {
    log_info "$MODULE_NAME" "=== INSTALLATION MODULE API ==="
    
    # Vérification privilèges root
    if [[ $UID -ne 0 ]]; then
        log_fatal "$MODULE_NAME" "Privilèges root requis"
    fi
    
    # Validation des prérequis
    validate_or_fatal "$MODULE_NAME" "[[ -n \$DOMAIN ]]" "Variable DOMAIN requise"
    validate_or_fatal "$MODULE_NAME" "[[ -n \$API_TOKEN ]]" "Variable API_TOKEN requise"
    validate_or_fatal "$MODULE_NAME" "[[ -n \$IPV6_PREFIX ]]" "Variable IPV6_PREFIX requise"
    
    # Séquence d'installation API
    create_api_structure
    generate_bin_scripts
    initialize_database
    generate_env_config
    generate_api_endpoints
    validate_api_setup
    
    # Export des informations pour autres modules
    echo "export APP_ROOT='$APP_ROOT'" > /tmp/boxion-api-vars.sh
    echo "export API_DIR='$API_DIR'" >> /tmp/boxion-api-vars.sh
    echo "export DB_PATH='$DB_PATH'" >> /tmp/boxion-api-vars.sh
    
    log_success "$MODULE_NAME" "Module API installé avec succès!"
    log_info "$MODULE_NAME" "API disponible: /api/"
    log_info "$MODULE_NAME" "Base de données: $DB_PATH"
    log_info "$MODULE_NAME" "Scripts sudo: $BIN_DIR/"
    
    return 0
}

# Exécution si appelé directement
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
