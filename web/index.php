<?php
/**
 * Boxion VPN Dashboard - Page d'accueil publique
 * Gasser IT Services - Système VPN professionnel
 */

// Configuration sécurisée
ini_set('display_errors', 0);
error_reporting(0);

// Headers de sécurité
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header('X-XSS-Protection: 1; mode=block');
header('Referrer-Policy: strict-origin-when-cross-origin');

// Récupérer les stats publiques
function getPublicStats() {
    $stats = ['connected_peers' => 0, 'total_peers' => 0, 'uptime' => 'N/A', 'server_status' => 'unknown'];
    
    // Vérifier le statut WireGuard
    exec('systemctl is-active wg-quick@wg0 2>/dev/null', $output, $return);
    $stats['server_status'] = ($return === 0 && isset($output[0]) && $output[0] === 'active') ? 'online' : 'offline';
    
    if ($stats['server_status'] === 'online') {
        // Compter les peers connectés
        exec('wg show wg0 2>/dev/null | grep -c "latest handshake"', $handshakes);
        $activeCount = 0;
        if (!empty($handshakes[0])) {
            exec('wg show wg0 2>/dev/null', $wgOutput);
            foreach ($wgOutput as $line) {
                if (strpos($line, 'latest handshake:') === 0) {
                    $handshake = trim(substr($line, 18));
                    if (!in_array($handshake, ['(none)', '']) && strtotime($handshake) > (time() - 300)) {
                        $activeCount++;
                    }
                }
            }
        }
        $stats['connected_peers'] = $activeCount;
        
        // Uptime du service
        exec('systemctl show wg-quick@wg0 --property=ActiveEnterTimestamp 2>/dev/null', $uptimeOutput);
        if (!empty($uptimeOutput[0])) {
            $timestamp = substr($uptimeOutput[0], strpos($uptimeOutput[0], '=') + 1);
            if ($timestamp && $timestamp !== 'n/a') {
                $startTime = strtotime($timestamp);
                if ($startTime) {
                    $uptime = time() - $startTime;
                    $days = floor($uptime / 86400);
                    $hours = floor(($uptime % 86400) / 3600);
                    $minutes = floor(($uptime % 3600) / 60);
                    $stats['uptime'] = ($days > 0 ? $days . 'j ' : '') . 
                                     ($hours > 0 ? $hours . 'h ' : '') . 
                                     $minutes . 'min';
                }
            }
        }
    }
    
    // Total des peers enregistrés
    $dbPath = '/var/lib/boxion/boxion.db';
    if (file_exists($dbPath)) {
        try {
            $pdo = new PDO("sqlite:$dbPath");
            $stmt = $pdo->query("SELECT COUNT(*) FROM peers");
            $stats['total_peers'] = (int)$stmt->fetchColumn();
        } catch (Exception $e) {}
    }
    
    return $stats;
}

$stats = getPublicStats();

?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Boxion VPN System</title>
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
        .header p { font-size: 1.2em; opacity: 0.9; }
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
        .status.offline { background: #e53e3e; color: white; }
        .stats-bar { 
            display: flex; flex-wrap: wrap; justify-content: center; 
            gap: 20px; margin-top: 20px; 
        }
        .stat-item { 
            background: rgba(255,255,255,0.2); padding: 8px 16px; 
            border-radius: 20px; font-size: 0.9em;
        }
        .tutorial-steps { counter-reset: step-counter; }
        .tutorial-step { 
            counter-increment: step-counter; margin-bottom: 20px;
            padding: 20px; border-left: 4px solid #667eea;
            position: relative;
        }
        .tutorial-step::before {
            content: counter(step-counter); position: absolute; left: -15px; top: 15px;
            background: #667eea; color: white; border-radius: 50%; 
            width: 30px; height: 30px; display: flex; align-items: center; 
            justify-content: center; font-weight: bold;
        }
        .tutorial-step h4 { margin-left: 20px; color: #667eea; }
        .tutorial-step p { margin-left: 20px; margin-top: 10px; }
        .legal-links { 
            text-align: center; margin: 20px 0;
        }
        .legal-links a {
            color: #667eea; text-decoration: none; margin: 0 15px;
            font-size: 0.9em;
        }
        .legal-links a:hover { text-decoration: underline; }
        .footer { text-align: center; padding: 40px 0; color: #666; }
    </style>
</head>
<body>
    <a href="admin/" class="admin-link">🔐 Dashboard Admin</a>
    
    <div class="header">
        <div class="container">
            <h1>🛡️ Boxion VPN</h1>
            <p>Système VPN WireGuard professionnel - <strong>Gasser IT Services</strong></p>
            <div class="stats-bar">
                <span class="stat-item">
                    <span class="status <?= $stats['server_status'] === 'online' ? 'online' : 'offline' ?>">
                        <?= $stats['server_status'] === 'online' ? '🟢 En ligne' : '🔴 Hors ligne' ?>
                    </span>
                </span>
                <span class="stat-item">📱 <strong><?= $stats['connected_peers'] ?></strong> Boxion connectés</span>
                <span class="stat-item">📋 <strong><?= $stats['total_peers'] ?></strong> clients enregistrés</span>
                <span class="stat-item">⏱️ Uptime: <strong><?= $stats['uptime'] ?></strong></span>
            </div>
        </div>
    </div>

    <div class="container">
        <div class="card">
            <h2>🚀 Qu'est-ce que Boxion ?</h2>
            <p>Boxion est un système VPN WireGuard complet avec gestion automatique des peers via API. 
            Il permet de déployer rapidement un serveur VPN sécurisé avec attribution automatique d'adresses IPv6 
            et une interface de gestion intuitive.</p>
        </div>

        <div class="features">
            <div class="feature">
                <h3>🔐 Sécurisé</h3>
                <p>Les clés privées sont générées côté client. Seules les clés publiques transitent par l'API. 
                Authentication par token Bearer et permissions limitées via sudoers.</p>
            </div>
            <div class="feature">
                <h3>🌐 IPv6 Native</h3>
                <p>Attribution automatique d'adresses IPv6 depuis un pool /64 avec support NDP proxy 
                pour un routage optimal.</p>
            </div>
            <div class="feature">
                <h3>🔄 Auto-Setup</h3>
                <p>Installation complète en une commande. Scripts idempotents et configuration 
                automatique de tous les composants.</p>
            </div>
            <div class="feature">
                <h3>📡 API REST</h3>
                <p>API complète pour la gestion des peers : création, suppression, consultation. 
                Interface programmatique pour l'intégration avec d'autres systèmes.</p>
            </div>
        </div>

        <div class="card">
            <h2>📱 Comment connecter votre Boxion ?</h2>
            <p>Suivez ce tutoriel étape par étape pour connecter votre appareil au VPN Boxion :</p>
            
            <div class="tutorial-steps">
                <div class="tutorial-step">
                    <h4>Obtenir votre token d'accès</h4>
                    <p>Contactez l'administrateur de ce serveur pour obtenir votre token d'accès personnel. Chaque client reçoit un token unique et sécurisé.</p>
                </div>
                
                <div class="tutorial-step">
                    <h4>Installer WireGuard sur votre appareil</h4>
                    <p><strong>Linux/Debian :</strong> <code>sudo apt install wireguard</code><br>
                    <strong>Windows/Mac/Mobile :</strong> Téléchargez l'app officielle WireGuard</p>
                </div>
                
                <div class="tutorial-step">
                    <h4>Lancer la configuration automatique</h4>
                    <p>Exécutez cette commande en remplaçant VOTRE_TOKEN par votre token :</p>
                    <div class="code-block">TOKEN='VOTRE_TOKEN' bash -c "$(curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/bootstrap_client.sh)"</div>
                </div>
                
                <div class="tutorial-step">
                    <h4>Activer la connexion</h4>
                    <p>Le script génère automatiquement votre configuration. Activez simplement WireGuard et votre Boxion sera connecté !</p>
                </div>
            </div>
            
            <p><strong>✨ C'est tout !</strong> Votre connexion VPN est maintenant sécurisée et chiffrée.</p>
        </div>

        <div class="card">
            <h2>⚡ Installation Serveur (Administrateurs)</h2>
            <p>Pour déployer votre propre serveur Boxion VPN :</p>
            <div class="code-block">curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/bootstrap.sh | sudo bash</div>
            <p><em>Installation complète automatique sur Debian/Ubuntu VPS</em></p>
        </div>

        <div class="card">
            <h2>🏗️ Architecture Technique</h2>
            <ul style="margin-left: 20px;">
                <li><strong>Backend :</strong> Debian + PHP-FPM + Nginx + SQLite</li>
                <li><strong>VPN :</strong> WireGuard avec configuration automatique</li>
                <li><strong>Base de données :</strong> SQLite pour la persistance des peers</li>
                <li><strong>Sécurité :</strong> Token API, sudoers limités, aucune clé privée stockée</li>
                <li><strong>Réseau :</strong> IPv6 avec pools /112 et proxy NDP</li>
            </ul>
        </div>

        <div class="card">
            <h2>🔧 Ports à Ouvrir (Firewall/Cloud)</h2>
            <div class="code-block">
- UDP 51820 (WireGuard)
- TCP 80 (HTTP API)  
- TCP 443 (HTTPS API)
- TCP 22 (SSH)
            </div>
        </div>

        <div class="card">
            <h2>📚 Documentation & Support</h2>
            <a href="https://github.com/J0bot/boxion-setup" class="btn">📖 GitHub Repository</a>
            <a href="https://github.com/J0bot/boxion-setup/blob/main/README.md" class="btn">📝 Documentation</a>
            <a href="api/" class="btn">🔌 API Documentation</a>
        </div>
    </div>

    <div class="footer">
        <div class="container">
            <div class="legal-links">
                <a href="privacy.php">Politique de Confidentialité</a>
                <a href="terms.php">Conditions d'Utilisation</a>
                <a href="legal.php">Mentions Légales</a>
                <a href="contact.php">Contact</a>
            </div>
            <p>🛡️ <strong>Boxion VPN System</strong> - Sécurisé, Rapide, Professionnel</p>
            <p>© <?= date('Y') ?> <strong>Gasser IT Services</strong> - Solutions d'infrastructure réseau et sécurité informatique</p>
            <p style="font-size: 0.8em; margin-top: 10px;">Développé avec ❤️ pour une infrastructure VPN moderne et décentralisée</p>
        </div>
    </div>
</body>
</html>
