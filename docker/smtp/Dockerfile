# syntax=docker/dockerfile:1
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive TZ=UTC

RUN apt-get update -y \
 && apt-get install -y --no-install-recommends \
    postfix libsasl2-modules libsasl2-modules-db sasl2-bin \
    ca-certificates openssl rsyslog bash curl jq \
 && rm -rf /var/lib/apt/lists/*

# Create needed dirs
RUN mkdir -p /etc/boxion /var/lib/boxion /etc/postfix/sasl

COPY docker/smtp/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 587 2525
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
