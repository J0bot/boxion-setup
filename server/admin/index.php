<?php
// Admin OTP generator (protected by Nginx Basic Auth)
?><!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Boxion Admin - OTP</title>
<style>
body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,"Helvetica Neue",Arial,sans-serif;margin:2rem;background:#0b1020;color:#e9eef7}
.container{max-width:860px;margin:0 auto}
.card{background:#121a33;border:1px solid #1e294d;border-radius:12px;padding:1.25rem;margin-bottom:1rem}
label{display:block;margin:.5rem 0 .25rem;color:#a9b7d9}
input,select,button{font:inherit;padding:.6rem .8rem;border-radius:8px;border:1px solid #33406b;background:#0f1530;color:#e9eef7}
button{background:#3b82f6;border-color:#3b82f6;cursor:pointer}
button:hover{background:#2563eb}
code{background:#0f1530;border:1px solid #33406b;border-radius:6px;padding:.2rem .4rem}
.table{width:100%;border-collapse:collapse}
.table th,.table td{border-bottom:1px solid #1e294d;padding:.5rem .4rem;text-align:left;font-size:.95rem}
.mono{font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono","Courier New",monospace}
.badge{display:inline-block;padding:.1rem .5rem;border-radius:9999px;background:#1e294d;color:#a9b7d9;font-size:.8rem}
.footer{color:#a9b7d9;font-size:.9rem;margin-top:1rem}
</style>
</head>
<body>
<div class="container">
  <h1>🔐 Boxion Admin · OTP d'enrôlement</h1>
  <p>Générez des tokens à usage unique et durée limitée pour l'enrôlement des clients Boxion.</p>
  <div class="card">
    <form method="post">
      <div style="display:flex;gap:1rem;flex-wrap:wrap;align-items:end">
        <div>
          <label for="ttl">Durée de validité</label>
          <select id="ttl" name="ttl">
            <option value="5">5 minutes</option>
            <option value="10" selected>10 minutes</option>
            <option value="30">30 minutes</option>
            <option value="60">1 heure</option>
          </select>
        </div>
        <div>
          <label for="note">Note (facultatif)</label>
          <input id="note" name="note" placeholder="ex: boxion-atelier-1" />
        </div>
        <div>
          <button type="submit" name="action" value="create">Créer un OTP</button>
        </div>
      </div>
    </form>
    <?php
    function db() {
        $env = [];
        $envFile = '/etc/boxion/boxion.env';
        if (is_file($envFile)) {
            foreach (file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
                if (strpos($line, '=') !== false) { [$k,$v]=explode('=', $line, 2); $env[trim($k)] = trim($v); }
            }
        }
        $dbPath = $env['DB_PATH'] ?? '/var/lib/boxion/peers.db';
        $pdo = new PDO('sqlite:' . $dbPath);
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        return $pdo;
    }

    $createdToken = null; $createdExp = null;
    if (($_POST['action'] ?? '') === 'create') {
        $ttl = max(1, (int)($_POST['ttl'] ?? 10));
        $note = trim($_POST['note'] ?? '');
        try {
            $token = bin2hex(random_bytes(16));
            $exp = gmdate('Y-m-d H:i:s', time() + $ttl*60);
            $by = $_SERVER['PHP_AUTH_USER'] ?? 'admin';
            $pdo = db();
            $stmt = $pdo->prepare('INSERT INTO otps (token, expires_at, created_by) VALUES (?, ?, ?)');
            $stmt->execute([$token, $exp, $by]);
            $createdToken = $token; $createdExp = $exp;
        } catch (Exception $e) {
            echo '<p class="mono" style="color:#f88">Erreur: '.htmlspecialchars($e->getMessage()).'</p>';
        }
    }

    if ($createdToken) {
        echo '<div class="card"><strong>NOUVEAU OTP</strong><br>';
        echo 'Token: <code class="mono">' . htmlspecialchars($createdToken) . '</code><br>';
        echo 'Expire (UTC): <code class="mono">' . htmlspecialchars($createdExp) . "</code><br>";
        echo '<div class="footer">Utilisez ce token comme Bearer pour appeler /api/ depuis le client (une seule fois).</div></div>';
    }
    ?>
  </div>

  <div class="card">
    <h3>OTP actifs</h3>
    <table class="table">
      <thead><tr><th>Token</th><th>Expire (UTC)</th><th>Créé par</th><th>Statut</th></tr></thead>
      <tbody>
      <?php
      try {
          $pdo = db();
          $q = $pdo->query("SELECT token, expires_at, created_by, used FROM otps WHERE expires_at > datetime('now') ORDER BY id DESC LIMIT 100");
          foreach ($q as $row) {
              $status = ((int)$row['used'] === 1) ? '<span class="badge">utilisé</span>' : '<span class="badge">valide</span>';
              echo '<tr>';
              echo '<td class="mono">' . htmlspecialchars($row['token']) . '</td>';
              echo '<td class="mono">' . htmlspecialchars($row['expires_at']) . '</td>';
              echo '<td>' . htmlspecialchars($row['created_by'] ?? 'admin') . '</td>';
              echo '<td>' . $status . '</td>';
              echo '</tr>';
          }
      } catch (Exception $e) {
          echo '<tr><td colspan="4" style="color:#f88" class="mono">Erreur DB: ' . htmlspecialchars($e->getMessage()) . '</td></tr>';
      }
      ?>
      </tbody>
    </table>
  </div>

  <div class="card">
    <h3>Diagnostic serveur</h3>
    <p>Consultez l'état IPv6, NDP proxy, WireGuard et Nginx.</p>
    <p><a href="/admin/status.php">🔎 Ouvrir le diagnostic</a></p>
  </div>

  <div class="card">
    <h3>Probe réseau</h3>
    <p>Testez un hôte (AAAA, ping6, HTTP/HTTPS en IPv6).</p>
    <p><a href="/admin/probe.php">🧪 Ouvrir la probe</a></p>
  </div>

  <div class="footer">Dashboard protégé par Basic Auth (admin). Accès API: <code class="mono">/api/</code></div>
</div>
</body>
</html>
