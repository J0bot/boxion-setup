# 🚀 Boxion VPN - IPv6 Simple

**Donnez une IPv6 publique à votre Boxion en 2 minutes !**

[![Debian 12](https://img.shields.io/badge/Debian-12%20(Bookworm)-blue?logo=debian)](https://www.debian.org/)
[![WireGuard](https://img.shields.io/badge/WireGuard-Latest-green?logo=wireguard)](https://www.wireguard.com/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## 🎯 Le Concept

**Problème :** Votre Boxion (Raspberry Pi, serveur maison...) n'a pas d'IPv6 publique

**Solution :** Un tunnel WireGuard simple qui donne une IPv6 publique à votre Boxion !

```
🏠 Votre Boxion ----[WireGuard]----> 🌐 Serveur VPS
   • Nextcloud                           ↓
   • Blog                     IPv6 publique : 2a0c:xxxx::1234
   • Services                        ↓
                              🌍 Accessible depuis Internet
```

## ⚡ Installation Ultra-Rapide

### 📱 **1. Connecter votre Boxion (2 minutes)**

```bash
# Sur votre Boxion/Raspberry Pi
sudo ./client-setup.sh
```

**C'est tout !** Votre Boxion a maintenant une IPv6 publique ! 🎉

### 🖥️ **2. Déployer votre propre serveur tunnel (optionnel)**

```bash
# Sur un VPS avec IPv6
sudo ./setup.sh
```

**Votre serveur tunnel est opérationnel !**

---

## 📋 Installation Détaillée

### 📱 **Client Boxion**

#### 🚨 **Prérequis**
- **Boxion** : Raspberry Pi, mini-PC, serveur maison...
- **OS** : Debian 12 ou Yunohost (recommandés)
- **Accès** : Sudo/root sur votre Boxion
- **Serveur** : URL du serveur tunnel + token API

#### ⚡ **Installation Simple**

**1️⃣ Télécharger le script :**
```bash
wget https://raw.githubusercontent.com/J0bot/boxion-setup/main/client-setup.sh
chmod +x client-setup.sh
```

**2️⃣ Exécuter l'installation :**
```bash
sudo ./client-setup.sh
```

**3️⃣ Configurer interactivement :**
- URL du serveur tunnel (ex: `https://tunnel.milkywayhub.org`)
- Token API (fourni par l'admin du serveur)
- Nom de votre Boxion (ex: `mon-raspberry`)

**4️⃣ Résultat :**
```
🎉 BOXION CONNECTÉE AVEC SUCCÈS !
✅ Nom: mon-raspberry
✅ IPv6 publique : 2a0c:xxxx:xxxx:abcd::1234
✅ Serveur tunnel : tunnel.milkywayhub.org:51820

🌐 Votre Boxion est maintenant accessible depuis Internet !
```

### 🖥️ **Serveur Tunnel (VPS)**

#### 🚨 **Prérequis**
- **VPS** : Serveur avec IPv6 publique
- **OS** : Debian 12 (recommandé)
- **Accès** : Root sur le VPS

#### ⚡ **Installation Simple**

**1️⃣ Télécharger le script :**
```bash
wget https://raw.githubusercontent.com/J0bot/boxion-setup/main/setup.sh
chmod +x setup.sh
```

**2️⃣ Exécuter l'installation :**
```bash
sudo ./setup.sh
```

**3️⃣ Résultat :**
```
🎉 INSTALLATION TERMINÉE AVEC SUCCÈS !
✅ Serveur tunnel opérationnel
📍 API disponible sur: http://[IP-VPS]/api/
🌐 Dashboard: http://[IP-VPS]/

🔑 TOKEN API (à garder secret):
abc123def456...
```

**4️⃣ Distribuer le token :**
Donnez ce token aux utilisateurs qui veulent connecter leur Boxion.

---

## 🔍 **Vérification et Maintenance**

### 📊 **Commandes Utiles**

```bash
# Statut WireGuard
sudo wg show

# Test connectivité IPv6
ping6 -c3 2001:4860:4860::8888

# Logs de connexion
journalctl -u wg-quick@boxion

# Redémarrer le tunnel
sudo systemctl restart wg-quick@boxion
```

---

## 🆘 **Support et Problèmes**

### 🔧 **Problèmes Courants**

| Problème | Solution |
|------------|----------|
| Token refusé | Vérifiez le token, contactez l'admin du serveur |
| Pas d'IPv6 | Redémarrez WireGuard : `sudo systemctl restart wg-quick@boxion` |
| Connexion impossible | Vérifiez le firewall et l'URL du serveur |
| Services non accessibles | Vérifiez la config locale de vos services |

### 🔍 **Debug Manuel**

```bash
# Vérifier la connexion WireGuard
sudo wg show

# Tester la connectivité IPv6
ping6 -c3 google.com

# Voir les logs
journalctl -u wg-quick@boxion
```

---

## 🏗️ **Architecture Technique**

### 🔌 **Comment ça marche**

```
🏠 Boxion                    🖥️ VPS Tunnel
   │                              │
   │--- WireGuard tunnel -------│
   │                              │
   │                          ┌────────────┐
   │                          │ API PHP    │
   │                          │ Dashboard  │
   │                          │ SQLite DB  │
   │                          └────────────┘
   │                              │
   🌍 IPv6: 2a0c:xxxx::1234 ←──── Internet
```

### 🔒 **Sécurité**

- ✅ **Clés privées** : Jamais stockées sur le serveur
- ✅ **API** : Protégée par token
- ✅ **Base de données** : Requiêtes préparées
- ✅ **Permissions** : Principe du moindre privilège

---

## 📜 **Licence & Crédits**

**Licence :** MIT - Libre d'utilisation

**Auteur :** Gasser IT Services  
**Contact :** support@milkywayhub.org

🚀 **Boxion VPN** - Simplifier l'auto-hébergement pour tous !




