# NomadMCU

IDE embarqué léger et multiplateforme (Android, iOS, Windows, macOS, Linux) pour éditer du
MicroPython et du C/C++, puis le transférer ou le flasher sur une carte par USB
(OTG sur mobile, port série sur desktop).

- Choix de stack : [docs/adr/0001-stack-flutter.md](docs/adr/0001-stack-flutter.md) (Flutter).
- État : **étape 1**, PoC de la couche USB/série et du moniteur série.

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
│   └── nomad_editor/                 🔜 Étape 2 — re_editor + grammaires Python/C
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
│   │       ├── editor/                  🔜 Étape 2 — onglets, coloration, autocomplétion
│   │       ├── projects/                🔜 Étape 2 — projets locaux, gestionnaire de fichiers
│   │       ├── micropython/             🔜 Étape 2 — REPL, explorateur du FS de la carte, « Run »
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
2. **Éditeur + MicroPython** : `nomad_editor`, raw REPL (`Ctrl-A` / `Ctrl-D`), transfert de fichiers
   par blocs encodés en base64, exécution de snippets.
3. **Flasheur** : ESP32 (esptool SLIP + stub, `enterEspBootloader` déjà prêt), puis RP2040
   (touch 1200 bauds → BOOTSEL → copie UF2), puis STM32 (AN3155). Compilateur cloud optionnel.
4. **Distribution** : CI multi-OS, signature (Play Store, notarisation macOS, MSIX), mises à jour.
