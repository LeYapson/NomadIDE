import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_hal/nomad_hal.dart';

import '../../../app/providers.dart';
import '../domain/log_entry.dart';
import '../domain/rx_line_assembler.dart';
import 'serial_monitor_state.dart';

final serialMonitorProvider =
    NotifierProvider<SerialMonitorController, SerialMonitorState>(SerialMonitorController.new);

/// ViewModel du moniteur série (MVVM).
///
/// Responsabilités :
///  * piloter la HAL (énumération, hotplug, ouverture et fermeture, DTR/RTS) ;
///  * transformer le flux d'octets en lignes horodatées ;
///  * limiter les rafraîchissements de l'UI : à 921600 bauds, un port produit
///    des centaines de chunks par seconde, on les regroupe toutes les 50 ms.
///
/// Il ne dépend que des interfaces de `nomad_hal` : ni Android, ni
/// libserialport, ni widgets. Il est donc testable avec [FakeSerialTransport].
class SerialMonitorController extends Notifier<SerialMonitorState> {
  static const int maxEntries = 5000;
  static const Duration flushInterval = Duration(milliseconds: 50);

  late SerialTransport _transport;
  SerialConnection? _connection;
  StreamSubscription<Uint8List>? _rxSubscription;
  StreamSubscription<DeviceEvent>? _hotplugSubscription;
  final RxLineAssembler _assembler = RxLineAssembler();
  final List<Uint8List> _pendingChunks = [];
  int _pendingBytes = 0;
  Timer? _flushTimer;

  @override
  SerialMonitorState build() {
    _transport = ref.watch(serialTransportProvider);
    ref.onDispose(_disposeResources);

    final transport = _transport;
    if (transport is UnsupportedSerialTransport) {
      return SerialMonitorState(transportName: transport.name, entries: [LogEntry.error(transport.reason)]);
    }

    _hotplugSubscription = transport.deviceEvents.listen(_onDeviceEvent);
    Future.microtask(refreshDevices);
    return SerialMonitorState(transportName: transport.name);
  }

  // ---------------------------------------------------------------------------
  // Périphériques
  // ---------------------------------------------------------------------------

  Future<void> refreshDevices() async {
    try {
      final devices = await _transport.listDevices();
      state = state.copyWith(devices: devices, selectedDevice: _pickSelection(devices));
    } catch (e) {
      _log(LogEntry.error('Énumération des ports impossible : $e'));
    }
  }

  void selectDevice(SerialDeviceInfo device) {
    if (state.status != ConnectionStatus.disconnected) return;
    state = state.copyWith(selectedDevice: device);
  }

  /// Conserve la sélection si elle est toujours là (ou si on y est connecté),
  /// sinon prend le premier périphérique USB.
  SerialDeviceInfo? _pickSelection(List<SerialDeviceInfo> devices) {
    final current = state.selectedDevice;
    if (current != null && (devices.contains(current) || _connection != null)) return current;
    return devices.where((d) => d.isUsb && d.chip.isSerial).firstOrNull ?? devices.firstOrNull;
  }

  void _onDeviceEvent(DeviceEvent event) {
    final label = event.device?.displayName ?? event.deviceId;
    _log(LogEntry.system(event.type == DeviceEventType.attached ? 'Branché : $label' : 'Débranché : $label'));
    // Si c'est la carte connectée, le transport signale déjà la perte via `done`.
    refreshDevices();
  }

  // ---------------------------------------------------------------------------
  // Connexion
  // ---------------------------------------------------------------------------

  Future<void> connect() async {
    final device = state.selectedDevice;
    if (device == null || state.status != ConnectionStatus.disconnected) return;

    state = state.copyWith(status: ConnectionStatus.connecting, errorMessage: null);
    try {
      final connection = await _transport.open(device, config: state.config);
      _connection = connection;
      _assembler.reset();
      _rxSubscription = connection.input.listen(_onRx);
      unawaited(connection.done.then((reason) => _onConnectionDone(connection, reason)));

      state = state.copyWith(
        status: ConnectionStatus.connected,
        dtr: connection.dtr,
        rts: connection.rts,
        rxBytes: 0,
        txBytes: 0,
      );
      _log(LogEntry.system('Connecté à ${device.displayName} (${state.config})'));
    } on SerialException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('Connexion impossible : $e');
    }
  }

  Future<void> disconnect() async {
    // La mise à jour de l'état se fait dans _onConnectionDone.
    await _connection?.close();
  }

  void _onConnectionDone(SerialConnection connection, DisconnectReason reason) {
    // Ignore les connexions remplacées ou fermées pendant la destruction du provider.
    if (!identical(connection, _connection)) return;

    _flushRx();
    _commitPartialRx();
    _rxSubscription?.cancel();
    _rxSubscription = null;
    _connection = null;

    final message = switch (reason) {
      DisconnectReason.closedByUser => 'Déconnecté.',
      DisconnectReason.deviceLost => 'La carte a été débranchée.',
      DisconnectReason.error => 'Connexion interrompue par une erreur.',
    };
    final byUser = reason == DisconnectReason.closedByUser;
    state = state.copyWith(
      status: ConnectionStatus.disconnected,
      dtr: false,
      rts: false,
      errorMessage: byUser ? null : message,
    );
    _log(byUser ? LogEntry.system(message) : LogEntry.error(message));
    if (!byUser) refreshDevices();
  }

  void _fail(String message) {
    state = state.copyWith(status: ConnectionStatus.disconnected, errorMessage: message);
    _log(LogEntry.error(message));
  }

  // ---------------------------------------------------------------------------
  // Paramètres de ligne et lignes de contrôle
  // ---------------------------------------------------------------------------

  /// Applique le débit à chaud si une carte est connectée.
  Future<void> setBaudRate(int baudRate) async {
    final config = state.config.copyWith(baudRate: baudRate);
    final connection = _connection;
    if (connection != null) {
      try {
        await connection.setConfig(config);
        _log(LogEntry.system('Débit : $baudRate bauds'));
      } on SerialException catch (e) {
        _log(LogEntry.error(e.message));
        return;
      }
    }
    state = state.copyWith(config: config);
  }

  Future<void> setDtr(bool value) => _withConnection((c) => c.setDtr(value));

  Future<void> setRts(bool value) => _withConnection((c) => c.setRts(value));

  Future<void> resetBoard() => _withConnection((c) async {
        await c.hardReset();
        _log(LogEntry.system('Reset matériel (impulsion RTS → EN)'));
      });

  Future<void> enterBootloader() => _withConnection((c) async {
        await c.enterEspBootloader();
        _log(LogEntry.system('Séquence bootloader ESP envoyée : la ROM attend esptool'));
      });

  Future<void> _withConnection(Future<void> Function(SerialConnection c) action) async {
    final connection = _connection;
    if (connection == null) return;
    try {
      await action(connection);
    } on SerialException catch (e) {
      _log(LogEntry.error(e.message));
    }
    state = state.copyWith(dtr: connection.dtr, rts: connection.rts);
  }

  // ---------------------------------------------------------------------------
  // Émission
  // ---------------------------------------------------------------------------

  /// Envoie [text] suivi de la fin de ligne choisie.
  Future<void> send(String text) {
    final data = Uint8List.fromList([...utf8.encode(text), ...state.lineEnding.bytes]);
    return sendBytes(data, label: text);
  }

  /// Envoie un caractère de contrôle (0x03 = Ctrl-C, 0x04 = Ctrl-D…).
  Future<void> sendControl(int code) =>
      sendBytes(Uint8List.fromList([code]), label: '^${String.fromCharCode(code + 0x40)}');

  Future<void> sendBytes(Uint8List data, {String? label}) async {
    final connection = _connection;
    if (connection == null || !connection.isOpen) return;

    // La ligne en cours (ex. « >>> ») s'affiche avant la commande envoyée.
    _flushRx();
    _commitPartialRx();
    try {
      await connection.write(data);
      final shown = label != null ? utf8.encode(label) : data;
      state = state.copyWith(
        entries: _appendCapped(state.entries, [LogEntry(kind: LogKind.tx, bytes: shown)]),
        txBytes: state.txBytes + data.length,
      );
    } on SerialException catch (e) {
      _log(LogEntry.error(e.message));
    }
  }

  // ---------------------------------------------------------------------------
  // Réception (regroupée par lots)
  // ---------------------------------------------------------------------------

  void _onRx(Uint8List chunk) {
    _pendingChunks.add(chunk);
    _pendingBytes += chunk.length;
    _flushTimer ??= Timer(flushInterval, _flushRx);
  }

  void _flushRx() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_pendingChunks.isEmpty) return;

    final lines = <LogEntry>[
      for (final chunk in _pendingChunks)
        for (final line in _assembler.add(chunk)) LogEntry(kind: LogKind.rx, bytes: line),
    ];
    final received = _pendingBytes;
    _pendingChunks.clear();
    _pendingBytes = 0;

    state = state.copyWith(
      entries: _appendCapped(state.entries, lines),
      partialLine: _assembler.hasPartial ? _assembler.partial : null,
      rxBytes: state.rxBytes + received,
    );
  }

  void _commitPartialRx() {
    final partial = _assembler.takePartial();
    if (partial == null) return;
    state = state.copyWith(
      entries: _appendCapped(state.entries, [LogEntry(kind: LogKind.rx, bytes: partial)]),
      partialLine: null,
    );
  }

  // ---------------------------------------------------------------------------
  // Affichage
  // ---------------------------------------------------------------------------

  void setLineEnding(LineEnding value) => state = state.copyWith(lineEnding: value);

  void toggleHexView() => state = state.copyWith(hexView: !state.hexView);

  void toggleTimestamps() => state = state.copyWith(showTimestamps: !state.showTimestamps);

  void clearLog() {
    _assembler.reset();
    state = state.copyWith(entries: const [], partialLine: null);
  }

  void _log(LogEntry entry) => state = state.copyWith(entries: _appendCapped(state.entries, [entry]));

  static List<LogEntry> _appendCapped(List<LogEntry> current, List<LogEntry> added) {
    if (added.isEmpty) return current;
    final overflow = current.length + added.length - maxEntries;
    return List.unmodifiable([...current, ...added].skip(overflow > 0 ? overflow : 0));
  }

  void _disposeResources() {
    _flushTimer?.cancel();
    _hotplugSubscription?.cancel();
    _rxSubscription?.cancel();
    final connection = _connection;
    _connection = null; // neutralise _onConnectionDone
    connection?.close();
  }
}
