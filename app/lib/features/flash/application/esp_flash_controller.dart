import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_protocols/nomad_protocols.dart';

import '../../../app/providers.dart';
import '../../../app/settings.dart';
import '../../../l10n/error_messages.dart';
import '../../../l10n/l10n.dart';
import '../../micropython/data/serial_connection_link.dart';
import '../data/file_pickers.dart';
import 'flash_controller.dart' show PickedFile, flashSizeLabel;

/// Sélecteur de fichier `.bin`. Dans les tests : un faux sélecteur.
final binPickerProvider = Provider<Future<PickedFile?> Function()>((ref) => pickBinWithSystemDialog);

/// Débits proposés pour l'écriture. Le bootloader démarre toujours à 115200.
const List<int> espWriteBauds = [115200, 460800, 921600];

/// Essais de passage en bootloader (le circuit de reset est parfois capricieux) et, pour chacun,
/// nombre et délai des paquets de synchronisation. Remplaçable dans les tests.
final espSyncPolicyProvider = Provider<({int bootAttempts, int syncAttempts, Duration syncTimeout})>(
  (ref) => (bootAttempts: 3, syncAttempts: 7, syncTimeout: const Duration(milliseconds: 200)),
);

enum EspFlashPhase { idle, connecting, writing, verifying, restarting, done, failed }

@immutable
class EspFlashState {
  const EspFlashState({
    this.devices = const [],
    this.selectedDevice,
    this.fileName,
    this.bytes,
    this.offsetText = '0x10000',
    this.baudRate = 115200,
    this.phase = EspFlashPhase.idle,
    this.done = 0,
    this.total = 0,
    this.message,
  });

  final List<SerialDeviceInfo> devices;
  final SerialDeviceInfo? selectedDevice;
  final String? fileName;
  final Uint8List? bytes;
  final String offsetText;
  final int baudRate;
  final EspFlashPhase phase;
  final int done;
  final int total;
  final String? message;

  bool get working => switch (phase) {
        EspFlashPhase.connecting ||
        EspFlashPhase.writing ||
        EspFlashPhase.verifying ||
        EspFlashPhase.restarting =>
          true,
        _ => false,
      };

  bool get succeeded => phase == EspFlashPhase.done;

  bool get canFlash => bytes != null && selectedDevice != null && !working;

  EspFlashState copyWith({
    List<SerialDeviceInfo>? devices,
    Object? selectedDevice = _unset,
    Object? fileName = _unset,
    Object? bytes = _unset,
    String? offsetText,
    int? baudRate,
    EspFlashPhase? phase,
    int? done,
    int? total,
    Object? message = _unset,
  }) {
    return EspFlashState(
      devices: devices ?? this.devices,
      selectedDevice: identical(selectedDevice, _unset) ? this.selectedDevice : selectedDevice as SerialDeviceInfo?,
      fileName: identical(fileName, _unset) ? this.fileName : fileName as String?,
      bytes: identical(bytes, _unset) ? this.bytes : bytes as Uint8List?,
      offsetText: offsetText ?? this.offsetText,
      baudRate: baudRate ?? this.baudRate,
      phase: phase ?? this.phase,
      done: done ?? this.done,
      total: total ?? this.total,
      message: identical(message, _unset) ? this.message : message as String?,
    );
  }
}

const Object _unset = Object();

final espFlashProvider = NotifierProvider<EspFlashController, EspFlashState>(EspFlashController.new);

/// Flashe un `.bin` sur un ESP32 / ESP8266 : reset en bootloader par DTR/RTS, synchronisation,
/// écriture compressée vérifiée par MD5, puis reset matériel.
class EspFlashController extends Notifier<EspFlashState> {
  late SerialTransport _transport;
  StreamSubscription<DeviceEvent>? _hotplug;

  AppLocalizations get _l10n => ref.read(l10nProvider);

  @override
  EspFlashState build() {
    _transport = ref.watch(serialTransportProvider);
    ref.onDispose(() => _hotplug?.cancel());
    if (_transport.isSupported) {
      _hotplug = _transport.deviceEvents.listen((_) => refreshDevices());
      Future.microtask(refreshDevices);
    }
    return const EspFlashState();
  }

  Future<void> refreshDevices() async {
    try {
      final devices = (await _transport.listDevices()).where((d) => d.isUsb).toList();
      if (!ref.mounted) return;
      final current = state.selectedDevice;
      state = state.copyWith(
        devices: devices,
        selectedDevice: current != null && devices.contains(current)
            ? current
            : (devices.where((d) => d.chip.boardFamily == BoardFamily.esp32).firstOrNull ?? devices.firstOrNull),
      );
    } catch (_) {
      // Énumération impossible : la liste reste telle quelle.
    }
  }

  void selectDevice(SerialDeviceInfo? device) => state = state.copyWith(selectedDevice: device);

  void setOffset(String text) => state = state.copyWith(offsetText: text);

  void setBaudRate(int baudRate) => state = state.copyWith(baudRate: baudRate);

  Future<void> pickFile() async {
    final PickedFile? picked;
    try {
      picked = await ref.read(binPickerProvider)();
    } catch (e) {
      state = state.copyWith(phase: EspFlashPhase.failed, message: _l10n.flashReadFailed(errorMessage(_l10n, e)));
      return;
    }
    if (picked == null) return;
    state = state.copyWith(fileName: picked.name, bytes: picked.bytes, phase: EspFlashPhase.idle, message: null, done: 0, total: 0);
  }

  /// Adresse saisie : « 0x10000 », « 10000h » ou décimal.
  static int? parseOffset(String text) {
    final t = text.trim().toLowerCase();
    if (t.isEmpty) return null;
    if (t.startsWith('0x')) return int.tryParse(t.substring(2), radix: 16);
    if (t.endsWith('h')) return int.tryParse(t.substring(0, t.length - 1), radix: 16);
    return int.tryParse(t);
  }

  Future<void> flash() async {
    final bytes = state.bytes;
    final device = state.selectedDevice;
    if (bytes == null || device == null || state.working) return;
    final l10n = _l10n;
    final offset = parseOffset(state.offsetText);
    if (offset == null || offset < 0) {
      state = state.copyWith(phase: EspFlashPhase.failed, message: l10n.espBadOffset(state.offsetText));
      return;
    }

    state = state.copyWith(phase: EspFlashPhase.connecting, done: 0, total: bytes.length, message: null);
    SerialConnection? connection;
    EspLoader? loader;
    try {
      connection = await _transport.open(device);
      loader = EspLoader(SerialConnectionLink(connection));
      await _enterBootloader(connection, loader);
      if (!ref.mounted) return;
      final chip = await loader.detectChip();

      if (state.baudRate != connection.config.baudRate) {
        final active = connection;
        await loader.changeBaudRate(
          state.baudRate,
          reconfigure: (b) => active.setConfig(active.config.copyWith(baudRate: b)),
        );
      }

      state = state.copyWith(phase: EspFlashPhase.writing);
      await loader.writeFlash(
        offset,
        bytes,
        // La vérification est une phase à part pour l'utilisateur : on la signale quand l'écriture est complète.
        onProgress: (done, total) {
          if (!ref.mounted) return;
          state = state.copyWith(
            done: done,
            total: total,
            phase: done >= total && chip.supportsMd5 ? EspFlashPhase.verifying : EspFlashPhase.writing,
          );
        },
      );

      state = state.copyWith(phase: EspFlashPhase.restarting);
      await connection.hardReset();
      if (!ref.mounted) return;
      final amount = flashSizeLabel(l10n, bytes.length);
      state = state.copyWith(
        phase: EspFlashPhase.done,
        message: chip.supportsMd5 ? l10n.espDone(chip.label, amount) : l10n.espDoneUnverified(chip.label, amount),
      );
    } catch (e) {
      if (!ref.mounted) return;
      final writing = state.phase == EspFlashPhase.writing || state.phase == EspFlashPhase.verifying;
      final cause = errorMessage(l10n, e);
      state = state.copyWith(
        phase: EspFlashPhase.failed,
        message: writing ? l10n.espInterrupted(cause) : cause,
      );
    } finally {
      await loader?.dispose();
      try {
        await connection?.close();
      } catch (_) {
        // déjà fermée (câble arraché)
      }
    }
  }

  /// Reset en bootloader puis synchronisation, jusqu'à [bootAttempts] fois.
  Future<void> _enterBootloader(SerialConnection connection, EspLoader loader) async {
    final policy = ref.read(espSyncPolicyProvider);
    for (var attempt = 1;; attempt++) {
      await connection.enterEspBootloader();
      try {
        await loader.sync(attempts: policy.syncAttempts, timeout: policy.syncTimeout);
        return;
      } on ProtocolTimeoutException catch (e) {
        if (e.code != ProtocolErrorCode.espSyncFailed || attempt >= policy.bootAttempts) rethrow;
      }
    }
  }
}
