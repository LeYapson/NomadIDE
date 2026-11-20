# NomadIDE — Document de spécifications produit (PRD)

| | |
|---|---|
| **Produit** | NomadIDE |
| **Version du document** | 0.38 — G1, G6 et G7 validés ; M3c terminé |
| **Date** | 2026-10-01 |
| **Statut du produit** | Étape 1 terminée (HAL USB/série + moniteur série) ; étape 2 en cours |
| **Documents liés** | [README.md](README.md) · [ADR 0001 — Flutter](docs/adr/0001-stack-flutter.md) · [Politique de confidentialité](docs/privacy.html) |

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
- Compilation locale C/C++ sur mobile (sur Android, la compilation passe par le service cloud ; sur ordinateur, elle peut aussi se faire en local, voir D9).
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
| D5 | Je veux compiler mon code C/C++ via un service cloud et flasher le résultat directement. | M | ✅ validé de bout en bout sur ESP32 (Windows et Android) : projet Arduino, compilation sur le serveur, flash, programme exécuté ; la compilation ESP32-S3 et RP2040 est validée sur le serveur (l'UF2 compilé n'a pas été flashé sur une carte RP2040) |
| D6 | Je veux voir une progression fiable et une vérification du flash. | M | ✅ progression et vérification (MD5 pour l'ESP, redémarrage de la carte pour l'UF2) validées sur matériel ; débranchement en pleine écriture validé sur ESP : message d'erreur avec avertissement « carte possiblement incomplète » et marche à suivre |
| D7 | Je veux installer le firmware MicroPython adapté à ma carte (ex. firmware Pimoroni pour la Badger 2040). | S | ✅ ESP32 et ESP32-S3 : recherche, téléchargement et flash du firmware officiel validés sur Windows et Android ; ✅ Badger 2040 : firmware Pimoroni téléchargé et flashé depuis l'app Windows, REPL et code exécuté vérifiés ; 🧪 Pico et Pico W (version et téléchargement validés contre micropython.org, flash depuis l'app non essayé), Badger 2040 W |
| D9 | Sur ordinateur, je veux compiler mon code C/C++ sur ma machine, sans serveur ni compte, et même hors ligne une fois l'outillage installé. | S | ✅ validé sur Windows : installation réelle d'`arduino-cli` et des cœurs, compilation locale puis flash et exécution sur ESP32 et ESP32-S3 ; RP2040 non essayé (la carte de test tourne sous MicroPython) ; macOS et Linux non essayés |
| D8 | Je veux flasher plusieurs fichiers à des adresses distinctes en une seule passe (ex. bootloader `0x1000`, table de partitions `0x8000`, application `0x10000`), pour les projets Arduino et ESP-IDF. | S | ✅ écrit et testé avec une fausse ROM : chaque fichier est reconnu par son contenu (image complète, bootloader, table de partitions, données OTA, application), l'adresse vient de la table de partitions quand elle est fournie, chevauchements refusés, un MD5 par fichier, un seul redémarrage ; validé sur une carte ESP32 avec un projet Arduino (bootloader, table de partitions et application en une passe), sur téléphone Android et sur PC (2026-11-19) |

**Critères d'acceptation**

- **D1** — *Étant donné* un ESP32 avec circuit d'auto-reset, *quand* je lance le flash, *alors* l'app met la carte en bootloader, écrit à la bonne adresse, vérifie, puis redémarre la carte. *Étant donné* une carte sans auto-reset, *alors* l'app affiche les instructions pour maintenir BOOT (étape guidée).
- **D2** — *Étant donné* un Pico en fonctionnement, *quand* je lance le flash, *alors* l'app le fait passer en BOOTSEL (touch 1200 bauds) puis écrit le fichier ; le message d'état distingue clairement « carte réapparue en BOOTSEL » de « échec ».
- **D3** — *Étant donné* un STM32 avec BOOT0 actif et un adaptateur USB-série, *alors* l'app détecte le bootloader (réponse ACK `0x79`) avant d'écrire.
- **D5** — *Quand* je lance la compilation, *alors* l'app indique explicitement quel code est envoyé et vers quel serveur, demande une confirmation la première fois, et affiche les erreurs du compilateur avec numéros de ligne cliquables. *Quand* la compilation réussit, *alors* le binaire est téléchargé et le flash peut être lancé en un clic. Le compilateur cible la bonne carte (ESP32 / ESP32-S / RP2040) d'après la carte détectée ou le projet.
- **D7** — *Étant donné* une carte RP2040 en BOOTSEL ou un ESP32, *alors* l'app propose le firmware correspondant (version indiquée) et le flashe ; pour la Badger 2040, c'est le firmware Pimoroni (qui embarque ses modules d'affichage) et non le MicroPython générique.
- **D8** — *Quand* je prépare un flash ESP, *alors* je peux ajouter plusieurs fichiers, chacun avec son adresse (déduite de l'en-tête quand c'est possible, modifiable). *Si* deux fichiers se chevauchent en mémoire flash, ou si un fichier ne correspond pas à la puce détectée, *alors* l'app refuse avant toute écriture. Chaque fichier est vérifié (MD5), la progression est globale, et la carte n'est redémarrée qu'une fois, à la fin.
- **D9** — *Étant donné* un ordinateur (Windows, macOS, Linux), *quand* je choisis « Sur cet ordinateur » dans la feuille de compilation, *alors* l'app indique ce qu'il faut installer et sa taille, le télécharge après confirmation (empreintes vérifiées), puis compile sans envoyer mon code nulle part. *Quand* l'outillage est installé, *alors* la compilation fonctionne sans réseau pour un projet sans nouvelle bibliothèque. Les erreurs, les bibliothèques et le passage au Flasher sont ceux de D5. Le mode choisi (ordinateur ou serveur) est retenu ; sur mobile, seul le serveur est proposé.
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

**Proposition de modèle économique (2026-11-16, ⚠️ à valider : rien n'est décidé)**

Proposée par l'auteur ; elle répond en partie aux questions ouvertes 3, 4 et 5 du §10 et ne devient une décision qu'une fois validée.

| Offre | Prix | Compilations cloud |
|---|---|---|
| Gratuite | 0 € | 5 par jour, sans compte (jeton d'appareil) |
| Pro | 4,99 €/mois ou 39,99 €/an | 150 par jour |
| Fondateur (à vie) | 79 € une fois | 60 par jour |

- **Pas de compte au lancement** : l'offre gratuite repose sur un jeton propre à l'appareil ; le compte n'est demandé qu'à l'achat d'une offre.
- **Paiement** : Google Play Billing sur Android ; un prestataire de paiement tiers (Lemon Squeezy ou Paddle) sur ordinateur.
- **Licence** : client sous MIT ou AGPL ; service sous licence « source disponible » (BSL) ou privé.

*Points à trancher avant de figer la proposition :*

1. **Licence** : garder le moteur de compilation (`services/cloud_compiler`, déjà sous MIT et auto-hébergeable) sous MIT, et ne mettre dans un dépôt privé que le code nouveau (comptes, quotas, facturation). Fermer le moteur après coup serait mal perçu et incohérent avec « le code reste à l'utilisateur ».
2. **Offre à vie** : un paiement unique finance un coût qui, lui, est récurrent (serveur). La plafonner (nombre de places, quota plus bas) ou y renoncer.
3. **Prix et quotas** : mesurer d'abord le coût réel d'une compilation (processeur, durée, espace du cache) ; les chiffres ci-dessus n'en sont pas déduits.
4. **Jeton d'appareil** : ce n'est qu'une limite souple (une réinstallation ou un autre appareil la contourne). Ajouter un plafond global et par adresse réseau, et ne pas présenter « 5 par jour » comme une garantie.
5. **Conformité** : Google Play Billing est exigé pour un abonnement acheté dans l'app Android (R8) ; la politique de confidentialité, le formulaire « Sécurité des données » et la suppression de compte (exigée par Google Play dès qu'il y a des comptes) sont à mettre à jour avant publication (voir ci-dessous).

**À faire avant de publier une version avec F1** *(rappel : la politique de confidentialité actuelle, [docs/privacy.html](docs/privacy.html), décrit une app sans compte et sans serveur fourni ; elle deviendrait fausse)*

- **Politique de confidentialité** : la réécrire en français et en anglais avant la mise en ligne de la version avec comptes. Elle doit couvrir l'identifiant de compte (e-mail ou autre), le code source envoyé au service, les quotas et l'historique d'usage, le prestataire de paiement et les autres sous-traitants, la durée de conservation, et le fait que le service de compilation devient exploité par NomadIDE (alors qu'elle dit aujourd'hui qu'aucun serveur n'est fourni par défaut).
- **Formulaire « Sécurité des données » de la Play Console** : le refaire (il passe de « aucune donnée collectée » à la déclaration des données de compte et de paiement, chiffrées en transit), puis mettre à jour l'URL de la politique si elle change.
- **Suppression du compte** : Google exige, pour une app qui permet de créer un compte, une suppression possible depuis l'app **et** une URL web pour la demander (à renseigner dans la Play Console). L'ajouter au périmètre de F1–F3.
- **Paiement** : trancher la question ouverte 4 et le risque R8 (Google Play Billing ou paiement hors boutique) avant d'écrire F3 ; créer le profil marchand de la Play Console si la boutique est retenue.
- **Compte développeur Play** : revoir la déclaration de statut professionnel (UE) et les informations de contact rendues publiques une fois l'app monétisée.

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
| G1 | Je veux une barre de raccourcis tactile au-dessus du clavier (`Tab`, `:`, `{`, `}` ; `Ctrl+C` et `Ctrl+D` dans la console MicroPython) pour programmer sans chercher les symboles. | M | ✅ touches de 48 dp, noms parlés des symboles (« Insérer deux-points »), français et anglais, testé automatiquement ; validé sur téléphone (2026-11-20) |
| G2 | Je veux que le flash soit un parcours guidé (1. Fichier, 2. Carte, 3. Écriture) lisible sur un écran de 360 dp, sans surcharge. | M | ✅ trois étapes avec divulgation progressive (étape terminée repliée sur son résumé, options avancées et firmware officiel repliés), testé à 360 dp et à 150 % de taille de texte ; validé sur téléphone (2026-11-19) |
| G3 | Je veux qu'un lecteur d'écran (TalkBack, VoiceOver) annonce l'état de l'app : carte connectée ou déconnectée, flash en cours avec son avancement, erreur. | M | ✅ état de connexion, progression (par paliers de 25 %) et résultats annoncés, zones sans nom nommées ; testé en simulation, puis validé avec TalkBack sur téléphone (2026-11-18) |
| G4 | Je veux que toutes les zones tactiles fassent au moins 48 × 48 dp. | M | ✅ vérifié par test sur les 5 écrans (thèmes sombre et clair, téléphone de 360 dp) ; texte agrandi à 150 % et 200 % sans débordement ; validé sur téléphone (2026-11-19) |
| G5 | Je veux un thème sombre lisible : contraste ≥ 4,5:1 pour le texte et ≥ 3:1 pour les composants et le focus. | M | ✅ appliqué et testé automatiquement (texte des 5 écrans, thèmes sombre et clair) ; validé à l'œil sur téléphone (2026-11-19) |
| G6 | Je veux une identité visuelle cohérente (palette ci-dessous) appliquée à tous les écrans. | S | ✅ aucune couleur écrite en dur dans les écrans ni les composants (test automatique) : tout vient du thème clair et sombre ; validé sur téléphone et sur PC (2026-11-20) |
| G7 | Je veux une interface construite à partir de composants réutilisables (atomes, molécules, organismes) et de la grille Material 3, pour que chaque écran se comporte de la même façon. | S | ✅ dossier `app/lib/ui/` (atomes : bouton d'action matérielle, pastille d'étape, titre de section ; molécules : étape repliable, bannière, section avancée, progression, liste des cartes) appliqué à Flasher, Réglages, Moniteur, MicroPython et aux feuilles de compilation et de bibliothèques ; validé sur téléphone et sur PC (2026-11-20) |
| G8 | Je veux une prise en main guidée au premier lancement (ce qu'est l'app, brancher sa carte, les onglets, un premier programme), que je peux passer et revoir. | S | ✅ visite guidée interactive en huit étapes sur les vrais écrans (bienvenue, brancher la carte, les cinq onglets, premier programme) : chaque étape affiche son onglet, assombrit le reste et éclaire l'élément concerné ; toucher un onglet éclairé passe à la suite, la liste des cartes et « Connecter » s'essaient ; démarre au premier lancement, « Passer » à tout moment, « Revoir la visite guidée » dans Réglages → Aide, touche « retour » = étape précédente ; le lecteur d'écran ne lit que la carte de la visite ; testé (14 tests, 360 dp, texte à 200 %), validé sur PC et sur téléphone (2026-11-20) |

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
| H3 | Je veux que l'app détecte les `#include` de mon projet C/C++ et me propose les bibliothèques Arduino correspondantes. | M | ✅ validé de bout en bout sur ordinateur (Windows) et sur téléphone (Android) : « Analyser les #include » dans la feuille Bibliothèques, et « Ajouter et compiler » quand une compilation échoue sur un en-tête introuvable ; le service retrouve la bibliothèque d'un en-tête (l'index officiel ne les déclare presque jamais : nom, archive vérifiée, en-têtes déjà connus) et indique celles dont l'en-tête est confirmé |
| H4 | Je veux chercher et ajouter une bibliothèque Arduino à mon projet ; la compilation l'utilise dans la version choisie. | M | ✅ validé de bout en bout sur ordinateur (Windows) et sur téléphone (Android) : recherche, détail, choix de la version, ajout avec dépendances à versions précises, retrait (avec les dépendances devenues inutiles), liste enregistrée dans le `nomad.json` du projet ; la licence n'est pas fournie par l'index officiel (« licence non précisée ») |
| H5 | Je veux ouvrir un exemple fourni par une bibliothèque comme point de départ d'un projet. | S | ✅ sur Windows (compilation locale, essai du 2026-11-16) ; 🧪 sur Android. Bibliothèques Arduino : « Voir les exemples » dans le détail d'une bibliothèque liste ses exemples (dossiers de `examples/` qui contiennent un croquis du même nom) ; en toucher un crée un projet avec ses fichiers, la bibliothèque et ses dépendances à la version de l'exemple, la carte de l'écran, et ouvre le croquis. Servi par le service de compilation (cloud et local) ; testé avec de fausses archives, puis validé avec le vrai catalogue sur Windows ; reste à essayer sur téléphone (avec un serveur de compilation configuré). MicroPython : sans objet pour l'instant, les paquets de `micropython-lib` ne livrent pas d'exemples |
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
| R10 | **Plantage sous Windows** : l'app peut se fermer brusquement en revenant sur l'onglet Éditeur. Analyse des quatre fichiers d'analyse (dumps) conservés par Windows sur le poste de développement, tous du 2026-10-06 (version 0.1.0.1, aucun depuis sur ce poste) : **corruption du tas mémoire** (`0xc0000374` en Release, le même défaut repéré par la bibliothèque C de débogage en Debug). Dans les deux dumps Release, le fil fautif traverse `serialport.dll` (libserialport) aux mêmes adresses (`+0xd910`, `+0x361f`) sous des appels natifs du moteur : le moteur n'est donc pas seul en cause, la bibliothèque des ports série est la piste principale (non prouvée : sans symboles, la corruption a pu avoir lieu plus tôt). Le plantage signalé depuis (0.4.0) vient sans doute de l'autre poste de l'auteur, où l'on soupçonne la machine elle-même (pilotes, matériel) : aucune trace de plantage depuis le 2026-10-06 sur le poste de développement, et les dumps de l'autre poste n'ont pas été analysés. **Non reproduit sur la 0.5.0** : l'auteur a rejoué sur le poste de développement, avec la version publiée, tous les scénarios qui plantaient, sans jamais obtenir de plantage (2026-11-17) ; ce n'est pas une preuve de correction, mais le risque est jugé lié à l'autre poste et n'est plus bloquant. | Perte du texte non enregistré, perte de confiance | Les brouillons sont écrits automatiquement (B5) et proposés à la réouverture. Pistes : (1) mesurer sans l'énumération des ports (elle tourne toutes les 1,5 s sur le fil de l'interface et décrit chaque port à chaque passage) ; (2) ne décrire un port que lorsqu'il apparaît ; (3) reproduire avec Application Verifier (PageHeap) pour avoir la pile exacte ; (4) un moteur Flutter plus récent ; avant tout, relever sur l'autre poste le module fautif et le code d'exception (Observateur d'événements, journal Application, source « Application Error ») pour savoir si c'est la même corruption du tas. |

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
3. Quelle limite pour l'offre gratuite (nombre de compilations par mois, durée de calcul, taille du projet) et quel prix pour l'offre payante ? À fixer avec une estimation du coût d'une compilation. *Proposition de l'auteur (2026-11-16) dans l'épopée F, à valider.*
4. Où se fait le paiement (site web, boutiques d'applications) ? Voir R8. *Proposition : Google Play Billing sur Android, un prestataire tiers sur ordinateur (épopée F).*
5. Le code du dépôt est sous licence MIT : l'application reste-t-elle open source avec seulement le service cloud payant, ou le service est-il aussi publié ? Cela influence ce qui est protégé. *Proposition : moteur de compilation sous MIT, code des comptes et de la facturation privé (épopée F).*

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
| **M3a** — Étape 3 | Flash ESP32/ESP32-S et RP2040, firmware MicroPython | D1, D2, D4, D6, D7, C6 | 🧪 D1, D2 (Windows), D4, D6 et D7 (ESP, Badger 2040) validés ; D2 validé aussi sur Android (PICOBOOT) ; reste D7 pour Pico et Pico W (C6 est couvert par D7, validé) |
| **M3c** — Étape 3 | UX/UI et accessibilité, flash multi-fichiers ESP | G1–G8, D8 | ✅ G1–G8 et D8 écrits, testés et validés ; thème, barre de raccourcis, parcours Flasher, réglages et tutoriel essayés sur téléphone et PC ; G3 (annonces TalkBack) validé sur téléphone ; D8 (flash de plusieurs fichiers) validé sur une carte, sur téléphone et sur PC ; G2, G4, G5 et G8 (visite guidée) validés sur téléphone ; G1, G6 et G7 validés sur téléphone et sur PC |
| **M3d** — Étape 3 | Bibliothèques MicroPython (sans serveur) | H1, H2, H5, H6, H7 | 🧪 H1 et H2 validés sur ESP32 (Android) ; H6 et H7 écrits et testés ; reste H5 (exemples) |
| **M3b** — Étape 3 | Service de compilation cloud, compte, quotas, abonnement | D5, F1–F4, H3, H4 | 🧪 D5, H3 et H4 validés ; restent F1–F4 (comptes, quotas, abonnement), qui attendent les décisions sur les limites gratuites, le paiement et la licence |
| Post-v1 | Flash STM32 (AN3155) | D3 | 🔜 |
| **M4** — Étape 4 | CI/CD, signature et distribution (Play Store, MSIX, notarisation macOS), mises à jour | E1, E4, E5 | 🧪 CI (analyse et tests) ; workflow de release desktop ; releases publiées sur GitHub depuis la 0.1.0 pour Windows, Linux et macOS, et pour Android depuis la 0.1.1 (APK signés avec une clé stable, App Bundle pour le Play Store) ; identifiant Android définitif `dev.nomadide.app` (0.4.1) ; **Play Store : fiche prête** (textes FR/EN, icône 512, image de présentation, 6 captures FR et 6 EN dans `docs/`, politique de confidentialité et page d'accueil en ligne, formulaires de la Play Console remplis) ; restent le **test fermé** (12 testeurs pendant 14 jours avant de pouvoir publier), la signature de l'app Windows, la notarisation macOS et le MSIX |

Les dates ne sont pas fixées : les jalons avancent par versions publiées (0.1.0 à 0.6.0 à ce jour, voir `CHANGELOG.md`).

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
| 0.20 | 2026-11-04 | D5 : service de compilation (Dart + Docker + `arduino-cli`, ESP32/S2/S3 et RP2040) et contrat d'API partagé ; hébergé pour l'instant sur un serveur personnel derrière un tunnel Cloudflare, avec un jeton unique (comptes et quotas : épopée F, plus tard) |
| 0.21 | 2026-11-04 | D5 : service de compilation installé et validé sur le serveur personnel ; client dans l'app (réglages, feuille de compilation, passage au Flasher) ; reste l'essai de bout en bout sur une carte |
| 0.22 | 2026-11-06 | D5 validé (compilation et flash sur ordinateur et sur mobile) ; H3 et H4 : côté service (catalogue officiel, recherche, résolution des `#include`, dépendances à versions précises, cache d'installation vérifié) |
| 0.23 | 2026-11-06 | H3 et H4 : écran « Bibliothèques » dans la feuille de compilation, suggestions d'après les `#include`, « Ajouter et compiler » ; le service retrouve la bibliothèque d'un en-tête malgré l'index (qui ne les déclare presque jamais) ; la licence n'est pas fournie par l'index officiel (« licence non précisée ») |
| 0.24 | 2026-11-06 | H3 et H4 validés sur Windows et Android ; coloration : un fichier sans langage reconnu (`nomad.json`) n'arrête plus la coloration de l'éditeur |
| 0.25 | 2026-11-07 | Ajout de D9 (compilation locale sur ordinateur) ; le non-objectif « compilation locale » ne vise plus que le mobile. Le service de compilation tourne dans l'app sur 127.0.0.1 avec `arduino-cli` à la place de Docker : un seul code pour le cloud et le local |
| 0.26 | 2026-11-07 | D9 validé sur Windows (ESP32 et ESP32-S3 : compilation locale, flash, programme exécuté) ; l'index des bibliothèques n'est téléchargé qu'à la demande |
| 0.27 | 2026-11-16 | Publication sur le Play Store : app gratuite, page de politique de confidentialité (`docs/privacy.html`, FR/EN, hébergée par GitHub Pages) ; épopée F : rappel de ce qu'il faut refaire avant la version avec comptes (politique, formulaire de sécurité des données, suppression du compte, paiement, statut du compte développeur) |
| 0.28 | 2026-11-16 | M4 : fiche Google Play prête (textes, icône, image de présentation, captures FR et EN prises sur téléphone, page d'accueil du site, politique de confidentialité) ; reste le test fermé (12 testeurs, 14 jours). Défauts relevés pendant les captures : onglet resté ouvert après la suppression d'un projet, « » » seul en fin de ligne dans le tutoriel, « licence » en anglais (corrigés dans la PR #71) ; renommer un fichier ou un dossier laisse son onglet sur l'ancien chemin (à traiter) |
| 0.29 | 2026-11-16 | H5 écrit et testé pour les bibliothèques Arduino (liste des exemples, création d'un projet depuis un exemple, nouvelles routes `/v1/libraries/{nom}/examples` et `/example` du service) ; renommer un fichier ou un dossier met à jour ses onglets ouverts ; essai sur Windows : sur ordinateur, sans serveur configuré, la compilation se fait par défaut sur cette machine et « Sur cet ordinateur » reste proposé dans la feuille de compilation ; bouton « Bibliothèques Arduino » dans la barre de l'éditeur (recherche et exemples sans passer par la feuille de compilation) |
| 0.30 | 2026-11-16 | H5 validé sur Windows (compilation locale) ; reste à essayer sur Android |
| 0.31 | 2026-11-17 | R10 : analyse des dumps Windows (corruption du tas, `serialport.dll` dans la pile des deux plantages Release) ; pistes précisées |
| 0.32 | 2026-11-17 | R10 : non reproduit sur la 0.5.0 (essai de tous les scénarios sur le poste de développement) ; attribué à l'autre poste de l'auteur, surveillé, non bloquant |
| 0.33 | 2026-11-18 | G3 validé : annonces de l'état (connexion, progression, résultats) vérifiées avec TalkBack sur téléphone ; reste D8 dans M3c |
| 0.34 | 2026-11-19 | D8 validé : bootloader, table de partitions et application d'un projet Arduino écrits en une seule passe sur une carte ESP32, sur téléphone Android et sur PC, aux adresses attendues ; la carte démarre sur le nouveau programme |
| 0.35 | 2026-11-19 | G2, G4 et G5 validés sur téléphone ; G8 : le tutoriel en quatre pages est jugé trop passif, le critère devient une visite guidée interactive sur les vrais écrans |
| 0.36 | 2026-11-20 | G8 validé : le tutoriel en quatre pages est remplacé par une visite guidée interactive sur les vrais écrans (huit étapes, élément éclairé, accessibilité), essayée sur PC et sur téléphone ; reste dans M3c : G1, G6 et G7 |
| 0.37 | 2026-11-20 | Épopée F : la proposition de modèle économique de l'auteur (offres, quotas, paiement, licence) est inscrite comme proposition à valider, avec cinq points à trancher ; questions ouvertes 3, 4 et 5 renvoyées vers elle. Aucune décision prise |
| 0.38 | 2026-11-20 | G1 (barre de raccourcis), G6 (identité visuelle) et G7 (composants communs) validés sur téléphone et sur PC : titre de section et liste des cartes communs, bannière de résultat sur les écrans qui écrivaient leur message à la main, test automatique contre les couleurs écrites en dur ; liste des cartes : nom seul dans le champ, port et puce sous le nom dans la liste ouverte. Jalon M3c terminé ; il ne reste que l'épopée F |
