import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../domain/serial_config.dart';
import '../domain/serial_device_info.dart';
import '../domain/serial_exceptions.dart';
import '../domain/serial_transport.dart';
import 'base_serial_connection.dart';

/// Transport simulé : une fausse carte MicroPython avec un mini REPL.
///
/// Sert à :
///  * développer l'UI sans matériel (`--dart-define=NOMAD_FAKE_SERIAL=true`) ;
///  * les tests unitaires et widgets ;
///  * les démos sur iOS, où l'USB-série est impossible.
class FakeSerialTransport implements SerialTransport {
  FakeSerialTransport({List<SerialDeviceInfo> devices = const [FakeSerialTransport.defaultDevice]})
      : _devices = [...devices];

  static const defaultDevice = SerialDeviceInfo(
    id: 'fake:0',
    displayName: 'Carte simulée (MicroPython)',
    systemPath: 'loop://',
    vendorId: 0xF055,
    productId: 0x9800,
    manufacturer: 'NomadMCU',
    product: 'Fake REPL',
  );

  final List<SerialDeviceInfo> _devices;
  final Map<String, FakeReplConnection> _open = {};
  final StreamController<DeviceEvent> _events = StreamController<DeviceEvent>.broadcast();

  @override
  TransportKind get kind => TransportKind.simulated;

  @override
  String get name => 'Simulateur';

  @override
  bool get isSupported => true;

  @override
  Future<List<SerialDeviceInfo>> listDevices() async => List.unmodifiable(_devices);

  @override
  Stream<DeviceEvent> get deviceEvents => _events.stream;

  @override
  Future<SerialConnection> open(
    SerialDeviceInfo device, {
    SerialConfig config = const SerialConfig(),
    bool dtr = true,
    bool rts = true,
  }) async {
    if (!_devices.contains(device)) {
      throw SerialDeviceNotFoundException(
        '${device.displayName} introuvable.',
        code: SerialErrorCode.deviceNotFound,
        params: {'device': device.displayName},
      );
    }
    if (_open.containsKey(device.id)) {
      throw SerialOpenException(
        '${device.displayName} est déjà ouvert.',
        code: SerialErrorCode.alreadyOpen,
        params: {'device': device.displayName},
      );
    }
    final connection = FakeReplConnection._(
      device: device,
      config: config,
      onClosed: () => _open.remove(device.id),
    );
    await connection.setDtr(dtr);
    await connection.setRts(rts);
    _open[device.id] = connection;
    connection._boot();
    return connection;
  }

  /// Simule le branchement d'une carte.
  void simulateAttach(SerialDeviceInfo device) {
    _devices.add(device);
    _events.add(DeviceEvent(DeviceEventType.attached, device.id, device));
  }

  /// Simule l'arrachage du câble.
  void simulateDetach(String deviceId) {
    final index = _devices.indexWhere((d) => d.id == deviceId);
    if (index < 0) return;
    final device = _devices.removeAt(index);
    _open[deviceId]?._unplug();
    _events.add(DeviceEvent(DeviceEventType.detached, deviceId, device));
  }

  @override
  Future<void> dispose() async {
    for (final connection in [..._open.values]) {
      await connection.close();
    }
    await _events.close();
  }
}

/// Mini REPL façon MicroPython : écho, `print("…")`, arithmétique entière,
/// Ctrl-C (nouvelle invite) et Ctrl-D (soft reboot).
class FakeReplConnection extends BaseSerialConnection {
  FakeReplConnection._({
    required super.device,
    required super.config,
    required void Function() onClosed,
  }) : _onClosed = onClosed;

  static const _banner =
      'MicroPython v1.24.1 on 2026-09-29; NomadMCU simulated board\r\nType "help()" for more information.\r\n';
  static const _prompt = '>>> ';
  static final _printCall = RegExp(r'''^print\((['"])(.*)\1\)$''');
  static final _arithmetic = RegExp(r'^(-?\d+)\s*([-+*/%])\s*(-?\d+)$');

  final void Function() _onClosed;
  final List<int> _line = [];
  int _previous = 0;

  void _boot() => _emit(utf8.encode('$_banner$_prompt'));

  void _unplug() => reportLost(DisconnectReason.deviceLost);

  /// Livraison asynchrone, comme un vrai périphérique (les timers de même
  /// durée se déclenchent dans l'ordre : l'ordre des octets est préservé).
  void _emit(List<int> bytes) {
    final data = Uint8List.fromList(bytes);
    Timer(const Duration(milliseconds: 5), () => emitData(data));
  }

  @override
  Future<void> writeNative(Uint8List data) async {
    final out = <int>[];
    for (final byte in data) {
      switch (byte) {
        case 0x0A when _previous == 0x0D: // CR+LF : un seul retour à la ligne
          break;
        case 0x0D || 0x0A:
          out.addAll(utf8.encode('\r\n'));
          final result = _evaluate(utf8.decode(_line, allowMalformed: true).trim());
          if (result.isNotEmpty) out.addAll(utf8.encode('$result\r\n'));
          out.addAll(utf8.encode(_prompt));
          _line.clear();
        case 0x03: // Ctrl-C
          _line.clear();
          out.addAll(utf8.encode('\r\n$_prompt'));
        case 0x04: // Ctrl-D
          _line.clear();
          out.addAll(utf8.encode('\r\nMPY: soft reboot\r\n$_banner$_prompt'));
        case 0x08 || 0x7F: // Backspace
          if (_line.isNotEmpty) {
            _line.removeLast();
            out.addAll(const [0x08, 0x20, 0x08]);
          }
        default:
          _line.add(byte);
          out.add(byte); // écho, comme le vrai REPL
      }
      _previous = byte;
    }
    if (out.isNotEmpty) _emit(out);
  }

  String _evaluate(String source) {
    if (source.isEmpty) return '';
    if (source == 'help()') return 'Carte simulée NomadMCU : essayez print("hello") ou 6*7.';

    final printed = _printCall.firstMatch(source);
    if (printed != null) return printed.group(2)!;

    final math = _arithmetic.firstMatch(source);
    if (math != null) {
      final a = int.parse(math.group(1)!);
      final b = int.parse(math.group(3)!);
      return switch (math.group(2)) {
        '+' => '${a + b}',
        '-' => '${a - b}',
        '*' => '${a * b}',
        '/' || '%' when b == 0 => 'ZeroDivisionError: divide by zero',
        '/' => '${a / b}',
        '%' => '${a % b}',
        _ => '',
      };
    }

    if (source.contains('=')) return ''; // affectation : silencieuse, comme en Python
    final name = source.split(RegExp(r'[^A-Za-z0-9_]')).first;
    return 'Traceback (most recent call last):\r\n'
        '  File "<stdin>", line 1, in <module>\r\n'
        "NameError: name '$name' isn't defined";
  }

  @override
  Future<void> applyConfigNative(SerialConfig config) async {}

  @override
  Future<void> setDtrNative(bool value) async {}

  @override
  Future<void> setRtsNative(bool value) async {}

  @override
  Future<void> closeNative() async => _onClosed();
}
