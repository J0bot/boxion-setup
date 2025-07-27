# 🚀 Plan de Refactorisation Modulaire - Boxion Setup

## 🎯 OBJECTIF
Refactoriser le monolithe `setup.sh` (977 lignes, 43KB) en modules distincts avec logging détaillé pour faciliter le debug et la maintenance.

## 🚨 PROBLÈMES ACTUELS IDENTIFIÉS

### ✅ API FONCTIONNELLE
- `https://tunnel.milkywayhub.org/api/` → `401 Unauthorized` (normal sans token)
- L'API répond correctement et rejette les requêtes non authentifiées

### ❌ ARCHITECTURE MONOLITHIQUE
- `setup.sh` = 977 lignes, tout mélangé
- Debug impossible, maintenance difficile
- Aucun logging modulaire
- Gestion d'erreur globale uniquement

## 🏗️ ARCHITECTURE ACTUELLE (Monolithe)

```
setup.sh (977 lignes) = TOUT MÉLANGÉ :
├── Paramètres + validation     (45 lignes)
├── Mode interactif            (37 lignes) 
├── Installation paquets       (38 lignes)
├── Config WireGuard          (103 lignes)
├── Création répertoires       (44 lignes)
├── Scripts bin/ (3x)         (151 lignes)
├── API PHP complète          (118 lignes)
├── Dashboard HTML complet    (297 lignes)
├── Authentification PHP       (89 lignes)
├── Configuration nginx        (55 lignes)
└── Affichage final            (40 lignes)
```

## 🎯 ARCHITECTURE CIBLE (Modulaire)

```
boxion-setup/
├── modules/
│   ├── api/
│   │   ├── api.php              # API REST séparée
│   │   ├── auth.php             # Authentification
│   │   └── install.sh           # Installation module API
│   ├── dashboard/
│   │   ├── admin/               # Dashboard admin
│   │   ├── public/              # Page publique
│   │   └── install.sh           # Installation module dashboard
│   ├── wireguard/
│   │   ├── config.sh            # Configuration WireGuard
│   │   ├── keys.sh              # Gestion clés
│   │   └── install.sh           # Installation module WG
│   ├── system/
│   │   ├── packages.sh          # Installation paquets
│   │   ├── sysctl.sh            # Configuration système
│   │   └── networking.sh        # Configuration réseau
│   └── logging/
│       ├── logger.sh            # Système de logs
│       └── debug.sh             # Outils de debug
├── install/
│   ├── provisioner.sh           # Orchestrateur principal
│   ├── validator.sh             # Tests et validations
│   └── rollback.sh              # Système de rollback
└── tests/
    ├── api_test.sh              # Tests API
    ├── dashboard_test.sh        # Tests dashboard
    └── integration_test.sh      # Tests intégration
```

## 📊 LOGGING MODULAIRE

### Niveaux de logs :
- `DEBUG` : Détails techniques complets
- `INFO` : Progression normale
- `WARN` : Avertissements non critiques
- `ERROR` : Erreurs critiques
- `FATAL` : Erreurs bloquantes

### Exemple de logging :
```bash
[2025-01-27 21:30:15] [WIREGUARD] [INFO] Configuration WireGuard démarrée
[2025-01-27 21:30:16] [WIREGUARD] [DEBUG] Génération clés : /etc/wireguard/server_private.key
[2025-01-27 21:30:17] [API] [INFO] Installation module API
[2025-01-27 21:30:18] [API] [ERROR] Erreur création /var/www/boxion-api/api/index.php
[2025-01-27 21:30:18] [SYSTEM] [FATAL] Installation interrompue - rollback
```

## 🔄 ÉTAPES DE MIGRATION

### PHASE 1 : Infrastructure
1. ✅ Créer structure modulaire
2. ⏳ Système de logging
3. ⏳ Orchestrateur principal
4. ⏳ Tests unitaires

### PHASE 2 : Modules Core  
1. ⏳ Module system (paquets, sysctl)
2. ⏳ Module wireguard
3. ⏳ Module API
4. ⏳ Module dashboard

### PHASE 3 : Tests & Validation
1. ⏳ Tests modulaires
2. ⏳ Tests d'intégration
3. ⏳ Système de rollback
4. ⏳ Documentation

## 🧪 TESTS SÉCURISÉS WSL

### ✅ AUTORISÉ :
- Tests en lecture seule
- Création de branches Git
- Tests modulaires isolés
- Validation syntaxique

### ❌ INTERDIT :
- Installation de packages système
- Modification services système
- Tests nécessitant sudo
- Modifications permanentes WSL

### 🔄 ROLLBACK PLAN :
```bash
# Revenir au main si problème
git checkout main
git branch -D refactor-modular

# Nettoyage complet si nécessaire  
git clean -fdx
git reset --hard HEAD
```

## 📋 CHECKLIST DE VALIDATION

### Module API :
- [ ] Séparation API/Auth/Install
- [ ] Logging détaillé à chaque étape
- [ ] Tests unitaires
- [ ] Validation syntaxe PHP
- [ ] Gestion d'erreur robuste

### Module Dashboard :
- [ ] Séparation Admin/Public/Install
- [ ] Templates statiques vs dynamiques
- [ ] Authentification modulaire
- [ ] Tests UI basiques

### Module WireGuard :
- [ ] Configuration séparée
- [ ] Gestion clés sécurisée
- [ ] Validation config
- [ ] Tests connectivité

### Module System :
- [ ] Installation paquets modulaire
- [ ] Configuration système séparée
- [ ] Validation prérequis
- [ ] Rollback automatique

## 🎯 RÉSULTATS ATTENDUS

### ✅ DEBUG FACILITÉ :
```bash
# Debug spécifique module API
./install/provisioner.sh --debug --module api

# Logs détaillés par composant
tail -f logs/api.log
tail -f logs/wireguard.log
```

### ✅ MAINTENANCE SIMPLIFIÉE :
- Modification d'un module sans impact autres
- Tests isolés par composant
- Rollback granulaire
- Documentation claire

### ✅ ROBUSTESSE ACCRUE :
- Validation à chaque étape
- Gestion d'erreur modulaire
- Recovery automatique
- Diagnostic précis

---

**🚀 READY TO START REFACTORING!**
