import 'package:flutter/foundation.dart';

/// Famille de pilote USB-série à utiliser (côté Android, les pilotes sont en userland).
enum UsbSerialDriver {
  ftdi,
  cp210x,
  ch34x,
  pl2303,
  cdcAcm,

  /// Périphérique reconnu mais pas série (bootloader DFU, BOOTSEL RP2040 en stockage de masse).
  notSerial,
  unknown,
}

/// Indice sur la carte, utile pour proposer le bon flasheur dès l'étape 3.
enum BoardFamily { esp32, rp2040, stm32, arduino, micropython, generic }

/// Puce identifiée d'après son couple VID:PID.
@immutable
class UsbChip {
  const UsbChip(this.driver, this.label, [this.boardFamily = BoardFamily.generic]);

  final UsbSerialDriver driver;
  final String label;
  final BoardFamily boardFamily;

  bool get isSerial => driver != UsbSerialDriver.notSerial;

  static const unknown = UsbChip(UsbSerialDriver.unknown, 'Inconnu');

  /// Cherche d'abord le couple exact VID:PID, puis se replie sur le fabricant.
  static UsbChip identify(int? vendorId, int? productId) {
    if (vendorId == null) return unknown;
    return _byVidPid[(vendorId, productId ?? 0)] ?? _byVendor[vendorId] ?? unknown;
  }

  @override
  String toString() => 'UsbChip($label, ${driver.name}, ${boardFamily.name})';
}

// Remarque : les CP210x / CH340 équipent la plupart des cartes de dev ESP32/ESP8266,
// mais aussi des Arduino clones : on ne présume pas de la famille de carte.
final Map<(int, int), UsbChip> _byVidPid = {
  // FTDI
  (0x0403, 0x6001): const UsbChip(UsbSerialDriver.ftdi, 'FT232R'),
  (0x0403, 0x6010): const UsbChip(UsbSerialDriver.ftdi, 'FT2232'),
  (0x0403, 0x6014): const UsbChip(UsbSerialDriver.ftdi, 'FT232H'),
  (0x0403, 0x6015): const UsbChip(UsbSerialDriver.ftdi, 'FT231X'),
  // Silicon Labs
  (0x10C4, 0xEA60): const UsbChip(UsbSerialDriver.cp210x, 'CP2102/CP2104'),
  (0x10C4, 0xEA70): const UsbChip(UsbSerialDriver.cp210x, 'CP2105'),
  // WCH
  (0x1A86, 0x7523): const UsbChip(UsbSerialDriver.ch34x, 'CH340'),
  (0x1A86, 0x5523): const UsbChip(UsbSerialDriver.ch34x, 'CH341'),
  (0x1A86, 0x55D4): const UsbChip(UsbSerialDriver.cdcAcm, 'CH9102 (CDC)'),
  // Prolific
  (0x067B, 0x2303): const UsbChip(UsbSerialDriver.pl2303, 'PL2303'),
  // Espressif : contrôleur USB-Serial-JTAG intégré (ESP32-C3/C6/S3/H2)
  (0x303A, 0x1001): const UsbChip(UsbSerialDriver.cdcAcm, 'ESP32 USB-Serial-JTAG', BoardFamily.esp32),
  // Raspberry Pi
  (0x2E8A, 0x0005): const UsbChip(UsbSerialDriver.cdcAcm, 'Pico (MicroPython)', BoardFamily.rp2040),
  (0x2E8A, 0x000A): const UsbChip(UsbSerialDriver.cdcAcm, 'Pico (SDK stdio USB)', BoardFamily.rp2040),
  (0x2E8A, 0x0003): const UsbChip(UsbSerialDriver.notSerial, 'RP2040 BOOTSEL (UF2)', BoardFamily.rp2040),
  // STMicroelectronics
  (0x0483, 0x5740): const UsbChip(UsbSerialDriver.cdcAcm, 'STM32 Virtual COM', BoardFamily.stm32),
  (0x0483, 0x374B): const UsbChip(UsbSerialDriver.cdcAcm, 'ST-LINK/V2-1 VCP', BoardFamily.stm32),
  (0x0483, 0x374E): const UsbChip(UsbSerialDriver.cdcAcm, 'STLINK-V3 VCP', BoardFamily.stm32),
  (0x0483, 0xDF11): const UsbChip(UsbSerialDriver.notSerial, 'STM32 DFU', BoardFamily.stm32),
  // VID officiel MicroPython
  (0xF055, 0x9800): const UsbChip(UsbSerialDriver.cdcAcm, 'Pyboard (MicroPython)', BoardFamily.micropython),
};

final Map<int, UsbChip> _byVendor = {
  0x0403: const UsbChip(UsbSerialDriver.ftdi, 'FTDI'),
  0x10C4: const UsbChip(UsbSerialDriver.cp210x, 'Silicon Labs CP210x'),
  0x1A86: const UsbChip(UsbSerialDriver.ch34x, 'WCH CH34x'),
  0x067B: const UsbChip(UsbSerialDriver.pl2303, 'Prolific PL2303'),
  0x303A: const UsbChip(UsbSerialDriver.cdcAcm, 'Espressif USB natif', BoardFamily.esp32),
  0x2E8A: const UsbChip(UsbSerialDriver.cdcAcm, 'Raspberry Pi', BoardFamily.rp2040),
  0x0483: const UsbChip(UsbSerialDriver.cdcAcm, 'STMicroelectronics', BoardFamily.stm32),
  0x2341: const UsbChip(UsbSerialDriver.cdcAcm, 'Arduino', BoardFamily.arduino),
  0x239A: const UsbChip(UsbSerialDriver.cdcAcm, 'Adafruit'),
  0xF055: const UsbChip(UsbSerialDriver.cdcAcm, 'MicroPython', BoardFamily.micropython),
};
