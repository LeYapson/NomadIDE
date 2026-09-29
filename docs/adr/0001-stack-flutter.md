# ADR 0001 — Flutter comme socle cross-platform

- **Statut :** accepté (PoC étape 1)
- **Date :** 2026-09-29

## Contexte

NomadMCU doit tourner sur Android, iOS, Windows, macOS et Linux avec une seule base de code,
et parler à des cartes via **USB-série** (FTDI, CP210x, CH34x, PL2303, CDC-ACM).

La contrainte qui décide de tout est **l'USB OTG sur Android** :
Android n'expose pas `/dev/ttyUSB*` aux applications. Tout passe par l'API Java `UsbManager`
(permission utilisateur + pilotes « userland » réimplémentant chaque puce). Les bibliothèques
natives desktop (`libserialport`, `serialport-rs`, `espflash`…) **ne fonctionnent donc pas** sur
Android sans root.

## Options comparées

| Critère | Flutter (Dart) | Tauri 2 (Rust + Web) |
|---|---|---|
| USB-série Android | Plugin `usb_serial` existant (pilotes CDC/FTDI/CP210x/CH34x/PL2303) | Aucun plugin mûr : écrire un plugin Kotlin + pont IPC |
| Série desktop | `flutter_libserialport` (FFI, lecture dans un isolate) | `serialport-rs`, excellent |
| Débit des octets bruts | Canal natif → `Uint8List`, pas de sérialisation JSON | IPC mobile en JSON (surcoût sur les gros flash) |
| Réutiliser des outils existants | Protocoles à porter en Dart (esptool-js, mpremote servent de référence) | `espflash` réutilisable… mais seulement sur desktop |
| Éditeur de code | `re_editor` (Dart pur, gère les gros fichiers) — moins riche que CM6 | CodeMirror 6 natif ; Monaco est mauvais sur mobile |
| UI mobile tactile | Excellente, rendu identique partout | WebView, clavier virtuel parfois capricieux |
| Tests sans matériel | `flutter test` + faux transport injecté | Tests Rust + tests JS séparés |

## Décision

**Flutter.** Le cœur de la valeur du produit (flasher depuis un téléphone en OTG) est déjà
couvert par l'écosystème Flutter, alors qu'avec Tauri il faudrait construire et maintenir
nous-mêmes toute la couche USB Android.

Le point faible de Flutter, c'est l'éditeur. On le compense avec `re_editor` et des grammaires
`highlight`. Si ça ne suffit pas, on garde en solution de secours un CodeMirror 6 dans une WebView,
isolé dans le package `nomad_editor`.

## Conséquences

- Toute la logique matérielle vit dans le package `nomad_hal`, derrière les interfaces
  `SerialTransport` / `SerialConnection`. Les plugins communautaires restent un détail
  d'implémentation : on peut les remplacer par un plugin Kotlin maison (basé sur
  `usb-serial-for-android`) sans toucher à l'UI ni aux protocoles.
- Les protocoles (raw REPL, esptool/SLIP, UF2, AN3155) sont écrits en **Dart pur**, testables
  sans carte, au-dessus d'une simple `SerialConnection`.
- **iOS :** aucune stack ne contourne la limite. iOS n'a pas d'API USB Host publique :
  seuls les accessoires certifiés MFi sont accessibles, et DriverKit sur iPad exige
  un entitlement Apple. Sur iOS, NomadMCU sera donc un éditeur, avec des transports
  **BLE** (Nordic UART) et **WebREPL** (Wi-Fi) à ajouter plus tard comme nouvelles
  implémentations de `SerialTransport`.
