# Service de compilation NomadIDE

Reçoit un projet Arduino (zip), le compile dans un conteneur Docker verrouillé avec `arduino-cli`, et renvoie
les binaires. Cartes de la v1 : ESP32, ESP32-S2, ESP32-S3 et RP2040. Le contrat d'API partagé avec l'app est dans
[packages/nomad_compile_api](../../packages/nomad_compile_api).

## Sécurité

Le service exécute des compilateurs sur du code envoyé par des clients. Chaque build tourne dans un conteneur
éphémère : sans réseau, sans privilèges (`--cap-drop ALL`, `no-new-privileges`), système de fichiers en lecture
seule, utilisateur non-root, processus, mémoire et CPU bornés, durée limitée (5 min par défaut). Le zip est
extrait avec refus des chemins sortants, liens symboliques, et limites de taille et de nombre de fichiers.
L'API exige un jeton (`Authorization: Bearer`) sauf `GET /v1/health`. Le code source est supprimé dès la fin
de la compilation ; les binaires restent téléchargeables 30 minutes puis sont effacés.

Le serveur écoute sur `127.0.0.1` : c'est le tunnel Cloudflare qui l'expose. Ne l'ouvrez pas sur le réseau local
sans raison.

## Installation (Ubuntu)

Prérequis : Docker, le SDK Dart (ou un binaire compilé avec `dart compile exe bin/server.dart`).

```bash
# 1. Image de compilation (plusieurs minutes, ~4 Go : les cores ESP32 et RP2040 y sont installés)
docker build -t nomad-compiler:latest -f docker/Dockerfile docker

# 2. Dossier de travail, lisible par le conteneur
sudo mkdir -p /var/lib/nomad-compiler && sudo chown $USER: /var/lib/nomad-compiler
id -u; id -g          # à reporter dans NOMAD_RUN_AS si ce n'est pas 1000:1000

# 3. Jeton (à garder : c'est le mot de passe de l'API)
openssl rand -hex 32

# 4. Essai à la main
NOMAD_TOKEN=<le jeton> dart run bin/server.dart
curl http://127.0.0.1:8787/v1/health
```

### Service systemd

`/etc/systemd/system/nomad-compiler.service` :

```ini
[Unit]
Description=NomadIDE compile service
After=network.target docker.service
Requires=docker.service

[Service]
User=<ton utilisateur>
WorkingDirectory=/opt/nomad/services/cloud_compiler
EnvironmentFile=/etc/nomad-compiler.env
ExecStart=/usr/bin/dart run bin/server.dart
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

`/etc/nomad-compiler.env` (permissions `600`) :

```
NOMAD_TOKEN=<le jeton>
NOMAD_RUN_AS=1000:1000
```

```bash
sudo systemctl daemon-reload && sudo systemctl enable --now nomad-compiler
```

### Tunnel Cloudflare

Dans `config.yml` de `cloudflared` :

```yaml
ingress:
  - hostname: compile.exemple.com
    service: http://127.0.0.1:8787
  - service: http_status:404
```

Pour une protection en plus du jeton, ajoutez une application **Cloudflare Access** sur ce nom d'hôte avec un
*service token* ; l'app enverra alors aussi les en-têtes `CF-Access-Client-Id` et `CF-Access-Client-Secret`.

## Réglages (variables d'environnement)

| Variable | Défaut | Rôle |
|---|---|---|
| `NOMAD_TOKEN` | *(obligatoire, 24 caractères minimum)* | Jeton de l'API |
| `NOMAD_HOST` / `NOMAD_PORT` | `127.0.0.1` / `8787` | Adresse d'écoute |
| `NOMAD_DOCKER_IMAGE` | `nomad-compiler:latest` | Image de compilation |
| `NOMAD_WORK_DIR` | `/var/lib/nomad-compiler` | Dossier des builds en cours |
| `NOMAD_RUN_AS` | `1000:1000` | `uid:gid` dans le conteneur |
| `NOMAD_MAX_JOBS` | `2` | Builds simultanés (16 Go de RAM : ne pas dépasser 3 avec `NOMAD_CONTAINER_MEMORY=3g`) |
| `NOMAD_MAX_QUEUE` | `8` | Builds en attente avant de répondre 429 |
| `NOMAD_BUILD_TIMEOUT_S` | `300` | Durée maximale d'un build |
| `NOMAD_MAX_UPLOAD_MB` | `8` | Taille maximale du zip |
| `NOMAD_JOB_RETENTION_MIN` | `30` | Durée de conservation des binaires |
| `NOMAD_CONTAINER_MEMORY` / `NOMAD_CONTAINER_CPUS` | `3g` / `2` | Limites par build |
| `NOMAD_LIB_CACHE` | `<NOMAD_WORK_DIR>/libraries` | Où sont installées les bibliothèques Arduino (partagées entre les builds) |
| `NOMAD_LIB_INDEX_URL` | index officiel d'Arduino | Catalogue des bibliothèques (`library_index.json.gz`) |

## API

| Requête | Rôle |
|---|---|
| `GET /v1/health` | État et cartes prises en charge (sans jeton) |
| `POST /v1/builds?board=esp32s3[&sketch=nom]` | Corps `application/zip` ; répond `202` avec l'état initial |
| `GET /v1/builds/{id}` | État (`queued`, `running`, `succeeded`, `failed`, `timedOut`, `cancelled`), journal, diagnostics, artefacts |
| `GET /v1/builds/{id}/artifacts/{nom}` | Télécharge un binaire (`merged` à écrire à `0x0` pour l'ESP, `uf2` pour le RP2040) |
| `DELETE /v1/builds/{id}` | Annule un build en cours, supprime un build terminé |

Le projet doit contenir un croquis `.ino` à la racine. Avec plusieurs `.ino`, `sketch=` indique le principal.

### Bibliothèques Arduino

| Requête | Rôle |
|---|---|
| `GET /v1/libraries/search?q=dht&board=esp32s3&limit=20` | Cherche dans le catalogue officiel (nom, auteur, descriptions) ; `board` écarte les bibliothèques d'une autre architecture |
| `GET /v1/libraries/{nom}` | Toutes les versions d'une bibliothèque, avec licence et dépendances |
| `POST /v1/libraries/resolve` | `{"includes": ["DHT.h"], "board": "esp32"}` : pour chaque en-tête, « fourni par le cœur de la carte » ou les bibliothèques qui le fournissent |
| `POST /v1/libraries/closure` | `{"libraries": [{"name": "DHT sensor library"}], "board": "esp32"}` : la liste complète (dépendances comprises), chaque bibliothèque à une version précise |

Un projet demande ses bibliothèques dans son `nomad.json`, qui part avec lui :

```json
{
  "board": "esp32",
  "libraries": [
    {"name": "DHT sensor library", "version": "1.4.6"},
    {"name": "Adafruit Unified Sensor", "version": "1.1.9"}
  ]
}
```

Le service compile avec exactement ces versions (il n'ajoute pas de dépendances de lui-même : c'est `closure` qui les liste), donc deux compilations du même projet donnent le même résultat.

**Fonctionnement et sécurité.** Le service télécharge lui-même l'index officiel d'Arduino (au démarrage puis chaque jour, l'ancien reste servi si le téléchargement échoue). Une bibliothèque n'est installée qu'à partir de cet index : adresse en HTTPS sur `downloads.arduino.cc`, taille et empreinte SHA-256 vérifiées, extraction qui refuse les chemins sortants et les liens symboliques. Chaque version n'est installée qu'une fois (cache partagé) et montée **en lecture seule** dans le conteneur de compilation, qui reste sans réseau. Tant que l'index n'est pas chargé, les routes répondent `503`.

**Vérifier à la main** (après un démarrage, avec le jeton) :

```bash
curl -s localhost:8787/v1/health                                   # "libraries": {"available": true, ...}
curl -s -H "Authorization: Bearer $TOKEN" 'localhost:8787/v1/libraries/search?q=dht&board=esp32'
curl -s -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"includes":["DHT.h","Wire.h"],"board":"esp32"}' localhost:8787/v1/libraries/resolve
```

## Tests

```bash
dart test        # sans Docker : le runner est simulé
```

La compilation réelle (image Docker, cores) n'est pas couverte par les tests automatiques : vérifier à la main après
chaque reconstruction de l'image avec un croquis `Blink` par carte.
