import 'dart:async';
import 'dart:typed_data';

import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_protocols/testing.dart';

/// Transport série de test dont l'unique « carte » est une [FakeEspRom] : l'écran de flash ESP passe
/// par les mêmes chemins que sur matériel (ouverture, reset DTR/RTS, protocole, fermeture).
class EspRomTransport implements SerialTransport {
  EspRomTransport(this.rom);

  final FakeEspRom rom;

  static const device = SerialDeviceInfo(
    id: 'fake:esp',
    displayName: 'Carte ESP de test',
    systemPath: 'fake://esp',
    vendorId: 0x10C4,
    productId: 0xEA60,
    isUsb: true,
  );

  /// Connexions ouvertes, dans l'ordre.
  final List<EspRomConnection> opened = [];

  @override
  TransportKind get kind => TransportKind.simulated;

  @override
  String get name => 'Carte ESP de test';

  @override
  bool get isSupported => true;

  @override
  Future<List<SerialDeviceInfo>> listDevices() async => const [device];

  @override
  Stream<DeviceEvent> get deviceEvents => const Stream.empty();

  @override
  Future<SerialConnection> open(
    SerialDeviceInfo device, {
    SerialConfig config = const SerialConfig(),
    bool dtr = true,
    bool rts = true,
  }) async {
    final connection = EspRomConnection(rom, device, config);
    opened.add(connection);
    return connection;
  }

  @override
  Future<void> dispose() async {}
}

class EspRomConnection implements SerialConnection {
  EspRomConnection(this._rom, this.device, this.config);

  final FakeEspRom _rom;
  final Completer<DisconnectReason> _done = Completer<DisconnectReason>();
  bool _closed = false;

  /// Historique des lignes de contrôle : « dtr=1 », « rts=0 »…
  final List<String> lineChanges = [];

  @override
  final SerialDeviceInfo device;

  @override
  SerialConfig config;

  @override
  bool get isOpen => !_closed;

  @override
  bool dtr = true;

  @override
  bool rts = true;

  @override
  Stream<Uint8List> get input => _rom.input;

  @override
  Future<DisconnectReason> get done => _done.future;

  @override
  Future<void> write(Uint8List data) async {
    if (_closed) throw const SerialClosedException('La connexion est fermée.');
    await _rom.write(data);
  }

  @override
  Future<void> setConfig(SerialConfig config) async => this.config = config;

  @override
  Future<void> setDtr(bool value) async {
    dtr = value;
    lineChanges.add('dtr=${value ? 1 : 0}');
  }

  @override
  Future<void> setRts(bool value) async {
    rts = value;
    lineChanges.add('rts=${value ? 1 : 0}');
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (!_done.isCompleted) _done.complete(DisconnectReason.closedByUser);
  }
}
