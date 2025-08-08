#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

API_DIR="/var/www/boxion-api"
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

sed -e "s|\${SERVER_NAME}|$server_name|g" \
    -e "s|\${API_DIR}|$API_DIR|g" \
    -e "s|\${PHP_FPM_SOCK}|$php_fpm_sock|g" \
    "$REPO_DIR/server/nginx/boxion-api.conf.tmpl" > /etc/nginx/sites-available/boxion-api

ln -sf /etc/nginx/sites-available/boxion-api /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Rate limit zone in http{} context
install -m 0644 "$REPO_DIR/server/nginx/boxion-rate.conf" /etc/nginx/conf.d/boxion-rate.conf

touch /etc/nginx/.htpasswd-boxion || true

nginx -t && systemctl reload nginx

log_success "Nginx configuré"
