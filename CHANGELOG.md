# Historique des versions

Les notes de chaque version sont reprises telles quelles dans la release GitHub.

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
