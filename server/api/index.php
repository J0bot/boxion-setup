<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { exit; }

function jsonResponse($data, $status = 200) {
    http_response_code($status);
    echo json_encode($data);
    exit;
}

// Load env from /etc/boxion/boxion.env
$env = [];
$envFile = '/etc/boxion/boxion.env';
if (is_file($envFile)) {
    $lines = file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        $line = trim($line);
        if ($line === '' || $line[0] === '#') continue;
        if (strpos($line, '=') !== false) {
            [$k, $v] = explode('=', $line, 2);
            $env[trim($k)] = trim($v);
        }
    }
}

// Route: GET /api/status -> diagnostics JSON (auth required)
$reqPath = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);
if ($_SERVER['REQUEST_METHOD'] === 'GET' && preg_match('#/api/status/?$#', $reqPath)) {
    try {
        $dbPath = $env['DB_PATH'] ?? '/var/lib/boxion/peers.db';
        $db = new PDO('sqlite:' . $dbPath);
        $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    } catch (Exception $e) {
        jsonResponse(['error' => 'DB erreur'], 500);
    }

    // Auth: master API token only (ne consomme pas d'OTP)
    $auth = getAuthHeader();
    if (stripos($auth, 'Bearer ') !== 0) {
        jsonResponse(['error' => 'Token manquant'], 401);
    }
    $token = substr($auth, 7);
    if (empty($env['API_TOKEN']) || !hash_equals($env['API_TOKEN'], $token)) {
        jsonResponse(['error' => 'Token invalide'], 403);
    }
    $out = shell_exec('sudo /usr/local/sbin/boxion-diag 2>&1');
    if ($out === null) {
        jsonResponse(['error' => 'Diagnostic indisponible'], 500);
    }
    $sections = preg_split('/^=== (.+) ===$/m', $out, -1, PREG_SPLIT_DELIM_CAPTURE);
    $diag = [];
    if ($sections && count($sections) > 1) {
        for ($i = 1; $i < count($sections); $i += 2) {
            $title = trim($sections[$i]);
            $body = trim($sections[$i+1] ?? '');
            $diag[$title] = $body;
        }
    } else {
        $diag['raw'] = $out;
    }
    jsonResponse(['success' => true, 'auth_method' => 'api', 'diag' => $diag]);
}

// Route: GET /api/peers/list -> list peers (master token required)
if ($_SERVER['REQUEST_METHOD'] === 'GET' && preg_match('#/api/peers/list/?$#', $reqPath)) {
    try {
        $dbPath = $env['DB_PATH'] ?? '/var/lib/boxion/peers.db';
        $db = new PDO('sqlite:' . $dbPath);
        $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    } catch (Exception $e) { jsonResponse(['error' => 'DB erreur'], 500); }

    // master token only
    $auth = getAuthHeader();
    if (stripos($auth, 'Bearer ') !== 0) jsonResponse(['error' => 'Token manquant'], 401);
    $token = substr($auth, 7);
    if (empty($env['API_TOKEN']) || !hash_equals($env['API_TOKEN'], $token)) {
        jsonResponse(['error' => 'Token invalide'], 403);
    }
    $rows = [];
    $stmt = $db->query('SELECT id, name, ipv6_address FROM peers ORDER BY id ASC');
    while ($r = $stmt->fetch(PDO::FETCH_ASSOC)) { $rows[] = $r; }
    jsonResponse(['success' => true, 'peers' => $rows]);
}

// Route: GET /api/otp/list -> list OTPs (master token only)
if ($_SERVER['REQUEST_METHOD'] === 'GET' && preg_match('#/api/otp/list/?$#', $reqPath)) {
    try {
        $dbPath = $env['DB_PATH'] ?? '/var/lib/boxion/peers.db';
        $db = new PDO('sqlite:' . $dbPath);
        $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    } catch (Exception $e) { jsonResponse(['error' => 'DB erreur'], 500); }
    // ensure table exists
    $db->exec("CREATE TABLE IF NOT EXISTS otps (token TEXT PRIMARY KEY, expires_at TEXT NOT NULL, used INTEGER NOT NULL DEFAULT 0)");
    $auth = getAuthHeader();
    if (stripos($auth, 'Bearer ') !== 0) jsonResponse(['error' => 'Token manquant'], 401);
    $token = substr($auth, 7);
    if (empty($env['API_TOKEN']) || !hash_equals($env['API_TOKEN'], $token)) {
        jsonResponse(['error' => 'Token invalide'], 403);
    }
    $rows = [];
    $stmt = $db->query("SELECT token, datetime(expires_at) as expires_at, used FROM otps ORDER BY expires_at DESC");
    while ($r = $stmt->fetch(PDO::FETCH_ASSOC)) { $rows[] = $r; }
    jsonResponse(['success' => true, 'otps' => $rows]);
}

// Route: POST /api/otp/create -> create OTP (master token only)
if ($_SERVER['REQUEST_METHOD'] === 'POST' && preg_match('#/api/otp/create/?$#', $reqPath)) {
    try {
        $dbPath = $env['DB_PATH'] ?? '/var/lib/boxion/peers.db';
        $db = new PDO('sqlite:' . $dbPath);
        $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    } catch (Exception $e) { jsonResponse(['error' => 'DB erreur'], 500); }
    // ensure table exists
    $db->exec("CREATE TABLE IF NOT EXISTS otps (token TEXT PRIMARY KEY, expires_at TEXT NOT NULL, used INTEGER NOT NULL DEFAULT 0)");
    $auth = getAuthHeader();
    if (stripos($auth, 'Bearer ') !== 0) jsonResponse(['error' => 'Token manquant'], 401);
    $token = substr($auth, 7);
    if (empty($env['API_TOKEN']) || !hash_equals($env['API_TOKEN'], $token)) {
        jsonResponse(['error' => 'Token invalide'], 403);
    }
    $input = json_decode(file_get_contents('php://input'), true) ?: [];
    $ttl = max(60, (int)($input['ttl'] ?? 600)); // default 10 min, min 60s
    $new = bin2hex(random_bytes(16));
    $stmt = $db->prepare("INSERT INTO otps (token, expires_at, used) VALUES (?, datetime('now', ?), 0)");
    $stmt->execute([$new, "+{$ttl} seconds"]);
    jsonResponse(['success' => true, 'token' => $new, 'expires_in' => $ttl]);
}

// Route: GET /api/proxy/mappings -> read nginx maps
if ($_SERVER['REQUEST_METHOD'] === 'GET' && preg_match('#/api/proxy/mappings/?$#', $reqPath)) {
    try {
        $dbPath = $env['DB_PATH'] ?? '/var/lib/boxion/peers.db';
        $db = new PDO('sqlite:' . $dbPath);
        $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    } catch (Exception $e) { jsonResponse(['error' => 'DB erreur'], 500); }
    // any valid token/OTP
    validateTokenOrOTP($env, $db);
    $mapDir = '/etc/nginx/boxion';
    $http = @file($mapDir . '/http.map', FILE_IGNORE_NEW_LINES) ?: [];
    $tls  = @file($mapDir . '/tls.map',  FILE_IGNORE_NEW_LINES) ?: [];
    $parse = function($lines) {
        $res = [];
        foreach ($lines as $ln) {
            $ln = trim($ln);
            if ($ln === '' || $ln[0] === '#') continue;
            if (!str_ends_with($ln, ';')) $ln .= ';';
            if (preg_match('/^([A-Za-z0-9.-]+)\s+([^;]+);$/', $ln, $m)) {
                $res[$m[1]] = trim($m[2]);
            }
        }
        return $res;
    };
    $httpMap = $parse($http); $tlsMap = $parse($tls);
    $domains = array_unique(array_merge(array_keys($httpMap), array_keys($tlsMap)));
    sort($domains);
    $items = [];
    foreach ($domains as $d) {
        $items[] = [ 'domain' => $d, 'http' => $httpMap[$d] ?? null, 'tls' => $tlsMap[$d] ?? null ];
    }
    jsonResponse(['success' => true, 'mappings' => $items]);
}

// Route: POST /api/proxy/add -> call wrapper
if ($_SERVER['REQUEST_METHOD'] === 'POST' && preg_match('#/api/proxy/add/?$#', $reqPath)) {
    try {
        $dbPath = $env['DB_PATH'] ?? '/var/lib/boxion/peers.db';
        $db = new PDO('sqlite:' . $dbPath);
        $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    } catch (Exception $e) { jsonResponse(['error' => 'DB erreur'], 500); }
    validateTokenOrOTP($env, $db);
    $in = json_decode(file_get_contents('php://input'), true);
    if (!$in) jsonResponse(['error' => 'JSON invalide'], 400);
    $domain = trim($in['domain'] ?? '');
    $ipv6 = trim($in['ipv6'] ?? '');
    $hport = (string)($in['http_port'] ?? '80');
    $tport = (string)($in['tls_port'] ?? '443');
    if ($domain === '' || $ipv6 === '') jsonResponse(['error' => 'domain/ipv6 requis'], 400);
    $cmd = 'sudo /usr/local/sbin/boxion-proxy-add ' . escapeshellarg($domain) . ' ' . escapeshellarg($ipv6)
         . ' ' . escapeshellarg($hport) . ' ' . escapeshellarg($tport) . ' 2>&1';
    exec($cmd, $out, $rc);
    if ($rc !== 0) jsonResponse(['error' => 'Échec ajout proxy', 'detail' => implode("\n", $out)], 500);
    jsonResponse(['success' => true, 'output' => implode("\n", $out)]);
}

// Route: GET /api/he/status -> read HE env from net container filesystem (mounted volume) and report basics
if ($_SERVER['REQUEST_METHOD'] === 'GET' && preg_match('#/api/he/status/?$#', $reqPath)) {
    try {
        $dbPath = $env['DB_PATH'] ?? '/var/lib/boxion/peers.db';
        $db = new PDO('sqlite:' . $dbPath);
        $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    } catch (Exception $e) { jsonResponse(['error' => 'DB erreur'], 500); }
    // any valid token/OTP (admin UI gate)
    validateTokenOrOTP($env, $db);
    $heFile = '/etc/boxion/he6in4.env';
    $he = [];
    if (is_file($heFile)) {
        $lines = file($heFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
        foreach ($lines as $ln) {
            $ln = trim($ln);
            if ($ln === '' || $ln[0] === '#') continue;
            if (strpos($ln, '=') !== false) {
                [$k,$v] = explode('=', $ln, 2);
                $he[trim($k)] = trim($v);
            }
        }
    }
    $enabled = ($he['HE_ENABLED'] ?? '0') === '1';
    jsonResponse(['success' => true, 'enabled' => $enabled, 'he' => $he]);
}

// Route: POST /api/he/apply -> call wrapper to apply HE 6in4 tunnel configuration
if ($_SERVER['REQUEST_METHOD'] === 'POST' && preg_match('#/api/he/apply/?$#', $reqPath)) {
    try {
        $dbPath = $env['DB_PATH'] ?? '/var/lib/boxion/peers.db';
        $db = new PDO('sqlite:' . $dbPath);
        $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    } catch (Exception $e) { jsonResponse(['error' => 'DB erreur'], 500); }
    $authInfo = validateTokenOrOTP($env, $db);
    $in = json_decode(file_get_contents('php://input'), true);
    if (!$in) jsonResponse(['error' => 'JSON invalide'], 400);
    $my_v4 = trim($in['my_v4'] ?? '');
    $srv_v4 = trim($in['he_server_v4'] ?? '');
    $cli6   = trim($in['he_tun_client6'] ?? '');
    $srv6   = trim($in['he_tun_server6'] ?? '');
    $prefix = trim($in['he_routed_prefix'] ?? '');
    $mtu    = (string)($in['mtu'] ?? '1480');
    $use_def= !empty($in['use_default_route']) ? '1' : '0';
    if ($my_v4===''||$srv_v4===''||$cli6===''||$srv6===''||$prefix==='') {
        jsonResponse(['error' => 'Champs HE requis manquants'], 400);
    }
    $cmd = 'sudo /usr/local/sbin/boxion-he-apply set '
        . escapeshellarg($my_v4) . ' ' . escapeshellarg($srv_v4) . ' '
        . escapeshellarg($cli6) . ' ' . escapeshellarg($srv6) . ' '
        . escapeshellarg($prefix) . ' ' . escapeshellarg($mtu) . ' '
        . escapeshellarg($use_def) . ' 2>&1';
    exec($cmd, $out, $rc);
    if ($rc !== 0) jsonResponse(['error' => "Échec application HE", 'detail' => implode("\n", $out)], 500);
    jsonResponse(['success' => true, 'output' => implode("\n", $out), 'auth_method' => $authInfo['method'] ?? 'api']);
}

// Route: GET /api/smtp/status -> read SMTP env and summarize (any valid token/OTP)
if ($_SERVER['REQUEST_METHOD'] === 'GET' && preg_match('#/api/smtp/status/?$#', $reqPath)) {
    try {
        $dbPath = $env['DB_PATH'] ?? '/var/lib/boxion/peers.db';
        $db = new PDO('sqlite:' . $dbPath);
        $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    } catch (Exception $e) { jsonResponse(['error' => 'DB erreur'], 500); }
    validateTokenOrOTP($env, $db);
    $smtpFile = '/etc/boxion/smtp.env';
    $smtp = [];
    if (is_file($smtpFile)) {
        $lines = file($smtpFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
        foreach ($lines as $ln) {
            $ln = trim($ln);
            if ($ln === '' || $ln[0] === '#') continue;
            if (strpos($ln, '=') !== false) {
                [$k,$v] = explode('=', $ln, 2);
                $smtp[trim($k)] = trim($v);
            }
        }
    }
    $relayConfigured = !empty($smtp['RELAY_HOST']);
    // Do not expose RELAY_PASS to UI
    $resp = [
        'inbound_user' => $smtp['SMTP_INBOUND_USER'] ?? null,
        'inbound_pass' => $smtp['SMTP_INBOUND_PASS'] ?? null,
        'relay' => [
            'host' => $smtp['RELAY_HOST'] ?? null,
            'port' => $smtp['RELAY_PORT'] ?? null,
            'user' => $smtp['RELAY_USER'] ?? null,
            'configured' => $relayConfigured,
        ],
        'listen_ports' => [587, 2525],
    ];
    jsonResponse(['success' => true, 'smtp' => $resp]);
}

// Route: POST /api/smtp/apply -> configure upstream relay (any valid token/OTP)
if ($_SERVER['REQUEST_METHOD'] === 'POST' && preg_match('#/api/smtp/apply/?$#', $reqPath)) {
    try {
        $dbPath = $env['DB_PATH'] ?? '/var/lib/boxion/peers.db';
        $db = new PDO('sqlite:' . $dbPath);
        $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    } catch (Exception $e) { jsonResponse(['error' => 'DB erreur'], 500); }
    $authInfo = validateTokenOrOTP($env, $db);
    $in = json_decode(file_get_contents('php://input'), true) ?: [];
    $relay_host = trim((string)($in['relay_host'] ?? ''));
    $relay_port = (string)($in['relay_port'] ?? '587');
    $relay_user = (string)($in['relay_user'] ?? '');
    $relay_pass = (string)($in['relay_pass'] ?? '');
    // Allow clearing host to disable relay
    $cmd = 'sudo /usr/local/sbin/boxion-smtp-apply set '
         . escapeshellarg($relay_host) . ' '
         . escapeshellarg($relay_port) . ' '
         . escapeshellarg($relay_user) . ' '
         . escapeshellarg($relay_pass) . ' 2>&1';
    exec($cmd, $out, $rc);
    if ($rc !== 0) jsonResponse(['error' => 'Échec configuration SMTP', 'detail' => implode("\n", $out)], 500);
    jsonResponse(['success' => true, 'output' => implode("\n", $out), 'auth_method' => $authInfo['method'] ?? 'api']);
}

// Route: POST /api/proxy/remove -> call wrapper
if ($_SERVER['REQUEST_METHOD'] === 'POST' && preg_match('#/api/proxy/remove/?$#', $reqPath)) {
    try {
        $dbPath = $env['DB_PATH'] ?? '/var/lib/boxion/peers.db';
        $db = new PDO('sqlite:' . $dbPath);
        $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    } catch (Exception $e) { jsonResponse(['error' => 'DB erreur'], 500); }
    validateTokenOrOTP($env, $db);
    $in = json_decode(file_get_contents('php://input'), true);
    if (!$in) jsonResponse(['error' => 'JSON invalide'], 400);
    $domain = trim($in['domain'] ?? '');
    if ($domain === '') jsonResponse(['error' => 'domain requis'], 400);
    $cmd = 'sudo /usr/local/sbin/boxion-proxy-remove ' . escapeshellarg($domain) . ' 2>&1';
    exec($cmd, $out, $rc);
    if ($rc !== 0) jsonResponse(['error' => 'Échec suppression proxy', 'detail' => implode("\n", $out)], 500);
    jsonResponse(['success' => true, 'output' => implode("\n", $out)]);
}

// Route: POST /api/proxy/reload -> call wrapper
if ($_SERVER['REQUEST_METHOD'] === 'POST' && preg_match('#/api/proxy/reload/?$#', $reqPath)) {
    try {
        $dbPath = $env['DB_PATH'] ?? '/var/lib/boxion/peers.db';
        $db = new PDO('sqlite:' . $dbPath);
        $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    } catch (Exception $e) { jsonResponse(['error' => 'DB erreur'], 500); }
    validateTokenOrOTP($env, $db);
    $cmd = 'sudo /usr/local/sbin/boxion-proxy-reload 2>&1';
    exec($cmd, $out, $rc);
    if ($rc !== 0) jsonResponse(['error' => 'Échec reload proxy', 'detail' => implode("\n", $out)], 500);
    jsonResponse(['success' => true, 'output' => implode("\n", $out)]);
}

function getAuthHeader() {
    if (isset($_SERVER['HTTP_AUTHORIZATION'])) return $_SERVER['HTTP_AUTHORIZATION'];
    if (isset($_SERVER['Authorization'])) return $_SERVER['Authorization'];
    return '';
}

function validateTokenOrOTP($env, $db) {
    $auth = getAuthHeader();
    if (stripos($auth, 'Bearer ') !== 0) {
        jsonResponse(['error' => 'Token manquant'], 401);
    }
    $token = substr($auth, 7);

    // Master API token
    if (!empty($env['API_TOKEN']) && hash_equals($env['API_TOKEN'], $token)) {
        return ['method' => 'api'];
    }

    // OTP: single-use and time-limited
    // Ensure table exists on fresh installs
    try {
        $db->exec("CREATE TABLE IF NOT EXISTS otps (token TEXT PRIMARY KEY, expires_at TEXT NOT NULL, used INTEGER NOT NULL DEFAULT 0)");
    } catch (Exception $e) {
        error_log('OTP table ensure error: ' . $e->getMessage());
    }
    try {
        $stmt = $db->prepare("UPDATE otps SET used=1 WHERE token = ? AND used = 0 AND expires_at > datetime('now')");
        $stmt->execute([$token]);
        if ($stmt->rowCount() === 1) {
            return ['method' => 'otp'];
        }
    } catch (Exception $e) {
        error_log('OTP check error: ' . $e->getMessage());
    }

    jsonResponse(['error' => 'Token invalide'], 403);
}

function getNextIPv6($prefixBase, $db) {
    $stmt = $db->query("SELECT MAX(id) as max_id FROM peers");
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    $next_id = (isset($row['max_id']) && $row['max_id'] !== null ? (int)$row['max_id'] : 0) + 1;
    $offset = 0x100; // start at ::100
    $hext = dechex($next_id + $offset);
    $prefixBase = rtrim($prefixBase, ':');
    return $prefixBase . '::' . $hext . '/128';
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    jsonResponse(['error' => 'Méthode non autorisée'], 405);
}

try {
    $dbPath = $env['DB_PATH'] ?? '/var/lib/boxion/peers.db';
    $db = new PDO('sqlite:' . $dbPath);
    $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (Exception $e) {
    jsonResponse(['error' => 'DB erreur'], 500);
}

$authInfo = validateTokenOrOTP($env, $db);

$input = json_decode(file_get_contents('php://input'), true);
if (!$input) { jsonResponse(['error' => 'JSON invalide'], 400); }
if (empty($input['name']) || empty($input['public_key'])) {
    jsonResponse(['error' => 'Nom et clé publique requis'], 400);
}
$name = trim($input['name']);
$public_key = trim($input['public_key']);
if (!preg_match('/^[A-Za-z0-9+\/]{43}=$/', $public_key)) {
    jsonResponse(['error' => 'Format de clé publique invalide'], 400);
}

try {
    $db->beginTransaction();

    // Ensure not exists
    $stmt = $db->prepare('SELECT COUNT(*) FROM peers WHERE public_key = ?');
    $stmt->execute([$public_key]);
    if ((int)$stmt->fetchColumn() > 0) {
        $db->rollBack();
        jsonResponse(['error' => 'Clé publique déjà enregistrée'], 409);
    }

    $prefixBase = $env['IPV6_PREFIX_BASE'] ?? '';
    if ($prefixBase === '') { $db->rollBack(); jsonResponse(['error' => 'Préfixe IPv6 indisponible'], 500); }

    $ipv6_address = getNextIPv6($prefixBase, $db);

    $stmt = $db->prepare('INSERT INTO peers (name, public_key, ipv6_address) VALUES (?, ?, ?)');
    $stmt->execute([$name, $public_key, $ipv6_address]);

    // Apply WG
    $cmd = 'sudo /usr/local/sbin/boxion-wg-apply add-peer '
        . escapeshellarg($public_key) . ' ' . escapeshellarg($ipv6_address);
    exec($cmd, $out, $rc);
    if ($rc !== 0) {
        $db->rollBack();
        jsonResponse(['error' => 'Échec application config WG'], 500);
    }

    $db->commit();

    $host = $_SERVER['HTTP_HOST'] ?? ($_SERVER['SERVER_NAME'] ?? 'localhost');
    $host = preg_replace('/:.*/', '', $host);
    $endpoint = $host . ':' . ($env['ENDPOINT_PORT'] ?? '51820');

    jsonResponse([
        'success' => true,
        'Address' => $ipv6_address,
        'PublicKey' => ($env['SERVER_PUBLIC_KEY'] ?? ''),
        'Endpoint' => $endpoint,
        'config' => [
            'interface' => [
                'PrivateKey' => '[VOTRE_CLE_PRIVEE]',
                'Address' => $ipv6_address,
            ],
            'peer' => [
                'PublicKey' => ($env['SERVER_PUBLIC_KEY'] ?? ''),
                'Endpoint' => $endpoint,
                'AllowedIPs' => '::/0',
            ],
        ],
        'auth_method' => $authInfo['method'] ?? 'api',
    ]);

} catch (Exception $e) {
    error_log('API error: ' . $e->getMessage());
    jsonResponse(['error' => 'Erreur interne du serveur'], 500);
}
