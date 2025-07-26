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
