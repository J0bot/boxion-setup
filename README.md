# 🚀 Boxion VPN - IPv6 Simple

**Donnez une IPv6 publique à votre Boxion en 2 minutes !**

[![Debian 12](https://img.shields.io/badge/Debian-12%20(Bookworm)-blue?logo=debian)](https://www.debian.org/)
[![WireGuard](https://img.shields.io/badge/WireGuard-Latest-green?logo=wireguard)](https://www.wireguard.com/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## 🎯 Le Concept

**Problème :** Votre Boxion (Raspberry Pi, serveur maison...) n'a pas d'IPv6 publique

**Solution :** Un tunnel WireGuard simple qui donne une IPv6 publique à votre Boxion !

```text
🏠 Votre Boxion ----[WireGuard]----> 🌐 Serveur VPS
   • Nextcloud                           ↓
   • Blog                     IPv6 publique : 2a0c:xxxx::1234
   • Services                        ↓
                              🌍 Accessible depuis Internet
```

## 🚢 Déploiement 100% Docker (recommandé)

> Nouveau: le serveur Boxion est désormais entièrement conteneurisé (proxy, API, WireGuard, ndppd). L'ancien « installer » système est déprécié.

### Prérequis

- Docker + Docker Compose
- Réseaux Docker externes (si non présents):

```bash
docker network create boxion || true
docker network create boxion-edge || true
```

### Démarrage

```bash
git clone https://github.com/J0bot/boxion-setup.git
cd boxion-setup
docker compose build
docker compose up -d
```

> Important (accès via 80/443 derrière le proxy) : ajoutez votre domaine dans `data/nginx-maps/http.map` pour router le Dashboard/API vers le conteneur `api`.

```nginx
# data/nginx-maps/http.map
tunnel.milkywayhub.org   api:8080;
```

Ensuite, ouvrez l'interface d'administration (web) et finalisez la configuration:

1. Ouvrez votre navigateur sur: `http://<IP-ou-domaine>/admin/`
2. Authentification HTTP Basic (par défaut): utilisez le couple `ADMIN_USER` / `ADMIN_PASS` affiché au démarrage de `boxion-api`.
    - Pour retrouver ces informations: `docker logs -n 200 boxion-api | sed -n '/\[api-entrypoint\]/p'`
3. Dans l'Admin UI, saisissez un jeton d'accès: soit le **token API** maître (affiché au démarrage), soit un **OTP** temporaire généré dans la page « OTP ».
4. Configurez selon vos besoins:
   - Page « HE »: tunnel Hurricane Electric 6in4 (si votre VPS n'a pas de /64 natif)
   - Page « Proxy »: mappages IPv4→IPv6 (SNI/Host) pour publier vos Boxion
   - Page « SMTP »: relai sortant (optionnel) et identifiants d'envoi authentifié (587/2525)
   - Page « Peers »: pairs WireGuard et adresses IPv6 /128

Par défaut:

- Le proxy Nginx écoute 80/443 et relaie par nom d’hôte (HTTP) ou SNI (TLS). Les hôtes inconnus vont vers `caddy:8080/8443` sur le réseau `boxion-edge`.
- Ajustez les fichiers de routes: `data/nginx-maps/http.map` et `data/nginx-maps/tls.map`.
- Le conteneur `net` (WireGuard + ndppd) tourne en mode `host` et expose UDP 51820 côté hôte.
- La configuration et la base SQLite persistent dans des volumes: `/etc/boxion`, `/var/lib/boxion`, `/etc/wireguard`.

### Récupérer le token API et tester

- Le **token API** maître est **affiché au démarrage** de `boxion-api` et persisté dans `/etc/boxion/boxion.env`.
- Pour l'afficher depuis les logs:

```bash
docker logs -n 200 boxion-api | sed -n '/\[api-entrypoint\] API Bearer token:/p'
```

- Exemple de test API (remplacez l'URL par la vôtre):

```bash
export API_TOKEN=... # valeur affichée au démarrage
curl -s -6 -H "Authorization: Bearer $API_TOKEN" http://<IP-ou-domaine>/api/status | jq
```

### DNS public (Infomaniak) — manuel

- Ne pas éditer automatiquement la zone DNS. Créez l’`AAAA` du domaine du serveur vers l’IPv6 native du VPS.
- Pour chaque Boxion enrôlée, créez un `AAAA` vers son `/128` (visible dans la réponse API et la DB SQLite).
- Avec YunoHost: suivez les « DNS records suggestions » dans l’admin YunoHost et appliquez-les chez Infomaniak.

### État de l’installateur legacy

- Les composants historiques (installeur shell et pages PHP d'admin) sont dépréciés.
- Ils seront déplacés dans `old/` pour référence. Utilisez désormais exclusivement **Docker Compose** + **Admin UI**.

## ⚡ Installation Ultra-Rapide

### 📱 **1. Connecter votre Boxion (2 minutes)**

```bash
# Sur votre Boxion/Raspberry Pi
sudo ./client-setup.sh
```

**C'est tout !** Votre Boxion a maintenant une IPv6 publique ! 🎉

### 🖥️ **2. Configurer votre serveur via l’interface web**

- DNS public: créez un enregistrement `AAAA` pointant le domaine de votre VPS vers son IPv6 (Infomaniak, manuel).
- Lancez la stack Docker (voir « Démarrage »), puis ouvrez `http://<IP-ou-domaine>/admin/`.
- Connectez-vous (Basic Auth), puis utilisez l’Admin UI:
  - « HE » pour activer/configurer un tunnel 6in4 (si absence de /64 natif)
  - « Proxy » pour publier vos Boxion en IPv4 via le VPS
  - « SMTP » pour définir un relai sortant et récupérer les identifiants d’envoi
  - « OTP » pour générer des jetons à usage unique

---

## ✅ Checklist de mise en service (rapide)

1. *DNS*: créer l’AAAA `tunnel.milkywayhub.org` → IPv6 native du VPS (Infomaniak, manuel).
2. *Pare-feu / Security groups*: ouvrir 80/tcp, 443/tcp, 51820/udp, et si HE: protocole 41 (IPv4).
3. *Démarrer la stack*: `docker compose up -d` puis finaliser la configuration dans l’**Admin UI** (`/admin`).
4. *Récupérer le token*: `cat /etc/boxion/boxion.env` → `API_TOKEN=...`.
5. *Tester l’API*: `curl -6 -H "Authorization: Bearer $API_TOKEN" https://tunnel.milkywayhub.org/api/status`.
6. *Enrôler un client*: section « Client Boxion » (mode interactif ou non-interactif).
7. *Vérifier côté client*: `curl -6 https://api64.ipify.org` → retourne son /128.
8. *Publier l’AAAA client*: sous-domaine → IPv6 /128 de la Boxion (Infomaniak, manuel).

## 📋 Installation Détaillée

### 📱 **Client Boxion**

#### 🚨 **Prérequis (Client)**

- **Boxion** : Raspberry Pi, mini-PC, serveur maison...
- **OS** : Debian 12 ou Yunohost (recommandés)
- **Accès** : Sudo/root sur votre Boxion
- **Serveur** : URL du serveur tunnel + token API

> Important: si vous prévoyez d'installer **YunoHost** sur votre Boxion, faites d'abord la **connexion VPN** avec ce script, vérifiez la connectivité IPv6 (ping6, curl -6), puis seulement ensuite lancez l'installation YunoHost. Cela garantit que le diagnostic et l'émission de certificats utilisent déjà l'IPv6 publique fournie par le tunnel.

#### ✅ **YunoHost : testé et validé**

YunoHost fonctionne parfaitement au-dessus de Boxion.

- **Plateforme testée**: Raspberry Pi 3 Model B+ (arm64) · Linux 6.12.34+rpt-rpi-v8 · Debian 12.11 · YunoHost 12.1.17.1 (stable)
- **Statut**: services OK (nginx, nftables, dovecot/postfix/…)

Interprétation du diagnostic YunoHost quand on utilise Boxion:

- **Ports IPv4 non atteignables (22/80/443/…):** attendu si la Boxion est derrière une box NAT. Pour une exposition publique en IPv4, utilisez le **proxy IPv4→IPv6 du VPS** (voir ci-dessous). Pas besoin d’ouvrir de ports sur votre box.
- **Web: IPv6 OK mais IPv4 KO**: ajoutez un enregistrement **A** vers l’IPv4 du VPS + activez le proxy; gardez l’**AAAA** pointant vers l’IPv6 /128 de la Boxion.
  - Résultat: les clients **IPv4** passent via le VPS (proxy), les clients **IPv6** atteignent la Boxion directement.
- **DNS “basic/extra”**: suivez les suggestions YunoHost et appliquez-les manuellement chez **Infomaniak** (conforme à la préférence: pas d’édition DNS automatique).
- **Email (SMTP/25, rDNS, blacklists)**: hors périmètre par défaut. Beaucoup d’ISP bloquent le 25 et imposent un rDNS. Options:
  - Ignorer ces vérifications si vous n’hébergez pas d’email.
  - Utiliser un **relai SMTP** tiers (recommandé si vous tenez à l’email).
  - En dernier recours, désactiver IPv6 pour l’envoi SMTP:

    ```bash
    sudo yunohost settings set email.smtp.smtp_allow_ipv6 -v off
    ```

Procédure express (publier un YunoHost via Boxion):

1. **Activer le proxy sur le VPS**

```bash
sudo ./tools/server-proxy-enable.sh
sudo ./tools/server-proxy-add.sh s1.boxion.milkywayhub.org 2001:470:b563:1::101 80 443
```

1. **DNS chez Infomaniak (manuel)**

- `A    s1.boxion.milkywayhub.org` → IPv4 du VPS
- `AAAA s1.boxion.milkywayhub.org` → `2001:470:b563:1::101` (IPv6 /128 de la Boxion)

1. **Côté Boxion (YunoHost)**

- S’assurer que `nginx` écoute sur `:80` et `:443`.
- Si nécessaire, ouvrir le firewall local sur 80/443.

1. **Vérification**

- `http://s1.boxion.milkywayhub.org/` (IPv4 via proxy) doit répondre.
- `https://s1.boxion.milkywayhub.org/` après émission des certificats.
- Re-lancer un “Diagnosis” dans l’admin YunoHost: la section Web devrait passer au vert.

#### ⚡ **Installation Simple (Client)**

**1. Télécharger le script :**

```bash
wget https://raw.githubusercontent.com/J0bot/boxion-setup/main/client-setup.sh
chmod +x client-setup.sh
```

**2. Exécuter l'installation :**

```bash
sudo ./client-setup.sh
```

Ou en mode non-interactif (pratique pour scripts/CI):

```bash
export BOXION_SERVER_URL="https://tunnel.milkywayhub.org"
export BOXION_API_TOKEN="...token maître ou OTP..."
sudo -E ./client-setup.sh
```

**3. Configurer interactivement :**

- URL du serveur tunnel (ex: `https://tunnel.milkywayhub.org`)
- Token API (fourni par l'admin du serveur)
- Nom de votre Boxion (ex: `mon-raspberry`)

**4. Résultat :**

```text
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

#### 🚨 **Prérequis (Serveur)**

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

- **nftables (exemple générique)** — à adapter à vos tables/chaînes existantes:

  ```bash
  sudo nft add rule inet filter input tcp dport {80,443} accept
  sudo nft add rule inet filter input udp dport 51820 accept
  # ICMPv6 indispensable (PMTUD, Neighbor Discovery)
  sudo nft add rule inet filter input ip6 nexthdr icmpv6 accept
  ```

- **Infomaniak/OpenStack**: vérifiez aussi les règles de sécurité (security groups) côté cloud.
  - Si HE 6in4 est activé, autorisez explicitement **Protocol 41** (IPv4) dans le security group.

### 🌀 HE 6in4 (optionnel) — si pas de /64 natif

Si votre fournisseur ne route pas un `/64` IPv6 vers votre VPS, activez un tunnel **Hurricane Electric (6in4)** depuis l’Admin UI (« HE ») ou via l’API.

- Le tunnel 6in4 crée une interface `he-ipv6` et vous fournit un `/64` routé publiquement, utilisable pour vos clients.

Champs demandés (exemples):

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

- Variables persistées dans `/etc/boxion/he6in4.env`, appliquées via le conteneur `net`.
- Ouverture du **protocole 41** côté VPS (IPv4) à prévoir dans vos security groups si HE est activé.
- Le `/64` routé est propagé dans la config WireGuard serveur, chaque Boxion recevant un `/128` dans ce /64.

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

#### 🔑 OTP d'enrôlement (recommandé)

- Ouvrez l’Admin UI: `http://<IP-ou-domaine>/admin/` (Basic Auth)
- Générez un OTP (usage unique, TTL court) et donnez-le au client
- Le client peut utiliser soit l'OTP, soit le token maître

---

## 🔍 **Vérification et Maintenance**

### 🧰 Diagnostics (web & CLI)

- **Web (Admin UI, Basic Auth)**
  - `http://<IP-ou-domaine>/admin/` — Dashboard (état système, API gate), pages « Proxy », « HE », « SMTP », « OTP », « Peers »
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

```text
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
**Contact :** [tunnel@milkywayhub.org](mailto:tunnel@milkywayhub.org)

🚀 **Boxion VPN** - Simplifier l'auto-hébergement pour tous !
