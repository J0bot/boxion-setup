# syntax=docker/dockerfile:1
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install networking tools: wireguard, ndppd, iproute2, iptables, curl, bash, sudo
RUN apt-get update -y \
 && apt-get install -y --no-install-recommends \
    iproute2 iptables ndppd wireguard-tools ca-certificates \
    curl bash sudo procps jq util-linux sqlite3 \
 && rm -rf /var/lib/apt/lists/*

# Directories that will be bound as volumes by docker-compose
RUN mkdir -p /etc/boxion /etc/wireguard /var/lib/boxion /opt/boxion

# Copy templates and scripts
COPY docker/net/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/net/boxion-diag /usr/local/sbin/boxion-diag
COPY docker/net/boxion-wg-apply /usr/local/sbin/boxion-wg-apply
COPY docker/net/boxion-he-apply /usr/local/sbin/boxion-he-apply
COPY server/wireguard/wg0.conf.tmpl /opt/boxion/wg0.conf.tmpl
COPY server/system/ndppd.conf.tmpl /opt/boxion/ndppd.conf.tmpl

RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/sbin/boxion-diag /usr/local/sbin/boxion-wg-apply /usr/local/sbin/boxion-he-apply

# Default command: bring up wg0, start ndppd in foreground
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
