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

  group('plusieurs fichiers (projet Arduino ou ESP-IDF)', () {
    final bootloader = _bootloaderImage();
    final app = _espImage(chipId: 0x00, fullImage: false);
    final otaData = Uint8List(0x2000)..fillRange(0, 0x2000, 0xFF);

    Future<void> add(String name, Uint8List bytes) async {
      nextPick = (name: name, bytes: bytes);
      await controller().addFile();
    }

    Future<void> arduinoProject({Uint8List? partitions}) async {
      nextPick = (name: 'sketch.ino.bootloader.bin', bytes: bootloader);
      await controller().pickFile();
      await add('sketch.ino.partitions.bin', partitions ?? _partitionTable());
      await add('boot_app0.bin', otaData);
      await add('sketch.ino.bin', app);
    }

    test('chaque fichier reçoit son adresse, déduite de son contenu', () async {
      await arduinoProject();

      expect(state().multiple, isTrue);
      expect(state().parts.map((p) => p.offsetText), ['0x1000', '0x8000', '0xe000', '0x10000']);
      expect(state().parts[0].note, contains('Bootloader pour ESP32'));
      expect(state().parts[1].note, contains('Table de partitions'));
      expect(state().parts[2].note, contains('Données de démarrage OTA'));
      expect(state().parts[3].note, contains('d’après la table de partitions'));
    });

    test('la table de partitions fournie donne l\'adresse de l\'application et des données OTA', () async {
      await arduinoProject(partitions: _partitionTable(otaData: 0xD000, app: 0x20000));
      expect(state().parts[2].offsetText, '0xd000');
      expect(state().parts[3].offsetText, '0x20000');
    });

    test('tout est écrit en une passe, chaque fichier vérifié, la carte redémarrée une seule fois', () async {
      await arduinoProject();
      final parts = <int>{};
      container.listen(espFlashProvider, (_, s) {
        if (s.phase == EspFlashPhase.writing) parts.add(s.currentPart);
      });
      await controller().flash();

      expect(state().phase, EspFlashPhase.done, reason: state().message);
      expect(rom.flash.sublist(0x1000, 0x1000 + bootloader.length), bootloader);
      expect(rom.flash.sublist(0x8000, 0x8000 + 0xC00), _partitionTable());
      expect(rom.flash.sublist(0xE000, 0xE000 + otaData.length), otaData);
      expect(rom.flash.sublist(0x10000, 0x10000 + app.length), app);
      expect(rom.commands.where((c) => c == EspLoader.opSpiFlashMd5).length, 4, reason: 'un MD5 par fichier');
      expect(parts, {0, 1, 2, 3});
      expect(state().message, contains('4 fichiers'));
      expect(transport.opened, hasLength(1));
    });

    test('deux fichiers qui se recouvrent : refusé avant d\'ouvrir le port', () async {
      await arduinoProject();
      controller().setOffset('0x8400', index: 3); // l'application empiéterait sur la table
      await controller().flash();

      expect(state().phase, EspFlashPhase.failed);
      expect(state().message, contains('se recouvrent'));
      expect(transport.opened, isEmpty);
    });

    test('un fichier non reconnu demande son adresse', () async {
      await arduinoProject();
      await add('donnees.bin', Uint8List.fromList(List.filled(64, 7)));

      expect(state().parts.last.offsetText, '');
      expect(state().parts.last.note, contains('Contenu non reconnu'));
      await controller().flash();
      expect(state().message, contains('donnees.bin'));
      expect(transport.opened, isEmpty);
    });

    test('une adresse corrigée à la main n\'est plus recalculée quand on ajoute un fichier', () async {
      nextPick = (name: 'sketch.ino.bin', bytes: app);
      await controller().pickFile();
      controller().setOffset('0x20000');
      await add('sketch.ino.bootloader.bin', bootloader);
      expect(state().parts.first.offsetText, '0x20000');
    });

    test('retirer des fichiers ramène au cas d\'un seul fichier', () async {
      await arduinoProject();
      controller().removePart(0);
      controller().removePart(0);
      controller().removePart(0);
      expect(state().multiple, isFalse);
      expect(state().fileName, 'sketch.ino.bin');
      expect(state().offsetText, '0x10000');
    });

    test('choisir un fichier remplace la liste', () async {
      await arduinoProject();
      nextPick = (name: 'ESP32_GENERIC.bin', bytes: _espImage(chipId: 0x00, fullImage: true));
      await controller().pickFile();
      expect(state().parts, hasLength(1));
      expect(state().offsetText, '0x1000');
    });
  });
}

/// Bootloader d'ESP32 : une image sans description d'application, assez petite pour tenir avant 0x8000.
Uint8List _bootloaderImage() {
  final out = _espImage(chipId: 0x00, fullImage: false);
  out.setAll(32, [1, 2, 3, 4]); // pas de marque esp_app_desc_t
  return out;
}

/// Table de partitions : nvs, otadata ([otaData]), app0 ([app]).
Uint8List _partitionTable({int otaData = 0xE000, int app = 0x10000}) {
  final out = Uint8List(0xC00)..fillRange(0, 0xC00, 0xFF);
  final view = ByteData.sublistView(out);
  void entry(int i, int type, int subtype, int offset, int size, String label) {
    final o = i * 32;
    out[o] = 0xAA;
    out[o + 1] = 0x50;
    out[o + 2] = type;
    out[o + 3] = subtype;
    view.setUint32(o + 4, offset, Endian.little);
    view.setUint32(o + 8, size, Endian.little);
    out.fillRange(o + 12, o + 28, 0);
    out.setAll(o + 12, label.codeUnits);
  }

  entry(0, 0x01, 0x02, 0x9000, 0x5000, 'nvs');
  entry(1, 0x01, 0x00, otaData, 0x2000, 'otadata');
  entry(2, 0x00, 0x10, app, 0x140000, 'app0');
  return out;
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
  } else {
    // Toute application ESP-IDF ou Arduino porte la description `esp_app_desc_t` après son en-tête.
    out.setAll(32, [0x32, 0x54, 0xCD, 0xAB]);
  }
  return out;
}
