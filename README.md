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

#### 🔎 Résolveurs DNS côté client (important)

- La ligne `DNS = ...` dans `/etc/wireguard/boxion.conf` demande à `wg-quick` de configurer un résolveur via `resolvconf` ou `systemd-resolved`.
- Le script `client-setup.sh` détecte automatiquement:
  - Si `resolvectl`/`systemd-resolve`/`resolvconf` est présent, il ajoute `DNS = 2001:4860:4860::8888, 2001:4860:4860::8844`.
  - Sinon, il n’écrit pas de ligne `DNS =` pour éviter l’erreur `resolvconf: command not found` et laisser votre système gérer le DNS.
- Ceci n’a aucun lien avec vos enregistrements DNS publics (AAAA). Cela concerne uniquement la résolution de noms sur la machine cliente.

Pour corriger une installation existante (sans ré-enrôler):

```bash
sudo bash tools/client-fix.sh
```

### 🖥️ **Serveur Tunnel (VPS)**

#### 🚨 **Prérequis**
- **VPS** : Serveur avec IPv6 publique
- **OS** : Debian 12 (recommandé)
- **Accès** : Root sur le VPS

#### 🌐 **Réseau / DNS / Firewall**

- **DNS**: créez un enregistrement `AAAA` pour votre domaine (ex: `tunnel.milkywayhub.org`) pointant vers l'IPv6 de votre VPS. Un `A` (IPv4) est optionnel mais pratique.
- **Ports ouverts**: `80/tcp` (HTTP, ACME), `443/tcp` (HTTPS), `51820/udp` (WireGuard), et — si vous utilisez Hurricane Electric — **protocole 41 (IPv4, 6in4)**.
- **UFW (si activé)**:

  ```bash
  sudo ufw allow 80/tcp
  sudo ufw allow 443/tcp
  sudo ufw allow 51820/udp
  # Pour HE 6in4 (protocole 41 via IPv4)
  sudo iptables -I INPUT -p 41 -j ACCEPT
  ```

- **Infomaniak/OpenStack**: vérifiez aussi les règles de sécurité (security groups) côté cloud.
  - Si HE 6in4 est activé, autorisez explicitement **Protocol 41** (IPv4) dans le security group.

### 🌀 HE 6in4 (optionnel) — si pas de /64 natif

Si votre fournisseur ne route pas un `/64` IPv6 vers votre VPS, l'installeur propose automatiquement la configuration d'un tunnel **Hurricane Electric (6in4)**.

- Étape concernée: `installer/steps/15-he-tunnel.sh` (exécutée juste après l'installation des paquets).
- Le tunnel 6in4 crée une interface `he-ipv6` et vous fournit un `/64` routé publiquement, utilisable pour vos clients.

Ce que l'installeur vous demandera (avec exemples):

```text
IPv4 publique locale (auto)         : 203.0.113.10
HE Server IPv4 (TunnelBroker)       : 216.66.80.98
IPv6 client P2P (/64)               : 2001:470:abcd:1234::2/64
IPv6 serveur P2P (auto: ::1)        : 2001:470:abcd:1234::1
Routed /64                          : 2001:470:beef::/64
MTU                                 : 1480 (défaut)
Utiliser HE comme route IPv6 par défaut ? [n]
```

Détails d'implémentation:

- Crée et active `he6in4.service` (systemd) et son env `/etc/boxion/he6in4.env`.
- Ouvre localement le **protocole 41** (`iptables -I INPUT -p 41 -j ACCEPT`). Pensez aussi au security group cloud.
- Définit `IPV6_PREFIX_BASE` sur le `/64` routé HE et désactive `ndppd` pour cette configuration (pas de proxy NDP nécessaire).
- La configuration WireGuard du serveur route automatiquement ce `/64` vers `wg0` (PostUp/PostDown), chaque Boxion recevant un `/128` dans ce `/64`.

Vérifications utiles:

```bash
sudo systemctl status he6in4
ip -6 addr show dev he-ipv6
ip -6 route show dev he-ipv6
ping6 -c1 2001:470:abcd:1234::1   # IPv6 côté HE (serveur P2P)
```

#### 🌍 DNS public (AAAA) & YunoHost — recommandations

- Boxion n’édite pas automatiquement votre zone DNS Infomaniak. Chaque Boxion reçoit une IPv6 /128 publique, et vous créez un enregistrement `AAAA` pointant dessus.
- Avec **YunoHost**:
  - Faites d’abord la connexion VPN (IPv6 OK), puis installez YunoHost.
  - Dans l’admin YunoHost (Diagnose), suivez les « DNS records suggestions » et appliquez-les chez Infomaniak.
  - Conservez/ajoutez l’`AAAA` du sous-domaine de la Boxion vers son IPv6 /128 fournie par le tunnel.
- Récupérer l’IPv6 à publier:
  - Côté client: `grep ^Address /etc/wireguard/boxion.conf`
  - Côté serveur: `sqlite3 /var/lib/boxion/peers.db 'SELECT name,ipv6_address FROM peers;'`
- Vérifier depuis Internet:

```bash
dig AAAA boxion1.milkywayhub.org +short
ping6 -c1 boxion1.milkywayhub.org
```

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

### 🧰 Diagnostics (web & CLI)

- **Web (admin, Basic Auth)**
  - `https://tunnel.milkywayhub.org/admin/status.php` — état système (IPv6, NDP, WG, routes, firewall, nginx)
  - `https://tunnel.milkywayhub.org/admin/probe.php` — tests AAAA/ping6/curl v6 sur une cible
- **API**
  - `GET /api/status` — JSON du diagnostic (auth Bearer avec token maître)
  - Script: `./tools/api-status.sh https://tunnel.milkywayhub.org "$API_TOKEN"`
- **CLI (VPS)**
  - `./tools/diag.sh` — diagnostic serveur (wrap du helper root)
  - `./tools/support-bundle.sh https://tunnel.milkywayhub.org "$API_TOKEN"` — archive à partager (secrets redacted)
- **CLI (Client)**
  - `./tools/client-diag.sh [cible]` — diagnostic client (interface, WG, ping6/curl v6)
  - `./tools/test-ipv6.sh [cible]` — tests IPv6 rapides
  - `./tools/client-fix.sh` — corrige la ligne `DNS =` selon la présence de resolvconf/resolved

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
| `wg-quick`: `resolvconf: command not found` | Exécutez `sudo bash tools/client-fix.sh` ou installez `resolvconf`/`openresolv` |

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

## ♻️ **Réinitialisation / Désinstallation**

> Danger: opérations destructives. Les scripts ci-dessous suppriment la configuration Boxion. Un backup compressé est créé côté VPS.

### 🖥️ VPS (Serveur)

- Désinstaller proprement:

```bash
cd ~/boxion-setup
sudo bash tools/server-uninstall.sh
```

- Réinitialiser (désinstaller puis réinstaller):

```bash
cd ~/boxion-setup
sudo BOXION_DOMAIN=tunnel.milkywayhub.org \
     BOXION_LE_EMAIL=admin@example.com \
     bash tools/server-reset.sh
```

Notes:
- Un backup est créé: `/root/boxion-backup-<timestamp>.tar.gz`.
- Après réinstall, si la portée IPv6 externe n’est pas immédiate: `sudo bash tools/server-ndp-ensure.sh`.
- Les enregistrements DNS publics (AAAA) restent manuels chez Infomaniak (voir recommandations plus haut).

### 📱 Client (Boxion)

- Désinstaller proprement:

```bash
cd ~/boxion-setup
sudo bash tools/client-uninstall.sh
```

- Réinitialiser (désinstaller puis réinstaller):

```bash
cd ~/boxion-setup
sudo bash tools/client-reset.sh
```

Mode non-interactif possible:

```bash
sudo BOXION_SERVER_URL=https://tunnel.milkywayhub.org \
     BOXION_API_TOKEN=XXXX... \
     BOXION_NAME=mon-boxion \
     bash tools/client-reset.sh
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
**Contact :** tunnel@milkywayhub.org

🚀 **Boxion VPN** - Simplifier l'auto-hébergement pour tous !
