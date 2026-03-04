# old/ — Composants dépréciés

Ce répertoire regroupe l’historique de l’installateur shell et des artefacts legacy qui ne sont plus utilisés depuis la transition vers une configuration 100% web (Admin UI) et Docker.

Important:

- Ces fichiers ne sont plus pris en charge.
- Ne les utilisez pas pour de nouvelles installations.
- Conservez-les uniquement pour référence ou migration.

Contenu à déplacer ici (proposition):

- installer/ → old/installer/
- server/admin/ (PHP legacy: status.php, probe.php, etc.) → old/server-admin-php/
- server/nginx/ (anciens templates Nginx) → old/server-nginx-legacy/
- server/web/ (ancienne page statique du dashboard) → old/server-web-legacy/
- server/system/sysctl.d/ (tuning sysctl legacy; la stack Docker applique les sysctl au runtime) → old/sysctl.d/
- setup.sh (script legacy qui s’auto-déprécie) → old/setup.sh

Composants à NE PAS déplacer car utilisés par la stack Docker actuelle:

- server/api/ (PHP API)
- server/system/ndppd.conf.tmpl (copié dans l’image `net`)
- server/wireguard/wg0.conf.tmpl (copié dans l’image `net`)

Pourquoi ces composants deviennent legacy ?

- L’Admin UI (React) et l’API (PHP) tournent en conteneurs et remplacent les anciennes pages PHP d’admin.
- Le proxy edge (conteneur `proxy/`) utilise `data/nginx-maps/` pour router vers `api:8080` et les services publiés en IPv6, remplaçant les templates Nginx anciens.
- Le conteneur `net/` applique dynamiquement les `sysctl` requis; le drop-in `sysctl.d` historique n’est plus nécessaire.

Comment déplacer proprement (à exécuter par vos soins sur votre VPS):

```bash
# Assurez-vous d’être sur une branche dédiée
# git checkout -b chore/move-legacy

# Créer les dossiers de destination
mkdir -p old/installer old/server-admin-php old/server-nginx-legacy old

# Déplacer avec git pour préserver l’historique
git mv installer old/installer
git mv server/admin old/server-admin-php
git mv server/nginx old/server-nginx-legacy
git mv server/system/sysctl.d old/sysctl.d
git mv setup.sh old/setup.sh

# Valider le changement
git add -A
git commit -m "chore(legacy): move legacy installer and admin php to old/; keep templates used by Docker"
```

Notes:

- Après ce déplacement, reconstruisez les images si besoin: `docker compose build`.
- Aucun Dockerfile ne référence les chemins déplacés ci-dessus (sauf les éléments explicitement exclus plus haut). Si vous déplacez par erreur `server/system/ndppd.conf.tmpl` ou `server/wireguard/wg0.conf.tmpl`, la build de `docker/net` échouera.
- La documentation principale (`README.md`) a été mise à jour pour n’expliquer que le parcours web.
