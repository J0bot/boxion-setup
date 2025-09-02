#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

API_DIR="${BOXION_API_DIR:-$REPO_DIR/server}"
server_name="${BOXION_DOMAIN:-_}"

# Détection socket PHP-FPM
php_fpm_sock=""
if [[ -S /run/php/php-fpm.sock ]]; then
  php_fpm_sock="/run/php/php-fpm.sock"
else
  php_version=$(php-fpm -v 2>/dev/null | awk '/PHP/{print $2}' | cut -d. -f1,2 || true)
  if [[ -n "$php_version" && -S "/run/php/php${php_version}-fpm.sock" ]]; then
    php_fpm_sock="/run/php/php${php_version}-fpm.sock"
  else
    php_fpm_sock="$(ls /run/php/php*-fpm.sock 2>/dev/null | head -n1 || true)"
  fi
fi
[[ -z "$php_fpm_sock" ]] && php_fpm_sock="/run/php/php-fpm.sock"

# Substitution du template
if command -v envsubst >/dev/null 2>&1; then
  # Préférer envsubst quand disponible
  export SERVER_NAME="$server_name"
  export API_DIR
  export PHP_FPM_SOCK="$php_fpm_sock"
  envsubst '${SERVER_NAME} ${API_DIR} ${PHP_FPM_SOCK}' \
    < "$REPO_DIR/server/nginx/boxion-api.conf.tmpl" \
    > /etc/nginx/sites-available/boxion-api
else
  # Fallback: sed avec échappement sûr
  server_name_esc=$(printf '%s' "$server_name" | sed -e 's/[\\\/&]/\\&/g')
  api_dir_esc=$(printf '%s' "$API_DIR" | sed -e 's/[\\\/&]/\\&/g')
  php_fpm_sock_esc=$(printf '%s' "$php_fpm_sock" | sed -e 's/[\\\/&]/\\&/g')
  sed -e "s|\\${SERVER_NAME}|$server_name_esc|g" \
      -e "s|\\${API_DIR}|$api_dir_esc|g" \
      -e "s|\\${PHP_FPM_SOCK}|$php_fpm_sock_esc|g" \
      "$REPO_DIR/server/nginx/boxion-api.conf.tmpl" > /etc/nginx/sites-available/boxion-api
fi

ln -sf /etc/nginx/sites-available/boxion-api /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Rate limit zone in http{} context
install -m 0644 "$REPO_DIR/server/nginx/boxion-rate.conf" /etc/nginx/conf.d/boxion-rate.conf

[[ -f /etc/nginx/.htpasswd-boxion ]] || touch /etc/nginx/.htpasswd-boxion

nginx -t && systemctl reload nginx

log_success "Nginx configuré"
