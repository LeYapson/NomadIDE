import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr')
  ];

  /// No description provided for @appTitle.
  ///
  /// In fr, this message translates to:
  /// **'NomadMCU'**
  String get appTitle;

  /// No description provided for @navMonitor.
  ///
  /// In fr, this message translates to:
  /// **'Moniteur série'**
  String get navMonitor;

  /// No description provided for @navMicroPython.
  ///
  /// In fr, this message translates to:
  /// **'MicroPython'**
  String get navMicroPython;

  /// No description provided for @navEditor.
  ///
  /// In fr, this message translates to:
  /// **'Éditeur'**
  String get navEditor;

  /// No description provided for @navSettings.
  ///
  /// In fr, this message translates to:
  /// **'Réglages'**
  String get navSettings;

  /// No description provided for @settingsTitle.
  ///
  /// In fr, this message translates to:
  /// **'NomadMCU · Réglages'**
  String get settingsTitle;

  /// No description provided for @settingsLanguage.
  ///
  /// In fr, this message translates to:
  /// **'Langue'**
  String get settingsLanguage;

  /// No description provided for @languageSystem.
  ///
  /// In fr, this message translates to:
  /// **'Langue du système'**
  String get languageSystem;

  /// No description provided for @languageFrench.
  ///
  /// In fr, this message translates to:
  /// **'Français'**
  String get languageFrench;

  /// No description provided for @languageEnglish.
  ///
  /// In fr, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @commonCancel.
  ///
  /// In fr, this message translates to:
  /// **'Annuler'**
  String get commonCancel;

  /// No description provided for @commonOk.
  ///
  /// In fr, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// No description provided for @commonCreate.
  ///
  /// In fr, this message translates to:
  /// **'Créer'**
  String get commonCreate;

  /// No description provided for @commonRename.
  ///
  /// In fr, this message translates to:
  /// **'Renommer'**
  String get commonRename;

  /// No description provided for @commonDelete.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer'**
  String get commonDelete;

  /// No description provided for @commonSave.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer'**
  String get commonSave;

  /// No description provided for @commonClose.
  ///
  /// In fr, this message translates to:
  /// **'Fermer'**
  String get commonClose;

  /// No description provided for @commonReplace.
  ///
  /// In fr, this message translates to:
  /// **'Remplacer'**
  String get commonReplace;

  /// No description provided for @bytesB.
  ///
  /// In fr, this message translates to:
  /// **'{count} o'**
  String bytesB(int count);

  /// No description provided for @bytesKb.
  ///
  /// In fr, this message translates to:
  /// **'{value} Ko'**
  String bytesKb(String value);

  /// No description provided for @bytesMb.
  ///
  /// In fr, this message translates to:
  /// **'{value} Mo'**
  String bytesMb(String value);

  /// No description provided for @monTitle.
  ///
  /// In fr, this message translates to:
  /// **'NomadMCU · Moniteur série'**
  String get monTitle;

  /// No description provided for @monStatusConnected.
  ///
  /// In fr, this message translates to:
  /// **'Connecté'**
  String get monStatusConnected;

  /// No description provided for @monStatusConnecting.
  ///
  /// In fr, this message translates to:
  /// **'Connexion…'**
  String get monStatusConnecting;

  /// No description provided for @monStatusDisconnected.
  ///
  /// In fr, this message translates to:
  /// **'Déconnecté'**
  String get monStatusDisconnected;

  /// No description provided for @monTransportTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Transport : {name}'**
  String monTransportTooltip(String name);

  /// No description provided for @transportDesktop.
  ///
  /// In fr, this message translates to:
  /// **'Port série (libserialport)'**
  String get transportDesktop;

  /// No description provided for @transportAndroidUsb.
  ///
  /// In fr, this message translates to:
  /// **'USB OTG (Android)'**
  String get transportAndroidUsb;

  /// No description provided for @transportSimulated.
  ///
  /// In fr, this message translates to:
  /// **'Simulateur'**
  String get transportSimulated;

  /// No description provided for @transportUnsupported.
  ///
  /// In fr, this message translates to:
  /// **'Non pris en charge'**
  String get transportUnsupported;

  /// No description provided for @monBoardLabel.
  ///
  /// In fr, this message translates to:
  /// **'Carte'**
  String get monBoardLabel;

  /// No description provided for @monNoBoardDetected.
  ///
  /// In fr, this message translates to:
  /// **'Aucune carte détectée'**
  String get monNoBoardDetected;

  /// No description provided for @monChooseBoard.
  ///
  /// In fr, this message translates to:
  /// **'Choisir une carte'**
  String get monChooseBoard;

  /// No description provided for @monRefreshList.
  ///
  /// In fr, this message translates to:
  /// **'Actualiser la liste'**
  String get monRefreshList;

  /// No description provided for @monBaudLabel.
  ///
  /// In fr, this message translates to:
  /// **'Débit (bauds)'**
  String get monBaudLabel;

  /// No description provided for @monConnect.
  ///
  /// In fr, this message translates to:
  /// **'Connecter'**
  String get monConnect;

  /// No description provided for @monConnecting.
  ///
  /// In fr, this message translates to:
  /// **'Connexion…'**
  String get monConnecting;

  /// No description provided for @monDisconnect.
  ///
  /// In fr, this message translates to:
  /// **'Déconnecter'**
  String get monDisconnect;

  /// No description provided for @monDtrTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Data Terminal Ready'**
  String get monDtrTooltip;

  /// No description provided for @monRtsTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Request To Send'**
  String get monRtsTooltip;

  /// No description provided for @monResetTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Reset matériel via RTS (cartes ESP32/ESP8266 à circuit auto-reset)'**
  String get monResetTooltip;

  /// No description provided for @monBootloader.
  ///
  /// In fr, this message translates to:
  /// **'Bootloader'**
  String get monBootloader;

  /// No description provided for @monBootloaderTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Séquence esptool : redémarre l’ESP32 en mode téléchargement'**
  String get monBootloaderTooltip;

  /// No description provided for @monCtrlCTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Interrompre le programme (MicroPython)'**
  String get monCtrlCTooltip;

  /// No description provided for @monCtrlDTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Soft reboot (MicroPython)'**
  String get monCtrlDTooltip;

  /// No description provided for @monHex.
  ///
  /// In fr, this message translates to:
  /// **'HEX'**
  String get monHex;

  /// No description provided for @monHexTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Afficher les octets en hexadécimal'**
  String get monHexTooltip;

  /// No description provided for @monTimestamp.
  ///
  /// In fr, this message translates to:
  /// **'Horodatage'**
  String get monTimestamp;

  /// No description provided for @monClear.
  ///
  /// In fr, this message translates to:
  /// **'Effacer'**
  String get monClear;

  /// No description provided for @monByteCounters.
  ///
  /// In fr, this message translates to:
  /// **'RX {rx} · TX {tx}'**
  String monByteCounters(String rx, String tx);

  /// No description provided for @monInputHintConnected.
  ///
  /// In fr, this message translates to:
  /// **'Commande… (Entrée pour envoyer, ↑/↓ historique)'**
  String get monInputHintConnected;

  /// No description provided for @monInputHintDisconnected.
  ///
  /// In fr, this message translates to:
  /// **'Connectez une carte'**
  String get monInputHintDisconnected;

  /// No description provided for @monLineEndingTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Fin de ligne ajoutée à l’envoi'**
  String get monLineEndingTooltip;

  /// No description provided for @monLineEndingNone.
  ///
  /// In fr, this message translates to:
  /// **'Aucune'**
  String get monLineEndingNone;

  /// No description provided for @monSend.
  ///
  /// In fr, this message translates to:
  /// **'Envoyer'**
  String get monSend;

  /// No description provided for @monEmptyLog.
  ///
  /// In fr, this message translates to:
  /// **'Connectez une carte : le flux série s’affichera ici.'**
  String get monEmptyLog;

  /// No description provided for @monLogEnumerationFailed.
  ///
  /// In fr, this message translates to:
  /// **'Énumération des ports impossible : {error}'**
  String monLogEnumerationFailed(String error);

  /// No description provided for @monLogAttached.
  ///
  /// In fr, this message translates to:
  /// **'Branché : {name}'**
  String monLogAttached(String name);

  /// No description provided for @monLogDetached.
  ///
  /// In fr, this message translates to:
  /// **'Débranché : {name}'**
  String monLogDetached(String name);

  /// No description provided for @monLogConnectedTo.
  ///
  /// In fr, this message translates to:
  /// **'Connecté à {name} ({config})'**
  String monLogConnectedTo(String name, String config);

  /// No description provided for @monLogConnectFailed.
  ///
  /// In fr, this message translates to:
  /// **'Connexion impossible : {error}'**
  String monLogConnectFailed(String error);

  /// No description provided for @monLogDisconnected.
  ///
  /// In fr, this message translates to:
  /// **'Déconnecté.'**
  String get monLogDisconnected;

  /// No description provided for @monLogDeviceLost.
  ///
  /// In fr, this message translates to:
  /// **'La carte a été débranchée.'**
  String get monLogDeviceLost;

  /// No description provided for @monLogConnectionError.
  ///
  /// In fr, this message translates to:
  /// **'Connexion interrompue par une erreur.'**
  String get monLogConnectionError;

  /// No description provided for @monLogBaud.
  ///
  /// In fr, this message translates to:
  /// **'Débit : {baud} bauds'**
  String monLogBaud(String baud);

  /// No description provided for @monLogReset.
  ///
  /// In fr, this message translates to:
  /// **'Reset matériel (impulsion RTS → EN)'**
  String get monLogReset;

  /// No description provided for @monLogBootloader.
  ///
  /// In fr, this message translates to:
  /// **'Séquence bootloader ESP envoyée : la ROM attend esptool'**
  String get monLogBootloader;

  /// No description provided for @mpTitle.
  ///
  /// In fr, this message translates to:
  /// **'NomadMCU · MicroPython'**
  String get mpTitle;

  /// No description provided for @mpTabConsole.
  ///
  /// In fr, this message translates to:
  /// **'Console'**
  String get mpTabConsole;

  /// No description provided for @mpTabFiles.
  ///
  /// In fr, this message translates to:
  /// **'Fichiers'**
  String get mpTabFiles;

  /// No description provided for @mpConnectRawRepl.
  ///
  /// In fr, this message translates to:
  /// **'Connecter (raw REPL)'**
  String get mpConnectRawRepl;

  /// No description provided for @mpTransferLine.
  ///
  /// In fr, this message translates to:
  /// **'{arrow} {name} · {done} / {total} o'**
  String mpTransferLine(String arrow, String name, int done, int total);

  /// No description provided for @mpParentFolder.
  ///
  /// In fr, this message translates to:
  /// **'Dossier parent'**
  String get mpParentFolder;

  /// No description provided for @mpRefresh.
  ///
  /// In fr, this message translates to:
  /// **'Actualiser'**
  String get mpRefresh;

  /// No description provided for @mpNewFile.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau fichier'**
  String get mpNewFile;

  /// No description provided for @mpNewFolder.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau dossier'**
  String get mpNewFolder;

  /// No description provided for @mpUploadFromProject.
  ///
  /// In fr, this message translates to:
  /// **'Envoyer sur la carte un fichier d’un projet'**
  String get mpUploadFromProject;

  /// No description provided for @mpSelfTest.
  ///
  /// In fr, this message translates to:
  /// **'Test de transfert (débit et intégrité)'**
  String get mpSelfTest;

  /// No description provided for @mpFolderEmpty.
  ///
  /// In fr, this message translates to:
  /// **'Dossier vide'**
  String get mpFolderEmpty;

  /// No description provided for @mpNotConnected.
  ///
  /// In fr, this message translates to:
  /// **'Non connecté'**
  String get mpNotConnected;

  /// No description provided for @mpRunFile.
  ///
  /// In fr, this message translates to:
  /// **'Exécuter ce fichier'**
  String get mpRunFile;

  /// No description provided for @mpActions.
  ///
  /// In fr, this message translates to:
  /// **'Actions'**
  String get mpActions;

  /// No description provided for @mpMenuRename.
  ///
  /// In fr, this message translates to:
  /// **'Renommer…'**
  String get mpMenuRename;

  /// No description provided for @mpMenuDownload.
  ///
  /// In fr, this message translates to:
  /// **'Télécharger vers un projet…'**
  String get mpMenuDownload;

  /// No description provided for @mpMenuDelete.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer…'**
  String get mpMenuDelete;

  /// No description provided for @mpRenameOnBoardTitle.
  ///
  /// In fr, this message translates to:
  /// **'Renommer sur la carte'**
  String get mpRenameOnBoardTitle;

  /// No description provided for @mpNewName.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau nom'**
  String get mpNewName;

  /// No description provided for @mpReplaceFileTitle.
  ///
  /// In fr, this message translates to:
  /// **'Remplacer le fichier ?'**
  String get mpReplaceFileTitle;

  /// No description provided for @mpReplaceFileMessage.
  ///
  /// In fr, this message translates to:
  /// **'« {name} » existe déjà dans {folder} sur la carte. Il sera remplacé.'**
  String mpReplaceFileMessage(String name, String folder);

  /// No description provided for @mpDownloadTitle.
  ///
  /// In fr, this message translates to:
  /// **'Télécharger vers un projet'**
  String get mpDownloadTitle;

  /// No description provided for @mpDownload.
  ///
  /// In fr, this message translates to:
  /// **'Télécharger'**
  String get mpDownload;

  /// No description provided for @mpBinaryFile.
  ///
  /// In fr, this message translates to:
  /// **'Fichier binaire ({bytes} octets) : aucun aperçu disponible.'**
  String mpBinaryFile(int bytes);

  /// No description provided for @mpNameLabel.
  ///
  /// In fr, this message translates to:
  /// **'Nom'**
  String get mpNameLabel;

  /// No description provided for @mpContentLabel.
  ///
  /// In fr, this message translates to:
  /// **'Contenu'**
  String get mpContentLabel;

  /// No description provided for @mpNewFileSample.
  ///
  /// In fr, this message translates to:
  /// **'print(\"fichier de test\")\n'**
  String get mpNewFileSample;

  /// No description provided for @mpWriteToBoard.
  ///
  /// In fr, this message translates to:
  /// **'Écrire sur la carte'**
  String get mpWriteToBoard;

  /// No description provided for @mpDeleteTitle.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer {name} ?'**
  String mpDeleteTitle(String name);

  /// No description provided for @mpDeleteWarning.
  ///
  /// In fr, this message translates to:
  /// **'Cette action est définitive.'**
  String get mpDeleteWarning;

  /// No description provided for @mpImageTitle.
  ///
  /// In fr, this message translates to:
  /// **'{name} ({bytes} octets)'**
  String mpImageTitle(String name, int bytes);

  /// No description provided for @mpImageUnreadable.
  ///
  /// In fr, this message translates to:
  /// **'Image illisible ou format non pris en charge.'**
  String get mpImageUnreadable;

  /// No description provided for @mpConsoleHint.
  ///
  /// In fr, this message translates to:
  /// **'Code MicroPython (Ctrl+Entrée pour exécuter)'**
  String get mpConsoleHint;

  /// No description provided for @mpStop.
  ///
  /// In fr, this message translates to:
  /// **'Arrêter'**
  String get mpStop;

  /// No description provided for @mpRun.
  ///
  /// In fr, this message translates to:
  /// **'Exécuter'**
  String get mpRun;

  /// No description provided for @mpDefaultCode.
  ///
  /// In fr, this message translates to:
  /// **'print(\"Bonjour depuis NomadMCU\")'**
  String get mpDefaultCode;

  /// No description provided for @snippetMemory.
  ///
  /// In fr, this message translates to:
  /// **'mémoire'**
  String get snippetMemory;

  /// No description provided for @snippetError.
  ///
  /// In fr, this message translates to:
  /// **'erreur'**
  String get snippetError;

  /// No description provided for @snippetLoop.
  ///
  /// In fr, this message translates to:
  /// **'boucle 3 s'**
  String get snippetLoop;

  /// No description provided for @snippetInfinite.
  ///
  /// In fr, this message translates to:
  /// **'boucle infinie'**
  String get snippetInfinite;

  /// No description provided for @qkTabTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Insérer une indentation'**
  String get qkTabTooltip;

  /// No description provided for @qkInsert.
  ///
  /// In fr, this message translates to:
  /// **'Insérer {symbol}'**
  String qkInsert(String symbol);

  /// No description provided for @qkCtrlCTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Interrompre le programme en cours'**
  String get qkCtrlCTooltip;

  /// No description provided for @qkCtrlDTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Redémarrer l’interpréteur (soft reset)'**
  String get qkCtrlDTooltip;

  /// No description provided for @mpLogPortOpened.
  ///
  /// In fr, this message translates to:
  /// **'Port ouvert : {name}'**
  String mpLogPortOpened(String name);

  /// No description provided for @mpLogRawActive.
  ///
  /// In fr, this message translates to:
  /// **'Raw REPL actif.'**
  String get mpLogRawActive;

  /// No description provided for @mpLogDone.
  ///
  /// In fr, this message translates to:
  /// **'Terminé.'**
  String get mpLogDone;

  /// No description provided for @mpLogDoneWithError.
  ///
  /// In fr, this message translates to:
  /// **'Terminé avec erreur.'**
  String get mpLogDoneWithError;

  /// No description provided for @mpLogSoftResetting.
  ///
  /// In fr, this message translates to:
  /// **'Redémarrage logiciel…'**
  String get mpLogSoftResetting;

  /// No description provided for @mpLogSoftReset.
  ///
  /// In fr, this message translates to:
  /// **'Interpréteur redémarré.'**
  String get mpLogSoftReset;

  /// No description provided for @mpLogSelfTestStart.
  ///
  /// In fr, this message translates to:
  /// **'Test de transfert : {kb} Ko, CRC32 vérifié par la carte.'**
  String mpLogSelfTestStart(String kb);

  /// No description provided for @mpLogSelfTestRow.
  ///
  /// In fr, this message translates to:
  /// **'· morceaux de {chunk} o : écriture {write}, lecture {read}, {verdict}'**
  String mpLogSelfTestRow(
      String chunk, String write, String read, String verdict);

  /// No description provided for @mpSelfTestSame.
  ///
  /// In fr, this message translates to:
  /// **'relecture identique ✓'**
  String get mpSelfTestSame;

  /// No description provided for @mpSelfTestDiff.
  ///
  /// In fr, this message translates to:
  /// **'RELECTURE DIFFÉRENTE ✗'**
  String get mpSelfTestDiff;

  /// No description provided for @mpLogSelfTestFail.
  ///
  /// In fr, this message translates to:
  /// **'· morceaux de {chunk} o : ÉCHEC ✗ {error}'**
  String mpLogSelfTestFail(String chunk, String error);

  /// No description provided for @mpLogSelfTestDone.
  ///
  /// In fr, this message translates to:
  /// **'Test de transfert terminé.'**
  String get mpLogSelfTestDone;

  /// No description provided for @mpRate.
  ///
  /// In fr, this message translates to:
  /// **'{kbps} Ko/s ({secs} s)'**
  String mpRate(String kbps, String secs);

  /// No description provided for @mpLogRead.
  ///
  /// In fr, this message translates to:
  /// **'Lu {path} ({bytes} octets)'**
  String mpLogRead(String path, int bytes);

  /// No description provided for @mpLogWritten.
  ///
  /// In fr, this message translates to:
  /// **'Écrit {path} ({bytes} octets, CRC32 vérifié)'**
  String mpLogWritten(String path, int bytes);

  /// No description provided for @mpLogDeleted.
  ///
  /// In fr, this message translates to:
  /// **'Supprimé {path}'**
  String mpLogDeleted(String path);

  /// No description provided for @mpLogRenamed.
  ///
  /// In fr, this message translates to:
  /// **'Renommé {from} en {to}'**
  String mpLogRenamed(String from, String to);

  /// No description provided for @mpLogLocalReadFailed.
  ///
  /// In fr, this message translates to:
  /// **'Lecture locale impossible : « {name} »'**
  String mpLogLocalReadFailed(String name);

  /// No description provided for @mpLogDownloadCorrupt.
  ///
  /// In fr, this message translates to:
  /// **'Téléchargement corrompu : {received} octets reçus pour {expected} attendus.'**
  String mpLogDownloadCorrupt(String received, String expected);

  /// No description provided for @mpLogLocalSaveFailed.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrement local impossible : « {name} »'**
  String mpLogLocalSaveFailed(String name);

  /// No description provided for @mpLogDownloaded.
  ///
  /// In fr, this message translates to:
  /// **'Téléchargé {from} vers {to} ({bytes} octets, CRC32 vérifié)'**
  String mpLogDownloaded(String from, String to, int bytes);

  /// No description provided for @mpLogFolderCreated.
  ///
  /// In fr, this message translates to:
  /// **'Dossier créé {path}'**
  String mpLogFolderCreated(String path);

  /// No description provided for @mpLogResync.
  ///
  /// In fr, this message translates to:
  /// **'Session désynchronisée, nouvelle tentative…'**
  String get mpLogResync;

  /// No description provided for @mpLogResynced.
  ///
  /// In fr, this message translates to:
  /// **'Session rétablie.'**
  String get mpLogResynced;

  /// No description provided for @mpLogResyncFailed.
  ///
  /// In fr, this message translates to:
  /// **'Resynchronisation impossible : {error}'**
  String mpLogResyncFailed(String error);

  /// No description provided for @edTitle.
  ///
  /// In fr, this message translates to:
  /// **'NomadMCU · Éditeur'**
  String get edTitle;

  /// No description provided for @edDraftsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Reprendre le travail non enregistré ?'**
  String get edDraftsTitle;

  /// No description provided for @edDraftsIntro.
  ///
  /// In fr, this message translates to:
  /// **'L’application s’est fermée avant l’enregistrement de ces fichiers :'**
  String get edDraftsIntro;

  /// No description provided for @edDraftItem.
  ///
  /// In fr, this message translates to:
  /// **'• {name}'**
  String edDraftItem(String name);

  /// No description provided for @edDraftItemProject.
  ///
  /// In fr, this message translates to:
  /// **'• {name}  ({project})'**
  String edDraftItemProject(String name, String project);

  /// No description provided for @edDraftsDiscard.
  ///
  /// In fr, this message translates to:
  /// **'Abandonner'**
  String get edDraftsDiscard;

  /// No description provided for @edDraftsRestore.
  ///
  /// In fr, this message translates to:
  /// **'Restaurer'**
  String get edDraftsRestore;

  /// No description provided for @edReplaceFileMessage.
  ///
  /// In fr, this message translates to:
  /// **'« {path} » existe déjà dans le projet « {project} ». Son contenu sera remplacé.'**
  String edReplaceFileMessage(String path, String project);

  /// No description provided for @edSendTitle.
  ///
  /// In fr, this message translates to:
  /// **'Envoyer sur la carte'**
  String get edSendTitle;

  /// No description provided for @edSendPathLabel.
  ///
  /// In fr, this message translates to:
  /// **'Chemin sur la carte'**
  String get edSendPathLabel;

  /// No description provided for @edSendHelper.
  ///
  /// In fr, this message translates to:
  /// **'Ex. /main.py (lancé au démarrage de la carte)'**
  String get edSendHelper;

  /// No description provided for @edSend.
  ///
  /// In fr, this message translates to:
  /// **'Envoyer'**
  String get edSend;

  /// No description provided for @edSentSnack.
  ///
  /// In fr, this message translates to:
  /// **'Envoyé sur la carte : {path} (CRC32 vérifié)'**
  String edSentSnack(String path);

  /// No description provided for @edCloseTitle.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer « {name} » ?'**
  String edCloseTitle(String name);

  /// No description provided for @edCloseBody.
  ///
  /// In fr, this message translates to:
  /// **'Ce fichier a des modifications non enregistrées.'**
  String get edCloseBody;

  /// No description provided for @edDontSave.
  ///
  /// In fr, this message translates to:
  /// **'Ne pas enregistrer'**
  String get edDontSave;

  /// No description provided for @edSaveTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer sur l’appareil (Ctrl+S)'**
  String get edSaveTooltip;

  /// No description provided for @edSendTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Envoyer sur la carte'**
  String get edSendTooltip;

  /// No description provided for @edConnectBoardHint.
  ///
  /// In fr, this message translates to:
  /// **'Connectez une carte (onglet MicroPython)'**
  String get edConnectBoardHint;

  /// No description provided for @edRunTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Exécuter la sélection ou le fichier sur la carte (sans enregistrer)'**
  String get edRunTooltip;

  /// No description provided for @edHideOutput.
  ///
  /// In fr, this message translates to:
  /// **'Masquer la sortie'**
  String get edHideOutput;

  /// No description provided for @edShowOutput.
  ///
  /// In fr, this message translates to:
  /// **'Afficher la sortie'**
  String get edShowOutput;

  /// No description provided for @edEmptyTitle.
  ///
  /// In fr, this message translates to:
  /// **'Aucun fichier ouvert.'**
  String get edEmptyTitle;

  /// No description provided for @edEmptyBody.
  ///
  /// In fr, this message translates to:
  /// **'Créez un fichier, ouvrez-en un depuis vos projets (menu en haut à gauche), ou touchez un fichier de la carte dans l’onglet MicroPython.'**
  String get edEmptyBody;

  /// No description provided for @edRunLabelSelection.
  ///
  /// In fr, this message translates to:
  /// **'run {name} (sélection)'**
  String edRunLabelSelection(String name);

  /// No description provided for @prNoProjects.
  ///
  /// In fr, this message translates to:
  /// **'Aucun projet.'**
  String get prNoProjects;

  /// No description provided for @prLoading.
  ///
  /// In fr, this message translates to:
  /// **'Chargement…'**
  String get prLoading;

  /// No description provided for @prNewProject.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau projet'**
  String get prNewProject;

  /// No description provided for @prProjectEmpty.
  ///
  /// In fr, this message translates to:
  /// **'Projet vide'**
  String get prProjectEmpty;

  /// No description provided for @prProjectNameLabel.
  ///
  /// In fr, this message translates to:
  /// **'Nom du projet'**
  String get prProjectNameLabel;

  /// No description provided for @prDefaultProjectName.
  ///
  /// In fr, this message translates to:
  /// **'Mon projet'**
  String get prDefaultProjectName;

  /// No description provided for @prProjects.
  ///
  /// In fr, this message translates to:
  /// **'Projets'**
  String get prProjects;

  /// No description provided for @prProjectActions.
  ///
  /// In fr, this message translates to:
  /// **'Actions du projet'**
  String get prProjectActions;

  /// No description provided for @prMenuNewProject.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau projet…'**
  String get prMenuNewProject;

  /// No description provided for @prMenuRenameProject.
  ///
  /// In fr, this message translates to:
  /// **'Renommer le projet…'**
  String get prMenuRenameProject;

  /// No description provided for @prMenuDeleteProject.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer le projet…'**
  String get prMenuDeleteProject;

  /// No description provided for @prRenameProjectTitle.
  ///
  /// In fr, this message translates to:
  /// **'Renommer le projet'**
  String get prRenameProjectTitle;

  /// No description provided for @prDeleteProjectTitle.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer le projet ?'**
  String get prDeleteProjectTitle;

  /// No description provided for @prDeleteProjectMessage.
  ///
  /// In fr, this message translates to:
  /// **'Le projet « {name} » et tous ses fichiers seront supprimés de cet appareil. Cette action est définitive.'**
  String prDeleteProjectMessage(String name);

  /// No description provided for @prFileNameLabel.
  ///
  /// In fr, this message translates to:
  /// **'Nom du fichier'**
  String get prFileNameLabel;

  /// No description provided for @prFolderNameLabel.
  ///
  /// In fr, this message translates to:
  /// **'Nom du dossier'**
  String get prFolderNameLabel;

  /// No description provided for @prMenuUpload.
  ///
  /// In fr, this message translates to:
  /// **'Envoyer sur la carte'**
  String get prMenuUpload;

  /// No description provided for @prMenuUploadDisconnected.
  ///
  /// In fr, this message translates to:
  /// **'Envoyer sur la carte (carte non connectée)'**
  String get prMenuUploadDisconnected;

  /// No description provided for @prDeleteFolderTitle.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer le dossier ?'**
  String get prDeleteFolderTitle;

  /// No description provided for @prDeleteFileTitle.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer le fichier ?'**
  String get prDeleteFileTitle;

  /// No description provided for @prDeleteFolderMessage.
  ///
  /// In fr, this message translates to:
  /// **'« {name} » et tout son contenu seront supprimés de cet appareil.'**
  String prDeleteFolderMessage(String name);

  /// No description provided for @prDeleteFileMessage.
  ///
  /// In fr, this message translates to:
  /// **'« {name} » sera supprimé de cet appareil.'**
  String prDeleteFileMessage(String name);

  /// No description provided for @sdSaveTitle.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer sur cet appareil'**
  String get sdSaveTitle;

  /// No description provided for @sdProject.
  ///
  /// In fr, this message translates to:
  /// **'Projet'**
  String get sdProject;

  /// No description provided for @sdNewProjectItem.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau projet…'**
  String get sdNewProjectItem;

  /// No description provided for @sdNewProjectName.
  ///
  /// In fr, this message translates to:
  /// **'Nom du nouveau projet'**
  String get sdNewProjectName;

  /// No description provided for @sdFileLabel.
  ///
  /// In fr, this message translates to:
  /// **'Fichier'**
  String get sdFileLabel;

  /// No description provided for @sdFileHelper.
  ///
  /// In fr, this message translates to:
  /// **'Ex. main.py ou lib/capteur.py'**
  String get sdFileHelper;

  /// No description provided for @pfTitle.
  ///
  /// In fr, this message translates to:
  /// **'Choisir un fichier à envoyer'**
  String get pfTitle;

  /// No description provided for @pfNoProject.
  ///
  /// In fr, this message translates to:
  /// **'Aucun projet'**
  String get pfNoProject;

  /// No description provided for @pfNothing.
  ///
  /// In fr, this message translates to:
  /// **'Rien ici'**
  String get pfNothing;

  /// No description provided for @navFlash.
  ///
  /// In fr, this message translates to:
  /// **'Flasher'**
  String get navFlash;

  /// No description provided for @flashTitle.
  ///
  /// In fr, this message translates to:
  /// **'NomadMCU · Flasher un programme'**
  String get flashTitle;

  /// No description provided for @flashUnsupported.
  ///
  /// In fr, this message translates to:
  /// **'La copie d’un fichier .uf2 n’est pas encore possible sur ce système (Android : prévu via le protocole PICOBOOT).'**
  String get flashUnsupported;

  /// No description provided for @flashStepFile.
  ///
  /// In fr, this message translates to:
  /// **'1. Fichier du programme'**
  String get flashStepFile;

  /// No description provided for @flashPickFile.
  ///
  /// In fr, this message translates to:
  /// **'Choisir un fichier .uf2'**
  String get flashPickFile;

  /// No description provided for @flashNoFile.
  ///
  /// In fr, this message translates to:
  /// **'Aucun fichier choisi'**
  String get flashNoFile;

  /// No description provided for @flashFileInfo.
  ///
  /// In fr, this message translates to:
  /// **'{family} · {amount} · {blocks} blocs'**
  String flashFileInfo(String family, String amount, int blocks);

  /// No description provided for @flashFamilyUnknown.
  ///
  /// In fr, this message translates to:
  /// **'famille non précisée'**
  String get flashFamilyUnknown;

  /// No description provided for @flashStepBoard.
  ///
  /// In fr, this message translates to:
  /// **'2. Carte'**
  String get flashStepBoard;

  /// No description provided for @flashBoardHint.
  ///
  /// In fr, this message translates to:
  /// **'La carte redémarre toute seule en mode BOOTSEL. Sinon : maintenez le bouton BOOTSEL, branchez le câble USB, puis relâchez.'**
  String get flashBoardHint;

  /// No description provided for @flashDriveFound.
  ///
  /// In fr, this message translates to:
  /// **'Disque BOOTSEL détecté : {drive} ({board})'**
  String flashDriveFound(String drive, String board);

  /// No description provided for @flashDriveNone.
  ///
  /// In fr, this message translates to:
  /// **'Aucun disque BOOTSEL détecté pour l’instant.'**
  String get flashDriveNone;

  /// No description provided for @flashStepRun.
  ///
  /// In fr, this message translates to:
  /// **'3. Écriture'**
  String get flashStepRun;

  /// No description provided for @flashRun.
  ///
  /// In fr, this message translates to:
  /// **'Flasher'**
  String get flashRun;

  /// No description provided for @flashPhaseTouching.
  ///
  /// In fr, this message translates to:
  /// **'Redémarrage de la carte en mode BOOTSEL…'**
  String get flashPhaseTouching;

  /// No description provided for @flashPhaseWaiting.
  ///
  /// In fr, this message translates to:
  /// **'Attente du disque BOOTSEL…'**
  String get flashPhaseWaiting;

  /// No description provided for @flashPhaseCopying.
  ///
  /// In fr, this message translates to:
  /// **'Copie vers la carte… {percent} %'**
  String flashPhaseCopying(int percent);

  /// No description provided for @flashPhaseRebooting.
  ///
  /// In fr, this message translates to:
  /// **'Attente du redémarrage de la carte…'**
  String get flashPhaseRebooting;

  /// No description provided for @flashDone.
  ///
  /// In fr, this message translates to:
  /// **'Programme écrit ({amount}). La carte a redémarré et exécute le nouveau programme.'**
  String flashDone(String amount);

  /// No description provided for @flashNoReboot.
  ///
  /// In fr, this message translates to:
  /// **'Le fichier a été copié mais la carte n’a pas redémarré : elle a sans doute refusé le programme (mauvaise puce ?). Vérifiez que le fichier est prévu pour cette carte.'**
  String get flashNoReboot;

  /// No description provided for @flashNoDrive.
  ///
  /// In fr, this message translates to:
  /// **'Aucun disque BOOTSEL n’est apparu. Maintenez le bouton BOOTSEL, branchez le câble USB puis relâchez, et recommencez.'**
  String get flashNoDrive;

  /// No description provided for @flashCopyFailed.
  ///
  /// In fr, this message translates to:
  /// **'Copie interrompue à {done} sur {total} octets ({cause}). La carte peut contenir un programme incomplet : débranchez-la, maintenez BOOTSEL en la rebranchant, puis recommencez.'**
  String flashCopyFailed(int done, int total, String cause);

  /// No description provided for @flashBadFile.
  ///
  /// In fr, this message translates to:
  /// **'Fichier UF2 invalide : {reason}'**
  String flashBadFile(String reason);

  /// No description provided for @flashWrongFamily.
  ///
  /// In fr, this message translates to:
  /// **'Ce fichier est prévu pour une autre puce ({family}) que cette carte Raspberry Pi RP2.'**
  String flashWrongFamily(String family);

  /// No description provided for @flashReadFailed.
  ///
  /// In fr, this message translates to:
  /// **'Lecture du fichier impossible : {cause}'**
  String flashReadFailed(String cause);

  /// No description provided for @errSerialUnsupportedIos.
  ///
  /// In fr, this message translates to:
  /// **'iOS n’autorise pas l’accès aux adaptateurs USB-série : pas d’API USB Host publique, seuls les accessoires certifiés MFi sont accessibles. Utilisez le mode simulé, et plus tard les transports BLE ou WebREPL.'**
  String get errSerialUnsupportedIos;

  /// No description provided for @errSerialUnsupportedPlatform.
  ///
  /// In fr, this message translates to:
  /// **'Plateforme non prise en charge : {platform}.'**
  String errSerialUnsupportedPlatform(String platform);

  /// No description provided for @errDeviceNotFound.
  ///
  /// In fr, this message translates to:
  /// **'{device} n’est plus connecté.'**
  String errDeviceNotFound(String device);

  /// No description provided for @errPortNotFound.
  ///
  /// In fr, this message translates to:
  /// **'Port {path} introuvable.'**
  String errPortNotFound(String path);

  /// No description provided for @errUsbPermissionDenied.
  ///
  /// In fr, this message translates to:
  /// **'Permission USB refusée, ou puce USB-série non prise en charge.'**
  String get errUsbPermissionDenied;

  /// No description provided for @errPortPermissionDenied.
  ///
  /// In fr, this message translates to:
  /// **'Impossible d’ouvrir {path} : {os}. Ajoutez votre utilisateur au groupe « dialout » (Debian/Ubuntu) ou « uucp » (Arch), puis rouvrez votre session.'**
  String errPortPermissionDenied(String path, String os);

  /// No description provided for @errOpenFailedPath.
  ///
  /// In fr, this message translates to:
  /// **'Impossible d’ouvrir {path} : {os}. Le port est peut-être utilisé par une autre application (Arduino IDE, Thonny…).'**
  String errOpenFailedPath(String path, String os);

  /// No description provided for @errOpenFailedDevice.
  ///
  /// In fr, this message translates to:
  /// **'Ouverture de {device} impossible.'**
  String errOpenFailedDevice(String device);

  /// No description provided for @errUnknownOsError.
  ///
  /// In fr, this message translates to:
  /// **'erreur inconnue'**
  String get errUnknownOsError;

  /// No description provided for @errUsbPortCreateFailed.
  ///
  /// In fr, this message translates to:
  /// **'Création du port USB impossible.'**
  String get errUsbPortCreateFailed;

  /// No description provided for @errUsbStreamUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Flux de réception USB indisponible.'**
  String get errUsbStreamUnavailable;

  /// No description provided for @errAlreadyOpen.
  ///
  /// In fr, this message translates to:
  /// **'{device} est déjà ouvert.'**
  String errAlreadyOpen(String device);

  /// No description provided for @errConnectionClosed.
  ///
  /// In fr, this message translates to:
  /// **'La connexion est fermée.'**
  String get errConnectionClosed;

  /// No description provided for @errClosedDuringRead.
  ///
  /// In fr, this message translates to:
  /// **'Le port a été fermé pendant la lecture.'**
  String get errClosedDuringRead;

  /// No description provided for @errReadFailed.
  ///
  /// In fr, this message translates to:
  /// **'Erreur de lecture sur le port série.'**
  String get errReadFailed;

  /// No description provided for @errNoResponse.
  ///
  /// In fr, this message translates to:
  /// **'Aucune réponse de la carte après {timeoutMs} ms.'**
  String errNoResponse(int timeoutMs);

  /// No description provided for @errOperationWrite.
  ///
  /// In fr, this message translates to:
  /// **'Écriture impossible sur {device}.'**
  String errOperationWrite(String device);

  /// No description provided for @errOperationConfigure.
  ///
  /// In fr, this message translates to:
  /// **'Configuration impossible sur {device}.'**
  String errOperationConfigure(String device);

  /// No description provided for @errOperationDtr.
  ///
  /// In fr, this message translates to:
  /// **'Pilotage DTR impossible sur {device}.'**
  String errOperationDtr(String device);

  /// No description provided for @errOperationRts.
  ///
  /// In fr, this message translates to:
  /// **'Pilotage RTS impossible sur {device}.'**
  String errOperationRts(String device);

  /// No description provided for @errUnsupportedStopBits.
  ///
  /// In fr, this message translates to:
  /// **'1,5 bit de stop non pris en charge par libserialport.'**
  String get errUnsupportedStopBits;

  /// No description provided for @errWriteTimeout.
  ///
  /// In fr, this message translates to:
  /// **'Écriture interrompue : {remaining} octets non envoyés après {seconds} s.'**
  String errWriteTimeout(int remaining, int seconds);

  /// No description provided for @errSerialOther.
  ///
  /// In fr, this message translates to:
  /// **'Erreur série : {message}'**
  String errSerialOther(String message);

  /// No description provided for @errLinkReadFailed.
  ///
  /// In fr, this message translates to:
  /// **'Erreur de lecture sur le lien.'**
  String get errLinkReadFailed;

  /// No description provided for @errLinkClosed.
  ///
  /// In fr, this message translates to:
  /// **'Le lien a été fermé.'**
  String get errLinkClosed;

  /// No description provided for @errRawReplNotEntered.
  ///
  /// In fr, this message translates to:
  /// **'La carte ne passe pas en raw REPL après {attempts} tentatives. Vérifiez qu’il s’agit bien d’une carte MicroPython et que le port n’est pas utilisé ailleurs.'**
  String errRawReplNotEntered(int attempts);

  /// No description provided for @errProgramTimeout.
  ///
  /// In fr, this message translates to:
  /// **'Le programme a dépassé {timeoutMs} ms et a été interrompu.'**
  String errProgramTimeout(int timeoutMs);

  /// No description provided for @errBusy.
  ///
  /// In fr, this message translates to:
  /// **'Une exécution est en cours.'**
  String get errBusy;

  /// No description provided for @errNotActive.
  ///
  /// In fr, this message translates to:
  /// **'Raw REPL inactif : connectez-vous d’abord.'**
  String get errNotActive;

  /// No description provided for @errSessionBroken.
  ///
  /// In fr, this message translates to:
  /// **'Session désynchronisée : reconnectez-vous pour la rétablir.'**
  String get errSessionBroken;

  /// No description provided for @errUnexpectedAck.
  ///
  /// In fr, this message translates to:
  /// **'Réponse inattendue au lieu de « OK » : {hex}.'**
  String errUnexpectedAck(String hex);

  /// No description provided for @errUnexpectedCrcReply.
  ///
  /// In fr, this message translates to:
  /// **'Réponse inattendue au calcul du CRC : « {reply} ».'**
  String errUnexpectedCrcReply(String reply);

  /// No description provided for @errIntegrity.
  ///
  /// In fr, this message translates to:
  /// **'Transfert corrompu sur {path} : {expectedSize} octets attendus, {actualSize} reçus.'**
  String errIntegrity(String path, int expectedSize, int actualSize);

  /// No description provided for @errProtocolOther.
  ///
  /// In fr, this message translates to:
  /// **'Erreur de protocole : {message}'**
  String errProtocolOther(String message);

  /// No description provided for @errStorageInvalidName.
  ///
  /// In fr, this message translates to:
  /// **'Nom invalide {name}. Évitez les caractères / \\ : * ? \" < > | et les noms réservés (CON, NUL…).'**
  String errStorageInvalidName(String name);

  /// No description provided for @errStorageAlreadyExists.
  ///
  /// In fr, this message translates to:
  /// **'{name} existe déjà.'**
  String errStorageAlreadyExists(String name);

  /// No description provided for @errStorageNotFound.
  ///
  /// In fr, this message translates to:
  /// **'{name} est introuvable.'**
  String errStorageNotFound(String name);

  /// No description provided for @errStorageOutsideProject.
  ///
  /// In fr, this message translates to:
  /// **'Chemin refusé {name} : il sortirait du projet.'**
  String errStorageOutsideProject(String name);

  /// No description provided for @errStorageIo.
  ///
  /// In fr, this message translates to:
  /// **'Erreur de stockage {name}: {cause}.'**
  String errStorageIo(String name, String cause);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
