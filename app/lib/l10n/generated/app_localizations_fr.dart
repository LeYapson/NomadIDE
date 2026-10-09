// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'NomadMCU';

  @override
  String get navMonitor => 'Moniteur série';

  @override
  String get navMicroPython => 'MicroPython';

  @override
  String get navEditor => 'Éditeur';

  @override
  String get navSettings => 'Réglages';

  @override
  String get settingsTitle => 'NomadMCU · Réglages';

  @override
  String get settingsLanguage => 'Langue';

  @override
  String get languageSystem => 'Langue du système';

  @override
  String get languageFrench => 'Français';

  @override
  String get languageEnglish => 'English';

  @override
  String get commonCancel => 'Annuler';

  @override
  String get commonOk => 'OK';

  @override
  String get commonCreate => 'Créer';

  @override
  String get commonRename => 'Renommer';

  @override
  String get commonDelete => 'Supprimer';

  @override
  String get commonSave => 'Enregistrer';

  @override
  String get commonClose => 'Fermer';

  @override
  String get commonReplace => 'Remplacer';

  @override
  String bytesB(int count) {
    return '$count o';
  }

  @override
  String bytesKb(String value) {
    return '$value Ko';
  }

  @override
  String bytesMb(String value) {
    return '$value Mo';
  }

  @override
  String get monTitle => 'NomadMCU · Moniteur série';

  @override
  String get monStatusConnected => 'Connecté';

  @override
  String get monStatusConnecting => 'Connexion…';

  @override
  String get monStatusDisconnected => 'Déconnecté';

  @override
  String monTransportTooltip(String name) {
    return 'Transport : $name';
  }

  @override
  String get transportDesktop => 'Port série (libserialport)';

  @override
  String get transportAndroidUsb => 'USB OTG (Android)';

  @override
  String get transportSimulated => 'Simulateur';

  @override
  String get transportUnsupported => 'Non pris en charge';

  @override
  String get monBoardLabel => 'Carte';

  @override
  String get monNoBoardDetected => 'Aucune carte détectée';

  @override
  String get monChooseBoard => 'Choisir une carte';

  @override
  String get monRefreshList => 'Actualiser la liste';

  @override
  String get monBaudLabel => 'Débit (bauds)';

  @override
  String get monConnect => 'Connecter';

  @override
  String get monConnecting => 'Connexion…';

  @override
  String get monDisconnect => 'Déconnecter';

  @override
  String get monDtrTooltip => 'Data Terminal Ready';

  @override
  String get monRtsTooltip => 'Request To Send';

  @override
  String get monResetTooltip =>
      'Reset matériel via RTS (cartes ESP32/ESP8266 à circuit auto-reset)';

  @override
  String get monBootloader => 'Bootloader';

  @override
  String get monBootloaderTooltip =>
      'Séquence esptool : redémarre l’ESP32 en mode téléchargement';

  @override
  String get monCtrlCTooltip => 'Interrompre le programme (MicroPython)';

  @override
  String get monCtrlDTooltip => 'Soft reboot (MicroPython)';

  @override
  String get monHex => 'HEX';

  @override
  String get monHexTooltip => 'Afficher les octets en hexadécimal';

  @override
  String get monTimestamp => 'Horodatage';

  @override
  String get monClear => 'Effacer';

  @override
  String monByteCounters(String rx, String tx) {
    return 'RX $rx · TX $tx';
  }

  @override
  String get monInputHintConnected =>
      'Commande… (Entrée pour envoyer, ↑/↓ historique)';

  @override
  String get monInputHintDisconnected => 'Connectez une carte';

  @override
  String get monLineEndingTooltip => 'Fin de ligne ajoutée à l’envoi';

  @override
  String get monLineEndingNone => 'Aucune';

  @override
  String get monSend => 'Envoyer';

  @override
  String get monEmptyLog =>
      'Connectez une carte : le flux série s’affichera ici.';

  @override
  String monLogEnumerationFailed(String error) {
    return 'Énumération des ports impossible : $error';
  }

  @override
  String monLogAttached(String name) {
    return 'Branché : $name';
  }

  @override
  String monLogDetached(String name) {
    return 'Débranché : $name';
  }

  @override
  String monLogConnectedTo(String name, String config) {
    return 'Connecté à $name ($config)';
  }

  @override
  String monLogConnectFailed(String error) {
    return 'Connexion impossible : $error';
  }

  @override
  String get monLogDisconnected => 'Déconnecté.';

  @override
  String get monLogDeviceLost => 'La carte a été débranchée.';

  @override
  String get monLogConnectionError => 'Connexion interrompue par une erreur.';

  @override
  String monLogBaud(String baud) {
    return 'Débit : $baud bauds';
  }

  @override
  String get monLogReset => 'Reset matériel (impulsion RTS → EN)';

  @override
  String get monLogBootloader =>
      'Séquence bootloader ESP envoyée : la ROM attend esptool';

  @override
  String get mpTitle => 'NomadMCU · MicroPython';

  @override
  String get mpTabConsole => 'Console';

  @override
  String get mpTabFiles => 'Fichiers';

  @override
  String get mpConnectRawRepl => 'Connecter (raw REPL)';

  @override
  String mpTransferLine(String arrow, String name, int done, int total) {
    return '$arrow $name · $done / $total o';
  }

  @override
  String get mpParentFolder => 'Dossier parent';

  @override
  String get mpRefresh => 'Actualiser';

  @override
  String get mpNewFile => 'Nouveau fichier';

  @override
  String get mpNewFolder => 'Nouveau dossier';

  @override
  String get mpUploadFromProject =>
      'Envoyer sur la carte un fichier d’un projet';

  @override
  String get mpSelfTest => 'Test de transfert (débit et intégrité)';

  @override
  String get mpFolderEmpty => 'Dossier vide';

  @override
  String get mpNotConnected => 'Non connecté';

  @override
  String get mpRunFile => 'Exécuter ce fichier';

  @override
  String get mpActions => 'Actions';

  @override
  String get mpMenuRename => 'Renommer…';

  @override
  String get mpMenuDownload => 'Télécharger vers un projet…';

  @override
  String get mpMenuDelete => 'Supprimer…';

  @override
  String get mpRenameOnBoardTitle => 'Renommer sur la carte';

  @override
  String get mpNewName => 'Nouveau nom';

  @override
  String get mpReplaceFileTitle => 'Remplacer le fichier ?';

  @override
  String mpReplaceFileMessage(String name, String folder) {
    return '« $name » existe déjà dans $folder sur la carte. Il sera remplacé.';
  }

  @override
  String get mpDownloadTitle => 'Télécharger vers un projet';

  @override
  String get mpDownload => 'Télécharger';

  @override
  String mpBinaryFile(int bytes) {
    return 'Fichier binaire ($bytes octets) : aucun aperçu disponible.';
  }

  @override
  String get mpNameLabel => 'Nom';

  @override
  String get mpContentLabel => 'Contenu';

  @override
  String get mpNewFileSample => 'print(\"fichier de test\")\n';

  @override
  String get mpWriteToBoard => 'Écrire sur la carte';

  @override
  String mpDeleteTitle(String name) {
    return 'Supprimer $name ?';
  }

  @override
  String get mpDeleteWarning => 'Cette action est définitive.';

  @override
  String mpImageTitle(String name, int bytes) {
    return '$name ($bytes octets)';
  }

  @override
  String get mpImageUnreadable =>
      'Image illisible ou format non pris en charge.';

  @override
  String get mpConsoleHint => 'Code MicroPython (Ctrl+Entrée pour exécuter)';

  @override
  String get mpStop => 'Arrêter';

  @override
  String get mpRun => 'Exécuter';

  @override
  String get mpDefaultCode => 'print(\"Bonjour depuis NomadMCU\")';

  @override
  String get snippetMemory => 'mémoire';

  @override
  String get snippetError => 'erreur';

  @override
  String get snippetLoop => 'boucle 3 s';

  @override
  String get snippetInfinite => 'boucle infinie';

  @override
  String get qkTabTooltip => 'Insérer une indentation';

  @override
  String qkInsert(String symbol) {
    return 'Insérer $symbol';
  }

  @override
  String get qkCtrlCTooltip => 'Interrompre le programme en cours';

  @override
  String get qkCtrlDTooltip => 'Redémarrer l’interpréteur (soft reset)';

  @override
  String mpLogPortOpened(String name) {
    return 'Port ouvert : $name';
  }

  @override
  String get mpLogRawActive => 'Raw REPL actif.';

  @override
  String get mpLogDone => 'Terminé.';

  @override
  String get mpLogDoneWithError => 'Terminé avec erreur.';

  @override
  String get mpLogSoftResetting => 'Redémarrage logiciel…';

  @override
  String get mpLogSoftReset => 'Interpréteur redémarré.';

  @override
  String mpLogSelfTestStart(String kb) {
    return 'Test de transfert : $kb Ko, CRC32 vérifié par la carte.';
  }

  @override
  String mpLogSelfTestRow(
      String chunk, String write, String read, String verdict) {
    return '· morceaux de $chunk o : écriture $write, lecture $read, $verdict';
  }

  @override
  String get mpSelfTestSame => 'relecture identique ✓';

  @override
  String get mpSelfTestDiff => 'RELECTURE DIFFÉRENTE ✗';

  @override
  String mpLogSelfTestFail(String chunk, String error) {
    return '· morceaux de $chunk o : ÉCHEC ✗ $error';
  }

  @override
  String get mpLogSelfTestDone => 'Test de transfert terminé.';

  @override
  String mpRate(String kbps, String secs) {
    return '$kbps Ko/s ($secs s)';
  }

  @override
  String mpLogRead(String path, int bytes) {
    return 'Lu $path ($bytes octets)';
  }

  @override
  String mpLogWritten(String path, int bytes) {
    return 'Écrit $path ($bytes octets, CRC32 vérifié)';
  }

  @override
  String mpLogDeleted(String path) {
    return 'Supprimé $path';
  }

  @override
  String mpLogRenamed(String from, String to) {
    return 'Renommé $from en $to';
  }

  @override
  String mpLogLocalReadFailed(String name) {
    return 'Lecture locale impossible : « $name »';
  }

  @override
  String mpLogDownloadCorrupt(String received, String expected) {
    return 'Téléchargement corrompu : $received octets reçus pour $expected attendus.';
  }

  @override
  String mpLogLocalSaveFailed(String name) {
    return 'Enregistrement local impossible : « $name »';
  }

  @override
  String mpLogDownloaded(String from, String to, int bytes) {
    return 'Téléchargé $from vers $to ($bytes octets, CRC32 vérifié)';
  }

  @override
  String mpLogFolderCreated(String path) {
    return 'Dossier créé $path';
  }

  @override
  String get mpLogResync => 'Session désynchronisée, nouvelle tentative…';

  @override
  String get mpLogResynced => 'Session rétablie.';

  @override
  String mpLogResyncFailed(String error) {
    return 'Resynchronisation impossible : $error';
  }

  @override
  String get edTitle => 'NomadMCU · Éditeur';

  @override
  String get edDraftsTitle => 'Reprendre le travail non enregistré ?';

  @override
  String get edDraftsIntro =>
      'L’application s’est fermée avant l’enregistrement de ces fichiers :';

  @override
  String edDraftItem(String name) {
    return '• $name';
  }

  @override
  String edDraftItemProject(String name, String project) {
    return '• $name  ($project)';
  }

  @override
  String get edDraftsDiscard => 'Abandonner';

  @override
  String get edDraftsRestore => 'Restaurer';

  @override
  String edReplaceFileMessage(String path, String project) {
    return '« $path » existe déjà dans le projet « $project ». Son contenu sera remplacé.';
  }

  @override
  String get edSendTitle => 'Envoyer sur la carte';

  @override
  String get edSendPathLabel => 'Chemin sur la carte';

  @override
  String get edSendHelper => 'Ex. /main.py (lancé au démarrage de la carte)';

  @override
  String get edSend => 'Envoyer';

  @override
  String edSentSnack(String path) {
    return 'Envoyé sur la carte : $path (CRC32 vérifié)';
  }

  @override
  String edCloseTitle(String name) {
    return 'Enregistrer « $name » ?';
  }

  @override
  String get edCloseBody => 'Ce fichier a des modifications non enregistrées.';

  @override
  String get edDontSave => 'Ne pas enregistrer';

  @override
  String get edSaveTooltip => 'Enregistrer sur l’appareil (Ctrl+S)';

  @override
  String get edSendTooltip => 'Envoyer sur la carte';

  @override
  String get edConnectBoardHint => 'Connectez une carte (onglet MicroPython)';

  @override
  String get edRunTooltip =>
      'Exécuter la sélection ou le fichier sur la carte (sans enregistrer)';

  @override
  String get edHideOutput => 'Masquer la sortie';

  @override
  String get edShowOutput => 'Afficher la sortie';

  @override
  String get edEmptyTitle => 'Aucun fichier ouvert.';

  @override
  String get edEmptyBody =>
      'Créez un fichier, ouvrez-en un depuis vos projets (menu en haut à gauche), ou touchez un fichier de la carte dans l’onglet MicroPython.';

  @override
  String edRunLabelSelection(String name) {
    return 'run $name (sélection)';
  }

  @override
  String get prNoProjects => 'Aucun projet.';

  @override
  String get prLoading => 'Chargement…';

  @override
  String get prNewProject => 'Nouveau projet';

  @override
  String get prProjectEmpty => 'Projet vide';

  @override
  String get prProjectNameLabel => 'Nom du projet';

  @override
  String get prDefaultProjectName => 'Mon projet';

  @override
  String get prProjects => 'Projets';

  @override
  String get prProjectActions => 'Actions du projet';

  @override
  String get prMenuNewProject => 'Nouveau projet…';

  @override
  String get prMenuRenameProject => 'Renommer le projet…';

  @override
  String get prMenuDeleteProject => 'Supprimer le projet…';

  @override
  String get prRenameProjectTitle => 'Renommer le projet';

  @override
  String get prDeleteProjectTitle => 'Supprimer le projet ?';

  @override
  String prDeleteProjectMessage(String name) {
    return 'Le projet « $name » et tous ses fichiers seront supprimés de cet appareil. Cette action est définitive.';
  }

  @override
  String get prFileNameLabel => 'Nom du fichier';

  @override
  String get prFolderNameLabel => 'Nom du dossier';

  @override
  String get prMenuUpload => 'Envoyer sur la carte';

  @override
  String get prMenuUploadDisconnected =>
      'Envoyer sur la carte (carte non connectée)';

  @override
  String get prDeleteFolderTitle => 'Supprimer le dossier ?';

  @override
  String get prDeleteFileTitle => 'Supprimer le fichier ?';

  @override
  String prDeleteFolderMessage(String name) {
    return '« $name » et tout son contenu seront supprimés de cet appareil.';
  }

  @override
  String prDeleteFileMessage(String name) {
    return '« $name » sera supprimé de cet appareil.';
  }

  @override
  String get sdSaveTitle => 'Enregistrer sur cet appareil';

  @override
  String get sdProject => 'Projet';

  @override
  String get sdNewProjectItem => 'Nouveau projet…';

  @override
  String get sdNewProjectName => 'Nom du nouveau projet';

  @override
  String get sdFileLabel => 'Fichier';

  @override
  String get sdFileHelper => 'Ex. main.py ou lib/capteur.py';

  @override
  String get pfTitle => 'Choisir un fichier à envoyer';

  @override
  String get pfNoProject => 'Aucun projet';

  @override
  String get pfNothing => 'Rien ici';

  @override
  String get navFlash => 'Flasher';

  @override
  String get flashTitle => 'NomadMCU · Flasher un programme';

  @override
  String get flashUnsupported =>
      'La copie d’un fichier .uf2 n’est pas encore possible sur ce système (Android : prévu via le protocole PICOBOOT).';

  @override
  String get flashStepFile => '1. Fichier du programme';

  @override
  String get flashPickFile => 'Choisir un fichier .uf2';

  @override
  String get flashNoFile => 'Aucun fichier choisi';

  @override
  String flashFileInfo(String family, String amount, int blocks) {
    return '$family · $amount · $blocks blocs';
  }

  @override
  String get flashFamilyUnknown => 'famille non précisée';

  @override
  String get flashStepBoard => '2. Carte';

  @override
  String get flashBoardHint =>
      'La carte redémarre toute seule en mode BOOTSEL. Sinon : maintenez le bouton BOOTSEL, branchez le câble USB, puis relâchez.';

  @override
  String flashDriveFound(String drive, String board) {
    return 'Disque BOOTSEL détecté : $drive ($board)';
  }

  @override
  String get flashDriveNone => 'Aucun disque BOOTSEL détecté pour l’instant.';

  @override
  String get flashStepRun => '3. Écriture';

  @override
  String get flashRun => 'Flasher';

  @override
  String get flashPhaseTouching => 'Redémarrage de la carte en mode BOOTSEL…';

  @override
  String get flashPhaseWaiting => 'Attente du disque BOOTSEL…';

  @override
  String flashPhaseCopying(int percent) {
    return 'Copie vers la carte… $percent %';
  }

  @override
  String get flashPhaseRebooting => 'Attente du redémarrage de la carte…';

  @override
  String flashDone(String amount) {
    return 'Programme écrit ($amount). La carte a redémarré et exécute le nouveau programme.';
  }

  @override
  String get flashNoReboot =>
      'Le fichier a été copié mais la carte n’a pas redémarré : elle a sans doute refusé le programme (mauvaise puce ?). Vérifiez que le fichier est prévu pour cette carte.';

  @override
  String get flashNoDrive =>
      'Aucun disque BOOTSEL n’est apparu. Maintenez le bouton BOOTSEL, branchez le câble USB puis relâchez, et recommencez.';

  @override
  String flashCopyFailed(int done, int total, String cause) {
    return 'Copie interrompue à $done sur $total octets ($cause). La carte peut contenir un programme incomplet : débranchez-la, maintenez BOOTSEL en la rebranchant, puis recommencez.';
  }

  @override
  String flashBadFile(String reason) {
    return 'Fichier UF2 invalide : $reason';
  }

  @override
  String flashWrongFamily(String family) {
    return 'Ce fichier est prévu pour une autre puce ($family) que cette carte Raspberry Pi RP2.';
  }

  @override
  String flashReadFailed(String cause) {
    return 'Lecture du fichier impossible : $cause';
  }

  @override
  String get errSerialUnsupportedIos =>
      'iOS n’autorise pas l’accès aux adaptateurs USB-série : pas d’API USB Host publique, seuls les accessoires certifiés MFi sont accessibles. Utilisez le mode simulé, et plus tard les transports BLE ou WebREPL.';

  @override
  String errSerialUnsupportedPlatform(String platform) {
    return 'Plateforme non prise en charge : $platform.';
  }

  @override
  String errDeviceNotFound(String device) {
    return '$device n’est plus connecté.';
  }

  @override
  String errPortNotFound(String path) {
    return 'Port $path introuvable.';
  }

  @override
  String get errUsbPermissionDenied =>
      'Permission USB refusée, ou puce USB-série non prise en charge.';

  @override
  String errPortPermissionDenied(String path, String os) {
    return 'Impossible d’ouvrir $path : $os. Ajoutez votre utilisateur au groupe « dialout » (Debian/Ubuntu) ou « uucp » (Arch), puis rouvrez votre session.';
  }

  @override
  String errOpenFailedPath(String path, String os) {
    return 'Impossible d’ouvrir $path : $os. Le port est peut-être utilisé par une autre application (Arduino IDE, Thonny…).';
  }

  @override
  String errOpenFailedDevice(String device) {
    return 'Ouverture de $device impossible.';
  }

  @override
  String get errUnknownOsError => 'erreur inconnue';

  @override
  String get errUsbPortCreateFailed => 'Création du port USB impossible.';

  @override
  String get errUsbStreamUnavailable => 'Flux de réception USB indisponible.';

  @override
  String errAlreadyOpen(String device) {
    return '$device est déjà ouvert.';
  }

  @override
  String get errConnectionClosed => 'La connexion est fermée.';

  @override
  String get errClosedDuringRead => 'Le port a été fermé pendant la lecture.';

  @override
  String get errReadFailed => 'Erreur de lecture sur le port série.';

  @override
  String errNoResponse(int timeoutMs) {
    return 'Aucune réponse de la carte après $timeoutMs ms.';
  }

  @override
  String errOperationWrite(String device) {
    return 'Écriture impossible sur $device.';
  }

  @override
  String errOperationConfigure(String device) {
    return 'Configuration impossible sur $device.';
  }

  @override
  String errOperationDtr(String device) {
    return 'Pilotage DTR impossible sur $device.';
  }

  @override
  String errOperationRts(String device) {
    return 'Pilotage RTS impossible sur $device.';
  }

  @override
  String get errUnsupportedStopBits =>
      '1,5 bit de stop non pris en charge par libserialport.';

  @override
  String errWriteTimeout(int remaining, int seconds) {
    return 'Écriture interrompue : $remaining octets non envoyés après $seconds s.';
  }

  @override
  String errSerialOther(String message) {
    return 'Erreur série : $message';
  }

  @override
  String get errLinkReadFailed => 'Erreur de lecture sur le lien.';

  @override
  String get errLinkClosed => 'Le lien a été fermé.';

  @override
  String errRawReplNotEntered(int attempts) {
    return 'La carte ne passe pas en raw REPL après $attempts tentatives. Vérifiez qu’il s’agit bien d’une carte MicroPython et que le port n’est pas utilisé ailleurs.';
  }

  @override
  String errProgramTimeout(int timeoutMs) {
    return 'Le programme a dépassé $timeoutMs ms et a été interrompu.';
  }

  @override
  String get errBusy => 'Une exécution est en cours.';

  @override
  String get errNotActive => 'Raw REPL inactif : connectez-vous d’abord.';

  @override
  String get errSessionBroken =>
      'Session désynchronisée : reconnectez-vous pour la rétablir.';

  @override
  String errUnexpectedAck(String hex) {
    return 'Réponse inattendue au lieu de « OK » : $hex.';
  }

  @override
  String errUnexpectedCrcReply(String reply) {
    return 'Réponse inattendue au calcul du CRC : « $reply ».';
  }

  @override
  String errIntegrity(String path, int expectedSize, int actualSize) {
    return 'Transfert corrompu sur $path : $expectedSize octets attendus, $actualSize reçus.';
  }

  @override
  String errProtocolOther(String message) {
    return 'Erreur de protocole : $message';
  }

  @override
  String errStorageInvalidName(String name) {
    return 'Nom invalide $name. Évitez les caractères / \\ : * ? \" < > | et les noms réservés (CON, NUL…).';
  }

  @override
  String errStorageAlreadyExists(String name) {
    return '$name existe déjà.';
  }

  @override
  String errStorageNotFound(String name) {
    return '$name est introuvable.';
  }

  @override
  String errStorageOutsideProject(String name) {
    return 'Chemin refusé $name : il sortirait du projet.';
  }

  @override
  String errStorageIo(String name, String cause) {
    return 'Erreur de stockage $name: $cause.';
  }
}
