<?php
/**
 * Boxion VPN Dashboard - Page de connexion sécurisée
 */

require_once 'auth.php';

$error = '';
$success = '';

// Si déjà connecté, rediriger vers le dashboard
if (BoxionAuth::isAuthenticated()) {
    header('Location: index.php');
    exit;
}

// Traitement du formulaire de connexion
if (isPost()) {
    $username = getPost('username');
    $password = getPost('password');
    
    if (empty($username) || empty($password)) {
        $error = 'Nom d\'utilisateur et mot de passe requis';
    } else {
        if (BoxionAuth::login($username, $password)) {
            header('Location: index.php');
            exit;
        } else {
            $error = 'Identifiants incorrects';
            // Log de tentative de connexion échouée
            error_log("Boxion Dashboard: Failed login attempt for user '$username' from " . ($_SERVER['REMOTE_ADDR'] ?? 'unknown'));
        }
    }
}

// Vérifier si les credentials existent
$credentialsExist = file_exists('/var/lib/boxion/admin_credentials.json');
?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Boxion Dashboard - Connexion</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh; display: flex; align-items: center; justify-content: center;
        }
        .login-container {
            background: white; border-radius: 12px; padding: 40px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2); width: 100%; max-width: 400px;
        }
        .logo { text-align: center; margin-bottom: 30px; }
        .logo h1 { color: #667eea; font-size: 2.2em; margin-bottom: 5px; }
        .logo p { color: #666; font-size: 0.9em; }
        .form-group { margin-bottom: 20px; }
        .form-group label { display: block; margin-bottom: 5px; color: #333; font-weight: 500; }
        .form-group input {
            width: 100%; padding: 12px; border: 2px solid #e1e5e9;
            border-radius: 6px; font-size: 16px; transition: border-color 0.3s;
        }
        .form-group input:focus {
            outline: none; border-color: #667eea; box-shadow: 0 0 0 3px rgba(102,126,234,0.1);
        }
        .btn {
            width: 100%; padding: 12px; background: #667eea; color: white;
            border: none; border-radius: 6px; font-size: 16px; cursor: pointer;
            transition: background 0.3s;
        }
        .btn:hover { background: #5a67d8; }
        .error {
            background: #fed7d7; color: #c53030; padding: 12px; border-radius: 6px;
            margin-bottom: 20px; border-left: 4px solid #c53030;
        }
        .warning {
            background: #fef5e7; color: #d69e2e; padding: 12px; border-radius: 6px;
            margin-bottom: 20px; border-left: 4px solid #d69e2e;
        }
        .info {
            background: #e6fffa; color: #2c7a7b; padding: 12px; border-radius: 6px;
            margin-bottom: 20px; border-left: 4px solid #2c7a7b; font-size: 0.9em;
        }
        .back-link {
            text-align: center; margin-top: 20px;
        }
        .back-link a {
            color: #667eea; text-decoration: none; font-size: 0.9em;
        }
        .back-link a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="login-container">
        <div class="logo">
            <h1>🛡️ Boxion</h1>
            <p>Dashboard Administration</p>
        </div>
        
        <?php if (!$credentialsExist): ?>
        <div class="warning">
            <strong>⚠️ Configuration manquante</strong><br>
            Les identifiants admin n'ont pas été configurés. Relancez l'installation du serveur.
        </div>
        <?php endif; ?>
        
        <?php if ($error): ?>
        <div class="error">
            <strong>❌ Erreur:</strong> <?= h($error) ?>
        </div>
        <?php endif; ?>
        
        <?php if ($credentialsExist): ?>
        <div class="info">
            <strong>💡 Info:</strong> Utilisez les identifiants générés lors de l'installation du serveur.
        </div>
        
        <form method="POST" action="">
            <div class="form-group">
                <label for="username">Nom d'utilisateur</label>
                <input type="text" id="username" name="username" required 
                       value="<?= h(getPost('username')) ?>" autocomplete="username">
            </div>
            
            <div class="form-group">
                <label for="password">Mot de passe</label>
                <input type="password" id="password" name="password" required autocomplete="current-password">
            </div>
            
            <button type="submit" class="btn">🔓 Se connecter</button>
        </form>
        <?php endif; ?>
        
        <div class="back-link">
            <a href="../">← Retour à l'accueil</a>
        </div>
    </div>
</body>
</html>
