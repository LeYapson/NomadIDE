import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import '../domain/serial_config.dart';
import '../domain/serial_device_info.dart';
import '../domain/serial_exceptions.dart';
import '../domain/serial_transport.dart';
import 'base_serial_connection.dart';

/// Transport desktop (Windows / macOS / Linux) basé sur libserialport (FFI).
///
/// libserialport ne fournit pas d'événements de hotplug : on sonde la liste
/// des ports à intervalle régulier, uniquement tant que quelqu'un écoute
/// [deviceEvents].
class DesktopSerialTransport implements SerialTransport {
  DesktopSerialTransport({this.pollInterval = const Duration(milliseconds: 1500)});

  final Duration pollInterval;
  final Map<String, DesktopSerialConnection> _open = {};
  late final StreamController<DeviceEvent> _events = StreamController<DeviceEvent>.broadcast(
    onListen: _startPolling,
    onCancel: _stopPolling,
  );
  Timer? _pollTimer;
  Map<String, SerialDeviceInfo> _known = const {};

  @override
  TransportKind get kind => TransportKind.desktop;

  @override
  String get name => 'Port série (libserialport)';

  @override
  bool get isSupported => true;

  @override
  Future<List<SerialDeviceInfo>> listDevices() async => _scan();

  @override
  Stream<DeviceEvent> get deviceEvents => _events.stream;

  @override
  Future<SerialConnection> open(
    SerialDeviceInfo device, {
    SerialConfig config = const SerialConfig(),
    bool dtr = true,
    bool rts = true,
  }) async {
    final path = device.systemPath ?? device.id;
    final port = _portHandle(path);
    if (port == null) {
      throw SerialDeviceNotFoundException(
        'Port $path introuvable.',
        code: SerialErrorCode.portNotFound,
        params: {'path': path},
      );
    }

    var opened = false;
    try {
      opened = port.openReadWrite();
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      final error = SerialPort.lastError;
      port.dispose();
      final message = "Impossible d'ouvrir $path : ${error?.message ?? 'erreur inconnue'}.";
      final isPermission = Platform.isLinux && error?.errorCode == 13; // EACCES
      throw isPermission
          ? SerialPermissionException(
              '$message Ajoutez votre utilisateur au groupe « dialout » (Debian/Ubuntu) '
              'ou « uucp » (Arch), puis rouvrez votre session.',
              cause: error,
              code: SerialErrorCode.portPermissionDenied,
              params: {'path': path, 'os': error?.message},
            )
          : SerialOpenException(
              '$message Le port est peut-être utilisé par une autre application (Arduino IDE, Thonny…).',
              cause: error,
              code: SerialErrorCode.openFailed,
              params: {'path': path, 'os': error?.message},
            );
    }

    final connection = DesktopSerialConnection._(
      device: device,
      config: config,
      port: port,
      onClosed: () => _open.remove(device.id),
    );
    try {
      await connection._init(dtr: dtr, rts: rts);
    } catch (_) {
      await connection.close();
      rethrow;
    }
    _open[device.id] = connection;
    return connection;
  }

  @override
  Future<void> dispose() async {
    _stopPolling();
    for (final connection in [..._open.values]) {
      await connection.close();
    }
    await _events.close();
  }

  // ---------------------------------------------------------------------------
  // Énumération
  // ---------------------------------------------------------------------------

  List<SerialDeviceInfo> _scan() {
    final devices = <SerialDeviceInfo>[];
    for (final name in _filterNames(SerialPort.availablePorts)) {
      final info = _describe(name);
      if (info != null) devices.add(info);
    }
    // Les ports USB (les cartes) d'abord, puis tri alphabétique.
    devices.sort((a, b) {
      if (a.isUsb != b.isUsb) return a.isUsb ? -1 : 1;
      return a.id.compareTo(b.id);
    });
    return devices;
  }

  /// Sous macOS, chaque port existe en `/dev/tty.*` (bloque en attendant DCD
  /// à l'ouverture) et en `/dev/cu.*` (appel sortant). Seul le second nous intéresse.
  static Iterable<String> _filterNames(List<String> names) {
    if (!Platform.isMacOS) return names;
    final all = names.toSet();
    return names.where(
      (n) => !(n.startsWith('/dev/tty.') && all.contains(n.replaceFirst('/dev/tty.', '/dev/cu.'))),
    );
  }

  static SerialDeviceInfo? _describe(String name) {
    final port = _portHandle(name);
    if (port == null) return null;
    try {
      final isUsb = _tryGet(() => port.transport) == SerialPortTransport.usb;
      final product = isUsb ? _tryGet(() => port.productName) : null;
      final description = _tryGet(() => port.description);
      return SerialDeviceInfo(
        id: name,
        systemPath: name,
        displayName: _firstNonEmpty([product, description]) ?? name,
        vendorId: isUsb ? _tryGet(() => port.vendorId) : null,
        productId: isUsb ? _tryGet(() => port.productId) : null,
        manufacturer: isUsb ? _tryGet(() => port.manufacturer) : null,
        product: product,
        serialNumber: isUsb ? _tryGet(() => port.serialNumber) : null,
        isUsb: isUsb,
      );
    } finally {
      port.dispose();
    }
  }

  static SerialPort? _portHandle(String name) {
    try {
      return SerialPort(name);
    } catch (_) {
      return null;
    }
  }

  /// Les métadonnées USB lèvent une erreur sur les ports natifs / Bluetooth.
  static T? _tryGet<T>(T? Function() read) {
    try {
      return read();
    } catch (_) {
      return null;
    }
  }

  static String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Hotplug par sondage
  // ---------------------------------------------------------------------------

  void _startPolling() {
    _known = {for (final d in _scan()) d.id: d};
    _pollTimer = Timer.periodic(pollInterval, (_) => _poll());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // Énumération synchrone sur l'isolate UI : quelques ms en pratique.
  // À déplacer dans un isolate si ça se voit dans les profils sous Windows.
  void _poll() {
    final current = {for (final d in _scan()) d.id: d};
    for (final entry in current.entries) {
      if (!_known.containsKey(entry.key)) {
        _events.add(DeviceEvent(DeviceEventType.attached, entry.key, entry.value));
      }
    }
    for (final entry in _known.entries) {
      if (!current.containsKey(entry.key)) {
        _open[entry.key]?._onDetached();
        _events.add(DeviceEvent(DeviceEventType.detached, entry.key, entry.value));
      }
    }
    _known = current;
  }
}

class DesktopSerialConnection extends BaseSerialConnection {
  DesktopSerialConnection._({
    required super.device,
    required super.config,
    required SerialPort port,
    required void Function() onClosed,
  })  : _port = port,
        _onClosed = onClosed;

  /// Délai maximal pour vider une écriture quand le tampon de l'OS est plein.
  static const Duration writeTimeout = Duration(seconds: 5);

  final SerialPort _port;
  final void Function() _onClosed;
  Timer? _readTimer;

  /// Intervalle de lecture et taille maximale par lecture.
  static const Duration readInterval = Duration(milliseconds: 4);
  static const int maxReadChunk = 4096;

  Future<void> _init({required bool dtr, required bool rts}) async {
    await applyConfigNative(config);
    // DTR avant RTS : voir AndroidUsbSerialConnection._init.
    await setDtr(dtr);
    await setRts(rts);

    // Lecture non bloquante sur l'isolate principal. Le SerialPortReader de
    // libserialport lit en boucle dans un autre isolate que `Isolate.kill` ne
    // peut pas interrompre : fermer ou débrancher le port pendant qu'il tourne
    // libère un `sp_port` encore utilisé.
    _readTimer = Timer.periodic(readInterval, (_) => _pollRead());
  }

  void _pollRead() {
    try {
      final available = _port.bytesAvailable;
      if (available < 0) {
        reportLost(DisconnectReason.deviceLost, SerialPort.lastError);
        return;
      }
      if (available == 0) return;
      emitData(_port.read(available < maxReadChunk ? available : maxReadChunk));
    } catch (e) {
      reportLost(DisconnectReason.deviceLost, e);
    }
  }

  void _onDetached() => reportLost(DisconnectReason.deviceLost);

  @override
  Future<void> applyConfigNative(SerialConfig config) async {
    // Le port devient propriétaire de la config affectée (il la libère à la
    // prochaine affectation et à sa propre fermeture) : ne jamais la disposer ici.
    final native = SerialPortConfig();
    native
        ..baudRate = config.baudRate
        ..bits = config.dataBits
        ..stopBits = switch (config.stopBits) {
          StopBits.one => 1,
          StopBits.two => 2,
          StopBits.onePointFive =>
            throw const SerialUnsupportedException(
              '1,5 bit de stop non pris en charge par libserialport.',
              code: SerialErrorCode.unsupportedStopBits,
            ),
        }
        ..parity = switch (config.parity) {
          Parity.none => SerialPortParity.none,
          Parity.odd => SerialPortParity.odd,
          Parity.even => SerialPortParity.even,
          Parity.mark => SerialPortParity.mark,
          Parity.space => SerialPortParity.space,
        }
        ..setFlowControl(switch (config.flowControl) {
          FlowControl.none => SerialPortFlowControl.none,
          FlowControl.rtsCts => SerialPortFlowControl.rtsCts,
          FlowControl.xonXoff => SerialPortFlowControl.xonXoff,
        });
    _port.config = native;
  }

  @override
  Future<void> setDtrNative(bool value) async =>
      _applyControlLines(dtr: value ? SerialPortDtr.on : SerialPortDtr.off);

  @override
  Future<void> setRtsNative(bool value) async =>
      _applyControlLines(rts: value ? SerialPortRts.on : SerialPortRts.off);

  /// Une config neuve a tous ses champs à -1 (« ne pas modifier ») :
  /// seules les lignes renseignées sont appliquées.
  void _applyControlLines({int? dtr, int? rts}) {
    final native = SerialPortConfig();
    if (dtr != null) native.dtr = dtr;
    if (rts != null) native.rts = rts;
    _port.config = native; // propriété transférée au port, voir applyConfigNative
  }

  /// Écriture non bloquante par morceaux : un `sp_blocking_write` figerait
  /// l'isolate UI (16 Ko à 115200 bauds ≈ 1,4 s).
  @override
  Future<void> writeNative(Uint8List data) async {
    final clock = Stopwatch()..start();
    var offset = 0;
    while (offset < data.length) {
      offset += _port.write(Uint8List.sublistView(data, offset));
      if (offset < data.length) {
        if (clock.elapsed > writeTimeout) {
          throw SerialTimeoutException(
            'Écriture interrompue : ${data.length - offset} octets non envoyés après ${writeTimeout.inSeconds} s.',
            code: SerialErrorCode.writeTimeout,
            params: {'remaining': data.length - offset, 'seconds': writeTimeout.inSeconds},
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    }
  }

  @override
  Future<void> closeNative() async {
    _readTimer?.cancel();
    _readTimer = null;
    try {
      if (_port.isOpen) _port.close();
    } finally {
      _port.dispose();
      _onClosed();
    }
  }
}
