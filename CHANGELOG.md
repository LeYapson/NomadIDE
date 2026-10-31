# Historique des versions

Les notes de chaque version sont reprises telles quelles dans la release GitHub.

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
