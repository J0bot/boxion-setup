#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}" 1>&2; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "Ce script doit être exécuté en tant que root"; exit 1;
  fi
}

ensure_dir() { mkdir -p "$1"; }

ENV_FILE="/etc/boxion/boxion.env"

set_env_var() {
  local key="$1" val="$2"
  ensure_dir "$(dirname "$ENV_FILE")"
  touch "$ENV_FILE"
  # Protéger le fichier tout en permettant la lecture par www-data (PHP)
  chown root:www-data "$ENV_FILE" 2>/dev/null || true
  chmod 640 "$ENV_FILE" 2>/dev/null || true
  if grep -qE "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${val}|g" "$ENV_FILE"
  else
    echo "${key}=${val}" >> "$ENV_FILE"
  fi
}

get_env_var() {
  local key="$1"
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    eval "echo \"\${$key:-}\""
  fi
}
