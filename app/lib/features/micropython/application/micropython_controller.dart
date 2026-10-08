import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_protocols/nomad_protocols.dart';

import '../../../app/providers.dart';
import '../data/serial_connection_link.dart';

enum ReplLogKind { info, input, out, err }

@immutable
class ReplLogEntry {
  const ReplLogEntry(this.kind, this.text);

  final ReplLogKind kind;
  final String text;
}

enum ReplStatus { disconnected, connecting, ready }

const Object _unset = Object();

@immutable
class MicroPythonState {
  const MicroPythonState({
    this.devices = const [],
    this.selectedDevice,
    this.status = ReplStatus.disconnected,
    this.busy = false,
    this.log = const [],
    this.cwd = '/',
    this.files = const [],
    this.errorMessage,
  });

  final List<SerialDeviceInfo> devices;
  final SerialDeviceInfo? selectedDevice;
  final ReplStatus status;

  /// Une commande est en cours : l'UI désactive les actions.
  final bool busy;
  final List<ReplLogEntry> log;
  final String cwd;
  final List<RemoteEntry> files;
  final String? errorMessage;

  bool get isReady => status == ReplStatus.ready;

  MicroPythonState copyWith({
    List<SerialDeviceInfo>? devices,
    Object? selectedDevice = _unset,
    ReplStatus? status,
    bool? busy,
    List<ReplLogEntry>? log,
    String? cwd,
    List<RemoteEntry>? files,
    Object? errorMessage = _unset,
  }) {
    return MicroPythonState(
      devices: devices ?? this.devices,
      selectedDevice: identical(selectedDevice, _unset) ? this.selectedDevice : selectedDevice as SerialDeviceInfo?,
      status: status ?? this.status,
      busy: busy ?? this.busy,
      log: log ?? this.log,
      cwd: cwd ?? this.cwd,
      files: files ?? this.files,
      errorMessage: identical(errorMessage, _unset) ? this.errorMessage : errorMessage as String?,
    );
  }
}

final microPythonProvider = NotifierProvider<MicroPythonController, MicroPythonState>(MicroPythonController.new);

/// Pilote une carte MicroPython : connexion, raw REPL, exécution de code et fichiers.
///
/// Page de validation du protocole : la connexion est indépendante de celle du
/// moniteur série (un seul des deux peut tenir le port à la fois).
class MicroPythonController extends Notifier<MicroPythonState> {
  static const maxLogEntries = 2000;
  static const runTimeout = Duration(seconds: 30);

  late SerialTransport _transport;
  SerialConnection? _connection;
  RawRepl? _repl;
  MicroPythonFs? _fs;
  StreamSubscription<DeviceEvent>? _hotplug;

  @override
  MicroPythonState build() {
    _transport = ref.watch(serialTransportProvider);
    ref.onDispose(_dispose);
    if (_transport.isSupported) {
      _hotplug = _transport.deviceEvents.listen((_) => refreshDevices());
      Future.microtask(refreshDevices);
    }
    return const MicroPythonState();
  }

  Future<void> refreshDevices() async {
    try {
      final devices = await _transport.listDevices();
      final current = state.selectedDevice;
      final keep = current != null && (devices.contains(current) || _connection != null);
      state = state.copyWith(
        devices: devices,
        selectedDevice: keep ? current : (devices.where((d) => d.isUsb).firstOrNull ?? devices.firstOrNull),
      );
    } catch (e) {
      _fail('Énumération des ports impossible : $e');
    }
  }

  void selectDevice(SerialDeviceInfo device) {
    if (state.status == ReplStatus.disconnected) state = state.copyWith(selectedDevice: device);
  }

  Future<void> connect() async {
    final device = state.selectedDevice;
    if (device == null || state.status != ReplStatus.disconnected) return;
    state = state.copyWith(status: ReplStatus.connecting, errorMessage: null);
    try {
      final connection = await _transport.open(device);
      _connection = connection;
      unawaited(connection.done.then((reason) => _onDone(connection, reason)));
      _info('Port ouvert : ${device.displayName}');

      final repl = RawRepl(SerialConnectionLink(connection));
      _repl = repl;
      _fs = MicroPythonFs(repl);
      await repl.enter();
      state = state.copyWith(status: ReplStatus.ready);
      _info('Raw REPL actif.');
      await refreshFiles();
    } on ProtocolException catch (e) {
      await _teardown();
      _fail(e.message);
    } on SerialException catch (e) {
      await _teardown();
      _fail(e.message);
    } catch (e) {
      await _teardown();
      _fail('Connexion impossible : $e');
    }
  }

  Future<void> disconnect() async {
    final repl = _repl;
    if (repl != null && state.isReady && !state.busy) {
      try {
        await repl.exit();
      } on ProtocolException {
        // La carte ne répond plus : on ferme quand même.
      }
    }
    await _teardown();
    _info('Déconnecté.');
  }

  void _onDone(SerialConnection connection, DisconnectReason reason) {
    if (!identical(connection, _connection)) return;
    _connection = null;
    _repl?.dispose();
    _repl = null;
    _fs = null;
    state = state.copyWith(status: ReplStatus.disconnected, busy: false, files: const []);
    if (reason != DisconnectReason.closedByUser) _fail('La carte a été débranchée.');
    refreshDevices();
  }

  Future<void> _teardown() async {
    final connection = _connection;
    _connection = null;
    await _repl?.dispose();
    _repl = null;
    _fs = null;
    state = state.copyWith(status: ReplStatus.disconnected, busy: false, files: const []);
    await connection?.close();
  }

  // ---------------------------------------------------------------------------
  // Exécution
  // ---------------------------------------------------------------------------

  /// Exécute [code] sans l'écrire sur la carte (script temporaire envoyé par le
  /// raw REPL). Pas de délai : l'utilisateur arrête avec [stop].
  Future<void> run(String code, {String? label}) async {
    final repl = _repl;
    if (repl == null || code.trim().isEmpty) return;
    await _guard(() async {
      _append(ReplLogKind.input, label ?? code.trimRight());
      final result = await repl.execute(
        code,
        timeout: null,
        onStdout: (d) => _append(ReplLogKind.out, utf8.decode(d, allowMalformed: true)),
        onStderr: (d) => _append(ReplLogKind.err, utf8.decode(d, allowMalformed: true)),
      );
      _info(result.ok ? 'Terminé.' : 'Terminé avec erreur.');
    });
  }

  /// Exécute un fichier de la carte (lu puis envoyé comme script temporaire).
  Future<void> runFile(String name) async {
    final bytes = await readBytes(name);
    if (bytes == null) return;
    await run(utf8.decode(bytes, allowMalformed: true), label: 'run ${_join(name)}');
  }

  /// Ctrl-C sur le programme en cours.
  Future<void> stop() async {
    try {
      await _repl?.interrupt();
    } on ProtocolException catch (e) {
      _fail(e.message);
    }
  }

  void clearLog() => state = state.copyWith(log: const []);

  // ---------------------------------------------------------------------------
  // Test de transfert (validation du lien, notamment USB OTG Android)
  // ---------------------------------------------------------------------------

  static const _selfTestPath = '/_nomad_selftest.bin';
  static const selfTestBytes = 8 * 1024;
  static const selfTestChunkSizes = [128, 256, 384, 512];

  /// Écrit puis relit [selfTestBytes] octets pseudo-aléatoires pour chaque taille
  /// de morceau, avec vérification CRC32 côté carte, et consigne débit et erreurs.
  Future<void> runTransferSelfTest() async {
    final repl = _repl;
    if (repl == null) return;
    await _guard(() async {
      var seed = 0x2545F491;
      final data = Uint8List.fromList(List.generate(selfTestBytes, (_) {
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
        return (seed >> 16) & 0xFF;
      }));
      _info('Test de transfert : ${selfTestBytes ~/ 1024} Ko, CRC32 vérifié par la carte.');

      for (final chunk in selfTestChunkSizes) {
        final fs = MicroPythonFs(repl, chunkSize: chunk);
        final clock = Stopwatch()..start();
        try {
          await fs.write(_selfTestPath, data, verify: true, retries: 0);
          final writeMs = clock.elapsedMilliseconds;
          clock.reset();
          final back = await fs.read(_selfTestPath);
          final readMs = clock.elapsedMilliseconds;
          final same = back.length == data.length && _equal(back, data);
          _info(
            '· morceaux de $chunk o : écriture ${_rate(data.length, writeMs)}, '
            'lecture ${_rate(data.length, readMs)}, '
            '${same ? 'relecture identique ✓' : 'RELECTURE DIFFÉRENTE ✗'}',
          );
        } on ProtocolException catch (e) {
          _info('· morceaux de $chunk o : ÉCHEC ✗ ${e.message}');
          // Une désynchronisation rend la suite impossible : _guard resynchronise.
          if (repl.state != RawReplState.ready) break;
        }
      }
      try {
        await MicroPythonFs(repl).remove(_selfTestPath);
      } on ProtocolException {
        // Fichier absent si tous les essais ont échoué.
      }
      _info('Test de transfert terminé.');
      await _loadFiles();
    });
  }

  static bool _equal(Uint8List a, Uint8List b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _rate(int bytes, int ms) =>
      '${(bytes / 1024 / (ms == 0 ? 1 : ms / 1000)).toStringAsFixed(1)} Ko/s (${(ms / 1000).toStringAsFixed(1)} s)';

  // ---------------------------------------------------------------------------
  // Fichiers
  // ---------------------------------------------------------------------------

  String _join(String name) => state.cwd == '/' ? '/$name' : '${state.cwd}/$name';

  Future<void> refreshFiles() => _guard(_loadFiles);

  Future<void> _loadFiles() async {
    final entries = await _fs!.list(state.cwd);
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    state = state.copyWith(files: entries);
  }

  Future<void> openDirectory(String name) => _guard(() async {
        state = state.copyWith(cwd: _join(name));
        await _loadFiles();
      });

  Future<void> goUp() => _guard(() async {
        final parts = state.cwd.split('/').where((p) => p.isNotEmpty).toList();
        if (parts.isEmpty) return;
        parts.removeLast();
        state = state.copyWith(cwd: '/${parts.join('/')}');
        await _loadFiles();
      });

  /// Octets d'un fichier ; null en cas d'échec (erreur signalée).
  Future<Uint8List?> readBytes(String name) async {
    Uint8List? bytes;
    await _guard(() async {
      bytes = await _fs!.read(_join(name));
      _info('Lu ${_join(name)} (${bytes!.length} octets)');
    });
    return bytes;
  }

  Future<void> writeText(String name, String content) => _guard(() async {
        final path = _join(name);
        final data = Uint8List.fromList(utf8.encode(content));
        await _fs!.write(path, data, verify: true);
        _info('Écrit $path (${data.length} octets, CRC32 vérifié)');
        await _loadFiles();
      });

  Future<void> delete(RemoteEntry entry) => _guard(() async {
        final path = _join(entry.name);
        entry.isDirectory ? await _fs!.rmdir(path) : await _fs!.remove(path);
        _info('Supprimé $path');
        await _loadFiles();
      });

  Future<void> makeDirectory(String name) => _guard(() async {
        await _fs!.mkdir(_join(name));
        _info('Dossier créé ${_join(name)}');
        await _loadFiles();
      });

  // ---------------------------------------------------------------------------
  // Utilitaires
  // ---------------------------------------------------------------------------

  /// Sérialise les actions : le raw REPL ne gère qu'une commande à la fois.
  Future<void> _guard(Future<void> Function() action) async {
    if (_repl == null || state.busy) return;
    state = state.copyWith(busy: true);
    try {
      await action();
    } on ProtocolRemoteException catch (e) {
      _append(ReplLogKind.err, '${e.stderr}\n');
      _fail(e.message);
    } on ProtocolTimeoutException catch (e) {
      _fail(e.message);
    } on ProtocolException catch (e) {
      _fail(e.message);
    } finally {
      if (_repl != null) state = state.copyWith(busy: false);
      // Une désynchronisation (timeout, réponse inattendue) rend la session inutilisable.
      if (_repl != null && _repl!.state == RawReplState.broken) await _resync();
    }
  }

  Future<void> _resync() async {
    _info('Session désynchronisée, nouvelle tentative…');
    try {
      await _repl!.enter();
      _info('Session rétablie.');
    } on ProtocolException catch (e) {
      _fail('Resynchronisation impossible : ${e.message}');
    }
  }

  void _info(String text) => _append(ReplLogKind.info, text, merge: false);

  void _fail(String message) {
    _append(ReplLogKind.info, message, merge: false);
    state = state.copyWith(errorMessage: message);
  }

  void _append(ReplLogKind kind, String text, {bool merge = true}) {
    if (text.isEmpty) return;
    final log = [...state.log];
    final last = log.isEmpty ? null : log.last;
    if (merge && last != null && last.kind == kind && (kind == ReplLogKind.out || kind == ReplLogKind.err)) {
      log[log.length - 1] = ReplLogEntry(kind, last.text + text);
    } else {
      log.add(ReplLogEntry(kind, text));
    }
    final overflow = log.length - maxLogEntries;
    state = state.copyWith(log: overflow > 0 ? log.sublist(overflow) : log);
  }

  void _dispose() {
    _hotplug?.cancel();
    final connection = _connection;
    _connection = null;
    _repl?.dispose();
    connection?.close();
  }
}
