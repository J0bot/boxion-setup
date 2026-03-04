# syntax=docker/dockerfile:1
FROM nginx:stable-alpine

# Minimal Nginx tuned for Boxion L4+L7 proxy
# - stream {} for TLS SNI passthrough on 443
# - http {} for Host header proxy on 80

RUN mkdir -p /etc/nginx/boxion /etc/nginx/conf.d

# Provide a clean nginx.conf that includes stream + http contexts
COPY nginx.conf /etc/nginx/nginx.conf

# Ensure log dirs exist
RUN mkdir -p /var/log/nginx && \
    touch /var/log/nginx/access.log /var/log/nginx/error.log

# No EXPOSE needed when using host network, but harmless
EXPOSE 80 443

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s CMD nginx -t || exit 1
