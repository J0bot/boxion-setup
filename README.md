# 🚀 Boxion VPN - Auto-hébergement Simple

**Exposez vos services maison sur Internet sans configuration réseau complexe**

[![Debian 12](https://img.shields.io/badge/Debian-12%20(Bookworm)-blue?logo=debian)](https://www.debian.org/)
[![WireGuard](https://img.shields.io/badge/WireGuard-Latest-green?logo=wireguard)](https://www.wireguard.com/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## 📊 Table des Matières

### 📱 **Pour les utilisateurs Boxion** (95%)
- [🎯 Quickstart : Connecter mon Boxion](#-quickstart--connecter-mon-boxion)
- [🔑 Comment obtenir un token ?](#-comment-obtenir-un-token-)
- [🔧 Installation détaillée](#-installation-détaillée)
- [🩺 Diagnostic et support](#-diagnostic-et-support)

### 🖥️ **Pour les hébergeurs VPS** (5%)
- [🌐 Déployer son service tunnel](#-déployer-son-service-tunnel)
- [🔑 Gérer les tokens d'accès](#-gérer-les-tokens-daccès)
- [🔧 Configuration DNS](#-configuration-dns)

### 📄 **Documentation technique**
- [🏗️ Architecture](#%EF%B8%8F-architecture)
- [🩺 Diagnostic & Maintenance](#-diagnostic--maintenance)
- [🔒 Sécurité](#-sécurité)

---

## 🎯 Le Concept

**Problème :** Vous avez un Boxion (Raspberry Pi, serveur maison...) avec des services à exposer, mais :
- ❌ Pas d'IP fixe ou ports bloqués
- ❌ Configuration réseau trop complexe
- ❌ DNS dynamique difficile

**Solution :** Connexion VPN sécurisée vers un tunnel, votre Boxion obtient :
- ✅ **IPv6 publique** : `2a0c:xxxx:xxxx:abcd::1234`
- ✅ **Domaine automatique** : `random123.boxion.milkywayhub.org`
- ✅ **Accès Internet** : Vos services sont publics !

```
🏠 Votre Boxion ----[WireGuard]----> 🌐 tunnel.milkywayhub.org
   • Yunohost                             ↓
   • Nextcloud              IPv6 publique + Domaine
   • Blog                   random123.boxion.milkywayhub.org
                                     ↓
                               🌍 Internet public
```

---

# 📱 Pour les Utilisateurs Boxion

## 🎯 Quickstart : Connecter mon Boxion

### 🚨 Prérequis
- **Boxion** : Raspberry Pi, mini-PC, serveur maison...
- **OS** : Debian 12 ou Yunohost (testés)
- **Accès** : Sudo/root sur votre Boxion
- **Token** : Code d'accès au service (voir section suivante)

### ⚡ Installation Ultra-Rapide

**1️⃣ Une seule commande à exécuter :**
```bash
# Sur votre Boxion (remplacez VOTRE_TOKEN par votre vrai token)
TOKEN='VOTRE_TOKEN' bash -c "$(curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/bootstrap_client.sh)"
```

**2️⃣ Résultat immédiat :**
```
🎉 Installation terminée !
✅ IPv6 publique : 2a0c:xxxx:xxxx:abcd::1234
✅ Votre domaine : abc123.boxion.milkywayhub.org
✅ Statut WireGuard : Actif

🌐 Testez vos services :
- Yunohost : https://abc123.boxion.milkywayhub.org/yunohost/admin/
- Nextcloud : https://abc123.boxion.milkywayhub.org/nextcloud/
- Votre site : https://abc123.boxion.milkywayhub.org/
```

**3️⃣ C'est fini !** Vos services sont maintenant accessibles publiquement ! 🎆

---

## 🔑 Comment obtenir un token ?

### 📧 **Demande automatisée future**

Pour obtenir votre token d'accès gratuit au service `tunnel.milkywayhub.org` :

1. 📨 **Email** : `tunnel@milkywayhub.org`
2. 📱 **Sujet** : "Demande token Boxion"
3. 📋 **Infos à fournir** : Pseudo souhaité uniquement

> 🚀 **Objectif** : Une plateforme automatisée sera développée pour générer les tokens instantanément sans intervention manuelle.

### ⏱️ **Délai de réponse actuel**
- 🟢 **Normal** : 24-48h
- 🟡 **Week-end** : Jusqu'à 72h
- 🔴 **Urgence** : Mentionnez-le dans l'email

### 🔐 **Votre token sera :**
```
TOKEN='a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6'
# 32 caractères aléatoires, unique pour vous
```

> ⚠️ **Important** : Gardez votre token secret ! Il donne accès à votre Boxion sur le tunnel.

## 🔧 Installation Détaillée

### 🔄 **Installation manuelle (si problème avec quickstart)**

**1️⃣ Télécharger le script :**
```bash
wget https://raw.githubusercontent.com/J0bot/boxion-setup/main/boxion-client-setup.sh
chmod +x boxion-client-setup.sh
```

**2️⃣ Exécuter avec vos paramètres :**
```bash
# Méthode 1 : Variables d'environnement
TOKEN='votre_token' DOMAIN='tunnel.milkywayhub.org' sudo ./boxion-client-setup.sh

# Méthode 2 : Mode interactif
sudo ./boxion-client-setup.sh
# Le script vous demandera le token et le domaine
```

### 🔍 **Vérifier l'installation**

```bash
# Statut WireGuard
sudo wg show

# Test connectivité IPv6
ping6 -c3 2001:4860:4860::8888

# Voir votre domaine
cat /etc/boxion/domain.txt
```

### 🚫 **Désinstaller**

```bash
# Désinstallation complète
curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/uninstall_client.sh | sudo bash
```

---

## 🩺 Diagnostic et Support

### 🔍 **Script de diagnostic automatique**

```bash
# Analyse complète de votre Boxion
curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/diagnostic_client.sh | bash
```

**Le script vérifie :**
- ✅ Installation WireGuard
- ✅ Configuration réseau
- ✅ Connectivité au tunnel
- ✅ Résolution DNS
- ✅ Services exposés

### 🆘 **Support**

**Problèmes courants :**

| Problème | Solution |
|------------|----------|
| Token refusé | Vérifiez votre token, contactez l'admin |
| Pas d'IPv6 | Relancez le script, redémarrez le Boxion |
| Domaine inaccessible | Attendez 5min (propagation DNS) |
| Services non exposés | Vérifiez config locale (Yunohost...) |

**Contact support :**
- 📨 Email : `support@milkywayhub.org`
- 📋 GitHub : [Issues](https://github.com/J0bot/boxion-setup/issues)

---

# 🖥️ Pour les Hébergeurs VPS

## 🌐 Déployer son Service Tunnel

### 🚨 **Prérequis VPS**

- **OS :** Debian 12 (Bookworm) avec accès root/sudo
- **IPv6 :** Adresse globale configurée sur le serveur
- **Ports :** `UDP/51820`, `TCP/80`, `TCP/443` ouverts dans le firewall
- **Domaine :** (Optionnel) Pointé vers l'IP du serveur

### ⚡ **Installation VPS** - 2 modes disponibles

#### 🤖 **Mode 1 : Installation Automatique (Recommandé)**
*Utilise des valeurs par défaut intelligentes - parfait pour débuter !*

```bash
# Installation automatique complète (OBLIGATOIRE: sudo/root)
curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/bootstrap.sh | sudo bash
```

**🎨 Configuration automatique :**
- 🌐 **Domaine :** `tunnel.milkywayhub.org`
- 📧 **Email :** `admin@tunnel.milkywayhub.org`  
- 🏢 **Entreprise :** `Gasser IT Services`
- 👤 **Admin :** `admin` + mot de passe généré
- ⚖️ **Pages légales :** Désactivées

#### 🎯 **Mode 2 : Installation Interactive (Personnalisée)**
*Choisissez vos paramètres : domaine, email, entreprise, admin...*

```bash
# Téléchargement du script
wget https://raw.githubusercontent.com/J0bot/boxion-setup/main/bootstrap.sh
chmod +x bootstrap.sh

# Lancement interactif (vous pourrez tout personnaliser)
sudo ./bootstrap.sh
```

**🎨 Le script installe automatiquement :**
- ✅ Toutes les dépendances Debian 12
- ✅ WireGuard + Nginx + PHP-FPM + SQLite
- ✅ Certificats TLS Let's Encrypt
- ✅ Dashboard web + API sécurisée
- ✅ Monitoring système optimisé

**🔑 Résultat :**
```
🎉 Service tunnel déployé !
✅ API disponible : https://votre-domaine.com/api/
✅ Dashboard admin : https://votre-domaine.com/
✅ Token maître : abc123def456...
✅ Service prêt pour vos Boxions !
```

---

## 🔑 Gérer les Tokens d'Accès

### 🎯 **Système de tokens expliqué**

Comme **hébergeur du service tunnel**, vous contrôlez qui peut se connecter :

**1️⃣ Token maître (vous) :**
- 🔐 Généré automatiquement à l'installation
- 🛡️ Accès complet au dashboard admin
- 📊 Voir tous les Boxions connectés
- ⚙️ Gérer les tokens utilisateurs

**2️⃣ Tokens utilisateurs (vos clients) :**
- 🎫 Créés par vous via le dashboard
- 🔒 Accès limité : connexion VPN uniquement
- 📱 Un token = un Boxion maximum
- 🚫 Pas d'accès admin

### 🎛️ **Créer des tokens utilisateurs**

**Via le dashboard web (recommandé) :**
1. 🌐 Allez sur `https://votre-domaine.com/`
2. 🔑 Connectez-vous avec vos credentials admin
3. ➕ Cliquez "Générer nouveau token"
4. 📝 Saisissez un nom pour identifier l'utilisateur
5. 📋 Copiez le token généré
6. 📨 Envoyez-le à votre utilisateur

**Via l'API (avancé) :**
```bash
# Générer un token via API
curl -X POST https://votre-domaine.com/api/ \
  -H "Authorization: Bearer VOTRE_TOKEN_MAITRE" \
  -H "Content-Type: application/json" \
  -d '{"action":"create_token","name":"utilisateur_nom"}'
```

### 📋 **Bonnes pratiques**

✅ **Recommandations :**
- 📝 Notez à qui vous donnez chaque token
- 🔄 Renouvelez les tokens régulièrement
- 🚫 Révoquent les tokens inutilisés
- 📧 Établissez un processus de demande (email...)
- 💬 Communiquez clairement les règles d'usage

❌ **À éviter :**
- 🚫 Partager votre token maître
- 🚫 Réutiliser le même token pour plusieurs Boxions
- 🚫 Oublier de documenter les attributions

---

## 🔧 Configuration DNS

### 🎯 **DNS requis pour votre service**

Pour que vos utilisateurs aient des domaines automatiques `*.boxion.votre-domaine.com` :

**Enregistrements DNS à créer :**
```
# Votre service principal
tunnel.votre-domaine.com.     IN  A     123.45.67.89
tunnel.votre-domaine.com.     IN  AAAA  2a0c:xxxx:xxxx::1

# Wildcard pour tous les Boxions
*.boxion.votre-domaine.com.   IN  AAAA  2a0c:xxxx:xxxx::*
# (le * sera remplacé par l'IPv6 spécifique de chaque Boxion)
```

### ⚙️ **Configuration manuelle (actuelle)**

**Étape 1 : Configurer le wildcard de base**
```bash
# Dans votre zone DNS, ajoutez :
*.boxion.votre-domaine.com.  IN  AAAA  2a0c:xxxx:xxxx:abcd::1
```

**Étape 2 : Pour chaque nouveau Boxion**
Quand un Boxion `abc123` se connecte avec l'IPv6 `2a0c:xxxx:xxxx:abcd::1234` :
```bash
# Ajoutez manuellement :
abc123.boxion.votre-domaine.com.  IN  AAAA  2a0c:xxxx:xxxx:abcd::1234
```

### 🚀 **Automatisation future (roadmap)**

**PowerDNS + API :**
- 🔄 Création automatique des enregistrements AAAA
- 🗑️ Suppression automatique lors de déconnexion
- 🔍 Vérification d'unicité des noms
- 📊 Logs DNS intégrés au dashboard

> 💡 **Note :** L'automatisation DNS sera ajoutée dans une version future. Pour l'instant, la gestion manuelle reste nécessaire mais simple.

---

### 📱 Installation client (full-auto)

```bash
# Après installation serveur, utiliser la commande affichée :
TOKEN='your_token' DOMAIN='your.domain' bash -c "$(curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/bootstrap_client.sh)"
```

### 🎆 Résultat
- 🌐 **Dashboard public** : `https://votre-domaine/`
- 🔒 **Panel admin** : `https://votre-domaine/admin/`
- 🔌 **API REST** : `https://votre-domaine/api/`

---

## 🗂️ Architecture

### 🏗️ Stack Technique
- **OS :** Debian 12 (Bookworm) - VPS uniquement
- **Boxions :** Debian 12, Yunohost (testés) - autres à vos risques
- **Web :** Nginx + PHP-FPM 8.2+ + SQLite 3 + Let's Encrypt TLS
- **VPN :** WireGuard (kernel natif) + IPv6 automatique
- **Sécurité :** Token Bearer API, Argon2id, validation stricte
- **Monitoring :** Métriques temps réel (cache 30s)

### ⚠️ Compatibilité

| Plateforme | Support | Statut |
|------------|---------|--------|
| **Debian 12** (VPS) | ✅ Officiel | Testé et supporté |
| **Yunohost** (Boxion) | ✅ Officiel | Testé et supporté |
| **Debian 12** (Boxion) | ✅ Officiel | Testé et supporté |
| Ubuntu/CentOS/etc | ❌ Non testé | Peut fonctionner, pas de support |
| Windows/macOS | ❌ Non supporté | Scripts bash uniquement |

---

## 🔒 Sécurité

### 🛡️ Fonctionnalités de sécurité

- 🔐 **Clés privées jamais stockées** côté serveur
- 🎫 **Token Bearer API** changeable à chaud
- 🔒 **Permissions sudo limitées** aux scripts wrapper
- ✅ **Validation stricte** noms et clés publiques
- 🧪 **Isolation processus** PHP-FPM dédié
- 🔄 **Sessions sécurisées** avec CSRF protection
- 📝 **Logging détaillé** pour audit complet

### 🔧 Maintenance sécurisée

```bash
# Changer le token API
sudo nano /var/www/boxion-api/.env
# Modifier: API_TOKEN=nouveau_token_32_chars
sudo systemctl reload php*-fpm

# Vérifier les logs de sécurité
sudo tail -f /var/log/auth.log
sudo journalctl -u nginx -f
```

---

## 🩺 Diagnostic & Maintenance

### 🔍 Scripts de diagnostic

```bash
# Diagnostic serveur complet
curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/diagnostic.sh | sudo bash

# Diagnostic client complet
curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/diagnostic_client.sh | bash
```

### ⚡ Commandes rapides

```bash
# Status WireGuard
wg show wg0
sudo systemctl status wg-quick@wg0

# Logs en temps réel
sudo tail -f /var/log/boxion-replay.log
sudo journalctl -u nginx -f

# Recovery peers après reboot
sudo /var/www/boxion-api/bin/replay_ndp.sh

# Test API
curl -H "Authorization: Bearer TOKEN" https://votre-domaine/api/peers
```

### 🧹 Désinstallation

```bash
# Désinstallation serveur complète
curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/uninstall.sh | sudo bash

# Désinstallation client
curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/uninstall_client.sh | bash
```

---

## 📊 Spécifications Techniques

### 🏗️ Architecture
- **Base de données** : SQLite WAL mode, schema optimisé
- **Attribution IPv6** : Pool /112 séquentiel (65535 peers max)
- **NDP Proxy** : Automatique pour routage IPv6 natif
- **Recovery** : Service systemd rejoue peers au boot
- **Isolation** : Wrappers sudo pour sécurité maximale

### 📈 Performances
- **Monitoring** : Cache 30s pour métriques VPS
- **API** : Validation stricte, rollback automatique
- **Web** : Nginx optimisé, compression, headers sécurité
- **DB** : Transactions atomiques, contraintes UNIQUE

### 🚫 Limitations Actuelles
- **Pool IPv6** : 65535 Boxions max par VPS (configurable)
- **Routage** : Nécessite préfixe IPv6 /64 routé sur le VPS
- **DNS automatique** : En développement, configuration manuelle requise
- **Compatibilité** : Debian 12 + Yunohost uniquement testés
- **Support** : Projet alpha, utilisez à vos risques !

---

## 📞 Support

### 🆘 Aide
- 📋 **Issues GitHub** : [Ouvrir un ticket](https://github.com/J0bot/boxion-setup/issues)
- 📚 **Documentation** : Ce README + commentaires dans le code
- 🔍 **Diagnostic** : Scripts automatiques inclus

### 🤝 Contribution
- 🍴 **Fork** le projet sur GitHub
- 🔧 **Améliorer** le code ou la documentation
- 📨 **Pull Request** avec description détaillée

---

**🎉 Profitez de votre VPN WireGuard sécurisé !**
