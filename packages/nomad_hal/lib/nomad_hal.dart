/// NomadMCU — Hardware Abstraction Layer USB/série.
///
/// Point d'entrée unique pour l'application et les protocoles :
///
/// ```dart
/// final transport = createPlatformTransport();
/// final devices = await transport.listDevices();
/// final conn = await transport.open(devices.first, config: const SerialConfig(baudRate: 115200));
/// conn.input.listen((bytes) => print(bytes));
/// await conn.write(Uint8List.fromList('print(42)\r'.codeUnits));
/// ```
///
/// Les implémentations Android et desktop ne sont pas exportées : on passe
/// toujours par [createPlatformTransport] (ou par un [FakeSerialTransport]
/// injecté dans les tests).
library;

export 'src/domain/serial_config.dart';
export 'src/domain/serial_device_info.dart';
export 'src/domain/serial_exceptions.dart';
export 'src/domain/serial_transport.dart';
export 'src/domain/usb_chip.dart';
export 'src/io/reset_sequences.dart';
export 'src/io/serial_reader.dart';
export 'src/platform/base_serial_connection.dart';
export 'src/platform/fake_transport.dart';
export 'src/platform/unsupported_transport.dart';
export 'src/transport_factory.dart';
