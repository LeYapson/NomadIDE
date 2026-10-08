import '../domain/serial_config.dart';
import '../domain/serial_device_info.dart';
import '../domain/serial_exceptions.dart';
import '../domain/serial_transport.dart';

/// Transport des plateformes sans accès série (iOS) : l'app reste utilisable
/// comme éditeur, et l'UI peut expliquer pourquoi aucune carte n'apparaît.
class UnsupportedSerialTransport implements SerialTransport {
  const UnsupportedSerialTransport(this.reason, {this.platform = ''});

  /// Explication en français pour les journaux ; l'interface s'appuie sur [platform].
  final String reason;

  /// Plateforme concernée (`ios`, ou le nom du système d'exploitation).
  final String platform;

  @override
  TransportKind get kind => TransportKind.unsupported;

  @override
  String get name => 'Non pris en charge';

  @override
  bool get isSupported => false;

  @override
  Future<List<SerialDeviceInfo>> listDevices() async => const [];

  @override
  Stream<DeviceEvent> get deviceEvents => const Stream<DeviceEvent>.empty();

  @override
  Future<SerialConnection> open(
    SerialDeviceInfo device, {
    SerialConfig config = const SerialConfig(),
    bool dtr = true,
    bool rts = true,
  }) =>
      Future.error(
        SerialUnsupportedException(reason, code: SerialErrorCode.unsupportedPlatform, params: {'platform': platform}),
      );

  @override
  Future<void> dispose() async {}
}
