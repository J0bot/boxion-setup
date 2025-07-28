#!/usr/bin/env bash
set -euo pipefail

# 🚀 BOXION VPN SERVER - WRAPPER MODULAIRE
# Ce script est un simple wrapper vers l'architecture modulaire
# Il assure la compatibilité avec les anciens appels mais utilise les modules

echo "🚀 Boxion VPN Server - Architecture Modulaire"
echo "============================================="
echo ""
echo "📢 MIGRATION: Ce script utilise maintenant l'architecture modulaire !"
echo "📂 Modules: /modules/ + /install/provisioner.sh"
echo ""

# Vérifier que l'architecture modulaire existe
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVISIONER="$SCRIPT_DIR/install/provisioner.sh"

if [[ ! -f "$PROVISIONER" ]]; then
    echo "❌ ERREUR: Architecture modulaire non trouvée !"
    echo "💡 Fichier manquant: $PROVISIONER"
    echo "💡 Utilisez le repository complet avec les modules"
    exit 1
fi

echo "✅ Architecture modulaire détectée"
echo "⚙️  Redirection vers: $PROVISIONER"
echo ""

# Rediriger tous les arguments vers le provisioner modulaire
exec "$PROVISIONER" "$@"
