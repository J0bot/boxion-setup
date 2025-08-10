<?php
// Admin Diagnostics (protected by Nginx Basic Auth)
?><!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Boxion Admin - Diagnostic</title>
  <style>
    body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,"Helvetica Neue",Arial,sans-serif;margin:2rem;background:#0b1020;color:#e9eef7}
    .container{max-width:1000px;margin:0 auto}
    .card{background:#121a33;border:1px solid #1e294d;border-radius:12px;padding:1.25rem;margin-bottom:1rem}
    pre{background:#0f1530;border:1px solid #33406b;border-radius:8px;padding:1rem;white-space:pre-wrap}
    .mono{font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono","Courier New",monospace}
    a{color:#9dd1ff}
    .muted{color:#a9b7d9}
    nav{margin-bottom:1rem}
  </style>
</head>
<body>
  <div class="container">
    <h1>🩺 Diagnostic serveur</h1>
    <nav class="muted">⇦ <a href="/admin/">Retour OTP</a></nav>
    <div class="card">
      <p>Cette page collecte l'état réseau (IPv6, NDP proxy, WireGuard, routes) via un utilitaire root contrôlé.<br>
      Pour des raisons de sécurité, seules des commandes en lecture sont exécutées.</p>
    </div>
    <?php
      $cmd = 'sudo /usr/local/sbin/boxion-diag 2>&1';
      $out = shell_exec($cmd);
      if ($out === null) {
        echo '<div class="card"><strong>Erreur</strong><br><pre class="mono">Impossible d\'exécuter le diagnostic. Vérifiez sudoers pour www-data.</pre></div>';
      } else {
        // Découpe par sections "=== NAME ==="
        $sections = preg_split('/^=== (.+) ===$/m', $out, -1, PREG_SPLIT_DELIM_CAPTURE);
        if ($sections && count($sections) > 1) {
          for ($i = 1; $i < count($sections); $i += 2) {
            $title = trim($sections[$i]);
            $body = $sections[$i+1] ?? '';
            echo '<div class="card">';
            echo '<h3>'.htmlspecialchars($title).'</h3>';
            echo '<pre class="mono">'.htmlspecialchars(trim($body))."</pre>";
            echo '</div>';
          }
        } else {
          echo '<div class="card"><h3>Sortie</h3><pre class="mono">'.htmlspecialchars($out).'</pre></div>';
        }
      }
    ?>
  </div>
</body>
</html>
