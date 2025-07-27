#!/usr/bin/env bash
set -euo pipefail

# 🔐 BOXION WIREGUARD - AJOUT PEER SÉCURISÉ
# Usage: wg_add_peer.sh <public_key> <ipv6_address>
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
# Vérifier interface WireGuard existe et est active
if ! ip link show "$WG_IF" >/dev/null 2>&1; then
    echo "❌ Erreur: Interface WireGuard '$WG_IF' introuvable" >&2
    exit 1
fi

if [[ $(ip link show "$WG_IF" | grep -c "state UP") -eq 0 ]]; then
    echo "❌ Erreur: Interface WireGuard '$WG_IF' inactive" >&2
    exit 1
fi

# Vérifier interface WAN existe
if ! ip link show "$WAN_IF" >/dev/null 2>&1; then
    echo "❌ Erreur: Interface WAN '$WAN_IF' introuvable" >&2
    echo "💡 Interfaces disponibles:" >&2
    ip link show | grep -E '^[0-9]+:' | awk -F': ' '{print "   " $2}' >&2
    exit 1
fi

# Vérifier que le peer n'existe pas déjà
if wg show "$WG_IF" | grep -q "peer: $PUB"; then
    echo "⚠️  Attention: Peer déjà existant, mise à jour..." >&2
fi

# ====== Ajout peer WireGuard ======
echo "🔐 Ajout peer WireGuard: $(echo "$PUB" | cut -c1-8)..."
if ! wg set "$WG_IF" peer "$PUB" allowed-ips "${IP6}/128"; then
    echo "❌ Erreur: Impossible d'ajouter le peer WireGuard" >&2
    exit 1
fi

# ====== Configuration NDP Proxy ======
echo "🌐 Configuration NDP proxy: $IP6"
# Supprimer ancien proxy si existe
ip -6 neigh del proxy "$IP6" dev "$WAN_IF" 2>/dev/null || true

# Ajouter nouveau proxy
if ! ip -6 neigh add proxy "$IP6" dev "$WAN_IF" 2>/dev/null; then
    echo "⚠️  Attention: NDP proxy impossible (peut être normal selon config réseau)" >&2
    # Ne pas échouer car NDP proxy peut ne pas être nécessaire selon l'environnement
fi

# ====== Vérification finale ======
if wg show "$WG_IF" | grep -q "peer: $PUB"; then
    echo "✅ Peer ajouté avec succès: $IP6"
else
    echo "❌ Erreur: Vérification échec, peer non ajouté" >&2
    exit 1
fi
