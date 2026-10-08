import 'dart:async';
import 'dart:typed_data';

import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_protocols/testing.dart';

/// Transport série de test dont l'unique « carte » est une [FakeRawReplBoard] :
/// la connexion passe par les mêmes chemins que sur matériel (ouverture, raw REPL,
/// fermeture, débranchement) sans aucun port réel.
class BoardTransport implements SerialTransport {
  BoardTransport(this.board);

  final FakeRawReplBoard board;

  @override
  TransportKind get kind => TransportKind.simulated;

  static const device = SerialDeviceInfo(
    id: 'fake:board',
    displayName: 'Carte de test',
    systemPath: 'fake://board',
    vendorId: 0x2E8A,
    productId: 0x0005,
    isUsb: true,
  );

  final StreamController<DeviceEvent> _events = StreamController<DeviceEvent>.broadcast();
  _BoardConnection? _connection;

  @override
  String get name => 'Carte de test';

  @override
  bool get isSupported => true;

  @override
  Future<List<SerialDeviceInfo>> listDevices() async => const [device];

  @override
  Stream<DeviceEvent> get deviceEvents => _events.stream;

  @override
  Future<SerialConnection> open(
    SerialDeviceInfo device, {
    SerialConfig config = const SerialConfig(),
    bool dtr = true,
    bool rts = true,
  }) async {
    return _connection = _BoardConnection(board, device, config);
  }

  @override
  Future<void> dispose() async {
    await _connection?.close();
    await _events.close();
  }
}

class _BoardConnection implements SerialConnection {
  _BoardConnection(this._board, this.device, this.config) {
    // Câble arraché : le flux de la carte se ferme, la connexion le signale.
    _board.input.listen(null, onDone: () => _finish(DisconnectReason.deviceLost));
  }

  final FakeRawReplBoard _board;
  final Completer<DisconnectReason> _done = Completer<DisconnectReason>();
  bool _closed = false;

  @override
  final SerialDeviceInfo device;

  @override
  SerialConfig config;

  @override
  bool get isOpen => !_closed;

  @override
  bool get dtr => true;

  @override
  bool get rts => true;

  @override
  Stream<Uint8List> get input => _board.input;

  @override
  Future<DisconnectReason> get done => _done.future;

  @override
  Future<void> write(Uint8List data) async {
    if (_closed) throw const SerialClosedException('La connexion est fermée.');
    await _board.write(data);
  }

  @override
  Future<void> setConfig(SerialConfig config) async => this.config = config;

  @override
  Future<void> setDtr(bool value) async {}

  @override
  Future<void> setRts(bool value) async {}

  @override
  Future<void> close() async => _finish(DisconnectReason.closedByUser);

  void _finish(DisconnectReason reason) {
    if (_closed) return;
    _closed = true;
    if (!_done.isCompleted) _done.complete(reason);
  }
}
