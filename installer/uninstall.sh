#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMMON_SH="$SCRIPT_DIR/lib/common.sh"

# Minimal logging if common.sh not present
if [[ -f "$COMMON_SH" ]]; then
  # shellcheck disable=SC1090
  source "$COMMON_SH"
else
  log_info(){ echo "[i] $*"; }
  log_success(){ echo "[+] $*"; }
  log_warning(){ echo "[!] $*"; }
  log_error(){ echo "[-] $*" 1>&2; }
fi

if [[ $EUID -ne 0 ]]; then
  log_error "Ce script doit être exécuté en root"; exit 1;
fi

log_info "Arrêt des services Boxion..."
systemctl disable --now he6in4 >/dev/null 2>&1 || true
systemctl disable --now wg-quick@wg0 >/dev/null 2>&1 || true
systemctl disable --now ndppd >/dev/null 2>&1 || true

log_info "Nettoyage du tunnel he-ipv6..."
# Supprimer route par défaut via he-ipv6 si laissée
ip -6 route del default dev he-ipv6 2>/dev/null || true
ip link set he-ipv6 down 2>/dev/null || true
ip tunnel del he-ipv6 2>/dev/null || true

log_info "Suppression des fichiers système..."
rm -f /etc/systemd/system/he6in4.service
rm -f /etc/sysctl.d/99-boxion.conf
rm -f /etc/sudoers.d/boxion-wg /etc/sudoers.d/boxion-diag
rm -f /usr/local/sbin/boxion-wg-apply /usr/local/sbin/boxion-diag

log_info "Nettoyage WireGuard..."
rm -f /etc/wireguard/wg0.conf

log_info "Nettoyage Nginx..."
rm -f /etc/nginx/sites-enabled/boxion-api /etc/nginx/sites-available/boxion-api
rm -f /etc/nginx/conf.d/boxion-rate.conf
rm -f /etc/nginx/.htpasswd-boxion

log_info "Nettoyage API/WWW..."
rm -rf /var/www/boxion-api

log_info "Nettoyage données/ENV..."
rm -f /etc/boxion/he6in4.env
rm -f /etc/boxion/boxion.env /etc/boxion/admin-password.txt
rm -f /var/lib/boxion/peers.db

log_info "Nettoyage firewall proto 41 (si iptables présent)..."
if command -v iptables >/dev/null 2>&1; then
  # Essayer de retirer la règle si présente
  while iptables -C INPUT -p 41 -j ACCEPT >/dev/null 2>&1; do
    iptables -D INPUT -p 41 -j ACCEPT || true
  done
fi

log_info "Reload systemd/nginx..."
systemctl daemon-reload || true
if nginx -t >/dev/null 2>&1; then
  systemctl reload nginx || true
fi

log_success "Désinstallation Boxion terminée. Le système est nettoyé."
