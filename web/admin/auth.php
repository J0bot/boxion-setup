<?php
/**
 * Boxion VPN Dashboard - Système d'authentification sécurisé
 * Gestion des sessions et vérification des accès
 */

// Configuration sécurisée
ini_set('display_errors', 0);
error_reporting(0);
session_set_cookie_params([
    'lifetime' => 3600, // 1 heure
    'path' => '/admin/',
    'domain' => '',
    'secure' => isset($_SERVER['HTTPS']),
    'httponly' => true,
    'samesite' => 'Strict'
]);

if (session_status() === PHP_SESSION_NONE) {
    session_start();
}

// Headers de sécurité
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header('X-XSS-Protection: 1; mode=block');
header('Referrer-Policy: strict-origin-when-cross-origin');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

class BoxionAuth {
    private const CREDENTIALS_FILE = '/var/lib/boxion/admin_credentials.json';
    private const SESSION_TIMEOUT = 3600; // 1 heure
    
    /**
     * Génère un mot de passe aléaoire fort
     */
    public static function generatePassword($length = 16) {
        $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*';
        return substr(str_shuffle(str_repeat($chars, ceil($length / strlen($chars)))), 0, $length);
    }
    
    /**
     * Crée les credentials admin lors de l'installation
     */
    public static function createCredentials($username = null, $password = null) {
        $username = $username ?: 'admin';
        $password = $password ?: self::generatePassword();
        
        $credentials = [
            'username' => $username,
            'password_hash' => password_hash($password, PASSWORD_ARGON2ID),
            'created_at' => time(),
            'last_login' => null
        ];
        
        $dir = dirname(self::CREDENTIALS_FILE);
        if (!is_dir($dir)) {
            mkdir($dir, 0750, true);
        }
        
        file_put_contents(self::CREDENTIALS_FILE, json_encode($credentials, JSON_PRETTY_PRINT));
        chmod(self::CREDENTIALS_FILE, 0600);
        
        return ['username' => $username, 'password' => $password];
    }
    
    /**
     * Vérifie les credentials
     */
    public static function verifyCredentials($username, $password) {
        if (!file_exists(self::CREDENTIALS_FILE)) {
            return false;
        }
        
        $credentials = json_decode(file_get_contents(self::CREDENTIALS_FILE), true);
        if (!$credentials) {
            return false;
        }
        
        if ($credentials['username'] !== $username) {
            return false;
        }
        
        if (!password_verify($password, $credentials['password_hash'])) {
            return false;
        }
        
        // Mettre à jour la dernière connexion
        $credentials['last_login'] = time();
        file_put_contents(self::CREDENTIALS_FILE, json_encode($credentials, JSON_PRETTY_PRINT));
        
        return true;
    }
    
    /**
     * Authentifie l'utilisateur et crée une session
     */
    public static function login($username, $password) {
        if (!self::verifyCredentials($username, $password)) {
            return false;
        }
        
        // Régénérer l'ID de session pour éviter la fixation
        session_regenerate_id(true);
        
        $_SESSION['authenticated'] = true;
        $_SESSION['username'] = $username;
        $_SESSION['login_time'] = time();
        $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
        
        return true;
    }
    
    /**
     * Vérifie si l'utilisateur est authentifié
     */
    public static function isAuthenticated() {
        if (!isset($_SESSION['authenticated']) || !$_SESSION['authenticated']) {
            return false;
        }
        
        if (!isset($_SESSION['login_time'])) {
            return false;
        }
        
        // Vérifier le timeout de session
        if ((time() - $_SESSION['login_time']) > self::SESSION_TIMEOUT) {
            self::logout();
            return false;
        }
        
        return true;
    }
    
    /**
     * Déconnecte l'utilisateur
     */
    public static function logout() {
        $_SESSION = [];
        if (ini_get("session.use_cookies")) {
            $params = session_get_cookie_params();
            setcookie(session_name(), '', time() - 42000,
                $params["path"], $params["domain"],
                $params["secure"], $params["httponly"]
            );
        }
        session_destroy();
    }
    
    /**
     * Génère un token CSRF
     */
    public static function getCsrfToken() {
        return $_SESSION['csrf_token'] ?? '';
    }
    
    /**
     * Vérifie le token CSRF
     */
    public static function verifyCsrfToken($token) {
        return isset($_SESSION['csrf_token']) && hash_equals($_SESSION['csrf_token'], $token);
    }
    
    /**
     * Redirige vers la page de login si non authentifié
     */
    public static function requireAuth() {
        if (!self::isAuthenticated()) {
            header('Location: login.php');
            exit;
        }
    }
    
    /**
     * Obtient les informations des credentials
     */
    public static function getCredentialsInfo() {
        if (!file_exists(self::CREDENTIALS_FILE)) {
            return null;
        }
        
        $credentials = json_decode(file_get_contents(self::CREDENTIALS_FILE), true);
        if (!$credentials) {
            return null;
        }
        
        return [
            'username' => $credentials['username'],
            'created_at' => $credentials['created_at'],
            'last_login' => $credentials['last_login']
        ];
    }
}

/**
 * Fonction helper pour l'échappement HTML sécurisé
 */
function h($str) {
    return htmlspecialchars($str, ENT_QUOTES | ENT_HTML5, 'UTF-8');
}

/**
 * Fonction helper pour vérifier si c'est une requête POST
 */
function isPost() {
    return $_SERVER['REQUEST_METHOD'] === 'POST';
}

/**
 * Fonction helper pour obtenir une valeur POST sécurisée
 */
function getPost($key, $default = '') {
    return isset($_POST[$key]) ? trim($_POST[$key]) : $default;
}
?>
