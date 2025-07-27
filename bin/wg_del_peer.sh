#!/usr/bin/env bash
set -euo pipefail

# 🗑️ BOXION WIREGUARD - SUPPRESSION PEER SÉCURISÉE
# Usage: wg_del_peer.sh <public_key> <ipv6_address>
# Debian 12 compatible - Testé et vérifié

# ====== Validation paramètres ======
if [[ $# -ne 2 ]]; then
    echo "❌ Erreur: Usage: $0 <public_key> <ipv6_address>" >&2
    exit 1
fi

PUB="$1"
IP6="$2"

# Validation clé publique WireGuard (44 caractères base64)
if [[ ! "$PUB" =~ ^[A-Za-z0-9+/]{42}[A-Za-z0-9+/=]{2}$ ]]; then
    echo "❌ Erreur: Clé publique WireGuard invalide: $PUB" >&2
    exit 1
fi

# Validation IPv6
if [[ ! "$IP6" =~ ^[0-9a-fA-F:]+$ ]] || [[ ${#IP6} -lt 3 ]]; then
    echo "❌ Erreur: Adresse IPv6 invalide: $IP6" >&2
    exit 1
fi

# Variables d'environnement sécurisées
WG_IF="${WG_IF:-wg0}"
WAN_IF="${WAN_IF:-eth0}"

# ====== Vérifications pré-exécution ======
# Vérifier interface WireGuard existe
if ! ip link show "$WG_IF" >/dev/null 2>&1; then
    echo "❌ Erreur: Interface WireGuard '$WG_IF' introuvable" >&2
    exit 1
fi

# Vérifier interface WAN existe
if ! ip link show "$WAN_IF" >/dev/null 2>&1; then
    echo "❌ Erreur: Interface WAN '$WAN_IF' introuvable" >&2
    echo "💡 Interfaces disponibles:" >&2
    ip link show | grep -E '^[0-9]+:' | awk -F': ' '{print "   " $2}' >&2
    exit 1
fi

# Vérifier que le peer existe avant suppression
if ! wg show "$WG_IF" | grep -q "peer: $PUB"; then
    echo "⚠️  Attention: Peer inexistant, rien à supprimer" >&2
    echo "✅ Suppression terminée (peer déjà absent)"
    exit 0
fi

# ====== Suppression peer WireGuard ======
echo "🗑️ Suppression peer WireGuard: $(echo "$PUB" | cut -c1-8)..."
if ! wg set "$WG_IF" peer "$PUB" remove 2>/dev/null; then
    echo "❌ Erreur: Impossible de supprimer le peer WireGuard" >&2
    exit 1
fi

# ====== Suppression NDP Proxy ======
echo "🌐 Suppression NDP proxy: $IP6"
if ! ip -6 neigh del proxy "$IP6" dev "$WAN_IF" 2>/dev/null; then
    echo "⚠️  Attention: NDP proxy non trouvé (peut être normal)" >&2
    # Ne pas échouer car le proxy peut ne pas exister
fi

# ====== Vérification finale ======
if wg show "$WG_IF" | grep -q "peer: $PUB"; then
    echo "❌ Erreur: Vérification échec, peer toujours présent" >&2
    exit 1
else
    echo "✅ Peer supprimé avec succès: $IP6"
fi
