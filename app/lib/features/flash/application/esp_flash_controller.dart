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

/// Un fichier à écrire et l'adresse où l'écrire.
@immutable
class EspFilePart {
  const EspFilePart({
    required this.name,
    required this.bytes,
    required this.guess,
    required this.offsetText,
    this.note,
    this.edited = false,
  });

  final String name;
  final Uint8List bytes;

  /// Ce que le contenu du fichier dit de lui (rôle, puce, adresse).
  final EspPartGuess guess;
  final String offsetText;

  /// Explication de l'adresse choisie automatiquement (« Bootloader pour ESP32 : adresse 0x1000. »).
  final String? note;

  /// Vrai quand l'utilisateur a saisi l'adresse : elle n'est plus recalculée.
  final bool edited;

  EspFilePart copyWith({String? offsetText, Object? note = _unset, bool? edited, EspPartGuess? guess}) => EspFilePart(
        name: name,
        bytes: bytes,
        guess: guess ?? this.guess,
        offsetText: offsetText ?? this.offsetText,
        note: identical(note, _unset) ? this.note : note as String?,
        edited: edited ?? this.edited,
      );
}

@immutable
class EspFlashState {
  const EspFlashState({
    this.devices = const [],
    this.selectedDevice,
    this.parts = const [],
    this.draftOffset = '0x10000',
    this.baudRate = 115200,
    this.phase = EspFlashPhase.idle,
    this.done = 0,
    this.total = 0,
    this.currentPart = 0,
    this.message,
  });

  final List<SerialDeviceInfo> devices;
  final SerialDeviceInfo? selectedDevice;

  /// Fichiers à écrire, dans l'ordre où ils ont été ajoutés. Un seul pour le cas courant (firmware).
  final List<EspFilePart> parts;

  /// Adresse saisie avant le choix d'un fichier, reprise pour un fichier non reconnu.
  final String draftOffset;
  final int baudRate;
  final EspFlashPhase phase;

  /// Avancement de l'ensemble des fichiers, en octets.
  final int done;
  final int total;

  /// Fichier en cours d'écriture (indice dans [parts]).
  final int currentPart;
  final String? message;

  // Le premier fichier : l'écran et les tests du cas à un seul fichier s'en servent.
  String? get fileName => parts.firstOrNull?.name;
  Uint8List? get bytes => parts.firstOrNull?.bytes;
  String get offsetText => parts.firstOrNull?.offsetText ?? draftOffset;
  String? get offsetNote => parts.firstOrNull?.note;

  /// Ce que l'en-tête du premier fichier dit de lui ; null si ce n'est pas une image ESP32 reconnue.
  EspImageInfo? get image => parts.isEmpty ? null : analyzeEspImage(parts.first.bytes);

  bool get multiple => parts.length > 1;
  int get totalBytes => parts.fold(0, (sum, p) => sum + p.bytes.length);

  bool get working => switch (phase) {
        EspFlashPhase.connecting ||
        EspFlashPhase.writing ||
        EspFlashPhase.verifying ||
        EspFlashPhase.restarting =>
          true,
        _ => false,
      };

  bool get succeeded => phase == EspFlashPhase.done;

  bool get canFlash => parts.isNotEmpty && selectedDevice != null && !working;

  EspFlashState copyWith({
    List<SerialDeviceInfo>? devices,
    Object? selectedDevice = _unset,
    List<EspFilePart>? parts,
    String? draftOffset,
    int? baudRate,
    EspFlashPhase? phase,
    int? done,
    int? total,
    int? currentPart,
    Object? message = _unset,
  }) {
    return EspFlashState(
      devices: devices ?? this.devices,
      selectedDevice: identical(selectedDevice, _unset) ? this.selectedDevice : selectedDevice as SerialDeviceInfo?,
      parts: parts ?? this.parts,
      draftOffset: draftOffset ?? this.draftOffset,
      baudRate: baudRate ?? this.baudRate,
      phase: phase ?? this.phase,
      done: done ?? this.done,
      total: total ?? this.total,
      currentPart: currentPart ?? this.currentPart,
      message: identical(message, _unset) ? this.message : message as String?,
    );
  }
}

const Object _unset = Object();

final espFlashProvider = NotifierProvider<EspFlashController, EspFlashState>(EspFlashController.new);

/// Flashe un ou plusieurs `.bin` sur un ESP32 / ESP8266 : reset en bootloader par DTR/RTS, synchronisation,
/// écriture compressée de chaque fichier vérifiée par MD5, puis reset matériel.
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

  /// Adresse du fichier [index] saisie à la main ; sans fichier, elle servira au premier fichier choisi.
  void setOffset(String text, {int index = 0}) {
    if (state.parts.isEmpty) {
      state = state.copyWith(draftOffset: text);
      return;
    }
    final parts = [...state.parts];
    parts[index] = parts[index].copyWith(offsetText: text, edited: true, note: null);
    state = state.copyWith(parts: parts);
  }

  void setBaudRate(int baudRate) => state = state.copyWith(baudRate: baudRate);

  /// Choisit le fichier à écrire (il remplace les fichiers déjà choisis).
  Future<void> pickFile() => _pick(add: false);

  /// Ajoute un fichier aux précédents (projet en plusieurs parties).
  Future<void> addFile() => _pick(add: true);

  Future<void> _pick({required bool add}) async {
    final PickedFile? picked;
    try {
      picked = await ref.read(binPickerProvider)();
    } catch (e) {
      state = state.copyWith(phase: EspFlashPhase.failed, message: _l10n.flashReadFailed(errorMessage(_l10n, e)));
      return;
    }
    if (picked == null) return;
    add ? addPickedFile(picked) : useFile(picked);
  }

  /// Retient [picked] comme seul fichier à écrire (choisi à la main ou téléchargé).
  void useFile(PickedFile picked) => _setParts([_newPart(picked)]);

  /// Ajoute [picked] aux fichiers à écrire.
  void addPickedFile(PickedFile picked) => _setParts([...state.parts, _newPart(picked)]);

  void removePart(int index) {
    final parts = [...state.parts]..removeAt(index);
    _setParts(parts);
  }

  EspFilePart _newPart(PickedFile picked) => EspFilePart(
        name: picked.name,
        bytes: picked.bytes,
        guess: guessEspPart(picked.name, picked.bytes),
        offsetText: state.offsetText,
      );

  /// Recalcule l'adresse de chaque fichier que l'utilisateur n'a pas corrigé. La table de partitions,
  /// si elle fait partie des fichiers, donne l'adresse exacte de l'application et des données OTA :
  /// l'adresse d'écriture n'est pas une chose que l'on devrait connaître par cœur.
  void _setParts(List<EspFilePart> parts) {
    final l10n = _l10n;
    final tableFile = parts.where((p) => p.guess.role == EspPartRole.partitionTable).firstOrNull;
    final table = tableFile == null ? const <EspPartition>[] : parsePartitionTable(tableFile.bytes);
    final single = parts.length == 1;
    final planned = [
      for (final p in parts)
        if (p.edited)
          p
        else
          _plan(p, guessEspPart(p.name, p.bytes, table: table), single: single, l10n: l10n),
    ];
    state = state.copyWith(parts: planned, phase: EspFlashPhase.idle, message: null, done: 0, total: 0, currentPart: 0);
  }

  EspFilePart _plan(EspFilePart part, EspPartGuess guess, {required bool single, required AppLocalizations l10n}) {
    final offset = guess.offset;
    if (offset == null) {
      // Contenu inconnu : un fichier seul garde l'adresse en cours (comme avant), sinon il faut la saisir.
      return part.copyWith(
        guess: guess,
        offsetText: single ? part.offsetText : '',
        note: single ? null : l10n.espRoleUnknown,
      );
    }
    final hex = _hex(offset);
    final chip = guess.chip?.label ?? '';
    final note = switch (guess.role) {
      EspPartRole.fullImage => l10n.espImageFull(chip, hex),
      EspPartRole.bootloader => l10n.espRoleBootloader(chip, hex),
      EspPartRole.partitionTable => l10n.espRolePartitions(hex),
      EspPartRole.otaData => l10n.espRoleOtaData(hex),
      EspPartRole.app => guess.fromTable ? l10n.espRoleAppFromTable(chip, hex) : l10n.espImageApp(chip, hex),
      EspPartRole.unknown => null,
    };
    return part.copyWith(guess: guess, offsetText: hex, note: note);
  }

  static String _hex(int value) => '0x${value.toRadixString(16)}';

  void _fail(String message) {
    if (!ref.mounted) return;
    state = state.copyWith(phase: EspFlashPhase.failed, message: message);
  }

  /// Adresse saisie : « 0x10000 », « 10000h » ou décimal.
  static int? parseOffset(String text) {
    final t = text.trim().toLowerCase();
    if (t.isEmpty) return null;
    if (t.startsWith('0x')) return int.tryParse(t.substring(2), radix: 16);
    if (t.endsWith('h')) return int.tryParse(t.substring(0, t.length - 1), radix: 16);
    return int.tryParse(t);
  }

  /// Vérifie les fichiers avant de toucher à la carte ; renvoie le plan d'écriture ou null (message posé).
  List<EspFlashPart>? _checkedPlan() {
    final l10n = _l10n;
    final plan = <EspFlashPart>[];
    for (final part in state.parts) {
      final offset = parseOffset(part.offsetText);
      if (offset == null || offset < 0) {
        _fail(state.multiple ? l10n.espBadOffsetPart(part.name, part.offsetText) : l10n.espBadOffset(part.offsetText));
        return null;
      }
      // Une image complète écrite ailleurs qu'à l'adresse du bootloader donne une carte qui redémarre
      // en boucle.
      final guess = part.guess;
      if (guess.role == EspPartRole.fullImage && guess.chip != null && offset != guess.offset) {
        _fail(l10n.espWrongOffset(guess.chip!.label, _hex(guess.offset!), part.offsetText.trim()));
        return null;
      }
      plan.add(EspFlashPart(name: part.name, offset: offset, data: part.bytes));
    }
    final overlap = findOverlap(plan);
    if (overlap != null) {
      _fail(l10n.espOverlap(overlap.$1.name, overlap.$2.name));
      return null;
    }
    return plan;
  }

  Future<void> flash() async {
    final device = state.selectedDevice;
    if (state.parts.isEmpty || device == null || state.working) return;
    final l10n = _l10n;
    final plan = _checkedPlan();
    if (plan == null) return;
    final total = state.totalBytes;

    state = state.copyWith(phase: EspFlashPhase.connecting, done: 0, total: total, currentPart: 0, message: null);
    SerialConnection? connection;
    EspLoader? loader;
    try {
      connection = await _transport.open(device);
      loader = EspLoader(SerialConnectionLink(connection));
      await _enterBootloader(connection, loader);
      if (!ref.mounted) return;
      final chip = await loader.detectChip();

      // Un fichier fait pour une autre puce ne démarrera pas : on s'arrête avant d'écrire.
      // (Puce non identifiée : on laisse faire, la détection de certaines puces reste à confirmer.)
      for (final part in state.parts) {
        final expected = part.guess.chip;
        if (expected != null && chip != EspChip.unknown && expected != chip) {
          _fail(l10n.espWrongChip(expected.label, chip.label));
          return;
        }
      }

      if (state.baudRate != connection.config.baudRate) {
        final active = connection;
        await loader.changeBaudRate(
          state.baudRate,
          reconfigure: (b) => active.setConfig(active.config.copyWith(baudRate: b)),
        );
      }

      var before = 0;
      for (var i = 0; i < plan.length; i++) {
        final part = plan[i];
        state = state.copyWith(phase: EspFlashPhase.writing, currentPart: i, done: before);
        await loader.writeFlash(
          part.offset,
          part.data,
          // La vérification est une phase à part pour l'utilisateur : on la signale quand le fichier est écrit.
          onProgress: (done, size) {
            if (!ref.mounted) return;
            state = state.copyWith(
              done: before + done,
              phase: done >= size && chip.supportsMd5 ? EspFlashPhase.verifying : EspFlashPhase.writing,
            );
          },
        );
        before += part.data.length;
      }

      state = state.copyWith(phase: EspFlashPhase.restarting);
      await connection.hardReset();
      if (!ref.mounted) return;
      final size = flashSizeLabel(l10n, total);
      final amount = plan.length > 1 ? l10n.espPartsSummary(plan.length, size) : size;
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
