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
# Sur un VPS Debian 12 avec IPv6 et un nom de domaine pointé (AAAA)
sudo bash installer/install.sh --domain tunnel.milkywayhub.org --email admin@example.com
# ou via variables env
sudo BOXION_DOMAIN=tunnel.milkywayhub.org BOXION_LE_EMAIL=admin@example.com bash installer/install.sh
```

**Le serveur configure WireGuard, NDP proxy, API, Dashboard et TLS (Let's Encrypt).**

---

## 📋 Installation Détaillée

### 📱 **Client Boxion**

#### 🚨 **Prérequis**
- **Boxion** : Raspberry Pi, mini-PC, serveur maison...
- **OS** : Debian 12 ou Yunohost (recommandés)
- **Accès** : Sudo/root sur votre Boxion
- **Serveur** : URL du serveur tunnel + token API

> Important: si vous prévoyez d'installer **YunoHost** sur votre Boxion, faites d'abord la **connexion VPN** avec ce script, vérifiez la connectivité IPv6 (ping6, curl -6), puis seulement ensuite lancez l'installation YunoHost. Cela garantit que le diagnostic et l'émission de certificats utilisent déjà l'IPv6 publique fournie par le tunnel.

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

#### 🌐 **Réseau / DNS / Firewall**

- **DNS**: créez un enregistrement `AAAA` pour votre domaine (ex: `tunnel.milkywayhub.org`) pointant vers l'IPv6 de votre VPS. Un `A` (IPv4) est optionnel mais pratique.
- **Ports ouverts**: `80/tcp` (HTTP, ACME), `443/tcp` (HTTPS), `51820/udp` (WireGuard).
- **UFW (si activé)**:

  ```bash
  sudo ufw allow 80/tcp
  sudo ufw allow 443/tcp
  sudo ufw allow 51820/udp
  ```

- **Infomaniak/OpenStack**: vérifiez aussi les règles de sécurité (security groups) côté cloud.

#### ⚡ **Installation Simple**

**1️⃣ Récupérer le projet :**

```bash
sudo apt-get update -qq && sudo apt-get install -y git
git clone https://github.com/J0bot/boxion-setup.git
cd boxion-setup
```

**2️⃣ Lancer l'installation :**

```bash
sudo BOXION_DOMAIN=tunnel.milkywayhub.org BOXION_LE_EMAIL=admin@example.com bash installer/install.sh
```

**3️⃣ Résultat :**
```
🎉 INSTALLATION TERMINÉE AVEC SUCCÈS !
✅ Serveur tunnel opérationnel
📍 API: <https://tunnel.milkywayhub.org/api/>
🌐 Dashboard: <https://tunnel.milkywayhub.org/>

🔑 Token API maître (secret) affiché et sauvegardé dans /etc/boxion/boxion.env
🔐 Admin (Basic Auth): login admin, mot de passe dans /etc/boxion/admin-password.txt
```

**4️⃣ OTP d'enrôlement (recommandé) :**

- Ouvrez <https://tunnel.milkywayhub.org/admin/> (Basic Auth)
- Générez un OTP (usage unique, TTL court) et donnez-le au client
- Le client peut utiliser soit l'OTP, soit le token maître

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

- ✅ **TLS**: HTTPS automatique via Let's Encrypt (si domaine + email)
- ✅ **API**: Bearer Token maître ou **OTP** (usage unique, limité dans le temps)
- ✅ **Rate limiting**: limite basique sur /api/ pour éviter l'abus
- ✅ **Clés privées**: jamais stockées côté serveur
- ✅ **DB**: requêtes préparées, SQLite avec droits restreints
- ✅ **Privilèges**: helper root minimal via sudoers (PHP n'édite pas wg directement)

---

## 📜 **Licence & Crédits**

**Licence :** MIT - Libre d'utilisation

**Auteur :** Gasser IT Services  
**Contact :** support@milkywayhub.org

🚀 **Boxion VPN** - Simplifier l'auto-hébergement pour tous !




