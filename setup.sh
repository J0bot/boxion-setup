#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Boxion VPN Server Setup"
echo "========================="

# ====== paramètres (flags ou interactif) ======
WG_IF=${WG_IF:-wg0}
PORT=${PORT:-51820}
DOMAIN=${DOMAIN:-}
WAN_IF=${WAN_IF:-$(ip r | awk '/default/ {print $5; exit}')}
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
apt-get install -y wireguard iptables php-fpm php-cli php-sqlite3 nginx jq

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
mkdir -p /etc/wireguard /var/lib/boxion
chmod 700 /etc/wireguard

if [[ ! -f /etc/wireguard/${WG_IF}.conf ]]; then
  umask 077
  wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
  SV_PRIV=$(cat /etc/wireguard/server_private.key)
  cat >/etc/wireguard/${WG_IF}.conf <<EOF
[Interface]
PrivateKey = ${SV_PRIV}
Address = ${IPV6_PREFIX}::1/64
ListenPort = ${PORT}
SaveConfig = true
EOF
  systemctl enable wg-quick@${WG_IF}
  systemctl start  wg-quick@${WG_IF}
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
sqlite3 /var/lib/boxion/boxion.db < ${APP}/sql/init.sql
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
    root ${APP}/api;

    location /api/ {
        include snippets/fastcgi-php.conf;
        fastcgi_param SCRIPT_FILENAME \$document_root/index.php;
        fastcgi_pass unix:/run/php/php-fpm.sock;
    }
    location / { return 404; }
}
EOF
install -m644 ${APP}/nginx/boxion-api.conf /etc/nginx/sites-available/boxion-api.conf
ln -sf /etc/nginx/sites-available/boxion-api.conf /etc/nginx/sites-enabled/boxion-api.conf
rm -f /etc/nginx/sites-enabled/default
systemctl reload nginx
systemctl restart php*-fpm.service || true

echo "OK ✓  Domain=${DOMAIN}  Port=${PORT}  WG_IF=${WG_IF}  WAN_IF=${WAN_IF}"
echo "Token API: ${API_TOKEN}"
echo "Server pubkey: ${SV_PUB}"
