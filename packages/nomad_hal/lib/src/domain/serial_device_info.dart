import 'package:flutter/foundation.dart';

import 'usb_chip.dart';

/// Description d'un périphérique série détecté, commune à toutes les plateformes.
@immutable
class SerialDeviceInfo {
  const SerialDeviceInfo({
    required this.id,
    required this.displayName,
    this.systemPath,
    this.vendorId,
    this.productId,
    this.manufacturer,
    this.product,
    this.serialNumber,
    this.isUsb = true,
  });

  /// Clé stable tant que le périphérique reste branché
  /// (Android : `usb:<deviceId>`, desktop : nom du port, ex. `COM5`).
  final String id;

  /// Libellé lisible pour l'UI.
  final String displayName;

  /// Chemin système (`/dev/ttyUSB0`, `COM5`, `/dev/bus/usb/001/002`…).
  final String? systemPath;

  final int? vendorId;
  final int? productId;
  final String? manufacturer;
  final String? product;
  final String? serialNumber;

  /// Faux pour les ports natifs (UART de la carte mère) ou Bluetooth.
  final bool isUsb;

  /// Puce USB-série identifiée d'après le couple VID:PID.
  UsbChip get chip => UsbChip.identify(vendorId, productId);

  /// « 1A86:7523 », vide si inconnu.
  String get vidPid => vendorId == null ? '' : '${_hex4(vendorId!)}:${_hex4(productId ?? 0)}';

  /// Ligne de détail pour l'UI, ex. « COM5 · CH340 · 1A86:7523 ».
  String get details => [
        systemPath,
        if (isUsb && chip != UsbChip.unknown) chip.label,
        vidPid,
      ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

  static String _hex4(int value) => value.toRadixString(16).toUpperCase().padLeft(4, '0');

  @override
  bool operator ==(Object other) => other is SerialDeviceInfo && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SerialDeviceInfo($id, $displayName, $vidPid)';
}
