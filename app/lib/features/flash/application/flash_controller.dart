import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_protocols/nomad_protocols.dart';

import '../../../app/providers.dart';
import '../../../app/settings.dart';
import '../../../l10n/error_messages.dart';
import '../../../l10n/l10n.dart';
import '../data/file_pickers.dart';
import '../data/picoboot_gateway.dart';

/// Fichier choisi par l'utilisateur : nom et contenu.
typedef PickedFile = ({String name, Uint8List bytes});

/// Ouvre le sélecteur de fichiers système. Dans les tests : un faux sélecteur.
typedef Uf2Picker = Future<PickedFile?> Function();

final uf2PickerProvider = Provider<Uf2Picker>((ref) => pickUf2WithSystemDialog);

/// Détection et copie vers les disques UF2. Dans les tests : des dossiers temporaires.
final uf2FlasherProvider = Provider<Uf2Flasher>((ref) => Uf2Flasher());

/// Accès PICOBOOT (écriture de la flash par USB). Seulement sur Android : les téléphones n'écrivent pas sur
/// le disque BOOTSEL (risque R1 du PRD), alors que les ordinateurs le font. Dans les tests : une fausse carte.
final picobootGatewayProvider = Provider<PicobootGateway?>((ref) => Platform.isAndroid ? AndroidPicobootGateway() : null);

/// Vrai si l'appareil sait écrire un fichier UF2 : copie sur le disque BOOTSEL (Windows, macOS, Linux)
/// ou PICOBOOT (Android).
final uf2SupportedProvider =
    Provider<bool>((ref) => Platform.isWindows || Platform.isMacOS || Platform.isLinux || Platform.isAndroid);

/// Intervalle de recherche du disque BOOTSEL ; `null` désactive l'interrogation (tests).
final uf2DrivePollProvider = Provider<Duration?>((ref) => const Duration(seconds: 1));

/// Délais d'attente : apparition du disque BOOTSEL après le touch, puis redémarrage après la copie.
final uf2TimeoutsProvider = Provider<({Duration touch, Duration drive, Duration reboot})>(
  (ref) => (touch: const Duration(seconds: 2), drive: const Duration(seconds: 10), reboot: const Duration(seconds: 15)),
);

enum FlashPhase { idle, touching, waitingDrive, permission, erasing, copying, verifying, rebooting, done, failed }

@immutable
class FlashState {
  const FlashState({
    this.devices = const [],
    this.selectedDevice,
    this.fileName,
    this.file,
    this.drive,
    this.bootselUsb = false,
    this.phase = FlashPhase.idle,
    this.done = 0,
    this.total = 0,
    this.message,
  });

  final List<SerialDeviceInfo> devices;
  final SerialDeviceInfo? selectedDevice;
  final String? fileName;
  final Uf2File? file;

  /// Disque BOOTSEL actuellement branché, s'il y en a un.
  final Uf2Drive? drive;

  /// Carte en BOOTSEL vue par USB (PICOBOOT, Android).
  final bool bootselUsb;
  final FlashPhase phase;
  final int done;
  final int total;

  /// Résultat ou erreur, déjà traduit.
  final String? message;

  bool get working => switch (phase) {
        FlashPhase.idle || FlashPhase.done || FlashPhase.failed => false,
        _ => true,
      };

  bool get succeeded => phase == FlashPhase.done;

  bool get canFlash => file != null && !working && (drive != null || bootselUsb || selectedDevice != null);

  FlashState copyWith({
    List<SerialDeviceInfo>? devices,
    Object? selectedDevice = _unset,
    Object? fileName = _unset,
    Object? file = _unset,
    Object? drive = _unset,
    bool? bootselUsb,
    FlashPhase? phase,
    int? done,
    int? total,
    Object? message = _unset,
  }) {
    return FlashState(
      devices: devices ?? this.devices,
      selectedDevice: identical(selectedDevice, _unset) ? this.selectedDevice : selectedDevice as SerialDeviceInfo?,
      fileName: identical(fileName, _unset) ? this.fileName : fileName as String?,
      file: identical(file, _unset) ? this.file : file as Uf2File?,
      drive: identical(drive, _unset) ? this.drive : drive as Uf2Drive?,
      bootselUsb: bootselUsb ?? this.bootselUsb,
      phase: phase ?? this.phase,
      done: done ?? this.done,
      total: total ?? this.total,
      message: identical(message, _unset) ? this.message : message as String?,
    );
  }
}

const Object _unset = Object();

final flashProvider = NotifierProvider<FlashController, FlashState>(FlashController.new);

/// Flashe un fichier `.uf2` sur une carte RP2040 / RP2350 : redémarre la carte en BOOTSEL
/// (touch 1200 bauds) si besoin, attend le disque, copie, puis constate le redémarrage.
class FlashController extends Notifier<FlashState> {
  late SerialTransport _transport;
  late Uf2Flasher _flasher;
  StreamSubscription<DeviceEvent>? _hotplug;
  Timer? _timer;

  AppLocalizations get _l10n => ref.read(l10nProvider);

  @override
  FlashState build() {
    _transport = ref.watch(serialTransportProvider);
    _flasher = ref.watch(uf2FlasherProvider);
    ref.onDispose(() {
      _hotplug?.cancel();
      _timer?.cancel();
    });
    if (_transport.isSupported) {
      _hotplug = _transport.deviceEvents.listen((_) => refresh());
    }
    // Le disque n'est recherché que tant que l'onglet est affiché.
    ref.listen(homeTabProvider, (_, tab) => _poll(tab == HomeTab.flash), fireImmediately: true);
    Future.microtask(refresh);
    return const FlashState();
  }

  void _poll(bool visible) {
    _timer?.cancel();
    _timer = null;
    final interval = ref.read(uf2DrivePollProvider);
    if (visible && interval != null) {
      _timer = Timer.periodic(interval, (_) => _refreshDrive());
      _refreshDrive();
    }
  }

  Future<void> refresh() async {
    await _refreshDevices();
    await _refreshDrive();
  }

  Future<void> _refreshDevices() async {
    if (!_transport.isSupported) return;
    try {
      final devices = (await _transport.listDevices()).where((d) => d.isUsb).toList();
      if (!ref.mounted) return;
      final current = state.selectedDevice;
      final keep = current != null && devices.contains(current);
      state = state.copyWith(
        devices: devices,
        selectedDevice: keep
            ? current
            : (devices.where((d) => d.chip.boardFamily == BoardFamily.rp2040).firstOrNull ?? devices.firstOrNull),
      );
    } catch (_) {
      // Énumération impossible : la liste reste vide, le disque BOOTSEL peut tout de même être détecté.
    }
  }

  Future<void> _refreshDrive() async {
    // Pendant l'écriture le disque est suivi par le flasheur lui-même.
    if (state.working) return;
    final gateway = ref.read(picobootGatewayProvider);
    if (gateway != null) {
      try {
        final present = (await gateway.list()).isNotEmpty;
        if (ref.mounted && !state.working && present != state.bootselUsb) state = state.copyWith(bootselUsb: present);
      } catch (_) {
        // USB illisible : on garde l'état précédent.
      }
      return;
    }
    try {
      final drive = (await _flasher.findDrives()).where((d) => d.isRaspberryPi).firstOrNull;
      if (!ref.mounted || state.working) return;
      if (drive?.path != state.drive?.path) state = state.copyWith(drive: drive);
    } catch (_) {
      // Lecteur illisible : on garde l'état précédent.
    }
  }

  void selectDevice(SerialDeviceInfo? device) => state = state.copyWith(selectedDevice: device);

  Future<void> pickFile() async {
    final PickedFile? picked;
    try {
      picked = await ref.read(uf2PickerProvider)();
    } catch (e) {
      state = state.copyWith(phase: FlashPhase.failed, message: _l10n.flashReadFailed(errorMessage(_l10n, e)));
      return;
    }
    if (picked != null) useFile(picked);
  }

  /// Retient [picked] comme fichier à écrire (choisi à la main ou téléchargé) après l'avoir vérifié.
  void useFile(PickedFile picked) {
    try {
      final file = Uf2File.parse(picked.bytes);
      state = state.copyWith(fileName: picked.name, file: file, phase: FlashPhase.idle, message: null, done: 0, total: 0);
    } on Uf2FormatException catch (e) {
      state = state.copyWith(
        fileName: picked.name,
        file: null,
        phase: FlashPhase.failed,
        message: _l10n.flashBadFile(e.blockIndex == null ? e.message : '${e.message} (bloc ${e.blockIndex})'),
      );
    }
  }

  Future<void> flash() async {
    final file = state.file;
    if (file == null || state.working) return;
    final l10n = _l10n;
    final gateway = ref.read(picobootGatewayProvider);
    if (gateway != null) return _flashPicoboot(file, gateway);
    final timeouts = ref.read(uf2TimeoutsProvider);
    state = state.copyWith(phase: FlashPhase.touching, done: 0, total: file.bytes.length, message: null);
    try {
      var drive = (await _flasher.findDrives()).where((d) => d.isRaspberryPi).firstOrNull;

      if (drive == null) {
        final device = state.selectedDevice;
        if (device == null) {
          _fail(l10n.flashNoDrive);
          return;
        }
        // 1. Touch 1200 bauds (Arduino, SDK Pico) ; 2. à défaut, `machine.bootloader()` (MicroPython,
        // qui ne connaît pas le touch).
        await _touch(device);
        if (!ref.mounted) return;
        state = state.copyWith(phase: FlashPhase.waitingDrive);
        drive = await _flasher.waitForDrive(timeout: timeouts.touch, where: (d) => d.isRaspberryPi);
        if (!ref.mounted) return;
        if (drive == null) {
          await _bootloaderFromRepl(device);
          if (!ref.mounted) return;
          drive = await _flasher.waitForDrive(timeout: timeouts.drive, where: (d) => d.isRaspberryPi);
          if (!ref.mounted) return;
        }
        if (drive == null) {
          _fail(l10n.flashNoDrive);
          return;
        }
      }

      if (file.family != Uf2Family.unknown && !file.family.isRaspberryPi) {
        _fail(l10n.flashWrongFamily(file.family.label));
        return;
      }

      state = state.copyWith(drive: drive, phase: FlashPhase.copying, done: 0, total: file.bytes.length);
      final result = await _flasher.flash(
        file,
        drive,
        fileName: _targetName(state.fileName),
        rebootTimeout: timeouts.reboot,
        onProgress: (done, total) {
          if (ref.mounted) state = state.copyWith(done: done, total: total);
        },
      );
      if (!ref.mounted) return;
      if (result == Uf2FlashResult.rebooted) {
        state = state.copyWith(
          phase: FlashPhase.done,
          drive: null,
          message: l10n.flashDone(_size(l10n, file.payloadSize)),
        );
      } else {
        _fail(l10n.flashNoReboot);
      }
    } on Uf2CopyException catch (e) {
      _fail(l10n.flashCopyFailed(e.written, e.total, '${e.cause}'));
    } catch (e) {
      _fail(errorMessage(l10n, e));
    }
  }

  /// Écrit [file] par USB (PICOBOOT), sans disque de stockage : la voie d'Android.
  ///
  /// Même déroulé que sur ordinateur : mettre la carte en BOOTSEL si besoin (touch 1200 bauds, puis
  /// `machine.bootloader()`), attendre qu'elle apparaisse, mais ici en USB ; demander l'autorisation d'accès
  /// à Android, puis effacer, écrire, vérifier et redémarrer.
  Future<void> _flashPicoboot(Uf2File file, PicobootGateway gateway) async {
    final l10n = _l10n;
    final timeouts = ref.read(uf2TimeoutsProvider);
    if (file.family != Uf2Family.unknown && !file.family.isRaspberryPi) {
      _fail(l10n.flashWrongFamily(file.family.label));
      return;
    }
    state = state.copyWith(phase: FlashPhase.touching, done: 0, total: file.bytes.length, message: null);
    OpenPicobootChannel? channel;
    try {
      var device = (await gateway.list()).firstOrNull;
      if (device == null) {
        final serial = state.selectedDevice;
        if (serial == null) {
          _fail(l10n.flashNoDrive);
          return;
        }
        await _touch(serial);
        if (!ref.mounted) return;
        state = state.copyWith(phase: FlashPhase.waitingDrive);
        device = await _waitForBootsel(gateway, timeouts.touch);
        if (!ref.mounted) return;
        if (device == null) {
          await _bootloaderFromRepl(serial);
          if (!ref.mounted) return;
          device = await _waitForBootsel(gateway, timeouts.drive);
          if (!ref.mounted) return;
        }
        if (device == null) {
          _fail(l10n.flashNoDrive);
          return;
        }
      }

      if (!device.hasPermission) {
        // Fenêtre du système : l'utilisateur doit autoriser NomadMCU à parler à la carte.
        state = state.copyWith(phase: FlashPhase.permission);
        if (!await gateway.requestPermission(device)) {
          _fail(l10n.flashUsbDenied);
          return;
        }
        if (!ref.mounted) return;
      }

      channel = await gateway.open(device);
      await PicobootFlasher(PicobootClient(channel)).flashUf2(
        file,
        onProgress: (phase, done, total) {
          if (!ref.mounted) return;
          state = state.copyWith(
            phase: switch (phase) {
              PicobootPhase.erasing => FlashPhase.erasing,
              PicobootPhase.writing => FlashPhase.copying,
              PicobootPhase.verifying => FlashPhase.verifying,
              PicobootPhase.rebooting => FlashPhase.rebooting,
            },
            done: done,
            total: total,
          );
        },
      );
      if (!ref.mounted) return;

      // La carte redémarre : sa disparition du bus confirme qu'elle exécute le nouveau programme.
      final gone = await _waitUntilGone(gateway, timeouts.reboot);
      if (!ref.mounted) return;
      if (gone) {
        state = state.copyWith(
          phase: FlashPhase.done,
          bootselUsb: false,
          message: l10n.flashDone(_size(l10n, file.payloadSize)),
        );
      } else {
        _fail(l10n.flashNoReboot);
      }
    } catch (e) {
      if (!ref.mounted) return;
      final cause = errorMessage(l10n, e);
      final interrupted = state.phase == FlashPhase.erasing || state.phase == FlashPhase.copying || state.phase == FlashPhase.verifying;
      _fail(interrupted ? l10n.flashUsbInterrupted(cause) : cause);
    } finally {
      await channel?.close();
    }
  }

  /// Attend qu'une carte en BOOTSEL apparaisse sur le bus USB.
  Future<PicobootDevice?> _waitForBootsel(PicobootGateway gateway, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final found = (await gateway.list()).firstOrNull;
      if (found != null) return found;
      if (DateTime.now().isAfter(deadline)) return null;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  /// Attend que la carte quitte le mode BOOTSEL (elle a redémarré).
  Future<bool> _waitUntilGone(PicobootGateway gateway, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      if ((await gateway.list()).isEmpty) return true;
      if (DateTime.now().isAfter(deadline)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  /// Passe la carte en BOOTSEL : ouverture à 1200 bauds puis fermeture (convention Arduino / SDK Pico).
  Future<void> _touch(SerialDeviceInfo device) async {
    final connection = await _transport.open(device);
    await connection.touch1200Baud();
  }

  /// Ctrl-C deux fois, puis la commande, saisie comme dans le REPL.
  static const _enterBootloaderCommand = '\x03\x03import machine\r\nmachine.bootloader()\r\n';

  /// Demande à MicroPython de redémarrer en BOOTSEL : Ctrl-C pour reprendre la main sur le programme
  /// en cours, puis `machine.bootloader()`. La carte disparaît aussitôt : une erreur à la fermeture est normale.
  Future<void> _bootloaderFromRepl(SerialDeviceInfo device) async {
    SerialConnection? connection;
    try {
      connection = await _transport.open(device);
      await connection.write(Uint8List.fromList(_enterBootloaderCommand.codeUnits));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    } finally {
      try {
        await connection?.close();
      } catch (_) {
        // carte déjà repartie
      }
    }
  }

  void _fail(String message) {
    if (!ref.mounted) return;
    state = state.copyWith(phase: FlashPhase.failed, message: message);
  }

  /// Nom du fichier posé sur le disque : l'original, sinon `firmware.uf2`.
  static String _targetName(String? name) => name != null && name.toLowerCase().endsWith('.uf2') ? name : 'firmware.uf2';

  static String _size(AppLocalizations l10n, int bytes) {
    if (bytes < 1024) return l10n.bytesB(bytes);
    if (bytes < 1024 * 1024) return l10n.bytesKb((bytes / 1024).toStringAsFixed(1));
    return l10n.bytesMb((bytes / (1024 * 1024)).toStringAsFixed(1));
  }
}

/// Libellé d'une taille d'après la langue courante, pour l'interface.
String flashSizeLabel(AppLocalizations l10n, int bytes) => FlashController._size(l10n, bytes);
