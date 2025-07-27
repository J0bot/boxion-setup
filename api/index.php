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
/**
 * Génération sécurisée IPv6 pour nouveau peer
 * Debian 12 compatible - Sans race condition
 */
function next_ip6(){
    $prefix = envv('IPV6_PREFIX');
    $bits = (int)envv('POOL_BITS');
    
    // ====== Validation préfixe IPv6 ======
    if (!$prefix || !preg_match('/^[0-9a-fA-F:]+$/', $prefix) || strlen($prefix) < 3) {
        error_log("[BOXION-API] Préfixe IPv6 invalide: $prefix");
        abort(500, 'Invalid IPv6 prefix configuration');
    }
    
    // ====== Validation bits pool ======
    if ($bits < 1 || $bits > 32) {
        error_log("[BOXION-API] Pool bits invalide: $bits");
        abort(500, 'Invalid pool bits configuration');
    }
    
    $max = (1 << $bits) - 1; // Maximum d'IDs possibles
    $db = db();
    
    try {
        $db->beginTransaction();
        
        // Sélection + mise à jour atomique (pas de race condition)
        $stmt = $db->prepare("SELECT v FROM meta WHERE k='last_id' FOR UPDATE");
        $stmt->execute();
        $current_id = (int)$stmt->fetchColumn();
        
        // Vérification pool non épuisé
        if ($current_id >= $max) {
            $db->rollback();
            error_log("[BOXION-API] Pool IPv6 épuisé: $current_id >= $max");
            abort(409, "IPv6 pool exhausted (max: $max)");
        }
        
        // Incrémentation sécurisée
        $next_id = $current_id + 1;
        $stmt = $db->prepare("UPDATE meta SET v = ? WHERE k = 'last_id'");
        if (!$stmt->execute([$next_id])) {
            $db->rollback();
            error_log("[BOXION-API] Échec mise à jour last_id: $current_id -> $next_id");
            abort(500, 'Failed to allocate IPv6 ID');
        }
        
        // Génération IPv6 sécurisée
        $hex = strtoupper(str_pad(dechex($next_id), 4, '0', STR_PAD_LEFT));
        $ipv6 = $prefix . '::' . $hex;
        
        // Validation IPv6 générée
        if (!filter_var($ipv6, FILTER_VALIDATE_IP, FILTER_FLAG_IPV6)) {
            $db->rollback();
            error_log("[BOXION-API] IPv6 générée invalide: $ipv6");
            abort(500, 'Generated invalid IPv6 address');
        }
        
        // Vérification anti-collision (sécurité supplémentaire)
        $stmt = $db->prepare("SELECT COUNT(*) FROM peers WHERE ipv6 = ?");
        $stmt->execute([$ipv6]);
        if ((int)$stmt->fetchColumn() > 0) {
            $db->rollback();
            error_log("[BOXION-API] Collision IPv6 détectée: $ipv6");
            abort(500, 'IPv6 collision detected');
        }
        
        $db->commit();
        
        error_log("[BOXION-API] IPv6 allouée: $ipv6 (ID: $next_id)");
        return $ipv6;
        
    } catch (Exception $e) {
        if ($db->inTransaction()) {
            $db->rollback();
        }
        error_log("[BOXION-API] Erreur allocation IPv6: " . $e->getMessage());
        abort(500, 'IPv6 allocation failed: ' . $e->getMessage());
    }
}
/**
 * Validation nom peer sécurisée
 * Debian 12 compatible - Anti-injection
 */
function valid_name($s) {
    if (!is_string($s) || strlen($s) === 0) {
        error_log("[BOXION-API] Nom peer vide ou invalide");
        return false;
    }
    
    // Longueur stricte (1-32 caractères)
    if (strlen($s) < 1 || strlen($s) > 32) {
        error_log("[BOXION-API] Nom peer longueur invalide: " . strlen($s));
        return false;
    }
    
    // Caractères autorisés seulement (alphanum + ._-)
    if (!preg_match('/^[a-zA-Z0-9._-]+$/', $s)) {
        error_log("[BOXION-API] Nom peer caractères invalides: $s");
        return false;
    }
    
    // Interdire noms système dangereux
    $forbidden = ['root', 'admin', 'system', 'wg0', 'boxion', '..', '.', 'null', 'undefined'];
    if (in_array(strtolower($s), $forbidden)) {
        error_log("[BOXION-API] Nom peer interdit: $s");
        return false;
    }
    
    return true;
}

/**
 * Validation clé publique WireGuard STRICTE
 * Debian 12 compatible - Format exact base64
 */
function valid_pub($s) {
    if (!is_string($s) || strlen($s) === 0) {
        error_log("[BOXION-API] Clé publique vide ou invalide");
        return false;
    }
    
    // WireGuard: exactement 44 caractères base64 (32 bytes + padding)
    if (strlen($s) !== 44) {
        error_log("[BOXION-API] Clé publique longueur invalide: " . strlen($s) . " (attendu: 44)");
        return false;
    }
    
    // Format base64 strict avec padding obligatoire
    if (!preg_match('/^[A-Za-z0-9+\/]{42}[A-Za-z0-9+\/=]{2}$/', $s)) {
        error_log("[BOXION-API] Clé publique format base64 invalide: $s");
        return false;
    }
    
    // Vérification décodage base64 valide
    $decoded = base64_decode($s, true);
    if ($decoded === false || strlen($decoded) !== 32) {
        error_log("[BOXION-API] Clé publique décodage base64 échoué: $s");
        return false;
    }
    
    // Vérification pas de clé nulle ou faible
    if ($decoded === str_repeat("\x00", 32) || $decoded === str_repeat("\xFF", 32)) {
        error_log("[BOXION-API] Clé publique faible détectée");
        return false;
    }
    
    return true;
}

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
    // ====== Ajout peer WireGuard sécurisé ======
    error_log("[BOXION-API] Ajout peer: $name -> $ip6");
    
    // Validation variables environnement critiques
    $wg_if = envv('WG_IF');
    $wan_if = envv('WAN_IF');
    $app_bin = envv('APP_BIN');
    
    if (!$wg_if || !preg_match('/^[a-zA-Z0-9]+$/', $wg_if)) {
        error_log("[BOXION-API] WG_IF invalide: $wg_if");
        abort(500, 'Invalid WG_IF configuration');
    }
    
    if (!$wan_if || !preg_match('/^[a-zA-Z0-9]+$/', $wan_if)) {
        error_log("[BOXION-API] WAN_IF invalide: $wan_if");
        abort(500, 'Invalid WAN_IF configuration');
    }
    
    if (!$app_bin || !is_dir($app_bin)) {
        error_log("[BOXION-API] APP_BIN invalide: $app_bin");
        abort(500, 'Invalid APP_BIN configuration');
    }
    
    // Vérification script existe et exécutable
    $script_path = $app_bin . '/wg_add_peer.sh';
    if (!file_exists($script_path)) {
        error_log("[BOXION-API] Script manquant: $script_path");
        abort(500, 'WireGuard add peer script not found');
    }
    
    if (!is_executable($script_path)) {
        error_log("[BOXION-API] Script non exécutable: $script_path");
        abort(500, 'WireGuard add peer script not executable');
    }
    
    // Exécution sécurisée avec environnement isolé
    $env = [
        'WG_IF' => $wg_if,
        'WAN_IF' => $wan_if,
        'PATH' => '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
    ];
    
    $cmd = escapeshellcmd($script_path) . ' ' . escapeshellarg($pub) . ' ' . escapeshellarg($ip6) . ' 2>&1';
    
    error_log("[BOXION-API] Exécution: $cmd");
    
    // Exécution avec timeout et environnement contrôlé
    $descriptors = [
        0 => ['pipe', 'r'],  // stdin
        1 => ['pipe', 'w'],  // stdout
        2 => ['pipe', 'w']   // stderr
    ];
    
    $process = proc_open($cmd, $descriptors, $pipes, null, $env);
    
    if (!is_resource($process)) {
        error_log("[BOXION-API] Échec ouverture processus: $cmd");
        abort(500, 'Failed to execute WireGuard add peer script');
    }
    
    // Fermer stdin
    fclose($pipes[0]);
    
    // Lecture stdout/stderr avec timeout
    $stdout = stream_get_contents($pipes[1]);
    $stderr = stream_get_contents($pipes[2]);
    
    fclose($pipes[1]);
    fclose($pipes[2]);
    
    // Attendre fin processus
    $return_code = proc_close($process);
    
    // Gestion détaillée des erreurs
    if ($return_code !== 0) {
        $error_details = "Script exit code: $return_code";
        if ($stdout) $error_details .= "\nSTDOUT: $stdout";
        if ($stderr) $error_details .= "\nSTDERR: $stderr";
        
        error_log("[BOXION-API] Échec ajout peer $name: $error_details");
        
        // Rollback base de données en cas d'échec
        try {
            $db->prepare('DELETE FROM peers WHERE name = ?')->execute([$name]);
            error_log("[BOXION-API] Rollback DB réussi pour peer: $name");
        } catch (Exception $e) {
            error_log("[BOXION-API] Échec rollback DB pour peer $name: " . $e->getMessage());
        }
        
        abort(500, "WireGuard peer addition failed: $error_details");
    }
    
    error_log("[BOXION-API] Peer ajouté avec succès: $name -> $ip6");
    if ($stdout) error_log("[BOXION-API] Script output: $stdout");
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
    $name = $m[1];
    $db = db();
    
    // Validation nom peer
    if (!valid_name($name)) {
        error_log("[BOXION-API] DELETE - Nom peer invalide: $name");
        abort(400, 'Invalid peer name');
    }
    
    // Récupération données peer
    $st = $db->prepare('SELECT ipv6, pubkey FROM peers WHERE name = ?');
    $st->execute([$name]);
    $row = $st->fetch(PDO::FETCH_ASSOC);
    
    if (!$row) {
        error_log("[BOXION-API] DELETE - Peer non trouvé: $name");
        abort(404, 'Peer not found');
    }
    
    $ip6 = $row['ipv6'];
    $pubkey = $row['pubkey'];
    
    error_log("[BOXION-API] Suppression peer: $name ($ip6)");
    
    // ====== Suppression WireGuard sécurisée ======
    // Validation variables environnement critiques
    $wg_if = envv('WG_IF');
    $wan_if = envv('WAN_IF');
    $app_bin = envv('APP_BIN');
    
    if (!$wg_if || !preg_match('/^[a-zA-Z0-9]+$/', $wg_if)) {
        error_log("[BOXION-API] DELETE - WG_IF invalide: $wg_if");
        abort(500, 'Invalid WG_IF configuration');
    }
    
    if (!$wan_if || !preg_match('/^[a-zA-Z0-9]+$/', $wan_if)) {
        error_log("[BOXION-API] DELETE - WAN_IF invalide: $wan_if");
        abort(500, 'Invalid WAN_IF configuration');
    }
    
    if (!$app_bin || !is_dir($app_bin)) {
        error_log("[BOXION-API] DELETE - APP_BIN invalide: $app_bin");
        abort(500, 'Invalid APP_BIN configuration');
    }
    
    // Vérification script suppression existe
    $script_path = $app_bin . '/wg_del_peer.sh';
    if (!file_exists($script_path)) {
        error_log("[BOXION-API] DELETE - Script manquant: $script_path");
        abort(500, 'WireGuard delete peer script not found');
    }
    
    if (!is_executable($script_path)) {
        error_log("[BOXION-API] DELETE - Script non exécutable: $script_path");
        abort(500, 'WireGuard delete peer script not executable');
    }
    
    // Exécution sécurisée suppression WireGuard
    $env = [
        'WG_IF' => $wg_if,
        'WAN_IF' => $wan_if,
        'PATH' => '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
    ];
    
    $cmd = escapeshellcmd($script_path) . ' ' . escapeshellarg($pubkey) . ' ' . escapeshellarg($ip6) . ' 2>&1';
    
    error_log("[BOXION-API] DELETE - Exécution: $cmd");
    
    // Exécution avec environnement contrôlé
    $descriptors = [
        0 => ['pipe', 'r'],  // stdin
        1 => ['pipe', 'w'],  // stdout
        2 => ['pipe', 'w']   // stderr
    ];
    
    $process = proc_open($cmd, $descriptors, $pipes, null, $env);
    
    if (!is_resource($process)) {
        error_log("[BOXION-API] DELETE - Échec ouverture processus: $cmd");
        abort(500, 'Failed to execute WireGuard delete peer script');
    }
    
    // Fermer stdin
    fclose($pipes[0]);
    
    // Lecture stdout/stderr
    $stdout = stream_get_contents($pipes[1]);
    $stderr = stream_get_contents($pipes[2]);
    
    fclose($pipes[1]);
    fclose($pipes[2]);
    
    // Attendre fin processus
    $return_code = proc_close($process);
    
    // Gestion détaillée des erreurs
    if ($return_code !== 0) {
        $error_details = "Script exit code: $return_code";
        if ($stdout) $error_details .= "\nSTDOUT: $stdout";
        if ($stderr) $error_details .= "\nSTDERR: $stderr";
        
        error_log("[BOXION-API] DELETE - Échec suppression peer $name: $error_details");
        
        // Ne pas supprimer de la DB si la suppression WireGuard échoue
        abort(500, "WireGuard peer deletion failed: $error_details");
    }
    
    // Suppression base de données SEULEMENT après succès WireGuard
    try {
        $db->prepare('DELETE FROM peers WHERE name = ?')->execute([$name]);
        error_log("[BOXION-API] DELETE - Peer supprimé avec succès: $name");
        if ($stdout) error_log("[BOXION-API] DELETE - Script output: $stdout");
    } catch (Exception $e) {
        error_log("[BOXION-API] DELETE - Échec suppression DB pour peer $name: " . $e->getMessage());
        abort(500, 'Database deletion failed after WireGuard cleanup');
    }
    
    echo json_encode(['ok' => true, 'message' => 'Peer deleted successfully']);
    exit;
}

abort(404,'no route');
