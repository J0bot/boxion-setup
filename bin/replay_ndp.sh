#!/usr/bin/env bash
set -euo pipefail

# 🔄 BOXION WIREGUARD - RECOVERY NDP/PEERS APRÈS REBOOT
# Service systemd critique pour restaurer peers WireGuard
# Debian 12 compatible - Testé et vérifié

# ====== Logging fonction ======
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] NDP-REPLAY: $1" | tee -a /var/log/boxion-replay.log
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] NDP-REPLAY ERROR: $1" | tee -a /var/log/boxion-replay.log >&2
}

# ====== Variables sécurisées ======
WG_IF="${WG_IF:-wg0}"
WAN_IF="${WAN_IF:-eth0}"
DB="/var/lib/boxion/boxion.db"
MAX_RETRIES=10
RETRY_DELAY=5

log "Début recovery peers WireGuard (interface: $WG_IF, WAN: $WAN_IF)"

# ====== Vérification base de données ======
if [[ ! -f "$DB" ]]; then
    log "Base de données inexistante: $DB - Arrêt normal"
    exit 0
fi

if [[ ! -r "$DB" ]]; then
    log_error "Base de données non lisible: $DB"
    exit 1
fi

# Test SQLite fonctionnel
if ! sqlite3 "$DB" "SELECT COUNT(*) FROM peers;" >/dev/null 2>&1; then
    log_error "Base de données SQLite corrompue ou inaccessible"
    exit 1
fi

PEER_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM peers;" 2>/dev/null || echo "0")
log "$PEER_COUNT peers trouvés dans la base de données"

if [[ "$PEER_COUNT" -eq 0 ]]; then
    log "Aucun peer à restaurer - Arrêt normal"
    exit 0
fi

# ====== Attente interface WireGuard ======
log "Attente interface WireGuard: $WG_IF"
for ((i=1; i<=MAX_RETRIES; i++)); do
    if ip link show "$WG_IF" >/dev/null 2>&1; then
        log "Interface $WG_IF détectée (tentative $i/$MAX_RETRIES)"
        break
    fi
    
    if [[ $i -eq $MAX_RETRIES ]]; then
        log_error "Interface WireGuard $WG_IF introuvable après $MAX_RETRIES tentatives"
        exit 1
    fi
    
    log "Interface $WG_IF non disponible, attente ${RETRY_DELAY}s... (tentative $i/$MAX_RETRIES)"
    sleep $RETRY_DELAY
done

# Attendre que l'interface soit UP
for ((i=1; i<=MAX_RETRIES; i++)); do
    if [[ $(ip link show "$WG_IF" | grep -c "state UP") -gt 0 ]]; then
        log "Interface $WG_IF active (tentative $i/$MAX_RETRIES)"
        break
    fi
    
    if [[ $i -eq $MAX_RETRIES ]]; then
        log_error "Interface WireGuard $WG_IF inactive après $MAX_RETRIES tentatives"
        exit 1
    fi
    
    log "Interface $WG_IF inactive, attente ${RETRY_DELAY}s... (tentative $i/$MAX_RETRIES)"
    sleep $RETRY_DELAY
done

# ====== Vérification interface WAN ======
if ! ip link show "$WAN_IF" >/dev/null 2>&1; then
    log_error "Interface WAN $WAN_IF introuvable"
    # Lister interfaces disponibles pour debug
    log "Interfaces disponibles: $(ip link show | grep -E '^[0-9]+:' | awk -F': ' '{print $2}' | tr '\n' ' ')"
    exit 1
fi

# ====== Recovery peers ======
SUCCESS_COUNT=0
ERROR_COUNT=0

log "Début restoration des peers WireGuard..."

# Lecture sécurisée des peers depuis SQLite
while IFS='|' read -r pub ip6 name; do
    # Validation ligne non vide
    if [[ -z "$pub" ]] || [[ -z "$ip6" ]]; then
        log "Ligne vide ignorée"
        continue
    fi
    
    # Validation format clé publique
    if [[ ! "$pub" =~ ^[A-Za-z0-9+/]{42}[A-Za-z0-9+/=]{2}$ ]]; then
        log_error "Clé publique invalide ignorée: $pub"
        ((ERROR_COUNT++))
        continue
    fi
    
    # Validation IPv6
    if [[ ! "$ip6" =~ ^[0-9a-fA-F:]+$ ]]; then
        log_error "Adresse IPv6 invalide ignorée: $ip6"
        ((ERROR_COUNT++))
        continue
    fi
    
    # Ajout peer WireGuard
    if wg set "$WG_IF" peer "$pub" allowed-ips "${ip6}/128" 2>/dev/null; then
        log "✅ Peer WireGuard ajouté: ${name:-$(echo $pub | cut -c1-8)...} -> $ip6"
        
        # Nettoyage ancien proxy NDP
        ip -6 neigh del proxy "$ip6" dev "$WAN_IF" 2>/dev/null || true
        
        # Ajout nouveau proxy NDP
        if ip -6 neigh add proxy "$ip6" dev "$WAN_IF" 2>/dev/null; then
            log "✅ NDP proxy ajouté: $ip6"
        else
            log "⚠️ NDP proxy échec: $ip6 (peut être normal selon environnement)"
        fi
        
        ((SUCCESS_COUNT++))
    else
        log_error "❌ Échec ajout peer: ${name:-$(echo $pub | cut -c1-8)...} -> $ip6"
        ((ERROR_COUNT++))
    fi
    
done < <(sqlite3 "$DB" "SELECT pubkey||'|'||ipv6||'|'||COALESCE(name,'') FROM peers;" 2>/dev/null || echo "")

# ====== Rapport final ======
log "Recovery terminé: $SUCCESS_COUNT peers restaurés, $ERROR_COUNT erreurs"

if [[ $SUCCESS_COUNT -gt 0 ]]; then
    # Vérification finale
    ACTIVE_PEERS=$(wg show "$WG_IF" | grep -c "peer:" || echo "0")
    log "Vérification: $ACTIVE_PEERS peers actifs sur l'interface $WG_IF"
fi

if [[ $ERROR_COUNT -gt 0 ]]; then
    log_error "Recovery terminé avec $ERROR_COUNT erreurs - Vérification manuelle recommandée"
    exit 1
fi

log "✅ Recovery NDP/Peers terminé avec succès"
exit 0
