import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:nomad_mcu/features/flash/application/esp_flash_controller.dart';
import 'package:nomad_mcu/features/flash/application/flash_controller.dart' show PickedFile;
import 'package:nomad_protocols/nomad_protocols.dart';
import 'package:nomad_protocols/testing.dart';

import 'support/esp_transport.dart';
import 'support/locale.dart';

Uint8List _image(int size) {
  final random = math.Random(3);
  return Uint8List.fromList([for (var i = 0; i < size; i++) i < size ~/ 2 ? random.nextInt(256) : i & 0x3F]);
}

void main() {
  late FakeEspRom rom;
  late EspRomTransport transport;
  late ProviderContainer container;
  late PickedFile? nextPick;

  void setUpBoard(FakeEspRom r) {
    rom = r;
    transport = EspRomTransport(rom);
    nextPick = (name: 'app.bin', bytes: _image(5000));
    container = ProviderContainer(overrides: [
      frenchLocale,
      serialTransportProvider.overrideWithValue(transport),
      binPickerProvider.overrideWithValue(() async => nextPick),
      espSyncPolicyProvider.overrideWithValue((bootAttempts: 2, syncAttempts: 2, syncTimeout: const Duration(milliseconds: 30))),
    ]);
    container.listen(espFlashProvider, (_, __) {});
  }

  setUp(() async {
    setUpBoard(FakeEspRom());
    await container.read(espFlashProvider.notifier).refreshDevices();
  });

  tearDown(() => container.dispose());

  EspFlashController controller() => container.read(espFlashProvider.notifier);
  EspFlashState state() => container.read(espFlashProvider);

  test('sélectionne la carte et attend un fichier avant d\'autoriser le flash', () {
    expect(state().selectedDevice?.id, 'fake:esp');
    expect(state().canFlash, isFalse);
  });

  test('flash complet : bootloader par DTR/RTS, écriture à l\'adresse choisie, vérification, reset', () async {
    await controller().pickFile();
    expect(state().canFlash, isTrue);
    await controller().flash();

    expect(state().phase, EspFlashPhase.done, reason: state().message);
    expect(rom.flash.sublist(0x10000, 0x10000 + 5000), _image(5000));
    expect(rom.commands, contains(EspLoader.opSpiFlashMd5));
    expect(state().message, contains('ESP32'));
    expect(state().message, contains('vérifié'));

    final lines = transport.opened.single.lineChanges;
    // Séquence d'entrée en bootloader (IO0 bas pendant que EN remonte), puis reset matériel final.
    expect(lines, containsAllInOrder(['dtr=0', 'rts=1', 'dtr=1', 'rts=0', 'dtr=0']));
    expect(lines.last, 'rts=0');
    expect(transport.opened.single.isOpen, isFalse);
  });

  test('adresse saisie en hexadécimal', () async {
    await controller().pickFile();
    controller().setOffset('0x0');
    await controller().flash();
    expect(rom.flash.sublist(0, 5000), _image(5000));
  });

  test('un débit plus élevé est négocié avec la ROM puis appliqué au port', () async {
    await controller().pickFile();
    controller().setBaudRate(460800);
    await controller().flash();
    expect(state().phase, EspFlashPhase.done, reason: state().message);
    expect(rom.baudRate, 460800);
    expect(transport.opened.single.config.baudRate, 460800);
  });

  test('adresse invalide : message clair, rien n\'est envoyé', () async {
    await controller().pickFile();
    controller().setOffset('abc');
    await controller().flash();
    expect(state().phase, EspFlashPhase.failed);
    expect(state().message, contains('Adresse invalide'));
    expect(transport.opened, isEmpty);
  });

  test('carte muette : plusieurs essais de reset, puis le conseil BOOT + EN', () async {
    setUpBoard(FakeEspRom(silentSyncs: 1000));
    await controller().refreshDevices();
    await controller().pickFile();
    await controller().flash();
    expect(state().phase, EspFlashPhase.failed);
    expect(state().message, contains('BOOT'));
    // Deux essais : deux séquences de reset (DTR passe à 1 une fois par essai).
    expect(transport.opened.single.lineChanges.where((l) => l == 'dtr=1'), hasLength(2));
  });

  test('écriture interrompue : on prévient que la carte peut être incomplète', () async {
    await controller().pickFile();
    rom.failing[EspLoader.opFlashDeflData] = 0x08;
    await controller().flash();
    expect(state().phase, EspFlashPhase.failed);
    expect(state().message, contains('incomplet'));
  });

  test('ESP8266 : écriture sans vérification, avec un message adapté', () async {
    setUpBoard(FakeEspRom(chip: EspChip.esp8266));
    await controller().refreshDevices();
    await controller().pickFile();
    await controller().flash();
    expect(state().phase, EspFlashPhase.done, reason: state().message);
    expect(state().message, contains('ESP8266'));
    expect(state().message, contains('ne permet pas la vérification'));
  });

  test('parseOffset accepte 0x, h et décimal', () {
    expect(EspFlashController.parseOffset('0x10000'), 0x10000);
    expect(EspFlashController.parseOffset(' 1000h '), 0x1000);
    expect(EspFlashController.parseOffset('4096'), 4096);
    expect(EspFlashController.parseOffset(''), isNull);
    expect(EspFlashController.parseOffset('0xZZ'), isNull);
  });
}
