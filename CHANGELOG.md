# Historique des versions

Les notes de chaque version sont reprises telles quelles dans la release GitHub.

## [0.6.0] — Visite guidée

- **Visite guidée** : le tutoriel en quatre pages laisse place à une visite interactive sur les vrais écrans, en huit
  étapes. Chaque étape éclaire l'élément dont elle parle (la liste des cartes, le bouton de connexion, chaque onglet
  de la barre) et le reste de l'app est inerte ; deux étapes invitent à essayer (brancher une carte, lancer un
  premier programme). « Passer » et la touche retour fonctionnent ; avec un lecteur d'écran, seule la carte de la
  visite est lue. Réglages → « Revoir la visite guidée » la relance.
- **Liste des cartes** : la même dans le Moniteur et dans l'onglet MicroPython. Le champ fermé n'affiche que le nom
  de la carte ; le port et la puce apparaissent sous le nom dans la liste ouverte, ce qui distingue deux cartes
  identiques.
- **Messages de résultat** : le résultat d'une compilation (réussi, échoué, annulé), les erreurs du service de
  compilation et des bibliothèques, l'échec de l'installation locale et le résultat du test du serveur (Réglages)
  s'affichent dans un encadré avec une icône, en plus de la couleur, et sont annoncés au lecteur d'écran.
- **Titres de section** des Réglages et des bibliothèques Arduino : même style partout, déclarés comme titres au
  lecteur d'écran.
- **Éditeur** : l'écran sans fichier ouvert ne déborde plus quand la taille du texte est très grande.
- **En interne** : un test vérifie qu'aucun écran n'écrit de couleur en dur (tout vient du thème clair et sombre).

## [0.5.0] — Exemples des bibliothèques Arduino

- **Exemples des bibliothèques** : dans le détail d'une bibliothèque Arduino, « Voir les exemples » liste ceux qu'elle
  fournit. En toucher un crée un projet avec ses fichiers, la bibliothèque et ses dépendances à la bonne version, et
  la carte de l'écran, puis ouvre le croquis. Un projet du même nom n'est jamais écrasé : le nouveau prend un numéro.
  Validé sur Windows (compilation locale).
- **Bouton « Bibliothèques Arduino »** dans la barre de l'éditeur (projets avec un croquis `.ino`) : la recherche et
  l'ajout de bibliothèques n'obligent plus à passer par la feuille de compilation.
- **Compilation locale proposée d'emblée** (Windows, macOS, Linux) : sans serveur configuré, l'app compile sur cet
  ordinateur par défaut, et le choix « Sur cet ordinateur / Serveur » reste visible dans la feuille de compilation
  (il manquait quand aucun serveur n'était configuré). Un choix déjà fait, ou un serveur déjà configuré, ne change pas.
- **Linux : AppImage** (`NomadIDE-<version>-linux-x86_64.AppImage`), en plus de l'archive : un seul fichier, qui se
  lance sans installation sur la plupart des distributions (construit sur Ubuntu 22.04, donc aussi Debian 12 et plus
  récent). GTK 3 vient du système. Merci à `orkeilius` pour la suggestion.
- **Onglets** : supprimer un projet, un fichier ou un dossier ferme les onglets concernés ; renommer un projet, un
  fichier ou un dossier met à jour ses onglets ouverts (un enregistrement ne recrée plus l'ancien fichier).
- **Textes** : en français, les guillemets « … » ne laissent plus le » seul en début de ligne (tutoriel notamment) ;
  en anglais, « Version 1.0 · License: MIT » remplace « licence MIT ».
- **Messages d'erreur du service de compilation** : un service plus ancien que l'app, sans les routes d'exemples, est
  nommé comme tel au lieu d'un « build expiré » ; les autres erreurs affichent le code et le message du service.
- **Si vous utilisez un serveur de compilation** (téléphone) : mettez-le à jour pour avoir les exemples (`git pull`,
  `dart pub get` dans `services/cloud_compiler`, redémarrage du service ; l'image Docker ne change pas). Voir le
  README du service. Sur ordinateur en mode local, rien à faire.
- **Site et Google Play** : page d'accueil et politique de confidentialité en ligne (GitHub Pages), fiche Google Play
  prête (textes FR/EN, captures).

## [0.4.1] — Nouvel identifiant Android

- **Identifiant de l'application Android** : `dev.nomadide.app`, à la place de `dev.nomadmcu.nomad_mcu` (reste de
  l'ancien nom du projet). Il est définitif sur Google Play et apparaît dans l'adresse de la fiche, d'où ce
  changement avant la première publication.
- **Conséquence à connaître** : pour Android, c'est une autre application. Elle **ne remplace pas** la version déjà
  installée : désinstallez l'ancienne NomadIDE avant d'installer celle-ci (les projets enregistrés dans l'ancienne
  seront perdus ; copiez le code important avant). Les versions suivantes se mettront à jour normalement, par-dessus.
- Windows, macOS et Linux ne sont pas concernés.

## [0.4.0] — Compilation sur cet ordinateur

- **Compilation sur cet ordinateur** (Windows, macOS, Linux) : la feuille de compilation propose « Sur cet ordinateur »
  ou « Serveur », et retient le choix. En local, le code n'est envoyé nulle part et aucun compte n'est nécessaire.
  Au premier usage, l'app annonce la taille puis télécharge `arduino-cli` (empreinte vérifiée) et les cœurs ESP32 et
  RP2040, environ 1,1 Go, dans son propre dossier ; une installation existante de l'Arduino IDE n'est pas touchée.
  Ensuite, la compilation fonctionne sans réseau, sauf pour récupérer une nouvelle bibliothèque.
- **Mêmes résultats qu'avec le serveur** : les projets, les bibliothèques à versions précises (`nomad.json`), les
  erreurs cliquables et le passage au Flasher sont identiques, car c'est le même service de compilation, lancé dans
  l'app sur cette machine. Validé sur Windows avec ESP32 et ESP32-S3.
- **Index des bibliothèques à la demande** : il n'est téléchargé que si le projet déclare des bibliothèques ou si
  l'écran Bibliothèques s'ouvre.
- **Réglages** : « Outils de compilation locale » indique s'ils sont installés et permet de les désinstaller pour
  libérer la place ; les projets ne sont pas touchés.
- Sur mobile, seule la compilation par le serveur est proposée.

À savoir : sous Windows, l'app peut encore se fermer brusquement de temps en temps en revenant sur l'onglet Éditeur.
Le problème existait avant cette version ; le plantage se produit dans le moteur Flutter et sa cause est en cours d'analyse.

## [0.3.0] — Bibliothèques Arduino

- **Bibliothèques Arduino** : dans la feuille de compilation, le bouton Bibliothèques cherche dans le catalogue
  officiel d'Arduino (plus de 10 000 bibliothèques), montre la description, l'auteur et les versions, ajoute une
  bibliothèque avec ses dépendances, la retire (les dépendances devenues inutiles partent avec) et change sa version.
  Chaque bibliothèque est enregistrée à une version précise dans le fichier `nomad.json` du projet : deux
  compilations du même projet utilisent les mêmes versions, sur ordinateur comme sur téléphone.
- **`#include` introuvable** : « Analyser les #include du projet » propose la bibliothèque qui fournit chaque
  en-tête (`DHT.h` : « DHT sensor library »). Quand une compilation échoue sur un en-tête introuvable, « Ajouter et
  compiler » ajoute la bonne bibliothèque et relance la compilation. L'index d'Arduino déclare presque jamais ses
  en-têtes : le service les retrouve d'après le nom des bibliothèques et en ouvrant leur archive, et indique celles
  dont l'en-tête est confirmé.
- **Service de compilation** : il doit être mis à jour avec cette version pour fournir les bibliothèques. Il ne les
  installe que depuis l'index officiel d'Arduino, vérifie leur taille et leur empreinte SHA-256, et les monte en
  lecture seule dans le conteneur de compilation, toujours sans réseau (voir `services/cloud_compiler/README.md`).
- **Éditeur** : un fichier sans langage reconnu (par exemple `nomad.json`) n'arrête plus la coloration des autres
  fichiers.

À savoir : l'index officiel ne fournit pas la licence des bibliothèques, l'app affiche donc « Licence non précisée ».

## [0.2.0] — Compilation C/C++ dans le cloud

- **Projets Arduino C/C++** : à la création d'un projet, choisissez MicroPython ou Arduino C/C++. Un projet
  Arduino démarre avec un croquis Blink prêt à compiler.
- **Compiler depuis l'éditeur** : le bouton de compilation envoie le projet à un service de compilation,
  pour ESP32, ESP32-S2, ESP32-S3 et RP2040. L'app dit quel code part et vers quel serveur (confirmation la
  première fois), suit la compilation, affiche les erreurs avec fichier et ligne (touchez-en une pour ouvrir
  le fichier) et le journal du compilateur. Le binaire est envoyé tel quel dans l'onglet Flasher, après
  vérification de son empreinte.
- **Service de compilation** : fourni dans le dépôt (`services/cloud_compiler`) à héberger soi-même pour
  l'instant ; adresse et jeton se règlent dans Réglages → Compilation cloud. Rien n'est envoyé tant que
  vous ne lancez pas de compilation.
- **Flash des ESP32 sous Windows** : le passage en bootloader est automatique et fiable (plus besoin de
  maintenir BOOT), l'ESP32-S3 branché par son USB natif redémarre sur son programme, et l'image complète
  d'Arduino est écrite à la bonne adresse (corrige « invalid header: 0xffffffff »).
- **Windows** : si le dossier Documents est protégé (accès contrôlé aux dossiers), les projets sont rangés
  dans le dossier de données de l'application au lieu d'échouer.
- **Logo NomadIDE** : icône de l'app sur Windows, Android et macOS, et dans le tutoriel et la page À propos.

À savoir : le jeton du service est enregistré tel quel dans le fichier de réglages de l'app, et toucher
une erreur de compilation ouvre le fichier sans encore aller à la ligne.

## [0.1.1] — Android

- **Android** : APK signés publiés avec chaque version (`arm64` pour la plupart des téléphones, `arm32`
  pour les plus anciens), ainsi que l'App Bundle destiné au Play Store. Les versions suivantes
  s'installeront par-dessus.
- Si vous aviez installé une version de développement : désinstallez-la d'abord (elle était signée avec
  une autre clé). Attention, la désinstallation efface les projets enregistrés dans l'app.

## [0.1.0] — version bêta

Première version publique de NomadIDE : programmer des cartes ESP32 et RP2040 en MicroPython, depuis un
ordinateur ou un téléphone Android.

### Ce que fait cette version

- **Moniteur série** : liste des cartes branchées (détection automatique), connexion, débit, DTR/RTS,
  redémarrage, affichage texte ou hexadécimal horodaté, envoi avec la fin de ligne choisie.
- **MicroPython** : console (raw REPL), exécution d'un fichier ou d'une sélection, arrêt (Ctrl-C) et
  redémarrage (Ctrl-D), fichiers de la carte (envoyer, télécharger, renommer, supprimer, `main.py`) avec
  vérification CRC32.
- **Bibliothèques MicroPython** : recherche dans `micropython-lib`, installation dans `/lib` en un
  toucher avec les dépendances, paquets GitHub, liste et suppression ; fonctionne hors ligne pour ce qui
  a déjà été téléchargé.
- **Éditeur** : Python, C et C++ avec coloration, numéros de ligne, indentation automatique,
  autocomplétion, onglets, brouillons enregistrés automatiquement, projets locaux, barre de symboles
  au-dessus du clavier sur téléphone.
- **Flash** : fichiers `.uf2` pour RP2040 (bascule automatique en BOOTSEL ; écriture USB directe sur
  Android) et `.bin` pour ESP32 / ESP32-S3 (reset automatique, vérification MD5, adresse déduite du
  fichier, plusieurs fichiers d'un projet Arduino ou ESP-IDF en une passe) ; téléchargement du firmware
  MicroPython officiel.
- **Interface** : français et anglais, thème clair ou sombre, réglages (éditeur, moniteur), tutoriel au
  premier lancement, journal de diagnostic à joindre à un signalement de bug.
- **Accessibilité** : lecteur d'écran (TalkBack, VoiceOver), zones tactiles de 48 dp, contrastes WCAG AA,
  texte agrandi jusqu'à 200 %.

### Validé sur matériel

Windows 11 et Android avec un Pimoroni Badger 2040 (RP2040), un ESP32 et un ESP32-S3.

### Limites connues

- **Windows** : l'app n'est pas signée. Windows affiche « Windows a protégé votre ordinateur » :
  cliquez sur « Informations complémentaires », puis « Exécuter quand même ».
- **macOS** : l'app n'est pas notarisée. À la première ouverture : clic droit sur l'app, puis « Ouvrir ».
  Version compilée mais **pas encore testée** sur un Mac.
- **Linux** : version compilée mais **pas encore testée**. L'utilisateur doit appartenir au groupe
  `dialout` (Debian, Ubuntu) ou `uucp` (Arch) pour accéder aux ports série.
- **Android** : pas encore publié ici (il faut d'abord une clé de signature stable) ; le Play Store suivra.
- **Pas encore disponibles** : compilation C/C++, flash des STM32, bibliothèques Arduino.

Un problème ? Réglages → Aide → « Exporter un journal de diagnostic », puis ouvrez une issue sur GitHub
avec ce journal.
