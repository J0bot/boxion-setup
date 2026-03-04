# syntax=docker/dockerfile:1
FROM node:18-alpine AS ui-builder
WORKDIR /app
COPY admin-ui/package.json ./
# Install deps (no lockfile for now)
RUN npm install --silent
COPY admin-ui/ .
RUN npm run build

FROM php:8.3-fpm-alpine

# Install nginx, tools, sudo, docker-cli, sqlite, apache2-utils (htpasswd)
RUN apk add --no-cache nginx bash tzdata curl sudo docker-cli sqlite sqlite-libs sqlite-dev apache2-utils $PHPIZE_DEPS && \
    docker-php-ext-install opcache pdo_sqlite && \
    apk del --no-cache $PHPIZE_DEPS sqlite-dev && \
    mkdir -p /run/nginx /var/log/nginx /etc/nginx/conf.d

# Create directories used by the app
RUN mkdir -p /etc/boxion /var/lib/boxion

WORKDIR /var/www/boxion

# Nginx config
COPY nginx.conf /etc/nginx/nginx.conf
COPY conf.d/ /etc/nginx/conf.d/

# Entrypoint to run php-fpm + nginx
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Wrapper scripts to control net container
COPY boxion-diag-wrapper /usr/local/sbin/boxion-diag
COPY boxion-wg-apply-wrapper /usr/local/sbin/boxion-wg-apply
COPY boxion-he-apply-wrapper /usr/local/sbin/boxion-he-apply
COPY boxion-proxy-add-wrapper /usr/local/sbin/boxion-proxy-add
COPY boxion-proxy-remove-wrapper /usr/local/sbin/boxion-proxy-remove
COPY boxion-proxy-reload-wrapper /usr/local/sbin/boxion-proxy-reload
COPY boxion-smtp-apply-wrapper /usr/local/sbin/boxion-smtp-apply
RUN chmod 755 /usr/local/sbin/boxion-diag /usr/local/sbin/boxion-wg-apply /usr/local/sbin/boxion-he-apply \
    /usr/local/sbin/boxion-proxy-add /usr/local/sbin/boxion-proxy-remove \
    /usr/local/sbin/boxion-proxy-reload /usr/local/sbin/boxion-smtp-apply && \
    echo "www-data ALL=(root) NOPASSWD: \
      /usr/local/sbin/boxion-diag, \
      /usr/local/sbin/boxion-wg-apply, \
      /usr/local/sbin/boxion-he-apply, \
      /usr/local/sbin/boxion-proxy-add, \
      /usr/local/sbin/boxion-proxy-remove, \
      /usr/local/sbin/boxion-proxy-reload, \
      /usr/local/sbin/boxion-smtp-apply" > /etc/sudoers.d/boxion && \
    chmod 440 /etc/sudoers.d/boxion

# Admin UI assets (built by ui-builder)
RUN mkdir -p /usr/share/boxion-admin
COPY --from=ui-builder /app/dist/ /usr/share/boxion-admin/

EXPOSE 8080
CMD ["/entrypoint.sh"]
