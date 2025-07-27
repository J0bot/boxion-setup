#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Tunnel VPN Server Setup"
echo "========================="

# ====== paramètres (flags ou interactif) ======
WG_IF=${WG_IF:-wg0}
PORT=${PORT:-51820}
DOMAIN=${DOMAIN:-}
# Auto-détection interface WAN robuste
WAN_IF_DETECTED=$(ip r | awk '/default/ {print $5; exit}' 2>/dev/null)
if [[ -z "$WAN_IF_DETECTED" ]]; then
    echo "⚠️  Pas de route par défaut détectée"
    # Fallback: première interface avec IPv4 globale
    WAN_IF_DETECTED=$(ip -4 addr show scope global | awk -F': ' '/^[0-9]+:/ && !/lo:/ {print $2; exit}')
    echo "💡 Interface fallback: $WAN_IF_DETECTED"
fi
WAN_IF=${WAN_IF:-$WAN_IF_DETECTED}

# Validation interface WAN critique
if [[ -z "$WAN_IF" ]]; then
    echo "❌ Erreur: Aucune interface réseau détectée"
    echo "💡 Spécifiez manuellement: --wan-if eth0"
    exit 1
fi
API_TOKEN=${API_TOKEN:-}
IPV6_PREFIX=${IPV6_PREFIX:-}      # ex: 2a0c:xxxx:xxxx:abcd
POOL_BITS=${POOL_BITS:-16}        # /112 = 16 bits libres
DNS_V6=${DNS_V6:-2606:4700:4700::1111}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    --wan-if) WAN_IF="$2"; shift 2;;
    --token) API_TOKEN="$2"; shift 2;;
    --prefix) IPV6_PREFIX="$2"; shift 2;;
    --pool-bits) POOL_BITS="$2"; shift 2;;
    --dns6) DNS_V6="$2"; shift 2;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

# ====== Mode interactif si paramètres manquants ======
if [[ -z "${DOMAIN}" ]]; then
  echo "🌐 Configuration du domaine"
  read -p "Nom de domaine [tunnel.milkywayhub.org]: " DOMAIN_INPUT
  DOMAIN="${DOMAIN_INPUT:-tunnel.milkywayhub.org}"
  if [[ "$DOMAIN" == "tunnel.milkywayhub.org" ]]; then
    echo "⚠️  Utilisation du domaine par défaut. Assurez-vous qu'il pointe vers ce serveur !"
  fi
fi

if [[ -z "${API_TOKEN}" ]]; then
  echo "🔐 Configuration du token API"
  read -p "Token API (laisser vide pour génération automatique): " TOKEN_INPUT
  if [[ -n "$TOKEN_INPUT" ]]; then
    API_TOKEN="$TOKEN_INPUT"
  else
    echo "🔐 Génération d'un token sécurisé..."
    API_TOKEN=$(openssl rand -hex 32)
    echo "Token généré: $API_TOKEN"
  fi
fi

if [[ -z "${IPV6_PREFIX}" ]]; then
  echo "🌐 Configuration IPv6"
  # Tentative d'auto-détection
  V6=$(ip -6 addr show dev "$WAN_IF" scope global | awk '/inet6/ && !/temporary/ {print $2; exit}' | cut -d/ -f1)
  if [[ -n "$V6" ]]; then
    AUTO_PREFIX=$(printf "%s:%s:%s:%s" $(echo "$V6" | awk -F: '{print $1,$2,$3,$4}'))
    echo "Préfixe IPv6 détecté: ${AUTO_PREFIX}::/64"
    read -p "Préfixe IPv6 /64 [${AUTO_PREFIX}]: " PREFIX_INPUT
    IPV6_PREFIX="${PREFIX_INPUT:-$AUTO_PREFIX}"
  else
    echo "⚠️  Aucune IPv6 globale détectée sur $WAN_IF"
    read -p "Préfixe IPv6 /64 (ex: 2a0c:xxxx:xxxx:abcd): " IPV6_PREFIX
  fi
fi

[[ -z "${API_TOKEN}" ]] && { echo "ERROR: --token requis"; exit 1; }
[[ -z "${IPV6_PREFIX}" ]] && { echo "ERROR: --prefix (préfixe IPv6 /64) requis"; exit 1; }

# ====== paquets ======
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y wireguard iptables php-fpm php-cli php-sqlite3 nginx jq sqlite3

# ====== sysctl et firewall ======
cat >/etc/sysctl.d/99-wireguard.conf <<EOF
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.all.proxy_ndp=1
EOF
sysctl -p /etc/sysctl.d/99-wireguard.conf >/dev/null

ufw allow "${PORT}/udp" >/dev/null 2>&1 || true
iptables -C INPUT -p udp --dport "${PORT}" -j ACCEPT 2>/dev/null || iptables -A INPUT -p udp --dport "${PORT}" -j ACCEPT

# ====== WG serveur (si absent) ======
echo "🔧 Configuration WireGuard serveur..."
# Création répertoires critiques avec vérification
echo "📁 Création répertoires système..."
if ! mkdir -p /etc/wireguard /var/lib/boxion 2>/dev/null; then
    echo "❌ Erreur création répertoires système"
    echo "💡 Vérifiez les permissions root"
    exit 1
fi
chmod 700 /etc/wireguard
chmod 755 /var/lib/boxion  # Permissions pour PHP

# ====== Validation IPv6 PREFIX ======
if [[ ! "$IPV6_PREFIX" =~ ^[0-9a-fA-F:]+$ ]] || [[ ${#IPV6_PREFIX} -lt 3 ]]; then
    echo "❌ Erreur: Préfixe IPv6 invalide: $IPV6_PREFIX" >&2
    echo "💡 Format attendu: 2a0c:xxxx:xxxx:abcd" >&2
    exit 1
fi

# ====== Validation PORT disponible ======
echo "🔍 Vérification port UDP/$PORT..."
if ss -ulpn | grep -q ":$PORT " 2>/dev/null; then
    echo "❌ Erreur: Port UDP/$PORT déjà utilisé" >&2
    echo "💡 Ports UDP utilisés:" >&2
    ss -ulpn | grep -E ':[0-9]+' | awk '{print "   " $5}' | sort -u >&2
    exit 1
fi

# ====== Test IPv6 forwarding (critique pour Debian 12) ======
echo "🌐 Vérification IPv6 forwarding..."
IPV6_FORWARD=$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null || echo "0")
if [[ "$IPV6_FORWARD" != "1" ]]; then
    echo "⚠️  IPv6 forwarding désactivé, activation..."
    echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf
    sysctl -p /etc/sysctl.conf >/dev/null 2>&1
fi

if [[ ! -f /etc/wireguard/${WG_IF}.conf ]]; then
    echo "🔐 Génération clés WireGuard serveur..."
    umask 077
    
    # Génération sécurisée des clés
    if ! wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key; then
        echo "❌ Erreur: Génération clés WireGuard échouée" >&2
        exit 1
    fi
    
    # Validation clés générées
    if [[ ! -f /etc/wireguard/server_private.key ]] || [[ ! -f /etc/wireguard/server_public.key ]]; then
        echo "❌ Erreur: Clés WireGuard non générées" >&2
        exit 1
    fi
    
    # Sécurisation permissions
    chmod 600 /etc/wireguard/server_private.key /etc/wireguard/server_public.key
    
    SV_PRIV=$(cat /etc/wireguard/server_private.key)
    
    # Validation clé privée format
    if [[ ! "$SV_PRIV" =~ ^[A-Za-z0-9+/]{42}[A-Za-z0-9+/=]{2}$ ]]; then
        echo "❌ Erreur: Clé privée WireGuard invalide" >&2
        exit 1
    fi
    
    echo "📝 Génération configuration WireGuard optimisée Debian 12..."
    cat >/etc/wireguard/${WG_IF}.conf <<EOF
# 🔐 BOXION WIREGUARD SERVER CONFIG - DEBIAN 12 OPTIMIZED
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# Interface: ${WG_IF} | Port: ${PORT} | Prefix: ${IPV6_PREFIX}::/64

[Interface]
# Clé privée serveur (gardée secrète)
PrivateKey = ${SV_PRIV}

# Adresse IPv6 serveur (::1 = gateway)
Address = ${IPV6_PREFIX}::1/64

# Port d'écoute UDP
ListenPort = ${PORT}

# SÉCURITÉ: SaveConfig désactivé (gestion via API)
SaveConfig = false

# PostUp: Règles IPv6 forwarding et NDP proxy (Debian 12)
PostUp = sysctl -w net.ipv6.conf.all.forwarding=1
PostUp = sysctl -w net.ipv6.conf.${WAN_IF}.proxy_ndp=1
PostUp = ip6tables -A FORWARD -i %i -j ACCEPT || true
PostUp = ip6tables -A FORWARD -o %i -j ACCEPT || true

# PreDown: Nettoyage règles
PreDown = ip6tables -D FORWARD -i %i -j ACCEPT || true
PreDown = ip6tables -D FORWARD -o %i -j ACCEPT || true

# Les peers seront ajoutés dynamiquement via l'API
EOF

    # Validation fichier généré
    if [[ ! -f /etc/wireguard/${WG_IF}.conf ]]; then
        echo "❌ Erreur: Configuration WireGuard non créée" >&2
        exit 1
    fi
    
    # Sécurisation permissions config
    chmod 600 /etc/wireguard/${WG_IF}.conf
    
    echo "🚀 Démarrage WireGuard..."
    
    # Activation service (avec gestion d'erreur)
    if ! systemctl enable wg-quick@${WG_IF}; then
        echo "❌ Erreur: Activation service WireGuard échouée" >&2
        exit 1
    fi
    
    # Démarrage service (avec gestion d'erreur)
    if ! systemctl start wg-quick@${WG_IF}; then
        echo "❌ Erreur: Démarrage WireGuard échoué" >&2
        echo "💡 Logs:" >&2
        journalctl -u wg-quick@${WG_IF} --no-pager -n 10 >&2 || true
        exit 1
    fi
    
    # Vérification interface active
    sleep 2
    if ! ip link show ${WG_IF} >/dev/null 2>&1; then
        echo "❌ Erreur: Interface WireGuard ${WG_IF} non créée" >&2
        systemctl status wg-quick@${WG_IF} --no-pager >&2 || true
        exit 1
    fi
    
    # Vérification interface WireGuard (UP,LOWER_UP est normal, pas state UP)
    if ! ip link show ${WG_IF} | grep -q "UP,LOWER_UP"; then
        echo "❌ Erreur: Interface WireGuard ${WG_IF} inactive" >&2
        ip link show ${WG_IF} >&2 || true
        exit 1
    fi
    
    echo "✅ WireGuard ${WG_IF} configuré et actif"
fi
SV_PUB=$(cat /etc/wireguard/server_public.key)

# ====== code app ======
APP=/var/www/boxion-api
mkdir -p ${APP}/{api,bin,sql,nginx,systemd,sudoers}
chown -R www-data:www-data ${APP}

# -------- bin: wrappers sudo --------
cat >${APP}/bin/wg_add_peer.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
WG_IF="${WG_IF:-wg0}"
WAN_IF="${WAN_IF:-eth0}"
PUB="$1"; IP6="$2"
wg set "$WG_IF" peer "$PUB" allowed-ips "${IP6}/128"
ip -6 neigh add proxy "$IP6" dev "$WAN_IF" 2>/dev/null || true
EOF
chmod +x ${APP}/bin/wg_add_peer.sh

cat >${APP}/bin/wg_del_peer.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
WG_IF="${WG_IF:-wg0}"
WAN_IF="${WAN_IF:-eth0}"
PUB="$1"; IP6="$2"
wg set "$WG_IF" peer "$PUB" remove 2>/dev/null || true
ip -6 neigh del proxy "$IP6" dev "$WAN_IF" 2>/dev/null || true
EOF
chmod +x ${APP}/bin/wg_del_peer.sh

cat >${APP}/bin/replay_ndp.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
WG_IF="${WG_IF:-wg0}"
WAN_IF="${WAN_IF:-eth0}"
DB="/var/lib/boxion/boxion.db"
[ -f "$DB" ] || exit 0
while IFS='|' read -r pub ip6; do
  [ -n "$pub" ] || continue
  wg set "$WG_IF" peer "$pub" allowed-ips "${ip6}/128" 2>/dev/null || true
  ip -6 neigh add proxy "$ip6" dev "$WAN_IF" 2>/dev/null || true
done < <(sqlite3 "$DB" "select pubkey||'|'||ip6 from peers;")
EOF
chmod +x ${APP}/bin/replay_ndp.sh

# -------- DB init --------
cat >${APP}/sql/init.sql <<'EOF'
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS peers (
  name TEXT PRIMARY KEY,
  pubkey TEXT UNIQUE NOT NULL,
  ip6 TEXT UNIQUE NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS meta (
  k TEXT PRIMARY KEY,
  v TEXT NOT NULL
);
INSERT OR IGNORE INTO meta(k,v) VALUES('last_id','1');
EOF
sqlite3 /var/lib/boxion/boxion.db < ${APP}/sql/init.sql >/dev/null
chown www-data:www-data /var/lib/boxion/boxion.db

# -------- .env --------
cat >${APP}/.env <<EOF
WG_IF=${WG_IF}
WAN_IF=${WAN_IF}
ENDPOINT_DOMAIN=${DOMAIN}
ENDPOINT_PORT=${PORT}
SERVER_PUBLIC_KEY=${SV_PUB}
IPV6_PREFIX=${IPV6_PREFIX}
POOL_BITS=${POOL_BITS}
API_TOKEN=${API_TOKEN}
DNS_V6=${DNS_V6}
DB_PATH=/var/lib/boxion/boxion.db
APP_BIN=${APP}/bin
EOF
chown www-data:www-data ${APP}/.env
chmod 640 ${APP}/.env

# -------- PHP API --------
cat >${APP}/api/index.php <<'EOF'
<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET,POST,DELETE,OPTIONS');
if ($_SERVER['REQUEST_METHOD']==='OPTIONS'){exit;}

function envv($k,$d=''){ static $E=null; if($E===null){ $E=parse_ini_file(__DIR__.'/../.env'); } return $E[$k]??$d; }
function abort($code,$msg){ http_response_code($code); echo json_encode(['error'=>$msg]); exit; }
function auth(){
  $h = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
  if (!preg_match('/Bearer\s+(.+)/i', $h, $m)) abort(401,'no token');
  if (trim($m[1]) !== envv('API_TOKEN')) abort(401,'bad token');
}
function db(){ static $pdo=null; if($pdo===null){ $pdo=new PDO('sqlite:'.envv('DB_PATH')); $pdo->setAttribute(PDO::ATTR_ERRMODE,PDO::ERRMODE_EXCEPTION);} return $pdo; }
function next_ip6(){
  $prefix = envv('IPV6_PREFIX'); $bits=(int)envv('POOL_BITS');
  $db=db(); $last=(int)$db->query("SELECT v FROM meta WHERE k='last_id'")->fetchColumn();
  $max=(1<<$bits)-1; if($last>$max) abort(409,'pool_exhausted');
  $db->beginTransaction();
  $id=(int)$db->query("SELECT v FROM meta WHERE k='last_id'")->fetchColumn();
  $db->exec("UPDATE meta SET v='".($id+1)."' WHERE k='last_id'");
  $db->commit();
  // compose ip6: prefix::<id> (simple /112 allocation)
  $hex=strtoupper(str_pad(dechex($id),4,'0',STR_PAD_LEFT));
  return $prefix.'::'.$hex;
}
function valid_name($s){ return preg_match('/^[a-zA-Z0-9._-]{1,32}$/',$s); }
function valid_pub($s){ return preg_match('#^[A-Za-z0-9+/=]{40,60}$#',$s); }

auth();
$method=$_SERVER['REQUEST_METHOD'];
$path=parse_url($_SERVER['REQUEST_URI'],PHP_URL_PATH);

if ($method==='POST' && preg_match('#^/api/peers$#',$path)){
  $in=json_decode(file_get_contents('php://input'),true);
  $name=$in['name']??''; $pub=$in['pubkey']??'';
  if(!valid_name($name)) abort(400,'bad name');
  if(!valid_pub($pub)) abort(400,'bad pubkey');

  $db=db();
  // idempotent: si existe déjà -> renvoyer la conf
  $st=$db->prepare('SELECT ip6 FROM peers WHERE name=?'); $st->execute([$name]);
  $row=$st->fetch(PDO::FETCH_ASSOC);
  if(!$row){
    $ip6 = next_ip6();
    $st=$db->prepare('INSERT INTO peers(name,pubkey,ip6,created_at) VALUES(?,?,?,?)');
    $st->execute([$name,$pub,$ip6,time()]);
    // add peer + NDP via wrappers
    putenv('WG_IF='.envv('WG_IF'));
    putenv('WAN_IF='.envv('WAN_IF'));
    $cmd = escapeshellcmd(envv('APP_BIN').'/wg_add_peer.sh').' '.escapeshellarg($pub).' '.escapeshellarg($ip6).' 2>&1';
    exec($cmd,$out,$rc); if($rc!==0){ abort(500,implode("\n",$out)); }
    $row=['ip6'=>$ip6];
  }
  $wgconf = "[Interface]\nAddress = ".$row['ip6']."/128\nDNS = ".envv('DNS_V6')."\n\n".
            "[Peer]\nPublicKey = ".envv('SERVER_PUBLIC_KEY')."\n".
            "Endpoint = ".envv('ENDPOINT_DOMAIN').":".envv('ENDPOINT_PORT')."\n".
            "AllowedIPs = ::/0\nPersistentKeepalive = 25\n";
  echo json_encode(['wg_conf'=>$wgconf,'ip6'=>$row['ip6']]); exit;
}

if ($method==='GET' && preg_match('#^/api/peers/([a-zA-Z0-9._-]+)$#',$path,$m)){
  $name=$m[1]; $st=db()->prepare('SELECT ip6,pubkey FROM peers WHERE name=?'); $st->execute([$name]);
  $row=$st->fetch(PDO::FETCH_ASSOC); if(!$row) abort(404,'not found');
  $wgconf = "[Interface]\nAddress = ".$row['ip6']."/128\nDNS = ".envv('DNS_V6')."\n\n".
            "[Peer]\nPublicKey = ".envv('SERVER_PUBLIC_KEY')."\n".
            "Endpoint = ".envv('ENDPOINT_DOMAIN').":".envv('ENDPOINT_PORT')."\n".
            "AllowedIPs = ::/0\nPersistentKeepalive = 25\n";
  echo json_encode(['wg_conf'=>$wgconf,'ip6'=>$row['ip6']]); exit;
}

if ($method==='DELETE' && preg_match('#^/api/peers/([a-zA-Z0-9._-]+)$#',$path,$m)){
  $name=$m[1]; $db=db();
  $st=$db->prepare('SELECT ip6,pubkey FROM peers WHERE name=?'); $st->execute([$name]);
  $row=$st->fetch(PDO::FETCH_ASSOC); if(!$row) abort(404,'not found');
  putenv('WG_IF='.envv('WG_IF')); putenv('WAN_IF='.envv('WAN_IF'));
  $cmd = escapeshellcmd(envv('APP_BIN').'/wg_del_peer.sh').' '.escapeshellarg($row['pubkey']).' '.escapeshellarg($row['ip6']).' 2>&1';
  exec($cmd,$out,$rc); if($rc!==0){ abort(500,implode("\n",$out)); }
  $db->prepare('DELETE FROM peers WHERE name=?')->execute([$name]);
  echo json_encode(['ok'=>true]); exit;
}

abort(404,'no route');
EOF
chown -R www-data:www-data ${APP}/api

# -------- Dashboard Web --------
echo "🌐 Installation du dashboard web..."
# Création des répertoires web critiques
if ! mkdir -p ${APP}/web/admin 2>/dev/null; then
    echo "❌ Erreur création répertoire web admin"
    echo "💡 Vérifiez les permissions: ${APP}/web/"
    exit 1
fi
echo "✅ Répertoires web créés: ${APP}/web/admin"

# Page d'accueil publique
cat >${APP}/web/index.php <<'WEBEOF'
<?php
/**
 * Tunnel VPN Dashboard - Page d'accueil publique
 */
ini_set('display_errors', 0);
error_reporting(0);
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header('X-XSS-Protection: 1; mode=block');
header('Referrer-Policy: strict-origin-when-cross-origin');
?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Tunnel VPN System</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6; color: #333; background: #f8f9fa;
        }
        .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
        .header { 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white; padding: 40px 0; text-align: center; margin-bottom: 40px;
        }
        .header h1 { font-size: 3em; margin-bottom: 10px; }
        .card { 
            background: white; border-radius: 10px; padding: 30px; 
            margin-bottom: 30px; box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .features { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
        .feature { padding: 20px; border-left: 4px solid #667eea; }
        .feature h3 { color: #667eea; margin-bottom: 10px; }
        .code-block { 
            background: #2d3748; color: #e2e8f0; padding: 20px; 
            border-radius: 8px; overflow-x: auto; font-family: 'Courier New', monospace;
        }
        .btn { 
            display: inline-block; padding: 12px 24px; background: #667eea; 
            color: white; text-decoration: none; border-radius: 6px; 
            margin: 10px 10px 10px 0; transition: all 0.3s;
        }
        .btn:hover { background: #5a67d8; }
        .admin-link { 
            position: fixed; top: 20px; right: 20px; 
            background: rgba(0,0,0,0.8); color: white; padding: 10px 20px; 
            border-radius: 6px; text-decoration: none;
        }
        .status { 
            display: inline-block; padding: 4px 12px; border-radius: 20px; 
            font-size: 0.9em; font-weight: bold;
        }
        .status.online { background: #48bb78; color: white; }
        .footer { text-align: center; padding: 40px 0; color: #666; }
    </style>
</head>
<body>
    <a href="admin/" class="admin-link">🔐 Dashboard Admin</a>
    
    <div class="header">
        <div class="container">
            <h1>🛡️ Tunnel VPN</h1>
            <p>Serveur tunnel WireGuard pour vos Boxions</p>
            <span class="status online">🟢 Système actif</span>
        </div>
    </div>

    <div class="container">
        <div class="card">
            <h2>🚀 Qu'est-ce que Boxion ?</h2>
            <p>Boxion est un système VPN WireGuard complet avec gestion automatique des peers via API.</p>
        </div>

        <div class="features">
            <div class="feature">
                <h3>🔐 Sécurisé</h3>
                <p>Les clés privées sont générées côté client. Authentication par token Bearer.</p>
            </div>
            <div class="feature">
                <h3>🌐 IPv6 Native</h3>
                <p>Attribution automatique d'adresses IPv6 avec support NDP proxy.</p>
            </div>
            <div class="feature">
                <h3>🔄 Auto-Setup</h3>
                <p>Installation complète en une commande.</p>
            </div>
            <div class="feature">
                <h3>📡 API REST</h3>
                <p>API complète pour la gestion des peers.</p>
            </div>
        </div>

        <div class="card">
            <h2>⚡ Installation</h2>
            <p><strong>Serveur VPS :</strong></p>
            <div class="code-block">curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/bootstrap.sh | sudo bash</div>
            
            <p><strong>Client Boxion :</strong></p>
            <div class="code-block">TOKEN='VOTRE_TOKEN' bash -c "\$(curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/bootstrap_client.sh)"</div>
        </div>

        <div class="card">
            <h2>📚 Documentation</h2>
            <a href="https://github.com/J0bot/boxion-setup" class="btn">📖 GitHub</a>
            <a href="api/" class="btn">🔌 API</a>
        </div>
    </div>

    <div class="footer">
        <div class="container">
            <p>🛡️ Tunnel VPN System - Sécurisé, Rapide, Open Source</p>
        </div>
    </div>
</body>
</html>
WEBEOF

# Système d'authentification sécurisé
cat >${APP}/web/admin/auth.php <<'AUTHEOF'
<?php
ini_set('display_errors', 0);
error_reporting(0);
session_set_cookie_params([
    'lifetime' => 3600, 'path' => '/admin/', 'domain' => '',
    'secure' => isset($_SERVER['HTTPS']), 'httponly' => true, 'samesite' => 'Strict'
]);
if (session_status() === PHP_SESSION_NONE) { session_start(); }
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header('X-XSS-Protection: 1; mode=block');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

class BoxionAuth {
    private const CREDENTIALS_FILE = '/var/lib/boxion/admin_credentials.json';
    private const SESSION_TIMEOUT = 3600;
    
    public static function generatePassword($length = 16) {
        $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*';
        return substr(str_shuffle(str_repeat($chars, ceil($length / strlen($chars)))), 0, $length);
    }
    
    public static function createCredentials($username = null, $password = null) {
        $username = $username ?: 'admin';
        $password = $password ?: self::generatePassword();
        $credentials = [
            'username' => $username, 'password_hash' => password_hash($password, PASSWORD_ARGON2ID),
            'created_at' => time(), 'last_login' => null
        ];
        $dir = dirname(self::CREDENTIALS_FILE);
        if (!is_dir($dir)) { mkdir($dir, 0750, true); }
        file_put_contents(self::CREDENTIALS_FILE, json_encode($credentials, JSON_PRETTY_PRINT));
        chmod(self::CREDENTIALS_FILE, 0600);
        return ['username' => $username, 'password' => $password];
    }
    
    public static function verifyCredentials($username, $password) {
        if (!file_exists(self::CREDENTIALS_FILE)) { return false; }
        $credentials = json_decode(file_get_contents(self::CREDENTIALS_FILE), true);
        if (!$credentials || $credentials['username'] !== $username) { return false; }
        if (!password_verify($password, $credentials['password_hash'])) { return false; }
        $credentials['last_login'] = time();
        file_put_contents(self::CREDENTIALS_FILE, json_encode($credentials, JSON_PRETTY_PRINT));
        return true;
    }
    
    public static function login($username, $password) {
        if (!self::verifyCredentials($username, $password)) { return false; }
        session_regenerate_id(true);
        $_SESSION['authenticated'] = true; $_SESSION['username'] = $username;
        $_SESSION['login_time'] = time(); $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
        return true;
    }
    
    public static function isAuthenticated() {
        if (!isset($_SESSION['authenticated']) || !$_SESSION['authenticated']) { return false; }
        if (!isset($_SESSION['login_time'])) { return false; }
        if ((time() - $_SESSION['login_time']) > self::SESSION_TIMEOUT) {
            self::logout(); return false;
        }
        return true;
    }
    
    public static function logout() {
        $_SESSION = [];
        if (ini_get("session.use_cookies")) {
            $params = session_get_cookie_params();
            setcookie(session_name(), '', time() - 42000, $params["path"], $params["domain"], $params["secure"], $params["httponly"]);
        }
        session_destroy();
    }
    
    public static function getCsrfToken() { return $_SESSION['csrf_token'] ?? ''; }
    public static function verifyCsrfToken($token) { return isset($_SESSION['csrf_token']) && hash_equals($_SESSION['csrf_token'], $token); }
    public static function requireAuth() { if (!self::isAuthenticated()) { header('Location: login.php'); exit; } }
    
    public static function getCredentialsInfo() {
        if (!file_exists(self::CREDENTIALS_FILE)) { return null; }
        $credentials = json_decode(file_get_contents(self::CREDENTIALS_FILE), true);
        if (!$credentials) { return null; }
        return ['username' => $credentials['username'], 'created_at' => $credentials['created_at'], 'last_login' => $credentials['last_login']];
    }
}

function h($str) { return htmlspecialchars($str, ENT_QUOTES | ENT_HTML5, 'UTF-8'); }
function isPost() { return $_SERVER['REQUEST_METHOD'] === 'POST'; }
function getPost($key, $default = '') { return isset($_POST[$key]) ? trim($_POST[$key]) : $default; }
?>
AUTHEOF

# Page de login (version compacte)
cat >${APP}/web/admin/login.php <<'LOGINEOF'
<?php
require_once 'auth.php';
$error = ''; if (BoxionAuth::isAuthenticated()) { header('Location: index.php'); exit; }
if (isPost()) {
    $username = getPost('username'); $password = getPost('password');
    if (empty($username) || empty($password)) { $error = 'Champs requis'; }
    else if (BoxionAuth::login($username, $password)) { header('Location: index.php'); exit; }
    else { $error = 'Identifiants incorrects'; }
}
$credentialsExist = file_exists('/var/lib/boxion/admin_credentials.json');
?>
<!DOCTYPE html><html lang="fr"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"><title>Tunnel Dashboard</title><style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);min-height:100vh;display:flex;align-items:center;justify-content:center}.login-container{background:white;border-radius:12px;padding:40px;box-shadow:0 10px 30px rgba(0,0,0,0.2);width:100%;max-width:400px}.logo{text-align:center;margin-bottom:30px}.logo h1{color:#667eea;font-size:2.2em;margin-bottom:5px}.form-group{margin-bottom:20px}.form-group label{display:block;margin-bottom:5px;color:#333;font-weight:500}.form-group input{width:100%;padding:12px;border:2px solid #e1e5e9;border-radius:6px;font-size:16px}.form-group input:focus{outline:none;border-color:#667eea}.btn{width:100%;padding:12px;background:#667eea;color:white;border:none;border-radius:6px;font-size:16px;cursor:pointer}.btn:hover{background:#5a67d8}.error{background:#fed7d7;color:#c53030;padding:12px;border-radius:6px;margin-bottom:20px}.warning{background:#fef5e7;color:#d69e2e;padding:12px;border-radius:6px;margin-bottom:20px}.back-link{text-align:center;margin-top:20px}.back-link a{color:#667eea;text-decoration:none;font-size:0.9em}</style></head><body><div class="login-container"><div class="logo"><h1>🛡️ Tunnel</h1><p>Dashboard Administration</p></div><?php if (!$credentialsExist): ?><div class="warning"><strong>⚠️ Configuration manquante</strong><br>Relancez l'installation du serveur.</div><?php endif; ?><?php if ($error): ?><div class="error"><strong>❌ Erreur:</strong> <?= h($error) ?></div><?php endif; ?><?php if ($credentialsExist): ?><form method="POST"><div class="form-group"><label for="username">Nom d'utilisateur</label><input type="text" id="username" name="username" required value="<?= h(getPost('username')) ?>"></div><div class="form-group"><label for="password">Mot de passe</label><input type="password" id="password" name="password" required></div><button type="submit" class="btn">🔓 Se connecter</button></form><?php endif; ?><div class="back-link"><a href="../">← Retour à l'accueil</a></div></div></body></html>
LOGINEOF

# Dashboard principal (version compacte intégrée directement)
cat >${APP}/web/admin/index.php <<'DASHEOF'
<?php
require_once 'auth.php';
BoxionAuth::requireAuth();

// Configuration
$envFile = '/var/www/boxion-api/.env';
$config = [];
if (file_exists($envFile)) {
    $lines = file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        if (strpos($line, '=') !== false && $line[0] !== '#') {
            list($key, $value) = explode('=', $line, 2);
            $config[trim($key)] = trim($value, '"');
        }
    }
}

// Stats WireGuard
function getWireGuardStats() {
    $stats = ['interface' => null, 'peers' => [], 'status' => 'unknown'];
    exec('systemctl is-active wg-quick@wg0 2>/dev/null', $output, $return);
    $stats['status'] = ($return === 0 && isset($output[0]) && $output[0] === 'active') ? 'active' : 'inactive';
    if ($stats['status'] !== 'active') return $stats;
    
    exec('wg show wg0 2>/dev/null', $wgOutput);
    if (empty($wgOutput)) return $stats;
    
    $currentPeer = null;
    foreach ($wgOutput as $line) {
        $line = trim($line);
        if (strpos($line, 'listening port:') === 0) {
            $stats['interface']['port'] = (int)substr($line, 16);
        } elseif (strpos($line, 'peer:') === 0) {
            $currentPeer = ['public_key' => substr($line, 6), 'endpoint' => null, 'allowed_ips' => [], 'latest_handshake' => null, 'connected' => false];
            $stats['peers'][] = &$currentPeer;
        } elseif ($currentPeer && strpos($line, 'endpoint:') === 0) {
            $currentPeer['endpoint'] = substr($line, 10);
        } elseif ($currentPeer && strpos($line, 'allowed ips:') === 0) {
            $ips = substr($line, 13);
            $currentPeer['allowed_ips'] = array_map('trim', explode(',', $ips));
        } elseif ($currentPeer && strpos($line, 'latest handshake:') === 0) {
            $handshake = substr($line, 18);
            $currentPeer['latest_handshake'] = $handshake;
            $currentPeer['connected'] = !in_array($handshake, ['(none)', '']) && strtotime($handshake) > (time() - 300);
        }
    }
    return $stats;
}

// Peers BDD
function getDatabasePeers() {
    $dbPath = '/var/lib/boxion/boxion.db';
    if (!file_exists($dbPath)) return [];
    try {
        $pdo = new PDO("sqlite:$dbPath");
        $stmt = $pdo->query("SELECT name, pubkey, ipv6, created_at FROM peers ORDER BY created_at DESC");
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    } catch (Exception $e) { return []; }
}

// Actions POST
if (isPost()) {
    $action = getPost('action'); $csrf = getPost('csrf_token');
    if (!BoxionAuth::verifyCsrfToken($csrf)) { $error = 'Token CSRF invalide'; }
    else {
        switch ($action) {
            case 'restart_wireguard':
                exec('sudo systemctl restart wg-quick@wg0 2>&1', $output, $return);
                $message = ($return === 0) ? 'WireGuard redémarré' : 'Erreur redémarrage';
                break;
        }
    }
}

$wgStats = getWireGuardStats();
$dbPeers = getDatabasePeers();
$totalPeers = count($dbPeers);
$activePeers = 0;
foreach ($wgStats['peers'] as $peer) {
    if ($peer['connected'] ?? false) $activePeers++;
}
?>
<!DOCTYPE html><html lang="fr"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"><title>Tunnel Dashboard</title><style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#f8f9fa;color:#333}.header{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:white;padding:20px 0}.container{max-width:1200px;margin:0 auto;padding:0 20px}.header-content{display:flex;justify-content:space-between;align-items:center}.main{padding:30px 0}.stats-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:20px;margin-bottom:30px}.stat-card{background:white;padding:20px;border-radius:10px;box-shadow:0 2px 4px rgba(0,0,0,0.1);text-align:center}.stat-value{font-size:2.5em;font-weight:bold;margin-bottom:5px}.stat-value.green{color:#48bb78}.stat-value.blue{color:#4299e1}.stat-value.orange{color:#ed8936}.stat-label{color:#666;font-size:0.9em}.card{background:white;border-radius:10px;padding:25px;box-shadow:0 2px 4px rgba(0,0,0,0.1);margin-bottom:20px}.table{width:100%;border-collapse:collapse;font-size:0.9em}.table th,.table td{padding:12px;text-align:left;border-bottom:1px solid #e2e8f0}.table th{background:#f7fafc;font-weight:600}.status{display:inline-block;padding:4px 12px;border-radius:20px;font-size:0.8em;font-weight:bold}.status.online{background:#c6f6d5;color:#22543d}.status.offline{background:#fed7d7;color:#742a2a}.btn{display:inline-block;padding:8px 16px;background:#667eea;color:white;text-decoration:none;border-radius:6px;font-size:0.9em;border:none;cursor:pointer;margin-right:10px}.btn:hover{background:#5a67d8}.pubkey{font-family:monospace;font-size:0.8em;word-break:break-all}.logout-form{display:inline}</style><script>setTimeout(()=>location.reload(),30000);</script></head><body><div class="header"><div class="container"><div class="header-content"><h1>🛡️ Tunnel Dashboard</h1><div>Connecté: <?=h($_SESSION['username'])?> | <a href="../" style="color:white;opacity:0.8">🏠 Accueil</a> | <form method="POST" action="logout.php" class="logout-form"><button type="submit" style="background:none;border:none;color:white;opacity:0.8;cursor:pointer">🚪 Déconnexion</button></form></div></div></div></div><div class="main"><div class="container"><?php if(isset($message)):?><div style="padding:12px;border-radius:6px;margin-bottom:20px;border-left:4px solid #48bb78;background:#f0fff4;color:#22543d"><?=h($message)?></div><?php endif;?><div class="stats-grid"><div class="stat-card"><div class="stat-value green"><?=$activePeers?></div><div class="stat-label">Connexions actives</div></div><div class="stat-card"><div class="stat-value blue"><?=$totalPeers?></div><div class="stat-label">Peers enregistrés</div></div><div class="stat-card"><div class="stat-value <?=$wgStats['status']==='active'?'green':'orange'?>"><?=$wgStats['status']==='active'?'ACTIF':'INACTIF'?></div><div class="stat-label">Statut WireGuard</div></div><div class="stat-card"><div class="stat-value blue"><?=$wgStats['interface']['port']??51820?></div><div class="stat-label">Port d'écoute</div></div></div><div class="card"><h2>⚡ Actions rapides</h2><form method="POST" style="display:inline"><input type="hidden" name="csrf_token" value="<?=BoxionAuth::getCsrfToken()?>"><button type="submit" name="action" value="restart_wireguard" class="btn">🔄 Redémarrer WireGuard</button></form><a href="../api/" class="btn">🔌 API</a></div><div class="card"><h2>🌐 Connexions actives</h2><?php if(empty($wgStats['peers'])):?><p style="color:#666;font-style:italic">Aucune connexion active</p><?php else:?><table class="table"><thead><tr><th>Clé publique</th><th>Endpoint</th><th>IPs autorisées</th><th>Dernière connexion</th><th>Statut</th></tr></thead><tbody><?php foreach($wgStats['peers'] as $peer):?><tr><td class="pubkey"><?=h(substr($peer['public_key'],0,20))?>...</td><td><?=h($peer['endpoint']??'N/A')?></td><td><?=h(implode(', ',$peer['allowed_ips']))?></td><td><?=h($peer['latest_handshake']??'Jamais')?></td><td><span class="status <?=($peer['connected']??false)?'online':'offline'?>"><?=($peer['connected']??false)?'En ligne':'Hors ligne'?></span></td></tr><?php endforeach;?></tbody></table><?php endif;?></div><div class="card"><h2>📋 Peers enregistrés</h2><?php if(empty($dbPeers)):?><p style="color:#666;font-style:italic">Aucun peer enregistré</p><?php else:?><table class="table"><thead><tr><th>Nom</th><th>Clé publique</th><th>IPv6</th><th>Date d'enregistrement</th></tr></thead><tbody><?php foreach($dbPeers as $peer):?><tr><td><strong><?=h($peer['name'])?></strong></td><td class="pubkey"><?=h(substr($peer['pubkey'],0,20))?>...</td><td><?=h($peer['ipv6'])?></td><td><?=date('d/m/Y H:i',strtotime($peer['created_at']))?></td></tr><?php endforeach;?></tbody></table><?php endif;?></div></div></div></body></html>
DASHEOF

# Page de déconnexion
cat >${APP}/web/admin/logout.php <<'LOGOUTEOF'
<?php
require_once 'auth.php';
BoxionAuth::logout();
header('Location: login.php'); exit;
?>
LOGOUTEOF

chown -R www-data:www-data ${APP}/web

# -------- sudoers (wrappers uniquement) --------
cat >${APP}/sudoers/boxion-api <<EOF
www-data ALL=(root) NOPASSWD: ${APP}/bin/wg_add_peer.sh, ${APP}/bin/wg_del_peer.sh, ${APP}/bin/replay_ndp.sh
EOF
install -m440 ${APP}/sudoers/boxion-api /etc/sudoers.d/boxion-api

# -------- systemd replay au boot --------
cat >${APP}/systemd/boxion-replay-ndp.service <<EOF
[Unit]
Description=Rejoue peers WireGuard et NDP au boot
After=network-online.target wg-quick@${WG_IF}.service
Wants=network-online.target

[Service]
Type=oneshot
Environment=WG_IF=${WG_IF}
Environment=WAN_IF=${WAN_IF}
ExecStart=${APP}/bin/replay_ndp.sh

[Install]
WantedBy=multi-user.target
EOF
install -m644 ${APP}/systemd/boxion-replay-ndp.service /etc/systemd/system/
systemctl enable boxion-replay-ndp.service

# -------- Nginx vhost --------
cat >${APP}/nginx/boxion-api.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    root ${APP}/web;
    index index.php index.html;

    # Dashboard web public
    location / {
        try_files \$uri \$uri/ /index.php\$is_args\$args;
    }
    
    # Dashboard admin sécurisé
    location /admin/ {
        try_files \$uri \$uri/ /admin/index.php\$is_args\$args;
    }
    
    # API REST
    location /api/ {
        root ${APP};
        include snippets/fastcgi-php.conf;
        fastcgi_param SCRIPT_FILENAME \$document_root/api/index.php;
        fastcgi_pass unix:/run/php/php-fpm.sock;
    }
    
    # Traitement PHP pour le dashboard
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_pass unix:/run/php/php-fpm.sock;
    }
    
    # Sécurité
    location ~ /\.ht { deny all; }
    location ~ /admin_credentials\.json { deny all; }
}
EOF
install -m644 ${APP}/nginx/boxion-api.conf /etc/nginx/sites-available/boxion-api.conf
ln -sf /etc/nginx/sites-available/boxion-api.conf /etc/nginx/sites-enabled/boxion-api.conf
rm -f /etc/nginx/sites-enabled/default

# Test configuration nginx avant reload (critique)
echo "🔍 Test configuration nginx..."
if ! nginx -t 2>/dev/null; then
    echo "❌ Configuration nginx invalide, diagnostic:"
    nginx -t
    echo "💡 Vérifiez les permissions et la syntaxe"
    exit 1
fi

# Reload sécurisé avec fallback
echo "🔄 Rechargement nginx..."
if ! systemctl reload nginx 2>/dev/null; then
    echo "⚠️  Reload nginx échoué, tentative restart..."
    if ! systemctl restart nginx; then
        echo "❌ Nginx service failed - voir logs:"
        journalctl -xeu nginx.service --no-pager -l | tail -20
        echo "💡 Diagnostic manuel: systemctl status nginx.service"
        exit 1
    fi
fi

systemctl restart php*-fpm.service || true

# -------- Génération credentials admin --------
echo "🔐 Génération des identifiants admin..."

# Variables sécurisées depuis bootstrap.sh
ADMIN_USER="${ADMIN_USERNAME:-admin}"
ADMIN_PASS="${ADMIN_PASSWORD}"
COMPANY="${COMPANY_NAME:-Gasser IT Services}"
LEGAL_PAGES="${INCLUDE_LEGAL:-false}"

# Génération sécurisée des credentials avec gestion d'erreur
# Création script PHP temporaire sécurisé
cat > /tmp/boxion_gen_creds.php << 'PHPEOF'
<?php
require_once getenv('BOXION_APP') . '/web/admin/auth.php';
$username = getenv('BOXION_ADMIN_USER') ?: 'admin';
$password = getenv('BOXION_ADMIN_PASS') ?: null;
try {
    $creds = BoxionAuth::createCredentials($username, $password);
    echo 'Admin créé: ' . $creds['username'] . ' / ' . $creds['password'] . "\n";
    file_put_contents('/tmp/boxion_admin_creds.txt', 'Username: ' . $creds['username'] . "\nPassword: " . $creds['password'] . "\n");
} catch (Exception $e) {
    error_log('Boxion credentials error: ' . $e->getMessage());
    exit(1);
}
?>
PHPEOF

# Test PHP basique d'abord
echo "🔍 Test PHP basique..."
if ! php -r "echo 'PHP OK';" 2>/dev/null; then
    echo "❌ PHP non fonctionnel sur ce système"
    php -v
    exit 1
fi

# Test accès répertoire
echo "🔍 Test accès /var/lib/boxion..."
if [[ ! -d /var/lib/boxion ]]; then
    echo "❌ Répertoire /var/lib/boxion inexistant"
    exit 1
fi
if [[ ! -w /var/lib/boxion ]]; then
    echo "❌ Répertoire /var/lib/boxion non writable"
    ls -la /var/lib/ | grep boxion
    exit 1
fi

# Exécution sécurisée avec variables d'environnement
export BOXION_APP="${APP}"
export BOXION_ADMIN_USER="${ADMIN_USER}"
export BOXION_ADMIN_PASS="${ADMIN_PASS}"
echo "🔍 Test génération credentials..."
if ! php /tmp/boxion_gen_creds.php 2>/tmp/boxion_php_error.log; then
    echo "❌ Erreur génération credentials admin"
    echo "💡 Logs PHP: /tmp/boxion_php_error.log"
    echo "💡 Vérifiez: ${APP}/web/admin/auth.php"
    if [[ -f /tmp/boxion_php_error.log && -s /tmp/boxion_php_error.log ]]; then
        echo "🐛 Erreur PHP détectée:"
        head -3 /tmp/boxion_php_error.log
    fi
    exit 1
fi

# Nettoyage fichiers temporaires
rm -f /tmp/boxion_gen_creds.php /tmp/boxion_php_error.log

if [[ ! -f /tmp/boxion_admin_creds.txt ]]; then
    echo "❌ Fichier credentials non généré"
    exit 1
fi

ADMIN_CREDS=$(cat /tmp/boxion_admin_creds.txt 2>/dev/null || echo "Erreur lecture credentials")
rm -f /tmp/boxion_admin_creds.txt

# -------- Personnalisation Dashboard --------
echo "🎨 Personnalisation du dashboard avec: $COMPANY"
# Remplacer le branding dans les fichiers web
sed -i "s/Gasser IT Services/$COMPANY/g" ${APP}/web/index.php
sed -i "s/Gasser IT Services/$COMPANY/g" ${APP}/web/admin/index.php

# Gestion conditionnelle des pages légales
if [[ "$LEGAL_PAGES" == "false" ]]; then
    echo "⚖️  Pages légales désactivées"
    # Supprimer les liens légaux du footer
    sed -i '/<div class="legal-links">/,/<\/div>/d' ${APP}/web/index.php
else
    echo "⚖️  Génération des pages légales pour: $COMPANY"
    # Générer les pages légales personnalisées (ici on pourrait ajouter la génération)
fi

# -------- Finalisation --------
echo
echo "🎉 ==============================================="
echo "🎉 BOXION VPN SERVER INSTALLÉ AVEC SUCCÈS!"
echo "🎉 ==============================================="
echo
echo "📊 Informations serveur:"
echo "   Domain: ${DOMAIN}"
echo "   Port WireGuard: ${PORT}"
echo "   Interface WG: ${WG_IF}"
echo "   Interface WAN: ${WAN_IF}"
echo
echo "🔑 API Token: ${API_TOKEN}"
echo "🔑 Server pubkey: ${SV_PUB}"
echo
echo "🔐 Dashboard Admin:"
echo "$ADMIN_CREDS"
echo
echo "🌐 Accès web:"
echo "   Dashboard public: http://${DOMAIN}/"
echo "   Dashboard admin: http://${DOMAIN}/admin/"
echo "   API: http://${DOMAIN}/api/"
echo
echo "📱 Commande client Boxion:"
echo "TOKEN='${API_TOKEN}' DOMAIN='${DOMAIN}' bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/bootstrap_client.sh)\""
echo
echo "🛡️ Développé par Gasser IT Services"
echo "📧 Support: https://github.com/J0bot/boxion-setup"
