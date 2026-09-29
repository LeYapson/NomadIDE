import '../domain/serial_config.dart';
import '../domain/serial_device_info.dart';
import '../domain/serial_exceptions.dart';
import '../domain/serial_transport.dart';

/// Transport des plateformes sans accès série (iOS) : l'app reste utilisable
/// comme éditeur, et l'UI peut expliquer pourquoi aucune carte n'apparaît.
class UnsupportedSerialTransport implements SerialTransport {
  const UnsupportedSerialTransport(this.reason);

  /// Explication à afficher à l'utilisateur.
  final String reason;

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
      Future.error(SerialUnsupportedException(reason));

  @override
  Future<void> dispose() async {}
}
