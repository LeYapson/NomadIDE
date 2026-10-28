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

  group('adresse choisie d\'après l\'en-tête du fichier', () {
    test('image complète d\'ESP32 (firmware MicroPython) : 0x1000, sans que l\'utilisateur ait à le savoir', () async {
      final full = _espImage(chipId: 0x00, fullImage: true);
      nextPick = (name: 'ESP32_GENERIC-v1.29.0.bin', bytes: full);
      await controller().pickFile();

      expect(state().offsetText, '0x1000');
      expect(state().offsetNote, contains('Image complète pour ESP32'));
      expect(state().offsetNote, contains('0x1000'));

      await controller().flash();
      expect(state().phase, EspFlashPhase.done, reason: state().message);
      expect(rom.flash.sublist(0x1000, 0x1000 + full.length), full);
      // Rien n'a été écrit là où une application aurait été.
      expect(rom.flash[0x10000], 0xFF);
    });

    test('image complète d\'ESP32-S3 : 0x0', () async {
      setUpBoard(FakeEspRom(chip: EspChip.esp32s3));
      await controller().refreshDevices();
      final full = _espImage(chipId: 0x09, fullImage: true);
      nextPick = (name: 'ESP32_GENERIC_S3.bin', bytes: full);
      await controller().pickFile();
      expect(state().offsetText, '0x0');
      await controller().flash();
      expect(state().phase, EspFlashPhase.done, reason: state().message);
      expect(rom.flash.sublist(0, full.length), full);
    });

    test('application seule : 0x10000', () async {
      nextPick = (name: 'app.bin', bytes: _espImage(chipId: 0x00, fullImage: false));
      await controller().pickFile();
      expect(state().offsetText, '0x10000');
      expect(state().offsetNote, contains('Application pour ESP32'));
    });

    test('fichier qui n\'est pas une image ESP32 : l\'adresse n\'est pas touchée, pas de note', () async {
      controller().setOffset('0x3000');
      await controller().pickFile(); // _image(5000) : données quelconques
      expect(state().offsetText, '0x3000');
      expect(state().offsetNote, isNull);
      expect(state().image, isNull);
    });

    test('image complète à une mauvaise adresse : refusée avant de toucher à la carte', () async {
      nextPick = (name: 'ESP32_GENERIC.bin', bytes: _espImage(chipId: 0x00, fullImage: true));
      await controller().pickFile();
      controller().setOffset('0x10000');
      await controller().flash();

      expect(state().phase, EspFlashPhase.failed);
      expect(state().message, contains('0x1000'));
      expect(state().message, contains('0x10000'));
      expect(transport.opened, isEmpty);
    });

    test('fichier d\'une autre puce : refusé après détection, rien n\'est écrit', () async {
      // La carte de test est un ESP32 ; le fichier est un firmware d'ESP32-S3.
      nextPick = (name: 'ESP32_GENERIC_S3.bin', bytes: _espImage(chipId: 0x09, fullImage: true));
      await controller().pickFile();
      await controller().flash();

      expect(state().phase, EspFlashPhase.failed);
      expect(state().message, contains('ESP32-S3'));
      expect(state().message, contains('Rien n’a été écrit'));
      expect(rom.commands, isNot(contains(EspLoader.opFlashDeflBegin)));
      expect(rom.commands, isNot(contains(EspLoader.opFlashBegin)));
      expect(transport.opened.single.isOpen, isFalse);
    });
  });
}

/// Image ESP32 minimale : en-tête étendu, puis (si [fullImage]) la table de partitions là où elle
/// se retrouve dans la flash, comme dans le firmware officiel de MicroPython.
Uint8List _espImage({required int chipId, required bool fullImage}) {
  final out = Uint8List(fullImage ? 0x8200 : 0x2000);
  out[0] = 0xE9;
  out[1] = 3;
  ByteData.sublistView(out)
    ..setUint16(12, chipId, Endian.little)
    ..setUint16(17, 0x018F, Endian.little);
  out[23] = 1;
  if (fullImage) {
    final tableAt = (chipId == 0x00 || chipId == 0x02) ? 0x7000 : 0x8000;
    out[tableAt] = 0xAA;
    out[tableAt + 1] = 0x50;
  }
  for (var i = 24; i < out.length; i++) {
    if (out[i] == 0) out[i] = (i * 7) & 0xFF | 1;
  }
  // Les octets de la marque ont pu être écrasés par le remplissage : on les remet.
  if (fullImage) {
    final tableAt = (chipId == 0x00 || chipId == 0x02) ? 0x7000 : 0x8000;
    out[tableAt] = 0xAA;
    out[tableAt + 1] = 0x50;
  }
  return out;
}
