#!/usr/bin/env bash
set -euo pipefail

SMTP_ENV="/etc/boxion/smtp.env"
mkdir -p /etc/boxion /var/lib/boxion /etc/postfix/sasl

rand() { tr -dc A-Za-z0-9 </dev/urandom | head -c "${1:-24}"; echo; }

get_kv(){ local k="$1"; [ -f "$SMTP_ENV" ] && awk -F= -v k="$k" '$1==k{print $2}' "$SMTP_ENV" | tail -n1 || true; }
set_kv(){ local k="$1" v="$2"; touch "$SMTP_ENV"; if grep -q "^${k}=" "$SMTP_ENV" 2>/dev/null; then sed -i "s|^${k}=.*$|${k}=${v}|" "$SMTP_ENV"; else echo "${k}=${v}" >> "$SMTP_ENV"; fi }

IN_USER="$(get_kv SMTP_INBOUND_USER || true)"
IN_PASS="$(get_kv SMTP_INBOUND_PASS || true)"
RELAY_HOST="$(get_kv RELAY_HOST || true)"
RELAY_PORT="$(get_kv RELAY_PORT || true)"
RELAY_USER="$(get_kv RELAY_USER || true)"
RELAY_PASS="$(get_kv RELAY_PASS || true)"

if [[ -z "${IN_USER}" ]]; then IN_USER="boxion"; set_kv SMTP_INBOUND_USER "$IN_USER"; fi
if [[ -z "${IN_PASS}" ]]; then IN_PASS="$(rand 28)"; set_kv SMTP_INBOUND_PASS "$IN_PASS"; fi

# Setup SASL (sasldb) for inbound auth on submission
cat >/etc/postfix/sasl/smtpd.conf <<EOF
pwcheck_method: auxprop
auxprop_plugin: sasldb
mech_list: PLAIN LOGIN
EOF

echo "$IN_PASS" | saslpasswd2 -c -p -f /etc/sasldb2 "$IN_USER"
chown root:postfix /etc/sasldb2 || true
chmod 640 /etc/sasldb2 || true

# Generate self-signed cert for STARTTLS if not present
if [[ ! -f /etc/ssl/certs/boxion-smtp.pem || ! -f /etc/ssl/private/boxion-smtp.key ]]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout /etc/ssl/private/boxion-smtp.key \
    -out /etc/ssl/certs/boxion-smtp.pem \
    -subj "/CN=boxion-smtp"
  chmod 600 /etc/ssl/private/boxion-smtp.key
fi

# Base Postfix config
postconf -e 'smtpd_banner = $myhostname ESMTP Boxion' \
            'biff = no' \
            'append_dot_mydomain = no' \
            'readme_directory = no' \
            'compatibility_level = 3.6' \
            'myhostname = boxion-smtp.local' \
            'myorigin = $myhostname' \
            'mydestination = ' \
            'inet_interfaces = all' \
            'inet_protocols = all' \
            'mynetworks = ' \
            'relay_domains = *' \
            'smtp_tls_security_level = may' \
            'smtpd_tls_security_level = may' \
            'smtpd_tls_cert_file = /etc/ssl/certs/boxion-smtp.pem' \
            'smtpd_tls_key_file = /etc/ssl/private/boxion-smtp.key' \
            'smtpd_sasl_auth_enable = yes' \
            'smtpd_sasl_type = cyrus' \
            'smtpd_sasl_path = smtpd' \
            'smtpd_sasl_security_options = noanonymous' \
            'smtpd_recipient_restrictions = permit_sasl_authenticated,reject' \
            'smtpd_relay_restrictions = permit_sasl_authenticated,reject' \
            'smtp_tls_loglevel = 1'

# Upstream relay (if configured)
if [[ -n "${RELAY_HOST}" && -n "${RELAY_PORT}" ]]; then
  echo "[${RELAY_HOST}]:${RELAY_PORT} ${RELAY_USER}:${RELAY_PASS}" > /etc/postfix/sasl_passwd
  postmap hash:/etc/postfix/sasl_passwd
  chmod 600 /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db
  postconf -e "relayhost = [${RELAY_HOST}]:${RELAY_PORT}" \
            'smtp_sasl_auth_enable = yes' \
            'smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd' \
            'smtp_sasl_security_options = noanonymous' \
            'smtp_sasl_tls_security_options = noanonymous' \
            'smtp_use_tls = yes'
else
  postconf -e 'relayhost = '
fi

# Enable submission (587) and alternative (2525)
postconf -M submission/inet='submission inet n - y - - smtpd'
postconf -P 'submission/inet/smtpd_tls_security_level=may'
postconf -P 'submission/inet/smtpd_sasl_auth_enable=yes'
postconf -P 'submission/inet/smtpd_client_restrictions=permit_sasl_authenticated,reject'
postconf -M 2525/inet='2525 inet n - y - - smtpd'
postconf -P '2525/inet/smtpd_tls_security_level=may'
postconf -P '2525/inet/smtpd_sasl_auth_enable=yes'
postconf -P '2525/inet/smtpd_client_restrictions=permit_sasl_authenticated,reject'

# Log a short summary for the operator
echo "[smtp] Inbound credentials: user=${IN_USER} pass=${IN_PASS}" >&2
if [[ -n "${RELAY_HOST}" ]]; then
  echo "[smtp] Upstream relay: ${RELAY_HOST}:${RELAY_PORT} as ${RELAY_USER}" >&2
else
  echo "[smtp] No upstream relay configured yet." >&2
fi

service rsyslog start || true
exec /usr/sbin/postfix -c /etc/postfix start-fg
