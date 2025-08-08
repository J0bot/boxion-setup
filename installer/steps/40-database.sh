#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

DB_DIR="/var/lib/boxion"
DB_PATH="$DB_DIR/peers.db"
ensure_dir "$DB_DIR"

log_info "Création/upgrade base SQLite..."
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

chown -R www-data:www-data "$DB_DIR"
chmod 750 "$DB_DIR"
chmod 640 "$DB_PATH"

set_env_var DB_PATH "$DB_PATH"

log_success "Base de données OK"
