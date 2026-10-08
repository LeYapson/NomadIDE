import 'dart:io' show Platform;

import 'domain/serial_transport.dart';
import 'platform/android_usb_transport.dart';
import 'platform/desktop_serial_transport.dart';
import 'platform/fake_transport.dart';
import 'platform/unsupported_transport.dart';

/// Choisit l'implémentation de [SerialTransport] adaptée à la plateforme.
///
/// [simulate] force la carte simulée (dev UI, CI, démo iOS).
SerialTransport createPlatformTransport({bool simulate = false}) {
  if (simulate) return FakeSerialTransport();
  if (Platform.isAndroid) return AndroidUsbSerialTransport();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return DesktopSerialTransport();
  if (Platform.isIOS) {
    return const UnsupportedSerialTransport(
      "iOS n'autorise pas l'accès aux adaptateurs USB-série : pas d'API USB Host publique, "
      'seuls les accessoires certifiés MFi sont accessibles. Utilisez le mode simulé, '
      'et plus tard les transports BLE ou WebREPL.',
      platform: 'ios',
    );
  }
  return UnsupportedSerialTransport(
    'Plateforme non prise en charge : ${Platform.operatingSystem}.',
    platform: Platform.operatingSystem,
  );
}
