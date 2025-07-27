<?php
/**
 * Boxion VPN Dashboard - Déconnexion sécurisée
 */

require_once 'auth.php';

// Déconnecter l'utilisateur
BoxionAuth::logout();

// Redirection vers la page de login
header('Location: login.php');
exit;
?>
