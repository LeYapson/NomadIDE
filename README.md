# NomadIDE

IDE embarqué léger et multiplateforme (Android, iOS, Windows, macOS, Linux) pour éditer du
MicroPython et du C/C++, puis le transférer ou le flasher sur une carte par USB
(OTG sur mobile, port série sur desktop).

- Choix de stack : [docs/adr/0001-stack-flutter.md](docs/adr/0001-stack-flutter.md) (Flutter).
- État : **version 0.1.0 bêta** : moniteur série, MicroPython (console, fichiers, bibliothèques), éditeur,
  flash UF2 et ESP32. Détail et limites connues : [CHANGELOG.md](CHANGELOG.md).

## Installer

Téléchargez la dernière version dans les [releases GitHub](https://github.com/LeYapson/NomadIDE/releases) :

| Système | Fichier | Installation |
|---|---|---|
| Windows 10/11 (64 bits) | `NomadIDE-<version>-windows-x64.zip` | Décompressez, lancez `nomad_mcu.exe`. App non signée : « Informations complémentaires » puis « Exécuter quand même ». |
| macOS | `NomadIDE-<version>-macos.zip` | Décompressez, glissez l'app dans Applications. Non notarisée : clic droit, « Ouvrir », la première fois. |
| Linux (64 bits) | `NomadIDE-<version>-linux-x64.tar.gz` | Décompressez, lancez `nomad_mcu`. Ajoutez votre utilisateur au groupe `dialout` (ou `uucp`). |
| Android 7+ | `NomadIDE-<version>-android-arm64.apk` (`-arm32` pour les anciens téléphones) | Ouvrez l'APK sur le téléphone et autorisez l'installation depuis cette source. Câble ou adaptateur OTG pour brancher la carte. |

L'app vérifie au démarrage si une nouvelle version est publiée (désactivable dans Réglages → À propos).

### Publier une version

Une seule fois : la clé de signature Android dans les secrets du dépôt (la même pour toutes les versions,
sinon une mise à jour refuse de s'installer ; à sauvegarder hors de l'ordinateur) :

```bash
K=~/.nomadide-keys   # nomadide-upload.jks et key.properties, jamais dans le dépôt
PW=$(grep '^storePassword=' $K/key.properties | cut -d= -f2-)
base64 -w0 $K/nomadide-upload.jks | gh secret set ANDROID_KEYSTORE_BASE64
printf '%s' "$PW" | gh secret set ANDROID_KEYSTORE_PASSWORD
printf '%s' "$PW" | gh secret set ANDROID_KEY_PASSWORD
printf 'nomadide' | gh secret set ANDROID_KEY_ALIAS
```

En local, `app/android/key.properties` (ignoré par git) signe aussi `flutter build apk --release` avec cette clé.

1. Mettre à jour `CHANGELOG.md` (section `## [x.y.z]`) et fusionner `develop` dans `main`.
2. Sur `main` : `git tag vx.y.z && git push origin vx.y.z`.
3. Le workflow [release.yml](.github/workflows/release.yml) compile Windows, Linux, macOS et Android (APK et
   App Bundle pour le Play Store) et publie la release avec les notes du CHANGELOG (pré-version pour toute
   version 0.x).

## Architecture

```
┌──────────────────────────── app/ (Flutter) ─────────────────────────────┐
│ presentation/   Widgets (pages, barres, journal)        ← aucune logique │
│ application/    ViewModels Riverpod (Notifier) + états immuables          │
│ domain/         Modèles et logique pure (LogEntry, RxLineAssembler…)      │
└───────────────┬──────────────────────────────────────────────────────────┘
                │ dépend uniquement des interfaces
┌───────────────▼─────────── packages/nomad_protocols (Dart pur, étapes 2-3)┐
│ raw REPL MicroPython · esptool/SLIP · UF2 · STM32 AN3155 · Intel HEX      │
└───────────────┬──────────────────────────────────────────────────────────┘
┌───────────────▼─────────── packages/nomad_hal ────────────────────────────┐
│ domain/    SerialTransport · SerialConnection · SerialConfig · UsbChip    │
│ io/        SerialReader (read/readUntil + timeout) · séquences DTR/RTS    │
│ platform/  Android (usb_serial) · Desktop (libserialport) · Fake · iOS ✗ │
└──────────────────────────────────────────────────────────────────────────┘
```

Règle : les dépendances vont uniquement vers le bas. L'UI et les protocoles ne voient que
`SerialTransport` / `SerialConnection` : on peut remplacer un plugin, ou ajouter un transport
BLE ou WebREPL, sans toucher au reste.

## Arborescence

Légende : ✅ présent dans ce PoC · 🔜 étape indiquée

```
NomadIDE/
├── pubspec.yaml                      ✅ workspace Dart (pub workspaces)
├── README.md                         ✅
├── docs/adr/0001-stack-flutter.md    ✅ décision Flutter vs Tauri
│
├── packages/
│   ├── nomad_hal/                    ✅ Étape 1 — HAL USB/série
│   │   ├── lib/nomad_hal.dart           barrel (API publique)
│   │   ├── lib/src/domain/
│   │   │   ├── serial_transport.dart    interfaces SerialTransport / SerialConnection, DeviceEvent
│   │   │   ├── serial_config.dart       baudrate, 8N1, contrôle de flux
│   │   │   ├── serial_device_info.dart  description commune d'un périphérique
│   │   │   ├── serial_exceptions.dart   erreurs typées (sealed)
│   │   │   └── usb_chip.dart            base VID:PID → pilote + famille de carte
│   │   ├── lib/src/io/
│   │   │   ├── serial_reader.dart       lecture tamponnée pour les protocoles
│   │   │   └── reset_sequences.dart     reset / bootloader ESP / touch 1200 bauds
│   │   ├── lib/src/platform/
│   │   │   ├── base_serial_connection.dart  socle commun (flux, done, DTR/RTS)
│   │   │   ├── android_usb_transport.dart   USB Host / OTG
│   │   │   ├── desktop_serial_transport.dart libserialport + hotplug par sondage
│   │   │   ├── fake_transport.dart          carte MicroPython simulée
│   │   │   └── unsupported_transport.dart   iOS
│   │   ├── lib/src/transport_factory.dart   choix selon la plateforme
│   │   └── test/
│   │
│   ├── nomad_protocols/              🔜 Étapes 2-3 — Dart pur, testé sans matériel
│   │   └── lib/src/
│   │       ├── micropython/             raw_repl.dart, board_fs.dart (ls/get/put/rm)
│   │       ├── esp/                     slip.dart, esp_loader.dart, stubs/
│   │       ├── rp2040/                  uf2.dart (+ picoboot)
│   │       ├── stm32/                   an3155.dart
│   │       └── formats/                 intel_hex.dart, elf_to_bin.dart
│   │
│   └── nomad_editor/                 ✅ Étape 2 — re_editor : coloration Python/C/C++, autocomplétion, barre de symboles
│
├── app/                              ✅ application Flutter « nomad_mcu »
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app/                         app.dart, theme.dart, providers.dart (injection)
│   │   └── features/
│   │       ├── serial_monitor/          ✅ Étape 1
│   │       │   ├── domain/              log_entry.dart, rx_line_assembler.dart
│   │       │   ├── application/         serial_monitor_controller.dart, serial_monitor_state.dart
│   │       │   └── presentation/        serial_monitor_page.dart, widgets/
│   │       ├── editor/                  ✅ Étape 2 — onglets, enregistrement local, envoi et exécution sur la carte
│   │       ├── projects/                ✅ Étape 2 — projets locaux, brouillons automatiques
│   │       ├── micropython/             ✅ Étape 2 — raw REPL, explorateur du FS de la carte, « Run », transferts vérifiés
│   │       ├── settings/                ✅ Étape 2 — langue de l'interface (français / anglais)
│   │       └── flasher/                 🔜 Étape 3 — choix .bin/.uf2/.hex, progression
│   ├── android/app/src/main/            ✅ AndroidManifest.xml + res/xml/usb_device_filter.xml
│   ├── macos/Runner/                    ✅ *.entitlements (com.apple.security.device.serial)
│   └── test/                            ✅ ViewModel, assembleur de lignes, widget
│
└── services/
    └── cloud_compiler/               🔜 Étape 3+ — API REST + conteneurs éphémères
                                         (arduino-cli, pico-sdk, esp-idf, gcc-arm-none-eabi)
```

## Démarrage

Prérequis : Flutter ≥ 3.27 (Dart ≥ 3.6).

```bash
# 1. Générer les dossiers natifs. flutter create n'écrase pas les fichiers existants
#    (manifeste Android, entitlements macOS, main.dart, widget_test.dart).
cd app
flutter create . --org dev.nomadmcu --project-name nomad_mcu --platforms=android,ios,windows,macos,linux
git status            # vérifier que les fichiers versionnés sont restés intacts

# 2. Résoudre les dépendances du workspace (depuis la racine)
cd ..
flutter pub get

# 3. Lancer
cd app
flutter run -d windows                                      # ou macos / linux
flutter run -d <id-android>                                 # téléphone + câble OTG
flutter run -d windows --dart-define=NOMAD_FAKE_SERIAL=true # sans matériel (carte simulée)

# 4. Tests
flutter test                               # dans app/
cd ../packages/nomad_hal && flutter test   # HAL
```

## Notes par plateforme

| Plateforme | Point d'attention |
|---|---|
| Android | Câble/adaptateur OTG requis. Au premier branchement, accepter la permission USB (cocher « toujours » pour ne plus la voir). |
| Linux | Ajouter l'utilisateur au groupe `dialout` (Debian/Ubuntu) ou `uucp` (Arch), puis rouvrir la session. |
| macOS | L'entitlement `com.apple.security.device.serial` est déjà ajouté ; utiliser les ports `/dev/cu.*` (filtrés automatiquement). |
| Windows | Les CH340 / CP210x demandent parfois le pilote du fabricant. « Accès refusé » = port déjà ouvert ailleurs (Arduino IDE, Thonny…). |
| iOS | Pas d'USB-série possible (pas d'API USB Host publique). App utilisable en éditeur et en mode simulé ; transports BLE et WebREPL prévus. |

## Feuille de route

1. **PoC USB/série + moniteur** ✅ : énumération, hotplug, connexion, DTR/RTS, reset, journal texte/hex, envoi.
2. **Éditeur + MicroPython** ✅ : `nomad_editor`, raw REPL (`Ctrl-A` / `Ctrl-D`), transfert de fichiers
   par blocs encodés en base64 et vérifiés par CRC32, exécution de scripts, projets locaux, interface
   en français et en anglais. Validé sur un Pimoroni Badger 2040 (Windows et Android).
3. **Flasheur** 🧪 : onglet « Flasher ». RP2040 / RP2350 : bascule en BOOTSEL (touch 1200 bauds ou
   `machine.bootloader()`) puis copie du `.uf2` (Windows) ou écriture USB en PICOBOOT (Android), validé sur un Badger 2040. ESP32 / ESP8266 :
   protocole de la ROM d'esptool (SLIP, écriture compressée, vérification MD5), validé sur ESP32 et
   ESP32-S3 (Windows et Android) ; l'adresse d'écriture est déduite de l'en-tête du fichier. Le
   firmware MicroPython officiel se télécharge depuis l'app (micropython.org, Pimoroni). Restent :
   STM32 (AN3155, après la v1) et compilateur cloud optionnel.
4. **Distribution** : CI multi-OS, signature (Play Store, notarisation macOS, MSIX), mises à jour.
