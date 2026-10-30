# NomadIDE — Document de spécifications produit (PRD)

| | |
|---|---|
| **Produit** | NomadIDE |
| **Version du document** | 0.19 — préparation de la release 0.1.0 bêta (desktop) |
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
| C6 | Je veux installer ou mettre à jour le firmware MicroPython sur ma carte. | S | ✅ (fait par D7 : téléchargement et flash du firmware depuis l'app) |

**Critères d'acceptation**

- **C2** — *Étant donné* une carte MicroPython connectée, *quand* je lance « Run », *alors* la sortie du programme s'affiche en direct dans le terminal ; une exception apparaît en rouge avec sa trace ; l'exécution peut être arrêtée à tout moment.
- **C3** — *Quand* je téléverse un fichier de 100 Ko, *alors* une progression s'affiche, le transfert est vérifié à la fin (taille ou somme de contrôle), et une coupure du câble est signalée sans corrompre silencieusement le fichier.
- **C4** — *Quand* j'enregistre `main.py` puis redémarre la carte, *alors* le programme se lance seul.
- **C5** — *Étant donné* un programme en boucle infinie, *quand* j'appuie sur « Stop », *alors* la carte reprend la main en moins de 2 s.

### Épopée D — Flashage C/C++ et firmware (étape 3)

| ID | User story | Prio | Statut |
|---|---|---|---|
| D1 | Je veux flasher un binaire `.bin` sur un ESP32. | M | ✅ sur ESP32 et ESP32-S3, avec l'app Windows et avec l'app Android |
| D2 | Je veux flasher un fichier `.uf2` sur un RP2040/RP2350. | M | ✅ sur Windows avec un Badger 2040, en BOOTSEL manuel et en bascule automatique et sur Android avec un Badger 2040 en OTG, par le protocole PICOBOOT (autorisation USB, effacement, écriture, relecture de vérification) |
| D3 | Je veux flasher un `.bin`/`.hex` sur un STM32 via son bootloader série. | C (post-v1) | 🔜 |
| D4 | Je veux que l'app mette la carte en mode bootloader quand c'est possible (DTR/RTS, 1200 bauds, ou `machine.bootloader()` depuis MicroPython). | M | ✅ RP2040 : bascule automatique validée sur Badger 2040 (MicroPython : `machine.bootloader()` ; touch 1200 bauds pour Arduino/SDK, non testé) ; ✅ ESP32 et ESP32-S3 : reset automatique par DTR/RTS validé (un seul clic sur « Flasher », sans toucher à BOOT ni EN), sur Windows et Android |
| D5 | Je veux compiler mon code C/C++ via un service cloud et flasher le résultat directement. | M | 🔜 |
| D6 | Je veux voir une progression fiable et une vérification du flash. | M | ✅ progression et vérification (MD5 pour l'ESP, redémarrage de la carte pour l'UF2) validées sur matériel ; débranchement en pleine écriture validé sur ESP : message d'erreur avec avertissement « carte possiblement incomplète » et marche à suivre |
| D7 | Je veux installer le firmware MicroPython adapté à ma carte (ex. firmware Pimoroni pour la Badger 2040). | S | ✅ ESP32 et ESP32-S3 : recherche, téléchargement et flash du firmware officiel validés sur Windows et Android ; ✅ Badger 2040 : firmware Pimoroni téléchargé et flashé depuis l'app Windows, REPL et code exécuté vérifiés ; 🧪 Pico et Pico W (version et téléchargement validés contre micropython.org, flash depuis l'app non essayé), Badger 2040 W |
| D8 | Je veux flasher plusieurs fichiers à des adresses distinctes en une seule passe (ex. bootloader `0x1000`, table de partitions `0x8000`, application `0x10000`), pour les projets Arduino et ESP-IDF. | S | 🧪 écrit et testé avec une fausse ROM : chaque fichier est reconnu par son contenu (image complète, bootloader, table de partitions, données OTA, application), l'adresse vient de la table de partitions quand elle est fournie, chevauchements refusés, un MD5 par fichier, un seul redémarrage ; à valider sur une carte avec un projet Arduino |

**Critères d'acceptation**

- **D1** — *Étant donné* un ESP32 avec circuit d'auto-reset, *quand* je lance le flash, *alors* l'app met la carte en bootloader, écrit à la bonne adresse, vérifie, puis redémarre la carte. *Étant donné* une carte sans auto-reset, *alors* l'app affiche les instructions pour maintenir BOOT (étape guidée).
- **D2** — *Étant donné* un Pico en fonctionnement, *quand* je lance le flash, *alors* l'app le fait passer en BOOTSEL (touch 1200 bauds) puis écrit le fichier ; le message d'état distingue clairement « carte réapparue en BOOTSEL » de « échec ».
- **D3** — *Étant donné* un STM32 avec BOOT0 actif et un adaptateur USB-série, *alors* l'app détecte le bootloader (réponse ACK `0x79`) avant d'écrire.
- **D5** — *Quand* je lance la compilation, *alors* l'app indique explicitement quel code est envoyé et vers quel serveur, demande une confirmation la première fois, et affiche les erreurs du compilateur avec numéros de ligne cliquables. *Quand* la compilation réussit, *alors* le binaire est téléchargé et le flash peut être lancé en un clic. Le compilateur cible la bonne carte (ESP32 / ESP32-S / RP2040) d'après la carte détectée ou le projet.
- **D7** — *Étant donné* une carte RP2040 en BOOTSEL ou un ESP32, *alors* l'app propose le firmware correspondant (version indiquée) et le flashe ; pour la Badger 2040, c'est le firmware Pimoroni (qui embarque ses modules d'affichage) et non le MicroPython générique.
- **D8** — *Quand* je prépare un flash ESP, *alors* je peux ajouter plusieurs fichiers, chacun avec son adresse (déduite de l'en-tête quand c'est possible, modifiable). *Si* deux fichiers se chevauchent en mémoire flash, ou si un fichier ne correspond pas à la puce détectée, *alors* l'app refuse avant toute écriture. Chaque fichier est vérifié (MD5), la progression est globale, et la carte n'est redémarrée qu'une fois, à la fin.
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
| E3 | Je veux utiliser l'app en thème clair ou sombre, selon le système. | S | ✅ (et choix manuel clair / sombre dans les réglages) |
| E4 | Je veux être informé clairement des limites de ma plateforme (iOS notamment). | M | 🧪 |
| E5 | Je veux recevoir les mises à jour de l'app facilement. | C | 🧪 releases GitHub (Windows, Linux, macOS) publiées par tag ; l'app signale une version plus récente au démarrage (désactivable) et ouvre sa page ; pas encore de mise à jour automatique ni de Play Store |
| E6 | Je veux utiliser l'app en français ou en anglais, selon la langue du système ou mon choix. | M | ✅ (changement de langue validé sur Android) |

### Épopée G — UX/UI et accessibilité

Référentiels visés : **WCAG 2.2 niveau AA** et **RGAA 4.1**. Méthode : la conception part des problèmes observés sur le terrain (clavier tactile, petits écrans, atelier sombre), pas d'un catalogue de composants.

| ID | User story | Prio | Statut |
|---|---|---|---|
| G1 | Je veux une barre de raccourcis tactile au-dessus du clavier (`Tab`, `:`, `{`, `}` ; `Ctrl+C` et `Ctrl+D` dans la console MicroPython) pour programmer sans chercher les symboles. | M | 🧪 existe déjà (B6) ; reste la mise en conformité : cibles 48 dp, libellés traduits, sémantique |
| G2 | Je veux que le flash soit un parcours guidé (1. Fichier, 2. Carte, 3. Écriture) lisible sur un écran de 360 dp, sans surcharge. | M | 🧪 trois étapes avec divulgation progressive (étape terminée repliée sur son résumé, options avancées et firmware officiel repliés), testé à 360 dp et à 150 % de taille de texte ; à valider sur téléphone |
| G3 | Je veux qu'un lecteur d'écran (TalkBack, VoiceOver) annonce l'état de l'app : carte connectée ou déconnectée, flash en cours avec son avancement, erreur. | M | 🧪 état de connexion, progression (par paliers de 25 %) et résultats annoncés, zones sans nom nommées ; testé en simulation, à valider avec TalkBack sur téléphone |
| G4 | Je veux que toutes les zones tactiles fassent au moins 48 × 48 dp. | M | 🧪 vérifié par test sur les 5 écrans (thèmes sombre et clair, téléphone de 360 dp) ; texte agrandi à 150 % et 200 % sans débordement ; à valider sur téléphone |
| G5 | Je veux un thème sombre lisible : contraste ≥ 4,5:1 pour le texte et ≥ 3:1 pour les composants et le focus. | M | 🧪 appliqué et testé automatiquement (texte des 5 écrans, thèmes sombre et clair) ; à valider à l'œil sur téléphone |
| G6 | Je veux une identité visuelle cohérente (palette ci-dessous) appliquée à tous les écrans. | S | 🧪 thème et couleurs de l'éditeur appliqués ; reste la refonte des composants (G7) |
| G7 | Je veux une interface construite à partir de composants réutilisables (atomes, molécules, organismes) et de la grille Material 3, pour que chaque écran se comporte de la même façon. | S | 🧪 dossier `app/lib/ui/` (atomes : bouton d'action matérielle, pastille d'étape ; molécules : étape repliable, bannière, section avancée, progression) appliqué à l'écran Flasher ; reste à l'appliquer aux autres écrans |
| G8 | Je veux une prise en main guidée au premier lancement (ce qu'est l'app, brancher sa carte, les onglets, un premier programme), que je peux passer et revoir. | S | 🧪 quatre étapes au premier lancement, « Passer » à tout moment, « Ouvrir l'onglet Python » à la fin, « Revoir le tutoriel » dans Réglages → Aide ; testé (accessibilité, 360 dp, texte à 200 %), à valider sur téléphone |

**Critères d'acceptation**

- **G1** — *Étant donné* un téléphone avec le clavier ouvert, *quand* je touche une touche de la barre, *alors* le symbole est inséré sans fermer le clavier ; chaque touche mesure au moins 48 × 48 dp, a un libellé vocal (« Insérer deux-points », « Indenter ») et est traduite en français et en anglais.
- **G3** — *Quand* l'état change (connexion, avancement du flash par paliers, fin, erreur), *alors* il est annoncé une fois par le lecteur d'écran, sans répéter chaque pourcentage ; les icônes et boutons sans texte ont un libellé.
- **G4** — Un test automatisé vérifie la taille des cibles sur les écrans principaux (guide `androidTapTargetGuideline` de Flutter).
- **G5** — Un test automatisé vérifie les contrastes (guide `textContrastGuideline`) ; les couleurs sont validées par le calcul ci-dessous. La couleur seule n'est jamais le seul indicateur : une erreur ou un succès s'accompagne d'une icône et d'un texte.

**Palette (thème sombre)** et contrastes calculés (WCAG). Deux teintes de la charte sont ajustées pour tenir les contrastes (colonne « Appliqué ») :

| Rôle | Teinte | Charte | Appliqué | Usage |
|---|---|---|---|---|
| Fond principal | Obsidian Dark | `#111318` | `#111318` | Fond de l'éditeur et de l'app |
| Surface | Deep Slate | `#1B1E28` | `#1B1E28` | Panneaux, terminal, onglets, barre de navigation |
| Accent de marque | Electric Indigo | `#6366F1` | `#818CF8` | Identité, sélection, focus, curseur, texte des boutons |
| Action matérielle | Solar Amber | `#FF6B35` | `#FF6B35` | Flasher, Exécuter (texte sombre) |
| Connexion et succès | Cyber Mint | `#00E5A3` | `#00E5A3` | USB connecté, flash réussi, « prêt » |
| Texte principal | Soft Chalk | `#F3F4F6` | `#F3F4F6` | Code et textes |
| Erreur et danger | Crimson Red | `#EF4444` | `#F87171` | Déconnexion, erreur de compilation, échec du flash |

| Combinaison (thème sombre) | Rapport | Verdict |
|---|---|---|
| Soft Chalk sur Obsidian / sur Deep Slate | 16,9 / 15,1 | ✅ AAA |
| Cyber Mint sur Obsidian / sur Deep Slate | 11,3 / 10,1 | ✅ AAA |
| Obsidian sur Solar Amber (texte des boutons d'action) | 6,6 | ✅ AA |
| Crimson Red `#F87171` sur Obsidian / sur Deep Slate | 6,7 / 6,0 | ✅ AA (`#EF4444` : 4,9 / 4,4, insuffisant sur panneau) |
| Electric Indigo `#818CF8` sur Obsidian / sur Deep Slate | 6,2 / 5,6 | ✅ AA (`#6366F1` : 4,2 / 3,7, mais Material colore le texte des boutons avec cette teinte : un test l'a montré à 3,8) |
| Obsidian sur Electric Indigo `#818CF8` (boutons pleins) | 6,2 | ✅ AA |
| Blanc sur Solar Amber | 2,8 | ❌ interdit : le texte des boutons d'action est sombre |

Le thème clair est décliné de la même palette (indigo `#4F46E5`, rouge `#B91C1C`, vert `#047857`). Les couleurs de coloration du code sont validées à 4,5:1 minimum. Les tests `test/theme_test.dart` et `syntax_theme_test.dart` vérifient chaque couple et le contraste du texte des cinq écrans dans les deux thèmes.

### Épopée H — Bibliothèques de composants (capteurs, écrans, moteurs)

C'est la force d'Arduino : on branche un capteur, on ajoute sa bibliothèque, on lance un exemple. Sans cela, l'IDE n'a pas d'usage réel. Deux mondes, deux sources :

- **MicroPython** : l'index public de `micropython-lib` (protocole `mip`) et les paquets tiers hébergés sur GitHub. Les fichiers `.py` (ou `.mpy`) sont copiés dans `/lib` sur la carte par le transfert vérifié existant (C3) : **aucun serveur nécessaire**, donc faisable avant la compilation cloud.
- **C/C++ (Arduino)** : l'index officiel des bibliothèques Arduino (plusieurs milliers). Elles sont installées et mises en cache **sur le serveur de compilation** (`arduino-cli`), jamais sur le téléphone ; le projet retient la liste des bibliothèques et leurs versions pour que la compilation soit reproductible.

| ID | User story | Prio | Statut |
|---|---|---|---|
| H1 | Je veux chercher une bibliothèque MicroPython (ex. capteur BME280, écran SSD1306) et l'installer sur ma carte en un toucher, avec ses dépendances. | M | 🧪 index `micropython-lib` (version `.mpy` de la carte, sinon sources), dépendances, paquets GitHub (`github:auteur/dépôt`) et adresses https, copie vérifiée dans `/lib`, place vérifiée avant d'écrire ; ✅ validé sur ESP32 avec l'app Android (installation, puis `import` dans la console) ; Badger 2040 non essayé |
| H2 | Je veux voir les bibliothèques installées sur ma carte, les mettre à jour ou les supprimer. | M | ✅ liste de `/lib` et suppression validées sur ESP32 avec l'app Android ; mise à jour = réinstaller |
| H3 | Je veux que l'app détecte les `#include` de mon projet C/C++ et me propose les bibliothèques Arduino correspondantes. | M | 🔜 (avec D5) |
| H4 | Je veux chercher et ajouter une bibliothèque Arduino à mon projet ; la compilation l'utilise dans la version choisie. | M | 🔜 (avec D5) |
| H5 | Je veux ouvrir un exemple fourni par une bibliothèque comme point de départ d'un projet. | S | 🔜 |
| H6 | Je veux retrouver hors ligne les bibliothèques MicroPython déjà téléchargées. | S | 🧪 index et fichiers de l'index gardés en cache sur l'appareil (les fichiers GitHub ne le sont pas encore) |
| H7 | Je veux voir la licence et l'origine d'une bibliothèque avant de l'installer. | C | 🧪 version et licence affichées pour chaque paquet de l'index (« non précisée » sinon) |

**Critères d'acceptation**

- **H1** — *Étant donné* une carte MicroPython connectée, *quand* je choisis une bibliothèque, *alors* l'app affiche sa version, sa source et sa taille, télécharge les fichiers (et leurs dépendances), les copie dans `/lib` avec vérification, puis confirme ; un `import` de la bibliothèque fonctionne dans la console sans autre manipulation. Si la place manque sur la carte, l'app le dit avant d'écrire.
- **H3** — *Quand* j'ouvre ou modifie un fichier `.ino`/`.cpp`, *alors* chaque `#include` qui ne correspond ni au cœur de la carte ni au projet est rapproché d'une bibliothèque de l'index, proposée en un toucher ; rien n'est ajouté sans confirmation.
- **H4** — La liste des bibliothèques et de leurs versions est enregistrée avec le projet ; deux compilations du même projet utilisent les mêmes versions.

---

## 6. Matrice de compatibilité

### 6.1 Plateformes hôtes

| Plateforme | Transport série | Éditeur | MicroPython | Flashage | Statut |
|---|---|---|---|---|---|
| Android 8+ (OTG requis) | API USB Host (pilotes userland) | 🔜 | 🧪 | ✅ ESP32, ESP32-S3 et UF2 (PICOBOOT) | Moniteur ✅ |
| Windows 10/11 | libserialport (COMx) | 🔜 | 🧪 | ✅ UF2 (Badger 2040), ✅ ESP32 et ESP32-S3 | Moniteur ✅ |
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
| **ESP32 / ESP32-S2/S3/C3/C6** | DevKitC, XIAO ESP32 | via pont USB-série, ou `303A:1001` (USB natif) | 🧪 | ✅ esptool/SLIP (ESP32, ESP32-S3 sur Windows) | 🧪 DTR/RTS (auto-reset) |
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
| 2. Détection | Carte listée automatiquement | Android propose d'ouvrir NomadIDE ; permission USB à accepter (case « toujours » recommandée) |
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
| **Accessibilité** | WCAG 2.2 AA / RGAA 4.1 : lecteur d'écran (TalkBack, VoiceOver) pris en charge, contraste ≥ 4,5:1 (texte) et ≥ 3:1 (composants), cibles tactiles ≥ 48 × 48 dp, taille de police réglable, information jamais portée par la couleur seule (voir épopée G). |
| **Internationalisation** | Interface en **français et anglais** dès la v1 (langue du système par défaut, choix manuel possible). Chaînes externalisées (ARB / `flutter_localizations`) **dès l'étape 2**, pour ne pas avoir à reprendre les écrans existants. |
| **Testabilité** | Les protocoles sont testables sans matériel (fausse carte) ; les parcours matériels sont couverts par le banc de test §6.4. |
| **Observabilité** | Journal de diagnostic exportable (versions, carte détectée, trames échouées) pour les rapports de bug. Fait : Réglages → Aide (copié dans le presse-papiers et enregistré dans `diagnostics/`) ; sans le code des projets ni le flux série. |

## 9. Contraintes de plateforme

- **Android** : pas d'accès aux fichiers `/dev` ; tout passe par `UsbManager` avec permission utilisateur. Le périphérique n'est pas toujours disponible si l'appareil ne fournit pas assez de courant en OTG.
- **iOS** : pas d'API USB Host publique ; DriverKit sur iPad exige un entitlement Apple. Prévu : mode éditeur + simulateur, puis BLE/WebREPL.
- **macOS** : sandbox, entitlement `com.apple.security.device.serial` requis (déjà ajouté) ; ports `/dev/cu.*` uniquement.
- **Linux** : l'utilisateur doit appartenir au groupe `dialout` ou `uucp`.
- **Windows** : certains ponts (CH340, CP210x) nécessitent le pilote du fabricant ; un port ouvert dans une autre application renvoie « Accès refusé ».

## 10. Risques et points ouverts

| # | Risque / question | Impact | Piste |
|---|---|---|---|
| R1 | **UF2 sur Android** : en BOOTSEL, le Pico se présente comme un disque USB. Android ne permet pas d'y écrire simplement depuis une application. | D2 non réalisable tel quel sur mobile | **Levé** : l'app parle le protocole **PICOBOOT** (USB bulk) via du code natif Android ; validé sur Badger 2040. |
| R2 | **Latence DTR/RTS sur Android** : les séquences de reset des ESP32 sont chronométrées à quelques ms. | D1/D4 peu fiables sur mobile | Valider sur matériel ; repli guidé « maintenez BOOT ». |
| R3 | **Plugins communautaires** (`usb_serial`, `flutter_libserialport`) : maintenance et API non garanties. | Blocage sur une mise à jour | Isolés derrière la HAL ; plugin Kotlin maison en solution de secours. |
| R4 | **Éditeur Flutter** moins riche que CodeMirror/Monaco. | B1–B3 en deçà des attentes | Solution de secours : CodeMirror 6 dans une WebView, isolé dans `nomad_editor`. |
| R5 | **Service de compilation cloud** (désormais dans le MVP) : coût de calcul, abus, confidentialité, exploitation 24/7. C'est un projet à part entière (API, conteneurs, files d'attente, facturation). | Charge importante, risque de retard de l'étape 3 | Démarrer par un seul toolchain par famille de carte ; quotas stricts dès le premier jour ; l'import de binaire reste le plan B ; décision d'hébergement à prendre. |
| R8 | **Abonnement et boutiques d'applications** : sur Google Play, un abonnement à un service numérique acheté dans l'app passe en principe par Google Play Billing (commission). | Modèle économique mobile | Vérifier les règles en vigueur avant de choisir où se fait le paiement (web ou boutique) ; ne pas afficher de prix dans l'app avant d'avoir tranché. |
| R6 | **Pilotes Windows** (CH340, CP210x, PL2303 contrefaits). | Support utilisateur | Détection et message dédié avec lien vers le pilote. |
| R7 | **Brick de carte** lors d'un flash interrompu. | Perte de confiance | Vérifications, avertissements, procédure de récupération documentée. |
| R9 | **Bibliothèques tierces** (épopée H) : qualité inégale, licences variées, index Arduino volumineux pour un téléphone. | Bibliothèque qui ne compile pas, licence ignorée | Recherche côté serveur (le téléphone ne télécharge pas l'index entier), licence affichée (H7), versions figées par projet (H4), sélection de bibliothèques recommandées pour les capteurs courants. |

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
| **M3a** — Étape 3 | Flash ESP32/ESP32-S et RP2040, firmware MicroPython | D1, D2, D4, D6, D7, C6 | 🧪 D1, D2 (Windows), D4, D6 et D7 (ESP, Badger 2040) validés ; D2 validé aussi sur Android (PICOBOOT) ; restent D7 pour Pico, C6 |
| **M3c** — Étape 3 | UX/UI et accessibilité, flash multi-fichiers ESP | G1–G7, D8 | 🔜 |
| **M3d** — Étape 3 | Bibliothèques MicroPython (sans serveur) | H1, H2, H5, H6, H7 | 🧪 H1 et H2 validés sur ESP32 (Android) ; H6 et H7 écrits et testés ; reste H5 (exemples) |
| **M3b** — Étape 3 | Service de compilation cloud, compte, quotas, abonnement | D5, F1–F4, H3, H4 | 🔜 |
| Post-v1 | Flash STM32 (AN3155) | D3 | 🔜 |
| **M4** — Étape 4 | CI/CD, signature et distribution (Play Store, MSIX, notarisation macOS), mises à jour | E1, E4, E5 | 🧪 CI (analyse et tests) ; workflow de release desktop ; restent la signature (Windows, macOS), Android (clé de signature, Play Store) |

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
| 0.6 | 2026-10-26 | Étape 3 : flash UF2 (Badger 2040), flash ESP32 et ESP32-S3 validés sur Windows ; restent D7, C6, Android (PICOBOOT), compilation cloud |
| 0.7 | 2026-10-28 | Étape 3 : D1 et D7 validés sur ESP32 et ESP32-S3 avec l'app Windows et l'app Android ; adresse d'écriture déduite de l'en-tête du fichier ; restent l'UF2 sur Android, Pico/Badger depuis D7, compilation cloud |
| 0.8 | 2026-10-29 | Étape 3 : D4 (reset automatique ESP par DTR/RTS), D6 (débranchement en pleine écriture) et D7 pour le Badger 2040 (firmware Pimoroni téléchargé et flashé depuis l'app Windows) validés sur matériel |
| 0.9 | 2026-10-29 | Étape 3 : D2 validé sur Android avec un Badger 2040 (PICOBOOT : autorisation USB, effacement, écriture, vérification, redémarrage) ; R1 levé |
| 0.10 | 2026-10-29 | C6 ✅ ; ajout de D8 (flash multi-fichiers ESP), de l'épopée G (UX/UI et accessibilité, WCAG 2.2 AA / RGAA 4.1) avec la palette et ses contrastes calculés, de l'exigence d'accessibilité détaillée et du jalon M3c |
| 0.11 | 2026-10-29 | Épopée G : barre de raccourcis accessible (G1), thème sombre et clair avec la palette de la marque, coloration du code, tests de contraste ; Electric Indigo éclairci (`#818CF8`) et Crimson Red éclairci (`#F87171`) en thème sombre |
| 0.12 | 2026-10-30 | Épopée G : composants communs (`app/lib/ui/`), parcours Flasher à divulgation progressive (G2), état de G7 |
| 0.13 | 2026-10-30 | Épopée G : cibles de 48 dp et libellés sur les cinq écrans, annonces pour le lecteur d'écran (G3, G4), texte agrandi sans débordement |
| 0.14 | 2026-10-30 | D8 écrit et testé (flash ESP en plusieurs fichiers) ; ajout de l'épopée H (bibliothèques de composants MicroPython et Arduino), du risque R9 et du jalon M3d |
| 0.15 | 2026-10-30 | Épopée H : bibliothèques MicroPython (recherche dans `micropython-lib`, installation dans `/lib` avec dépendances, paquets GitHub, cache hors ligne, licence affichée, liste et suppression) |
| 0.16 | 2026-10-30 | H1 et H2 validés sur ESP32 avec l'app Android |
| 0.17 | 2026-10-30 | Réglages : thème clair / sombre / système, taille du code et retour à la ligne, valeurs par défaut du moniteur, journal de diagnostic (exigence d'observabilité), dossier des projets, cache des bibliothèques, version et licences |
| 0.18 | 2026-10-30 | Épopée G : tutoriel de prise en main au premier lancement (G8), à revoir depuis les réglages |
| 0.19 | 2026-10-30 | Release : workflow de publication desktop sur tag, CHANGELOG, contrôle de nouvelle version (E5) ; Android reporté faute de clé de signature stable |
