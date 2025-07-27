<?php
/**
 * Boxion VPN Dashboard - Interface d'administration principale
 * Affichage des connexions WireGuard et gestion du système
 */

require_once 'auth.php';

// Vérifier l'authentification
BoxionAuth::requireAuth();

// Charger la configuration
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

/**
 * Récupère les statistiques WireGuard
 */
function getWireGuardStats() {
    $stats = ['interface' => null, 'peers' => [], 'status' => 'unknown'];
    
    // Vérifier le statut du service
    exec('systemctl is-active wg-quick@wg0 2>/dev/null', $output, $return);
    $stats['status'] = ($return === 0 && isset($output[0]) && $output[0] === 'active') ? 'active' : 'inactive';
    
    if ($stats['status'] !== 'active') {
        return $stats;
    }
    
    // Récupérer les infos de l'interface
    exec('wg show wg0 2>/dev/null', $wgOutput);
    if (empty($wgOutput)) {
        return $stats;
    }
    
    $currentPeer = null;
    foreach ($wgOutput as $line) {
        $line = trim($line);
        
        if (strpos($line, 'interface:') === 0) {
            $stats['interface'] = ['name' => 'wg0'];
        } elseif (strpos($line, 'public key:') === 0) {
            $stats['interface']['public_key'] = substr($line, 12);
        } elseif (strpos($line, 'private key:') === 0) {
            // Ne pas afficher la clé privée pour la sécurité
            $stats['interface']['has_private_key'] = true;
        } elseif (strpos($line, 'listening port:') === 0) {
            $stats['interface']['port'] = (int)substr($line, 16);
        } elseif (strpos($line, 'peer:') === 0) {
            $currentPeer = [
                'public_key' => substr($line, 6),
                'endpoint' => null,
                'allowed_ips' => [],
                'latest_handshake' => null,
                'transfer_rx' => 0,
                'transfer_tx' => 0
            ];
            $stats['peers'][] = &$currentPeer;
        } elseif ($currentPeer && strpos($line, 'endpoint:') === 0) {
            $currentPeer['endpoint'] = substr($line, 10);
        } elseif ($currentPeer && strpos($line, 'allowed ips:') === 0) {
            $ips = substr($line, 13);
            $currentPeer['allowed_ips'] = array_map('trim', explode(',', $ips));
        } elseif ($currentPeer && strpos($line, 'latest handshake:') === 0) {
            $handshake = substr($line, 18);
            $currentPeer['latest_handshake'] = $handshake;
            $currentPeer['connected'] = !in_array($handshake, ['(none)', '']) && 
                                       strtotime($handshake) > (time() - 300); // 5 min
        } elseif ($currentPeer && strpos($line, 'transfer:') === 0) {
            $transfer = substr($line, 10);
            if (preg_match('/(\d+(?:\.\d+)?)\s*([KMGT]?iB)\s+received,\s+(\d+(?:\.\d+)?)\s*([KMGT]?iB)\s+sent/', $transfer, $matches)) {
                $currentPeer['transfer_rx'] = $matches[1] . ' ' . $matches[2];
                $currentPeer['transfer_tx'] = $matches[3] . ' ' . $matches[4];
            }
        }
    }
    
    return $stats;
}

/**
 * Récupère les peers depuis la base de données
 */
function getDatabasePeers() {
    $dbPath = '/var/lib/boxion/boxion.db';
    if (!file_exists($dbPath)) {
        return [];
    }
    
    try {
        $pdo = new PDO("sqlite:$dbPath");
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        
        $stmt = $pdo->query("SELECT name, pubkey, ipv6, created_at FROM peers ORDER BY created_at DESC");
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    } catch (Exception $e) {
        return [];
    }
}

/**
 * Traitement des actions POST
 */
if (isPost()) {
    $action = getPost('action');
    $csrf = getPost('csrf_token');
    
    if (!BoxionAuth::verifyCsrfToken($csrf)) {
        $error = 'Token CSRF invalide';
    } else {
        switch ($action) {
            case 'restart_wireguard':
                exec('sudo systemctl restart wg-quick@wg0 2>&1', $output, $return);
                $message = ($return === 0) ? 'WireGuard redémarré avec succès' : 'Erreur lors du redémarrage';
                break;
                
            case 'reload_nginx':
                exec('sudo systemctl reload nginx 2>&1', $output, $return);
                $message = ($return === 0) ? 'Nginx rechargé avec succès' : 'Erreur lors du rechargement';
                break;
        }
    }
}

// Cache des métriques système (évite surcharge VPS)
function getSystemMetrics() {
    $cache_file = '/tmp/boxion_system_cache.json';
    $cache_ttl = 30; // 30 secondes cache
    
    if (file_exists($cache_file) && (time() - filemtime($cache_file)) < $cache_ttl) {
        return json_decode(file_get_contents($cache_file), true);
    }
    
    $metrics = [];
    
    // RAM (rapide)
    $mem = file_get_contents('/proc/meminfo');
    preg_match('/MemTotal:\s+(\d+)/', $mem, $total);
    preg_match('/MemAvailable:\s+(\d+)/', $mem, $available);
    $metrics['ram'] = [
        'total' => round($total[1] / 1024, 1),
        'available' => round($available[1] / 1024, 1),
        'used_pct' => round((($total[1] - $available[1]) / $total[1]) * 100, 1)
    ];
    
    // Stockage (rapide)
    $disk = disk_free_space('/') / 1024 / 1024 / 1024;
    $disk_total = disk_total_space('/') / 1024 / 1024 / 1024;
    $metrics['disk'] = [
        'free' => round($disk, 1),
        'total' => round($disk_total, 1),
        'used_pct' => round((($disk_total - $disk) / $disk_total) * 100, 1)
    ];
    
    // Load Average (très rapide)
    $load = sys_getloadavg();
    $metrics['load'] = round($load[0], 2);
    
    // Tests de connectivité (optimisés)
    $metrics['ports'] = [
        'wg' => checkPortOptimized(51820, 'udp'),
        'http' => checkPortOptimized(80, 'tcp'),
        'https' => checkPortOptimized(443, 'tcp')
    ];
    
    // Cache pour 30s
    file_put_contents($cache_file, json_encode($metrics));
    return $metrics;
}

function checkPortOptimized($port, $protocol) {
    if ($protocol === 'udp') {
        // UDP check rapide via netstat
        exec("netstat -ulpn 2>/dev/null | grep ':$port '", $output, $ret);
        return !empty($output);
    } else {
        // TCP check rapide via ss
        exec("ss -tlpn 2>/dev/null | grep ':$port '", $output, $ret);
        return !empty($output);
    }
}

// Action handling
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action'])) {
    if (!validateCSRF($_POST['csrf_token'] ?? '')) {
        $error = 'Token CSRF invalide';
    } else {
        switch ($_POST['action']) {
            case 'restart_wg':
                exec('sudo systemctl restart wg-quick@wg0', $output, $ret);
                $message = $ret === 0 ? 'WireGuard redémarré avec succès' : 'Erreur lors du redémarrage';
                // Clear cache
                @unlink('/tmp/boxion_system_cache.json');
                break;
            case 'reload_nginx':
                exec('sudo systemctl reload nginx', $output, $ret);
                $message = $ret === 0 ? 'Nginx rechargé avec succès' : 'Erreur lors du rechargement';
                break;
            case 'refresh_metrics':
                @unlink('/tmp/boxion_system_cache.json');
                $message = 'Métriques système actualisées';
                break;
        }
    }
}

// Récupérer les données
$wgStats = getWireGuardStats();
$dbPeers = getDatabasePeers();
$systemMetrics = getSystemMetrics();
$credentialsInfo = BoxionAuth::getCredentialsInfo();

// Calculer les statistiques
$totalPeers = count($dbPeers);
$activePeers = 0;
foreach ($wgStats['peers'] as $peer) {
    if ($peer['connected'] ?? false) {
        $activePeers++;
    }
}
?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Boxion Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #f8f9fa; color: #333; line-height: 1.6;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white; padding: 20px 0;
        }
        .container { max-width: 1200px; margin: 0 auto; padding: 0 20px; }
        .header-content { display: flex; justify-content: space-between; align-items: center; }
        .header h1 { font-size: 1.8em; }
        .user-info { font-size: 0.9em; opacity: 0.9; }
        .main { padding: 30px 0; }
        .stats-grid {
            display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px; margin-bottom: 30px;
        }
        .stat-card {
            background: white; padding: 20px; border-radius: 10px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1); text-align: center;
        }
        .stat-value { font-size: 2.5em; font-weight: bold; margin-bottom: 5px; }
        .stat-value.green { color: #48bb78; }
        .stat-value.blue { color: #4299e1; }
        .stat-value.orange { color: #ed8936; }
        .stat-label { color: #666; font-size: 0.9em; }
        .card {
            background: white; border-radius: 10px; padding: 25px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 20px;
        }
        .card h2 { margin-bottom: 20px; color: #333; }
        .table {
            width: 100%; border-collapse: collapse; font-size: 0.9em;
        }
        .table th, .table td { padding: 12px; text-align: left; border-bottom: 1px solid #e2e8f0; }
        .table th { background: #f7fafc; font-weight: 600; color: #4a5568; }
        .status {
            display: inline-block; padding: 4px 12px; border-radius: 20px;
            font-size: 0.8em; font-weight: bold;
        }
        .status.online { background: #c6f6d5; color: #22543d; }
        .status.offline { background: #fed7d7; color: #742a2a; }
        .status.active { background: #bee3f8; color: #2a4365; }
        .btn {
            display: inline-block; padding: 8px 16px; background: #667eea;
            color: white; text-decoration: none; border-radius: 6px;
            font-size: 0.9em; border: none; cursor: pointer;
            margin-right: 10px; transition: background 0.3s;
        }
        .btn:hover { background: #5a67d8; }
        .btn.danger { background: #e53e3e; }
        .btn.danger:hover { background: #c53030; }
        .actions { margin-bottom: 20px; }
        .message {
            padding: 12px; border-radius: 6px; margin-bottom: 20px;
            border-left: 4px solid #48bb78;
            background: #f0fff4; color: #22543d;
        }
        .error {
            border-left-color: #e53e3e; background: #fef5f5; color: #742a2a;
        }
        .pubkey { font-family: monospace; font-size: 0.8em; word-break: break-all; }
        .logout-form { display: inline; }
        .system-info { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; }
        .info-item { background: #f7fafc; padding: 10px; border-radius: 6px; }
        .info-item strong { display: block; color: #4a5568; margin-bottom: 5px; }
        
        /* Métriques système optimisées */
        .metrics-grid {
            display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 20px; margin-top: 15px;
        }
        .metric-card {
            background: #f8f9fa; border-radius: 8px; padding: 20px;
            border-left: 4px solid #4a90e2;
        }
        .metric-card h4 { margin-bottom: 15px; color: #333; font-size: 1.1em; }
        .progress-bar {
            background: #e9ecef; border-radius: 10px; height: 12px;
            overflow: hidden; margin: 10px 0;
        }
        .progress {
            background: linear-gradient(135deg, #48bb78 0%, #38a169 100%);
            height: 100%; transition: width 0.3s ease;
        }
        .progress-bar .progress[style*="width: 7"], .progress-bar .progress[style*="width: 8"], .progress-bar .progress[style*="width: 9"] {
            background: linear-gradient(135deg, #ed8936 0%, #dd6b20 100%);
        }
        .load-avg {
            font-size: 2em; font-weight: bold; margin: 10px 0;
        }
        .load-avg.low { color: #48bb78; }
        .load-avg.medium { color: #ed8936; }
        .load-avg.high { color: #e53e3e; }
        .metric-card p { margin: 8px 0; line-height: 1.4; }
        .metric-card small { color: #666; font-size: 0.85em; }
    </style>
    <script>
        // Auto-refresh toutes les 30 secondes
        setTimeout(() => location.reload(), 30000);
    </script>
</head>
<body>
    <div class="header">
        <div class="container">
            <div class="header-content">
                <h1>🛡️ Boxion Dashboard</h1>
                <div class="user-info">
                    Connecté: <?= h($_SESSION['username']) ?> | 
                    <a href="../" style="color: white; opacity: 0.8;">🏠 Accueil</a> |
                    <form method="POST" action="logout.php" class="logout-form">
                        <button type="submit" style="background: none; border: none; color: white; opacity: 0.8; cursor: pointer;">🚪 Déconnexion</button>
                    </form>
                </div>
            </div>
        </div>
    </div>

    <div class="main">
        <div class="container">
            <?php if (isset($message)): ?>
            <div class="message<?= isset($error) ? ' error' : '' ?>">
                <?= h($message) ?>
            </div>
            <?php endif; ?>
            
            <!-- Statistiques principales -->
            <div class="stats-grid">
                <div class="stat-card">
                    <div class="stat-value green"><?= $activePeers ?></div>
                    <div class="stat-label">Connexions actives</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value blue"><?= $totalPeers ?></div>
                    <div class="stat-label">Peers enregistrés</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value <?= $wgStats['status'] === 'active' ? 'green' : 'orange' ?>">
                        <?= $wgStats['status'] === 'active' ? 'ACTIF' : 'INACTIF' ?>
                    </div>
                    <div class="stat-label">Statut WireGuard</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value blue"><?= $wgStats['interface']['port'] ?? 51820 ?></div>
                    <div class="stat-label">Port d'écoute</div>
                </div>
            </div>

            <!-- Métriques système -->
            <div class="card">
                <h2>💻 Métriques Système <small>(cache 30s)</small></h2>
                <div class="metrics-grid">
                    <div class="metric-card">
                        <h4>🧠 RAM</h4>
                        <div class="progress-bar">
                            <div class="progress" style="width: <?= $systemMetrics['ram']['used_pct'] ?>%;"></div>
                        </div>
                        <p><?= $systemMetrics['ram']['used_pct'] ?>% utilisée - <?= number_format($systemMetrics['ram']['total'] - $systemMetrics['ram']['available']) ?> / <?= number_format($systemMetrics['ram']['total']) ?> MB</p>
                    </div>
                    
                    <div class="metric-card">
                        <h4>💾 Stockage</h4>
                        <div class="progress-bar">
                            <div class="progress" style="width: <?= $systemMetrics['disk']['used_pct'] ?>%;"></div>
                        </div>
                        <p><?= $systemMetrics['disk']['used_pct'] ?>% utilisé - <?= number_format($systemMetrics['disk']['total'] - $systemMetrics['disk']['free'], 1) ?> / <?= number_format($systemMetrics['disk']['total'], 1) ?> GB</p>
                    </div>
                    
                    <div class="metric-card">
                        <h4>⚡ Charge CPU</h4>
                        <p class="load-avg <?= $systemMetrics['load'] > 2 ? 'high' : ($systemMetrics['load'] > 1 ? 'medium' : 'low') ?>">
                            <?= $systemMetrics['load'] ?>
                        </p>
                        <small>Load Average 1min</small>
                    </div>
                    
                    <div class="metric-card">
                        <h4>🌐 Ports Réseau</h4>
                        <p>
                            🔒 WireGuard (UDP/51820): <?= $systemMetrics['ports']['wg'] ? '✅ Ouvert' : '❌ Fermé' ?><br>
                            🌐 HTTP (TCP/80): <?= $systemMetrics['ports']['http'] ? '✅ Ouvert' : '❌ Fermé' ?><br>
                            🔒 HTTPS (TCP/443): <?= $systemMetrics['ports']['https'] ? '✅ Ouvert' : '❌ Fermé' ?>
                        </p>
                    </div>
                </div>
            </div>

            <!-- Actions rapides -->
            <div class="card">
                <h2>🔧 Actions Rapides</h2>
                <div class="actions">
                    <form method="post" style="display: inline;">
                        <input type="hidden" name="csrf_token" value="<?= BoxionAuth::getCsrfToken() ?>">
                        <button type="submit" name="action" value="restart_wg">🔄 Redémarrer WireGuard</button>
                    </form>
                    <form method="post" style="display: inline;">
                        <input type="hidden" name="csrf_token" value="<?= BoxionAuth::getCsrfToken() ?>">
                        <button type="submit" name="action" value="reload_nginx">🌐 Recharger Nginx</button>
                    </form>
                    <form method="post" style="display: inline;">
                        <input type="hidden" name="csrf_token" value="<?= BoxionAuth::getCsrfToken() ?>">
                        <button type="submit" name="action" value="refresh_metrics">📊 Actualiser Métriques</button>
                    </form>
                </div>
            </div>
{{ ... }}
            <!-- Liste des connexions actives -->
            <div class="card">
                <h2>🌐 Connexions WireGuard actives</h2>
                <?php if (empty($wgStats['peers'])): ?>
                <p style="color: #666; font-style: italic;">Aucune connexion active</p>
                <?php else: ?>
                <table class="table">
                    <thead>
                        <tr>
                            <th>Clé publique</th>
                            <th>Endpoint</th>
                            <th>IPs autorisées</th>
                            <th>Dernière connexion</th>
                            <th>Transfert</th>
                            <th>Statut</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($wgStats['peers'] as $peer): ?>
                        <tr>
                            <td class="pubkey"><?= h(substr($peer['public_key'], 0, 20)) ?>...</td>
                            <td><?= h($peer['endpoint'] ?? 'N/A') ?></td>
                            <td><?= h(implode(', ', $peer['allowed_ips'])) ?></td>
                            <td><?= h($peer['latest_handshake'] ?? 'Jamais') ?></td>
                            <td>
                                ↓ <?= h($peer['transfer_rx']) ?><br>
                                ↑ <?= h($peer['transfer_tx']) ?>
                            </td>
                            <td>
                                <span class="status <?= ($peer['connected'] ?? false) ? 'online' : 'offline' ?>">
                                    <?= ($peer['connected'] ?? false) ? 'En ligne' : 'Hors ligne' ?>
                                </span>
                            </td>
                        </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
                <?php endif; ?>
            </div>

            <!-- Liste des peers enregistrés -->
            <div class="card">
                <h2>📋 Peers enregistrés</h2>
                <?php if (empty($dbPeers)): ?>
                <p style="color: #666; font-style: italic;">Aucun peer enregistré</p>
                <?php else: ?>
                <table class="table">
                    <thead>
                        <tr>
                            <th>Nom</th>
                            <th>Clé publique</th>
                            <th>IPv6 attribuée</th>
                            <th>Date d'enregistrement</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($dbPeers as $peer): ?>
                        <tr>
                            <td><strong><?= h($peer['name']) ?></strong></td>
                            <td class="pubkey"><?= h(substr($peer['pubkey'], 0, 20)) ?>...</td>
                            <td><?= h($peer['ipv6']) ?></td>
                            <td><?= date('d/m/Y H:i', strtotime($peer['created_at'])) ?></td>
                        </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
                <?php endif; ?>
            </div>

            <!-- Informations système -->
            <div class="card">
                <h2>🖥️ Informations système</h2>
                <div class="system-info">
                    <div class="info-item">
                        <strong>Interface WireGuard</strong>
                        <?= h($config['WG_IF'] ?? 'wg0') ?>
                    </div>
                    <div class="info-item">
                        <strong>Préfixe IPv6</strong>
                        <?= h($config['IPV6_PREFIX'] ?? 'N/A') ?>
                    </div>
                    <div class="info-item">
                        <strong>Domaine API</strong>
                        <?= h($config['ENDPOINT_DOMAIN'] ?? 'N/A') ?>
                    </div>
                    <div class="info-item">
                        <strong>Dernière connexion admin</strong>
                        <?= $credentialsInfo['last_login'] ? date('d/m/Y H:i', $credentialsInfo['last_login']) : 'Jamais' ?>
                    </div>
                </div>
            </div>
        </div>
    </div>
</body>
</html>
