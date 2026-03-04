#!/usr/bin/env sh
set -e

# Ensure base dirs
mkdir -p /etc/boxion /var/lib/boxion

# Load or create env
ENV_FILE="/etc/boxion/boxion.env"
if [ ! -f "$ENV_FILE" ]; then
  touch "$ENV_FILE"
fi

get_env() {
  key="$1"
  if [ -f "$ENV_FILE" ]; then
    grep -E "^${key}=" "$ENV_FILE" | sed -e "s/^${key}=//" | tail -n1
  fi
}

set_env() {
  key="$1"; val="$2"
  if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
    sed -i "s|^${key}=.*$|${key}=${val}|" "$ENV_FILE"
  else
    echo "${key}=${val}" >> "$ENV_FILE"
  fi
}

# Default DB path
DB_PATH="$(get_env DB_PATH)"
if [ -z "$DB_PATH" ]; then
  DB_PATH="/var/lib/boxion/peers.db"
  set_env DB_PATH "$DB_PATH"
fi
DB_DIR="$(dirname "$DB_PATH")"
mkdir -p "$DB_DIR"

# Initialize DB schema if missing
if [ ! -f "$DB_PATH" ]; then
  echo "[api-entrypoint] Initializing SQLite schema at $DB_PATH"
  sqlite3 "$DB_PATH" <<'SQL'
CREATE TABLE IF NOT EXISTS peers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  public_key TEXT UNIQUE NOT NULL,
  ipv6_address TEXT UNIQUE NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  last_seen DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_peers_public_key ON peers(public_key);
CREATE INDEX IF NOT EXISTS idx_peers_ipv6 ON peers(ipv6_address);

CREATE TABLE IF NOT EXISTS otps (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  token TEXT UNIQUE NOT NULL,
  expires_at DATETIME NOT NULL,
  used INTEGER DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  created_by TEXT
);
CREATE INDEX IF NOT EXISTS idx_otps_token ON otps(token);
SQL
fi

# Ownership and permissions (match legacy installer)
chown -R www-data:www-data "$DB_DIR"
chmod 750 "$DB_DIR"
chmod 640 "$DB_PATH" 2>/dev/null || true

# Generate API token if missing
API_TOKEN="$(get_env API_TOKEN)"
if [ -z "$API_TOKEN" ]; then
  API_TOKEN=$(php -r 'echo bin2hex(random_bytes(32));')
  set_env API_TOKEN "$API_TOKEN"
fi

# Ensure HTTP Basic Auth for /admin
HTPASS_FILE="/etc/nginx/.htpasswd-boxion"
ADMIN_USER="$(get_env ADMIN_USER)"
ADMIN_PASS="$(get_env ADMIN_PASS)"
if [ ! -f "$HTPASS_FILE" ]; then
  # If not preset via env file, generate strong randoms
  if [ -z "$ADMIN_USER" ]; then ADMIN_USER="admin"; set_env ADMIN_USER "$ADMIN_USER"; fi
  if [ -z "$ADMIN_PASS" ]; then ADMIN_PASS="$(php -r 'echo bin2hex(random_bytes(8));')"; set_env ADMIN_PASS "$ADMIN_PASS"; fi
  # Create htpasswd
  htpasswd -bc "$HTPASS_FILE" "$ADMIN_USER" "$ADMIN_PASS"
  chmod 640 "$HTPASS_FILE" || true
fi

# Print a startup summary
echo "[api-entrypoint] Boxion API is starting…" >&2
echo "[api-entrypoint] Admin UI Basic Auth: user=${ADMIN_USER:-$(get_env ADMIN_USER)}" >&2
if [ -n "${ADMIN_PASS}" ]; then echo "[api-entrypoint] Admin UI Basic Auth password: $ADMIN_PASS" >&2; fi
echo "[api-entrypoint] API Bearer token: $API_TOKEN" >&2

# If SMTP env exists, surface inbound credentials for convenience
if [ -f "/etc/boxion/smtp.env" ]; then
  SMTP_USER="$(grep -E '^SMTP_INBOUND_USER=' /etc/boxion/smtp.env | sed 's/^SMTP_INBOUND_USER=//')"
  SMTP_PASS="$(grep -E '^SMTP_INBOUND_PASS=' /etc/boxion/smtp.env | sed 's/^SMTP_INBOUND_PASS=//')"
  if [ -n "$SMTP_USER" ] && [ -n "$SMTP_PASS" ]; then
    echo "[api-entrypoint] SMTP inbound credentials: user=$SMTP_USER pass=$SMTP_PASS" >&2
  fi
fi

# Start PHP-FPM (daemonized)
php-fpm -D

# Start Nginx in foreground
exec nginx -g 'daemon off;'
