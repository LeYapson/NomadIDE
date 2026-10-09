# NomadMCU — Document de spécifications produit (PRD)

| | |
|---|---|
| **Produit** | NomadMCU (dépôt : NomadIDE) |
| **Version du document** | 0.2 — décisions de cadrage intégrées (cartes v1, compilation cloud, abonnement, langues) |
| **Date** | 2026-10-01 |
| **Statut du produit** | Étape 1 terminée (HAL USB/série + moniteur série) ; étape 2 en cours |
| **Documents liés** | [README.md](README.md) · [ADR 0001 — Flutter](docs/adr/0001-stack-flutter.md) |

### Légende des statuts (utilisée dans tout le document)

| Symbole | Sens |
|---|---|
| ✅ | Réalisé et validé sur matériel |
| 🧪 | Écrit, mais pas encore validé sur matériel |
| 🔜 | Planifié, pas encore écrit |
| ⚠️ | Risque ou point ouvert (voir §10 et §11) |
| ❌ | Hors périmètre ou techniquement impossible |

Priorités : **M** = Must (indispensable au MVP), **S** = Should, **C** = Could.

---

## 1. Contexte et problème

Programmer un microcontrôleur oblige aujourd'hui à jongler entre plusieurs outils : Arduino IDE ou PlatformIO pour le C/C++, Thonny ou mpremote pour MicroPython, esptool ou STM32CubeProgrammer pour le flashage. Ces outils sont lourds à installer, pensés pour le seul desktop, et inutilisables sur un téléphone ou une tablette, alors qu'un câble OTG suffit techniquement pour parler à une carte.

**Proposition de valeur :** une application unique, légère, identique sur mobile et desktop, qui permet d'écrire du code, de le transférer ou de le flasher, et d'observer la carte, avec une simple liaison USB.

## 2. Objectifs et non-objectifs

### Objectifs

1. **Une seule app, un seul parcours** sur Android, Windows, macOS et Linux ; iOS en éditeur et en mode simulé (voir §9).
2. **Zéro configuration** pour les cas courants : la carte est reconnue, le bon protocole est choisi.
3. **MicroPython de bout en bout** : éditer, envoyer sur la carte, exécuter, lire la sortie.
4. **C/C++ de bout en bout dans le MVP** : compilation via un service cloud, puis flashage, pour les cartes de la v1 : **ESP32, ESP32-S (S2/S3) et RP2040** (ex. Pimoroni Badger 2040). Bascule automatique en bootloader quand le matériel le permet. STM32 : après la v1.
5. **Utilisable hors ligne** : tout sauf la compilation cloud fonctionne sans réseau, sans compte et sans payer.
6. **Modèle économique** : l'application et ses fonctions locales restent gratuites ; la compilation cloud est un service par **abonnement mensuel**, avec une **offre gratuite limitée** par un quota d'usage.

### Non-objectifs (version 1)

- Débogage pas à pas (JTAG/SWD), points d'arrêt.
- Compilation locale C/C++ sur la machine (la compilation passe par le service cloud, ou par un binaire importé).
- Cartes STM32 (bootloader série AN3155) : reportées après la v1, la v1 se concentre sur ESP32 et RP2040.
- Gestionnaire de bibliothèques (équivalent de PlatformIO Library Manager).
- Prise en charge des AVR/Arduino classiques (protocole STK500) et du DFU USB natif STM32 (autre protocole que celui de l'étape 3).
- Accès USB-série sur iOS (impossible, voir §9).

## 3. Personas

| Persona | Contexte | Besoin principal |
|---|---|---|
| **Léa, étudiante / débutante** | Possède un ESP32 ou un Pico, un PC portable ou seulement un téléphone | Faire clignoter une LED en quelques minutes, sans installer de chaîne d'outils |
| **Marc, maker / enseignant** | Anime des ateliers, flashe des dizaines de cartes | Procédure identique pour tous les participants, quel que soit leur appareil |
| **Sam, développeur embarqué** | Utilise déjà PlatformIO sur desktop | Dépanner une carte sur le terrain depuis un téléphone : lire les logs, pousser un correctif |

## 4. Principes produit

- **Le chemin simple d'abord** : une carte branchée doit mener à un résultat visible en moins de 2 minutes.
- **Dire pourquoi ça échoue** : chaque erreur (permission, port occupé, carte non répondante) a un message qui indique l'action à faire.
- **Pas de verrou de plateforme** : une fonctionnalité impossible sur une plateforme est désactivée avec une explication, jamais cachée.
- **Le code reste à l'utilisateur** : projets stockés en local, aucun envoi réseau sans action explicite.

---

## 5. User stories et critères d'acceptation

Format des critères : **Étant donné** / **Quand** / **Alors**. Chaque story est rattachée à une étape de la feuille de route.

### Épopée A — Connexion et moniteur série (étape 1)

| ID | User story | Prio | Statut |
|---|---|---|---|
| A1 | En tant qu'utilisateur, je veux voir la liste des cartes branchées et leur type reconnu, pour choisir la bonne. | M | ✅ |
| A2 | En tant qu'utilisateur, je veux que la liste se mette à jour quand je branche ou débranche une carte. | M | ✅ |
| A3 | En tant qu'utilisateur, je veux me connecter à une carte en choisissant le débit, pour lire ses messages. | M | ✅ |
| A4 | En tant qu'utilisateur, je veux envoyer du texte à la carte, avec la fin de ligne de mon choix. | M | ✅ |
| A5 | En tant qu'utilisateur, je veux piloter DTR/RTS et redémarrer la carte depuis l'app. | S | ✅ |
| A6 | En tant qu'utilisateur, je veux voir le flux en texte ou en hexadécimal, horodaté, et l'effacer. | S | ✅ |
| A7 | En tant qu'utilisateur, je veux tester l'app sans carte grâce à une carte simulée. | S | ✅ |

**Critères d'acceptation**

- **A1/A2** — *Étant donné* une carte USB-série branchée, *quand* j'ouvre l'app ou que je branche la carte, *alors* elle apparaît en moins de 3 s, avec son nom et son couple VID:PID. *Quand* je la débranche, *alors* elle disparaît de la liste, et si j'y étais connecté, un message « La carte a été débranchée » s'affiche et l'état passe à « Déconnecté ».
- **A3** — *Quand* je clique sur « Connecter », *alors* sur Android la demande de permission USB s'affiche si nécessaire ; en cas de refus ou de port occupé, un message précis explique la cause et la solution (groupe `dialout` sous Linux, autre application ouverte, etc.).
- **A4** — *Quand* j'envoie une commande, *alors* elle apparaît dans le journal (couleur distincte) et les octets envoyés sont comptés.
- **A6** — *Étant donné* un flux à haut débit (921 600 bauds), *alors* l'interface reste fluide (pas de blocage perceptible) et le journal est plafonné à 5 000 lignes.

### Épopée B — Éditeur et projets (étape 2)

| ID | User story | Prio | Statut |
|---|---|---|---|
| B1 | Je veux éditer un fichier `.py`, `.c`, `.cpp`, `.h` avec coloration syntaxique et numéros de ligne. | M | ✅ (coloration et numéros de ligne validés sur Windows et Android ; fichier de 5 000 lignes fluide sur téléphone) |
| B2 | Je veux une auto-indentation adaptée au langage (Python, C). | M | ✅ (validé sur Android) |
| B3 | Je veux une autocomplétion de base (mots-clés, symboles du fichier ouvert). | S | ✅ (mots-clés Python/C/C++, noms MicroPython courants, identifiants du fichier ; validé sur Android) |
| B4 | Je veux créer, ouvrir, renommer, supprimer des fichiers et des projets en local. | M | ✅ (validé sur Android ; Ctrl+S validé sur Windows) |
| B5 | Je veux plusieurs fichiers ouverts en onglets, avec enregistrement automatique des brouillons. | S | ✅ (onglets et restauration des brouillons après fermeture de l'app validés sur Android) |
| B6 | Je veux un clavier mobile adapté au code (barre de symboles `: ( ) [ ] { } " _ Tab`). | M | ✅ (validé sur Android avec le clavier virtuel) |

**Critères d'acceptation**

- **B1** — *Quand* j'ouvre un fichier de 5 000 lignes, *alors* le défilement et la saisie restent fluides sur un téléphone d'entrée de gamme (cible : ≥ 30 images/s).
- **B2** — *Quand* j'appuie sur Entrée après `if x:`, *alors* la ligne suivante est indentée d'un niveau.
- **B4** — *Quand* je ferme l'app brutalement, *alors* aucun fichier enregistré n'est perdu et les brouillons non enregistrés sont proposés à la réouverture.
- **B6** — *Étant donné* un téléphone, *alors* les symboles de code courants sont accessibles sans changer de disposition du clavier.

### Épopée C — MicroPython (étape 2)

| ID | User story | Prio | Statut |
|---|---|---|---|
| C1 | Je veux ouvrir un REPL interactif sur ma carte MicroPython. | M | ✅ (moniteur série validé à l'étape 1, avec Ctrl-C / Ctrl-D) |
| C2 | Je veux exécuter le fichier ou la sélection courante sur la carte sans l'enregistrer dessus (« Run »). | M | ✅ (fichier et sélection validés sur Windows et Android avec un Badger 2040) |
| C3 | Je veux voir les fichiers de la carte et en téléverser, télécharger, renommer, supprimer. | M | ✅ (liste, lecture, écriture vérifiée par CRC32, suppression, envoi depuis un projet, téléchargement et renommage validés sur Badger 2040 depuis un téléphone Android ; coupure de câble testée avec une fausse carte) |
| C4 | Je veux enregistrer mon `main.py` sur la carte pour qu'il s'exécute au démarrage. | M | ✅ (validé sur Android avec un Badger 2040) |
| C5 | Je veux interrompre un programme (Ctrl-C) et redémarrer la carte (soft reset). | M | ✅ (arrêt d'une boucle infinie et soft reset validés sur Badger 2040) |
| C6 | Je veux installer ou mettre à jour le firmware MicroPython sur ma carte. | S | 🔜 (voir épopée D) |

**Critères d'acceptation**

- **C2** — *Étant donné* une carte MicroPython connectée, *quand* je lance « Run », *alors* la sortie du programme s'affiche en direct dans le terminal ; une exception apparaît en rouge avec sa trace ; l'exécution peut être arrêtée à tout moment.
- **C3** — *Quand* je téléverse un fichier de 100 Ko, *alors* une progression s'affiche, le transfert est vérifié à la fin (taille ou somme de contrôle), et une coupure du câble est signalée sans corrompre silencieusement le fichier.
- **C4** — *Quand* j'enregistre `main.py` puis redémarre la carte, *alors* le programme se lance seul.
- **C5** — *Étant donné* un programme en boucle infinie, *quand* j'appuie sur « Stop », *alors* la carte reprend la main en moins de 2 s.

### Épopée D — Flashage C/C++ et firmware (étape 3)

| ID | User story | Prio | Statut |
|---|---|---|---|
| D1 | Je veux flasher un binaire `.bin` sur un ESP32. | M | 🔜 |
| D2 | Je veux flasher un fichier `.uf2` sur un RP2040/RP2350. | M | ✅ sur Windows avec un Badger 2040 (Android : 🔜 ⚠️ PICOBOOT) |
| D3 | Je veux flasher un `.bin`/`.hex` sur un STM32 via son bootloader série. | C (post-v1) | 🔜 |
| D4 | Je veux que l'app mette la carte en mode bootloader quand c'est possible (DTR/RTS, 1200 bauds, ou `machine.bootloader()` depuis MicroPython). | M | 🧪 (séquences DTR/RTS et 1200 bauds écrites) |
| D5 | Je veux compiler mon code C/C++ via un service cloud et flasher le résultat directement. | M | 🔜 |
| D6 | Je veux voir une progression fiable et une vérification du flash. | M | 🔜 |
| D7 | Je veux installer le firmware MicroPython adapté à ma carte (ex. firmware Pimoroni pour la Badger 2040). | S | 🔜 |

**Critères d'acceptation**

- **D1** — *Étant donné* un ESP32 avec circuit d'auto-reset, *quand* je lance le flash, *alors* l'app met la carte en bootloader, écrit à la bonne adresse, vérifie, puis redémarre la carte. *Étant donné* une carte sans auto-reset, *alors* l'app affiche les instructions pour maintenir BOOT (étape guidée).
- **D2** — *Étant donné* un Pico en fonctionnement, *quand* je lance le flash, *alors* l'app le fait passer en BOOTSEL (touch 1200 bauds) puis écrit le fichier ; le message d'état distingue clairement « carte réapparue en BOOTSEL » de « échec ».
- **D3** — *Étant donné* un STM32 avec BOOT0 actif et un adaptateur USB-série, *alors* l'app détecte le bootloader (réponse ACK `0x79`) avant d'écrire.
- **D5** — *Quand* je lance la compilation, *alors* l'app indique explicitement quel code est envoyé et vers quel serveur, demande une confirmation la première fois, et affiche les erreurs du compilateur avec numéros de ligne cliquables. *Quand* la compilation réussit, *alors* le binaire est téléchargé et le flash peut être lancé en un clic. Le compilateur cible la bonne carte (ESP32 / ESP32-S / RP2040) d'après la carte détectée ou le projet.
- **D7** — *Étant donné* une carte RP2040 en BOOTSEL ou un ESP32, *alors* l'app propose le firmware correspondant (version indiquée) et le flashe ; pour la Badger 2040, c'est le firmware Pimoroni (qui embarque ses modules d'affichage) et non le MicroPython générique.
- **D6** — *Quand* une écriture est interrompue (câble débranché), *alors* l'app l'indique clairement et rappelle que la carte peut avoir un firmware incomplet, avec la marche à suivre pour la récupérer.

### Épopée F — Compte, abonnement et quotas (compilation cloud)

Le compte n'est exigé **que** pour la compilation cloud. Éditeur, moniteur, MicroPython et flash d'un binaire local restent utilisables sans compte.

| ID | User story | Prio | Statut |
|---|---|---|---|
| F1 | Je veux utiliser la compilation cloud avec l'offre gratuite sans saisir de moyen de paiement. | M | 🔜 |
| F2 | Je veux voir mon quota restant (compilations, ou temps de calcul) avant de lancer une compilation. | M | 🔜 |
| F3 | Je veux m'abonner mensuellement pour lever la limite, et résilier facilement. | M | 🔜 |
| F4 | Je veux savoir clairement ce qui reste gratuit et local quoi qu'il arrive. | M | 🔜 |

**Critères d'acceptation**

- **F1/F2** — *Étant donné* un compte gratuit, *quand* j'atteins le quota, *alors* la compilation est refusée avec un message qui indique la date de renouvellement du quota, l'offre payante, et le rappel que l'import d'un binaire déjà compilé fonctionne toujours.
- **F3** — *Quand* je résilie, *alors* l'abonnement reste actif jusqu'à la fin de la période payée, et mes projets (stockés en local) ne sont pas affectés.
- **F4** — *Étant donné* l'absence de réseau ou de compte, *alors* aucune fonction locale n'est dégradée.

### Épopée E — Expérience multi-plateforme (étape 4)

| ID | User story | Prio | Statut |
|---|---|---|---|
| E1 | Je veux la même interface sur téléphone, tablette et ordinateur, adaptée à la taille d'écran. | M | 🧪 |
| E2 | Je veux que l'app s'ouvre (ou me le propose) quand je branche une carte sur Android. | S | ✅ (filtre USB du manifeste) |
| E3 | Je veux utiliser l'app en thème clair ou sombre, selon le système. | S | ✅ |
| E4 | Je veux être informé clairement des limites de ma plateforme (iOS notamment). | M | 🧪 |
| E5 | Je veux recevoir les mises à jour de l'app facilement. | C | 🔜 |
| E6 | Je veux utiliser l'app en français ou en anglais, selon la langue du système ou mon choix. | M | ✅ (changement de langue validé sur Android) |

---

## 6. Matrice de compatibilité

### 6.1 Plateformes hôtes

| Plateforme | Transport série | Éditeur | MicroPython | Flashage | Statut |
|---|---|---|---|---|---|
| Android 8+ (OTG requis) | API USB Host (pilotes userland) | 🔜 | 🧪 | 🔜 ⚠️ UF2 | Moniteur ✅ |
| Windows 10/11 | libserialport (COMx) | 🔜 | 🧪 | 🔜 | Moniteur ✅ |
| macOS 12+ | libserialport (`/dev/cu.*`) | 🔜 | 🧪 | 🔜 | 🧪 |
| Linux (glibc) | libserialport (`/dev/ttyUSB*`, `ttyACM*`) | 🔜 | 🧪 | 🔜 | 🧪 |
| iOS | ❌ Aucune API USB Host publique (MFi uniquement) | 🔜 | ❌ (futur : BLE/WebREPL) | ❌ | Mode simulé uniquement |

> Seules les cases « Moniteur ✅ » ont été validées sur matériel (Android et Windows), conformément au retour de l'étape 1. macOS et Linux sont écrits mais à valider.

### 6.2 Puces USB-série (pont USB↔UART)

| Puce | VID:PID | Android | Desktop | Remarque |
|---|---|---|---|---|
| FTDI FT232R / FT231X / FT2232 / FT232H | `0403:6001/6015/6010/6014` | 🧪 | 🧪 | Pilote système sur desktop |
| Silicon Labs CP2102 / CP2104 | `10C4:EA60` | 🧪 | 🧪 | Pilote fabricant parfois requis sous Windows |
| WCH CH340 / CH341 | `1A86:7523 / 5523` | 🧪 | 🧪 | Pilote fabricant souvent requis sous Windows/macOS |
| WCH CH9102 | `1A86:55D4` | 🧪 | 🧪 | Mode CDC |
| Prolific PL2303 | `067B:2303` | 🧪 | 🧪 | Contrefaçons fréquentes, pilotes capricieux |
| CDC-ACM (USB natif) | variable | 🧪 | 🧪 | Pas de pilote spécifique |

### 6.3 Cartes cibles

**Cartes de la v1 : ESP32, ESP32-S (S2/S3, à confirmer) et RP2040 (ex. Pimoroni Badger 2040).** Les autres lignes servent à la reconnaissance et à la suite.

| Famille | Exemples | Reconnaissance (VID:PID) | MicroPython | Flashage binaire | Mise en bootloader auto |
|---|---|---|---|---|---|
| **ESP32 / ESP32-S2/S3/C3/C6** | DevKitC, XIAO ESP32 | via pont USB-série, ou `303A:1001` (USB natif) | 🧪 | 🔜 esptool/SLIP | 🧪 DTR/RTS (auto-reset) |
| **ESP8266** | NodeMCU, Wemos D1 | via pont USB-série | 🧪 | 🔜 (même protocole, stub différent) | 🧪 DTR/RTS |
| **RP2040 / RP2350** | Raspberry Pi Pico, Pico W | `2E8A:0005` (MicroPython), `2E8A:000A` (SDK), `2E8A:0003` (BOOTSEL) | 🧪 | 🔜 UF2 ⚠️ | 🧪 touch 1200 bauds |
| **Pimoroni Badger 2040** (v1) | RP2040 + écran e-ink ; version « W » avec Wi-Fi | à relever sur la carte réelle (le VID est `2E8A`, le PID peut différer du Pico) ⚠️ | 🧪 firmware Pimoroni recommandé | 🔜 UF2 ⚠️ | Boutons BOOT/RST, ou `machine.bootloader()` depuis MicroPython |
| **STM32** (post-v1) | Nucleo (ST-LINK VCP), Blue Pill | `0483:374B/374E` (VCP), `0483:5740` | 🧪 (Pyboard `F055:9800`) | ❌ reporté (AN3155 prévu après la v1) | ❌ manuel (BOOT0) |
| **Arduino (SAMD, nRF52, RP2040)** | Nano 33, Feather | `2341:*`, `239A:*` | selon carte | 🔜 via UF2 | 🧪 touch 1200 bauds |
| **Arduino AVR** (Uno, Nano) | | `2341:0043`, CH340 | ❌ | ❌ (STK500 hors périmètre v1) | – |
| **STM32 DFU natif** | | `0483:DF11` | – | ❌ (hors périmètre v1) | – |

La table VID:PID du code ([usb_chip.dart](packages/nomad_hal/lib/src/domain/usb_chip.dart)) et le filtre Android ([usb_device_filter.xml](app/android/app/src/main/res/xml/usb_device_filter.xml)) doivent rester synchronisés avec ce tableau.

### 6.4 Banc de test matériel

Avant de passer une ligne de ce tableau à ✅, il faut un test manuel documenté (carte, câble, version de l'OS, résultat). Banc minimal de la v1 : 1 ESP32 DevKit (pont CP2102 ou CH340), 1 ESP32-S2 ou S3 (USB natif), 1 Pimoroni Badger 2040 (et si possible 1 Raspberry Pi Pico standard pour comparer), un téléphone Android avec adaptateur OTG, un PC Windows et un Mac ou un Linux.

---

## 7. Parcours utilisateurs

### 7.1 Parcours « Premier programme MicroPython »

| Étape | Desktop (Windows/macOS/Linux) | Mobile (Android) |
|---|---|---|
| 1. Brancher | Câble USB direct | Câble ou adaptateur OTG |
| 2. Détection | Carte listée automatiquement | Android propose d'ouvrir NomadMCU ; permission USB à accepter (case « toujours » recommandée) |
| 3. Connexion | « Connecter » ; le REPL affiche `>>>` | Idem |
| 4. Écriture | Éditeur plein écran, raccourcis clavier | Éditeur avec barre de symboles, écran partagé éditeur/terminal en paysage |
| 5. Exécution | Bouton « Run » (ou raccourci), sortie dans le terminal | Bouton « Run » flottant, sortie dans un panneau repliable |
| 6. Installation | « Enregistrer sur la carte » → `main.py` | Idem |
| Critère de réussite | Premier résultat visible en < 2 min après branchement | Idem |

### 7.2 Parcours « Flasher un binaire sur ESP32 »

| Étape | Desktop | Mobile |
|---|---|---|
| 1. Fichier | Sélection d'un `.bin` local, ou compilation cloud | Sélecteur de fichiers Android, ou compilation cloud |
| 2. Cible | Carte détectée, famille proposée (modifiable) | Idem |
| 3. Bootloader | Automatique (DTR/RTS) ; sinon étape guidée « maintenez BOOT » | Idem ; la latence des commandes DTR/RTS est plus élevée sur Android ⚠️, repli guidé prévu |
| 4. Écriture | Barre de progression, vitesse choisie (115 200 → 921 600 bauds) | Débit plus prudent par défaut |
| 5. Fin | Vérification, redémarrage, bascule vers le moniteur série | Idem |
| Erreur | Message avec cause probable et action | Idem, plus rappel de la batterie/du câble OTG |

### 7.3 Parcours « Dépannage terrain » (Sam)

1. Brancher la carte au téléphone → le moniteur série s'ouvre sur le flux de logs.
2. Ctrl-C pour interrompre, lecture de la trace d'erreur.
3. Ouverture du fichier fautif depuis la carte (explorateur de fichiers), correction, enregistrement.
4. Soft reset, vérification dans les logs.

### 7.4 Parcours « iOS »

L'utilisateur ouvre l'app, voit un bandeau expliquant que l'USB-série n'est pas disponible sur iOS, peut éditer ses projets et essayer la carte simulée. Les transports BLE (UART Nordic) et WebREPL (Wi-Fi) sont étudiés pour plus tard.

---

## 8. Exigences non fonctionnelles

| Domaine | Exigence |
|---|---|
| **Performance** | Interface fluide à 921 600 bauds en réception continue ; journal plafonné ; démarrage à froid < 3 s sur desktop. |
| **Fiabilité** | Aucune corruption silencieuse : tout transfert ou flash est vérifié ; toute perte de connexion est signalée. |
| **Taille** | Application légère : binaire Android < 50 Mo (cible, à mesurer). |
| **Hors ligne** | Édition, moniteur, REPL, transfert et flash d'un binaire local fonctionnent sans réseau. |
| **Confidentialité** | Aucune télémétrie par défaut. Le code n'est envoyé au service de compilation qu'après confirmation explicite, et n'est pas conservé au-delà de la compilation (durée de rétention à définir). |
| **Sécurité** | Service de compilation : conteneurs éphémères, sans réseau, limites CPU/mémoire/durée, quotas par compte ; authentification obligatoire pour la compilation uniquement. |
| **Disponibilité du service** | Si le service est indisponible, l'app le dit clairement et propose l'import de binaire ; aucune autre fonction n'est touchée. |
| **Accessibilité** | Taille de police réglable, contraste suffisant, cibles tactiles ≥ 48 dp sur mobile. |
| **Internationalisation** | Interface en **français et anglais** dès la v1 (langue du système par défaut, choix manuel possible). Chaînes externalisées (ARB / `flutter_localizations`) **dès l'étape 2**, pour ne pas avoir à reprendre les écrans existants. |
| **Testabilité** | Les protocoles sont testables sans matériel (fausse carte) ; les parcours matériels sont couverts par le banc de test §6.4. |
| **Observabilité** | Journal de diagnostic exportable (versions, carte détectée, trames échouées) pour les rapports de bug. |

## 9. Contraintes de plateforme

- **Android** : pas d'accès aux fichiers `/dev` ; tout passe par `UsbManager` avec permission utilisateur. Le périphérique n'est pas toujours disponible si l'appareil ne fournit pas assez de courant en OTG.
- **iOS** : pas d'API USB Host publique ; DriverKit sur iPad exige un entitlement Apple. Prévu : mode éditeur + simulateur, puis BLE/WebREPL.
- **macOS** : sandbox, entitlement `com.apple.security.device.serial` requis (déjà ajouté) ; ports `/dev/cu.*` uniquement.
- **Linux** : l'utilisateur doit appartenir au groupe `dialout` ou `uucp`.
- **Windows** : certains ponts (CH340, CP210x) nécessitent le pilote du fabricant ; un port ouvert dans une autre application renvoie « Accès refusé ».

## 10. Risques et points ouverts

| # | Risque / question | Impact | Piste |
|---|---|---|---|
| R1 | **UF2 sur Android** : en BOOTSEL, le Pico se présente comme un disque USB. Android ne permet pas d'y écrire simplement depuis une application. | D2 non réalisable tel quel sur mobile | Parler le protocole **PICOBOOT** (USB bulk) via un plugin USB maison, ou guider l'utilisateur vers le sélecteur de fichiers système. À trancher avant l'étape 3. |
| R2 | **Latence DTR/RTS sur Android** : les séquences de reset des ESP32 sont chronométrées à quelques ms. | D1/D4 peu fiables sur mobile | Valider sur matériel ; repli guidé « maintenez BOOT ». |
| R3 | **Plugins communautaires** (`usb_serial`, `flutter_libserialport`) : maintenance et API non garanties. | Blocage sur une mise à jour | Isolés derrière la HAL ; plugin Kotlin maison en solution de secours. |
| R4 | **Éditeur Flutter** moins riche que CodeMirror/Monaco. | B1–B3 en deçà des attentes | Solution de secours : CodeMirror 6 dans une WebView, isolé dans `nomad_editor`. |
| R5 | **Service de compilation cloud** (désormais dans le MVP) : coût de calcul, abus, confidentialité, exploitation 24/7. C'est un projet à part entière (API, conteneurs, files d'attente, facturation). | Charge importante, risque de retard de l'étape 3 | Démarrer par un seul toolchain par famille de carte ; quotas stricts dès le premier jour ; l'import de binaire reste le plan B ; décision d'hébergement à prendre. |
| R8 | **Abonnement et boutiques d'applications** : sur Google Play, un abonnement à un service numérique acheté dans l'app passe en principe par Google Play Billing (commission). | Modèle économique mobile | Vérifier les règles en vigueur avant de choisir où se fait le paiement (web ou boutique) ; ne pas afficher de prix dans l'app avant d'avoir tranché. |
| R6 | **Pilotes Windows** (CH340, CP210x, PL2303 contrefaits). | Support utilisateur | Détection et message dédié avec lien vers le pilote. |
| R7 | **Brick de carte** lors d'un flash interrompu. | Perte de confiance | Vérifications, avertissements, procédure de récupération documentée. |

**Décisions de cadrage (2026-10-01)**

| Sujet | Décision |
|---|---|
| Cartes v1 | ESP32, ESP32-S, RP2040 (ex. Pimoroni Badger 2040) |
| Compilation C/C++ | Dans le MVP, via service cloud |
| Modèle économique | Abonnement mensuel pour la compilation cloud ; offre gratuite avec limite d'usage |
| Langues | Français et anglais |

**Questions ouvertes**

1. « ESP32-S » désigne-t-il l'ESP32-S2, l'ESP32-S3, ou les deux ? Et l'ESP32-C3 (USB natif, très répandu) est-il à inclure ?
2. Quelles chaînes de compilation proposer : Arduino (arduino-cli, core ESP32 et RP2040) pour démarrer, ESP-IDF et Pico SDK ensuite ? Cela fixe le périmètre du service cloud.
3. Quelle limite pour l'offre gratuite (nombre de compilations par mois, durée de calcul, taille du projet) et quel prix pour l'offre payante ? À fixer avec une estimation du coût d'une compilation.
4. Où se fait le paiement (site web, boutiques d'applications) ? Voir R8.
5. Le code du dépôt est sous licence MIT : l'application reste-t-elle open source avec seulement le service cloud payant, ou le service est-il aussi publié ? Cela influence ce qui est protégé.

## 11. Indicateurs de succès

| Indicateur | Cible v1 |
|---|---|
| Temps entre le branchement et le premier programme MicroPython exécuté | < 2 min (utilisateur débutant) |
| Taux de réussite du flash ESP32 sur le banc de test | ≥ 95 % sur 20 essais, desktop et Android |
| Cartes de la matrice 6.3 validées sur matériel | Toutes les lignes « Must » en ✅ |
| Plantages | < 1 % des sessions |
| Parité des fonctionnalités mobile/desktop | Écarts documentés uniquement pour les limites de plateforme |

## 12. Jalons

| Jalon | Contenu | Stories | Statut |
|---|---|---|---|
| **M1** — Étape 1 | HAL USB/série, moniteur série, carte simulée | A1–A7, E2, E3 | ✅ |
| **M2** — Étape 2 | Éditeur, projets, raw REPL, explorateur de fichiers de la carte, « Run », internationalisation FR/EN | B1–B6, C1–C5, E6 | ✅ (écrit, testé et validé sur Badger 2040 avec Windows et Android) |
| **M3a** — Étape 3 | Flash ESP32/ESP32-S et RP2040, firmware MicroPython | D1, D2, D4, D6, D7, C6 | 🔜 |
| **M3b** — Étape 3 | Service de compilation cloud, compte, quotas, abonnement | D5, F1–F4 | 🔜 |
| Post-v1 | Flash STM32 (AN3155) | D3 | 🔜 |
| **M4** — Étape 4 | CI/CD, signature et distribution (Play Store, MSIX, notarisation macOS), mises à jour | E1, E4, E5 | 🔜 |

La date de chaque jalon sera fixée après la décision sur R1 et le banc de test.

---

## Historique du document

| Version | Date | Changement |
|---|---|---|
| 0.1 | 2026-10-01 | Première version |
| 0.2 | 2026-10-01 | Cartes v1 (ESP32, ESP32-S, RP2040/Badger 2040), compilation cloud dans le MVP, abonnement + offre gratuite limitée, FR/EN ; STM32 reporté ; ajout épopée F, D7, E6, R8 |
| 0.3 | 2026-10-08 | Étape 2 : statuts de B1–B6, C2–C5 et E6 mis à jour après implémentation et validation sur Badger 2040 (Windows, Android) |
| 0.4 | 2026-10-08 | Étape 2 : B3, B4, B5, C3 et E6 validés sur Android ; reste B1 (fluidité), B2, C2 (sélection), C4, C5 (délai d'arrêt) |
| 0.5 | 2026-10-08 | Étape 2 terminée : B1, B2, C2, C4 et C5 validés sur Android et Windows ; jalon M2 ✅ |
