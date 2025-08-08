<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
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
