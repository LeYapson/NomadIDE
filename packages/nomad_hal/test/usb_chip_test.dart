import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_hal/nomad_hal.dart';

void main() {
  test('identification exacte VID:PID', () {
    final chip = UsbChip.identify(0x1A86, 0x7523);
    expect(chip.driver, UsbSerialDriver.ch34x);
    expect(chip.label, 'CH340');
  });

  test('famille de carte déduite pour les puces à USB natif', () {
    expect(UsbChip.identify(0x303A, 0x1001).boardFamily, BoardFamily.esp32);
    expect(UsbChip.identify(0x2E8A, 0x0005).boardFamily, BoardFamily.rp2040);
  });

  test('repli sur le fabricant pour un PID inconnu', () {
    expect(UsbChip.identify(0x10C4, 0x1234).driver, UsbSerialDriver.cp210x);
  });

  test('bootloaders non série signalés comme tels', () {
    expect(UsbChip.identify(0x2E8A, 0x0003).isSerial, isFalse);
    expect(UsbChip.identify(0x0483, 0xDF11).isSerial, isFalse);
  });

  test('VID absent ou inconnu → UsbChip.unknown', () {
    expect(UsbChip.identify(null, null), same(UsbChip.unknown));
    expect(UsbChip.identify(0xDEAD, 0xBEEF), same(UsbChip.unknown));
  });

  test('SerialDeviceInfo.details compose chemin, puce et VID:PID', () {
    const info = SerialDeviceInfo(
      id: 'COM5',
      displayName: 'USB-SERIAL CH340',
      systemPath: 'COM5',
      vendorId: 0x1A86,
      productId: 0x7523,
    );
    expect(info.details, 'COM5 · CH340 · 1A86:7523');
  });
}
