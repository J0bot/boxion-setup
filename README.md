# Boxion WireGuard VPN API Setup

Un pack complet "git clone → setup.sh → API prête → clients auto" pour WireGuard avec gestion automatique des peers via API.

**Architecture :** Debian VPS + PHP-FPM + Nginx + SQLite + WireGuard

## Fonctionnalités

- 🔐 **Sécurisé** : Le client génère sa clé privée localement, seule la clé publique est envoyée
- 🌐 **IPv6** : Attribution automatique d'adresses IPv6 depuis un pool /64
- 🔄 **Idempotent** : Les clients peuvent redemander leur configuration
- 🚀 **Auto-setup** : Installation complète en une commande
- 🔒 **Token protégé** : API sécurisée par token Bearer
- 📡 **NDP Proxy** : Support IPv6 avec proxy NDP automatique

## Structure du projet

```
boxion-api/
├─ setup.sh                          # Script d'installation serveur (tout-en-un)
├─ .env.example                       # Variables d'environnement
├─ api/index.php                      # API REST PHP
├─ sql/init.sql                       # Schéma base de données
├─ bin/wg_add_peer.sh                 # Wrapper ajout peer
├─ bin/wg_del_peer.sh                 # Wrapper suppression peer
├─ bin/replay_ndp.sh                  # Restauration peers au boot
├─ systemd/boxion-replay-ndp.service  # Service systemd
├─ nginx/boxion-api.conf              # Configuration Nginx
├─ sudoers/boxion-api                 # Permissions sudo limitées
└─ boxion-client-setup.sh             # Script client Boxion
```

## 🔥 Ports Firewall à Ouvrir

**IMPORTANT:** Ouvrez ces ports sur votre firewall/cloud AVANT l'installation :

### 📡 Ports Requis
- **UDP 51820** - WireGuard (port VPN principal)
- **TCP 80** - HTTP (API et Let's Encrypt)
- **TCP 443** - HTTPS (API sécurisée)
- **TCP 22** - SSH (administration)

### ☁️ Configuration Cloud/VPS

**OpenStack / OVH / Scaleway :**
```
Groupe de sécurité :
- Ingress UDP 51820 (0.0.0.0/0)
- Ingress TCP 80 (0.0.0.0/0) 
- Ingress TCP 443 (0.0.0.0/0)
- Ingress TCP 22 (votre IP)
```

**AWS Security Group :**
```
Inbound Rules :
- UDP 51820 Source: 0.0.0.0/0
- TCP 80 Source: 0.0.0.0/0
- TCP 443 Source: 0.0.0.0/0
- TCP 22 Source: Your IP
```

⚠️ **Sans ces ports ouverts, les clients ne pourront pas se connecter !**

---

## 🚀 Installation Ultra-Simple

### Mode FULL AUTO (Recommandé)

**🖥️ Serveur VPS (Debian/Ubuntu) - Une seule commande :**

```bash
curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/bootstrap.sh | sudo bash
```

*⚠️ Nécessite les permissions root/sudo pour l'installation des paquets*

**📱 Client Boxion - Une seule commande :**

```bash
TOKEN='VOTRE_TOKEN' bash -c "$(curl -fsSL https://raw.githubusercontent.com/J0bot/boxion-setup/main/bootstrap_client.sh)"
```

*Le serveur vous donnera la commande client exacte avec le bon token !*

---

### Mode Manuel (Avancé)

#### Prérequis
- Serveur Debian/Ubuntu avec accès root
- Nom de domaine pointant vers le serveur (ou utiliser `tunnel.milkywayhub.org`)
- Préfixe IPv6 /64 routé vers le serveur

#### Installation serveur

```bash
# Clone du repository
git clone https://github.com/J0bot/boxion-setup.git boxion-api
cd boxion-api

# Installation interactive (recommandé)
sudo ./setup.sh

# Ou installation avec paramètres
sudo ./setup.sh --domain tunnel.milkywayhub.org --token "VOTRE_TOKEN" --prefix "2a0c:xxxx:xxxx:abcd"
```

#### Installation client

```bash
# Télécharger et exécuter (interactif)
wget https://raw.githubusercontent.com/J0bot/boxion-setup/main/boxion-client-setup.sh
chmod +x boxion-client-setup.sh
sudo ./boxion-client-setup.sh

# Ou avec variables d'environnement
TOKEN="VOTRE_TOKEN" DOMAIN="tunnel.milkywayhub.org" sudo ./boxion-client-setup.sh
```

### Paramètres disponibles

- `--domain` : Nom de domaine du serveur (requis)
- `--token` : Token API (requis, 32+ caractères recommandés)
- `--prefix` : Préfixe IPv6 /64 (requis, ex: 2a0c:xxxx:xxxx:abcd)
- `--port` : Port WireGuard (défaut: 51820)
- `--wan-if` : Interface WAN (auto-détecté par défaut)
- `--pool-bits` : Bits pour le pool d'adresses (défaut: 16 = /112)
- `--dns6` : Serveur DNS IPv6 (défaut: Cloudflare)

## Configuration TLS (recommandé)

Après l'installation, sécurisez avec Let's Encrypt :

```bash
apt-get install -y certbot python3-certbot-nginx
certbot --nginx -d tunnel.milkywayhub.org --redirect -n --agree-tos -m admin@milkywayhub.org
systemctl reload nginx
```

## Installation client Boxion

1. Éditez `boxion-client-setup.sh` et remplacez `PLACE_YOUR_TOKEN` par votre token API
2. Exécutez sur le client :

```bash
sudo ./boxion-client-setup.sh
```

Le script :
- Génère une paire de clés WireGuard
- Envoie la clé publique à l'API
- Récupère la configuration complète
- Configure et démarre WireGuard

## API Endpoints

### POST /api/peers
Crée un nouveau peer ou récupère la configuration existante.

**Headers :**
```
Authorization: Bearer YOUR_TOKEN
Content-Type: application/json
```

**Body :**
```json
{
  "name": "client-name",
  "pubkey": "CLIENT_PUBLIC_KEY"
}
```

**Response :**
```json
{
  "wg_conf": "[Interface]\nAddress = 2a0c:xxxx:xxxx:abcd::1234/128\n...",
  "ip6": "2a0c:xxxx:xxxx:abcd::1234"
}
```

### GET /api/peers/{name}
Récupère la configuration d'un peer existant.

### DELETE /api/peers/{name}
Supprime un peer.

## Sécurité

- ✅ **Clés privées** : Jamais stockées côté serveur
- ✅ **Token API** : Changeable à chaud via `.env`
- ✅ **Sudoers** : Limité aux scripts wrapper uniquement
- ✅ **Validation** : Noms et clés publiques validés
- ✅ **Isolation** : PHP-FPM avec utilisateur www-data

## Dépannage

### Vérifier le statut WireGuard
```bash
wg show
systemctl status wg-quick@wg0
```

### Vérifier les logs API
```bash
tail -f /var/log/nginx/error.log
journalctl -u php*-fpm -f
```

### Tester l'API
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"name":"test","pubkey":"TEST_KEY"}' \
     https://tunnel.milkywayhub.org/api/peers
```

### Rejouer les peers après redémarrage
```bash
sudo /var/www/boxion-api/bin/replay_ndp.sh
```

## Architecture technique

- **Base de données** : SQLite avec WAL mode
- **Attribution IPv6** : Pool /112 avec compteur séquentiel
- **NDP Proxy** : Proxy automatique pour routage IPv6
- **Persistance** : Service systemd rejoue les peers au boot
- **Sécurité** : Wrappers sudo pour isolation des commandes système

## Limites

- Pool IPv6 : 65535 peers maximum avec /112 (configurable)
- Si le préfixe /64 n'est pas routé, l'IPv6 publique ne fonctionnera pas
- Prévoir un flag NAT66 pour les cas sans routage IPv6 direct

## Support

Pour les problèmes et questions, ouvrez une issue sur le repository GitHub.