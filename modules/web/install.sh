#!/usr/bin/env bash

# 🌐 Module Web - Dashboard et configuration Nginx
# Version condensée pour respecter les limites de tokens

set -euo pipefail

# Source du logging
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../logging/logger.sh"

MODULE_NAME="WEB"
log_info "$MODULE_NAME" "Début installation module Web"

# Variables globales
APP_ROOT="/var/www/boxion-api"
WEB_DIR="$APP_ROOT/web"
ADMIN_DIR="$WEB_DIR/admin"
NGINX_SITES="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"
SITE_CONFIG="boxion-api"

# ====== CRÉATION STRUCTURE WEB ======

create_web_structure() {
    log_step "$MODULE_NAME" "Création structure Web" "1/4"
    
    local directories=("$WEB_DIR" "$ADMIN_DIR" "$WEB_DIR/assets")
    
    for dir in "${directories[@]}"; do
        if ! mkdir -p "$dir" 2>/dev/null; then
            log_fatal "$MODULE_NAME" "Impossible de créer: $dir"
        fi
    done
    
    chown -R www-data:www-data "$WEB_DIR"
    log_success "$MODULE_NAME" "Structure Web créée"
}

# ====== GÉNÉRATION NGINX CONFIG ======

generate_nginx_config() {
    log_step "$MODULE_NAME" "Configuration Nginx" "2/4"
    
    local nginx_conf="$NGINX_SITES/$SITE_CONFIG.conf"
    local domain="${DOMAIN:-tunnel.milkywayhub.org}"
    
    log_info "$MODULE_NAME" "Génération: $nginx_conf"
    
    cat > "$nginx_conf" << EOF
# Configuration Nginx - Boxion Tunnel VPN
# Domaine: $domain
# Générée automatiquement

server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    
    root $WEB_DIR;
    index index.php index.html;
    
    # Logs d'accès optimisés
    access_log /var/log/nginx/boxion-access.log;
    error_log /var/log/nginx/boxion-error.log;
    
    # Sécurité headers
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-XSS-Protection "1; mode=block";
    
    # Page publique
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    
    # API REST
    location ^~ /api/ {
        root $APP_ROOT;
        try_files \$uri \$uri/ /api/index.php?\$args;
        
        location ~ \.php$ {
            fastcgi_pass unix:/run/php/php8.2-fpm.sock;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            include fastcgi_params;
            
            # Timeout API
            fastcgi_read_timeout 30s;
        }
    }
    
    # Admin dashboard
    location ^~ /admin/ {
        auth_basic "Administration Boxion";
        auth_request off;  # Authentification gérée par PHP
        
        location ~ \.php$ {
            fastcgi_pass unix:/run/php/php8.2-fpm.sock;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            include fastcgi_params;
        }
    }
    
    # PHP processing général
    location ~ \.php$ {
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_read_timeout 60s;
    }
    
    # Sécurité fichiers sensibles
    location ~ /\. {
        deny all;
    }
    
    location ~ \.(env|json|log)$ {
        deny all;
    }
    
    # Assets statiques optimisés
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

    # Validation syntaxe Nginx
    if ! nginx -t 2>/tmp/nginx-test.log; then
        log_error_context "$MODULE_NAME" "Configuration Nginx invalide" "$(cat /tmp/nginx-test.log)"
        rm -f /tmp/nginx-test.log
        return 1
    fi
    
    # Activation du site
    if ! ln -sf "$nginx_conf" "$NGINX_ENABLED/$SITE_CONFIG.conf" 2>/dev/null; then
        log_fatal "$MODULE_NAME" "Impossible d'activer le site"
    fi
    
    # Suppression du site par défaut
    rm -f "$NGINX_ENABLED/default"
    
    log_success "$MODULE_NAME" "Configuration Nginx activée"
    rm -f /tmp/nginx-test.log
}

# ====== GÉNÉRATION CREDENTIALS ADMIN ======

generate_admin_credentials() {
    log_step "$MODULE_NAME" "Génération credentials admin" "3/4"
    
    local username="${ADMIN_USERNAME:-admin}"
    local password="${ADMIN_PASSWORD:-$(openssl rand -base64 12)}"
    local cred_file="/var/lib/boxion/admin_credentials.json"
    
    # Hash sécurisé du mot de passe
    local password_hash
    if ! password_hash=$(php -r "echo password_hash('$password', PASSWORD_DEFAULT);"); then
        log_fatal "$MODULE_NAME" "Impossible de hasher le mot de passe"
    fi
    
    # Sauvegarde credentials JSON sécurisée
    cat > "$cred_file" << EOF
{
    "username": "$username",
    "password_hash": "$password_hash",
    "created_at": $(date +%s)
}
EOF

    # Permissions sécurisées
    chmod 600 "$cred_file"
    chown www-data:www-data "$cred_file"
    
    # Export pour affichage final
    echo "export ADMIN_USERNAME='$username'" > /tmp/boxion-admin-vars.sh
    echo "export ADMIN_PASSWORD='$password'" >> /tmp/boxion-admin-vars.sh
    
    log_success "$MODULE_NAME" "Credentials admin générés"
    log_info "$MODULE_NAME" "Username: $username"
    log_info "$MODULE_NAME" "Password: $password"
}

# ====== GÉNÉRATION PAGES WEB MINIMALISTES ======

generate_web_pages() {
    log_step "$MODULE_NAME" "Génération pages web" "4/4"
    
    # Page d'accueil publique minimaliste
    cat > "$WEB_DIR/index.php" << 'EOF'
<?php
header('Content-Type: text/html; charset=UTF-8');
$dbPath = '/var/lib/boxion/boxion.db';
$peerCount = 0;
if (file_exists($dbPath)) {
    try {
        $pdo = new PDO("sqlite:$dbPath");
        $peerCount = $pdo->query('SELECT COUNT(*) FROM peers')->fetchColumn();
    } catch (Exception $e) {}
}
?>
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Boxion Tunnel VPN</title>
<style>body{font-family:Arial;margin:40px;background:#f0f0f0}
.card{background:white;padding:20px;border-radius:8px;margin:20px 0}
.stat{font-size:2em;color:#333}</style></head>
<body>
<h1>🌐 Boxion Tunnel VPN</h1>
<div class="card">
<h3>Statistiques</h3>
<div class="stat"><?=$peerCount?> Boxions connectées</div>
<p>Service de tunnel IPv6 pour l'auto-hébergement</p>
</div>
<div class="card">
<h3>Installation</h3>
<code>curl -fsSL https://github.com/j0bot/boxion-setup/raw/main/bootstrap_client.sh | sudo bash</code>
<p>Contact: tunnel@milkywayhub.org</p>
</div>
<p><a href="/admin/">Administration</a></p>
</body></html>
EOF

    # Page d'authentification admin minimaliste
    cat > "$ADMIN_DIR/auth.php" << 'EOF'
<?php
session_start();
if ($_POST['login'] ?? false) {
    $creds = json_decode(file_get_contents('/var/lib/boxion/admin_credentials.json'), true);
    if ($creds && password_verify($_POST['password'], $creds['password_hash'])) {
        $_SESSION['boxion_admin'] = true;
        header('Location: index.php'); exit;
    }
    $error = 'Identifiants incorrects';
}
if (isset($_SESSION['boxion_admin'])) { header('Location: index.php'); exit; }
?>
<!DOCTYPE html>
<html><head><title>Admin - Boxion</title>
<style>body{font-family:Arial;background:#667eea;display:flex;height:100vh;align-items:center;justify-content:center}
.form{background:white;padding:30px;border-radius:10px;width:300px}
input{width:100%;padding:10px;margin:10px 0;border:1px solid #ddd}
button{width:100%;padding:10px;background:#667eea;color:white;border:none;border-radius:5px}</style></head>
<body>
<form method="POST" class="form">
<h2>🔐 Administration</h2>
<?php if(isset($error)) echo "<p style='color:red'>$error</p>"; ?>
<input name="username" placeholder="Utilisateur" required>
<input name="password" type="password" placeholder="Mot de passe" required>
<button name="login">Connexion</button>
</form></body></html>
EOF

    # Dashboard admin minimaliste
    cat > "$ADMIN_DIR/index.php" << 'EOF'
<?php
session_start();
if (!($_SESSION['boxion_admin'] ?? false)) { header('Location: auth.php'); exit; }
if (isset($_GET['logout'])) { session_destroy(); header('Location: auth.php'); exit; }

$dbPath = '/var/lib/boxion/boxion.db';
$peers = [];
$peerCount = 0;
if (file_exists($dbPath)) {
    try {
        $pdo = new PDO("sqlite:$dbPath");
        $peerCount = $pdo->query('SELECT COUNT(*) FROM peers')->fetchColumn();
        $peers = $pdo->query('SELECT name,ipv6,datetime(created_at,"unixepoch") as date FROM peers ORDER BY created_at DESC LIMIT 10')->fetchAll();
    } catch (Exception $e) {}
}
?>
<!DOCTYPE html>
<html><head><title>Dashboard - Boxion</title>
<style>body{font-family:Arial;margin:0}
.header{background:#667eea;color:white;padding:15px;display:flex;justify-content:space-between}
.container{padding:20px}
.card{background:white;border:1px solid #ddd;padding:20px;margin:20px 0;border-radius:5px}
table{width:100%;border-collapse:collapse}
th,td{padding:10px;border:1px solid #ddd;text-align:left}
.stat{font-size:2em;color:#333}</style></head>
<body>
<div class="header">
<h1>📊 Dashboard Boxion</h1>
<a href="?logout" style="color:white">Déconnexion</a>
</div>
<div class="container">
<div class="card">
<h3>Statistiques</h3>
<div class="stat"><?=$peerCount?> Peers connectés</div>
</div>
<div class="card">
<h3>Derniers Peers</h3>
<table>
<tr><th>Nom</th><th>IPv6</th><th>Date</th></tr>
<?php foreach($peers as $p): ?>
<tr><td><?=htmlspecialchars($p['name'])?></td><td><?=htmlspecialchars($p['ipv6'])?></td><td><?=htmlspecialchars($p['date'])?></td></tr>
<?php endforeach; ?>
</table>
</div>
</div>
</body></html>
EOF

    # Permissions
    chown -R www-data:www-data "$WEB_DIR"
    find "$WEB_DIR" -type f -exec chmod 644 {} \;
    
    log_success "$MODULE_NAME" "Pages web générées"
}

# ====== RESTART NGINX ======

restart_nginx() {
    log_info "$MODULE_NAME" "Redémarrage Nginx..."
    
    if ! systemctl restart nginx 2>/tmp/nginx-restart.log; then
        log_error_context "$MODULE_NAME" "Échec redémarrage Nginx" "$(cat /tmp/nginx-restart.log)"
        rm -f /tmp/nginx-restart.log
        return 1
    fi
    
    # Validation service actif
    if ! systemctl is-active nginx >/dev/null 2>&1; then
        log_fatal "$MODULE_NAME" "Nginx non actif après redémarrage"
    fi
    
    log_success "$MODULE_NAME" "Nginx redémarré avec succès"
    rm -f /tmp/nginx-restart.log
}

# ====== MAIN MODULE ======

main() {
    log_info "$MODULE_NAME" "=== INSTALLATION MODULE WEB ==="
    
    # Vérification privilèges root
    if [[ $UID -ne 0 ]]; then
        log_fatal "$MODULE_NAME" "Privilèges root requis"
    fi
    
    # Validation prérequis
    validate_or_fatal "$MODULE_NAME" "[[ -n \$DOMAIN ]]" "Variable DOMAIN requise"
    
    # Séquence d'installation Web
    create_web_structure
    generate_nginx_config
    generate_admin_credentials
    generate_web_pages
    restart_nginx
    
    # Export variables
    echo "export WEB_DIR='$WEB_DIR'" > /tmp/boxion-web-vars.sh
    echo "export ADMIN_DIR='$ADMIN_DIR'" >> /tmp/boxion-web-vars.sh
    
    log_success "$MODULE_NAME" "Module Web installé avec succès!"
    log_info "$MODULE_NAME" "Site web: http://$DOMAIN/"
    log_info "$MODULE_NAME" "Admin: http://$DOMAIN/admin/"
    
    return 0
}

# Exécution si appelé directement
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
