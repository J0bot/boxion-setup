<?php
// Admin Probe (protected by Nginx Basic Auth)
?><!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Boxion Admin - Probe</title>
  <style>
    body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,"Helvetica Neue",Arial,sans-serif;margin:2rem;background:#0b1020;color:#e9eef7}
    .container{max-width:1000px;margin:0 auto}
    .card{background:#121a33;border:1px solid #1e294d;border-radius:12px;padding:1.25rem;margin-bottom:1rem}
    input,button{font:inherit;padding:.6rem .8rem;border-radius:8px;border:1px solid #33406b;background:#0f1530;color:#e9eef7}
    button{background:#3b82f6;border-color:#3b82f6;cursor:pointer}
    button:hover{background:#2563eb}
    pre{background:#0f1530;border:1px solid #33406b;border-radius:8px;padding:1rem;white-space:pre-wrap}
    .mono{font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono","Courier New",monospace}
    a{color:#9dd1ff}
  </style>
</head>
  <body>
    <div class="container">
      <h1>🔎 Probe réseau (HTTP/ICMP v6)</h1>
      <p><a href="/admin/">⇦ Retour OTP</a> · <a href="/admin/status.php">Diagnostic</a></p>
      <div class="card">
        <form method="get">
          <label for="host">Hôte (IPv6 ou domaine)</label>
          <input id="host" name="host" placeholder="ex: 2001:db8::1 ou box1.milkywayhub.org" value="<?= htmlspecialchars($_GET['host'] ?? '') ?>" />
          <button type="submit">Tester</button>
        </form>
      </div>
      <?php
        $host = trim($_GET['host'] ?? '');
        if ($host !== '') {
          // sanitation: only allow IPv6 chars and domain-safe chars
          if (!preg_match('/^([0-9a-fA-F:.]+|[A-Za-z0-9.-]+)$/', $host)) {
            echo '<div class="card"><strong>Erreur</strong><br><pre class="mono">Hôte invalide.</pre></div>';
          } else {
            // helpers
            $is_ipv6_literal = (strpos($host, ':') !== false) && (strpos($host, '[') === false) && (strpos($host, ']') === false);
            $curl_host = $is_ipv6_literal ? ('['.$host.']') : $host;

            $esc = escapeshellarg($host);
            $out = [];
            // DNS AAAA (fallback to getent if dig is missing)
            $has_dig = trim(shell_exec('command -v dig 2>/dev/null')) !== '';
            if ($has_dig) {
              $out[] = "=== DIG AAAA ===\n" . shell_exec("dig +short AAAA $esc 2>&1");
            } else {
              $out[] = "=== AAAA (getent) ===\n" . shell_exec("getent ahostsv6 $esc 2>&1");
            }

            // ICMPv6 ping
            $out[] = "=== PING6 (1) ===\n" . shell_exec("ping6 -c 1 -w 3 $esc 2>&1");

            // HTTP/HTTPS over IPv6 with proper bracketization for IPv6 literals
            $esc_curl = escapeshellarg($curl_host);
            $out[] = "=== CURL -6 HTTP ===\n" . shell_exec("curl -6 -I -m 5 http://$esc_curl 2>&1");
            $out[] = "=== CURL -6 HTTPS ===\n" . shell_exec("curl -6 -I -m 5 https://$esc_curl 2>&1");

            echo '<div class="card"><h3>Résultats</h3><pre class="mono">' . htmlspecialchars(implode("\n\n", $out)) . '</pre></div>';
          }
        }
      ?>
    </div>
  </body>
</html>
