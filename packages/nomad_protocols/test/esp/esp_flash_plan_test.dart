import 'dart:typed_data';

import 'package:nomad_protocols/nomad_protocols.dart';
import 'package:test/test.dart';

/// En-tête d'image ESP étendu pour [chipId] ; [appDesc] ajoute la marque `esp_app_desc_t` d'une application.
Uint8List image({int chipId = 0, int length = 0x6000, bool appDesc = false}) {
  final out = Uint8List(length);
  out[0] = 0xE9;
  out[1] = 3;
  ByteData.sublistView(out).setUint16(12, chipId, Endian.little);
  if (appDesc) out.setAll(32, [0x32, 0x54, 0xCD, 0xAB]);
  return out;
}

/// Table de partitions : nvs (0x9000), otadata ([otaData]), app0 ([app]).
Uint8List table({int otaData = 0xE000, int app = 0x10000}) {
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

void main() {
  group('parsePartitionTable', () {
    test('lit les entrées jusqu\'à la fin de la table', () {
      final entries = parsePartitionTable(table());
      expect(entries.map((e) => e.label), ['nvs', 'otadata', 'app0']);
      expect(entries[1].isOtaData, isTrue);
      expect(entries[2].isApp, isTrue);
      expect(entries[2].offset, 0x10000);
    });

    test('une entrée d\'application incohérente (adresse 0) n\'est pas retenue', () {
      final broken = Uint8List(0xC00)..fillRange(0, 0xC00, 0xFF);
      broken.fillRange(0, 32, 0);
      broken
        ..[0] = 0xAA
        ..[1] = 0x50;
      final entries = parsePartitionTable(broken);
      expect(entries.single.isApp, isFalse);
      expect(guessEspPart('app.bin', image(length: 0x40000, appDesc: true), table: entries).offset, 0x10000);
    });

    test('un fichier qui n\'est pas une table donne une liste vide', () {
      expect(parsePartitionTable(image()), isEmpty);
    });
  });

  group('guessEspPart', () {
    test('les trois fichiers d\'un projet Arduino pour ESP32, sans table', () {
      final boot = guessEspPart('sketch.ino.bootloader.bin', image());
      expect(boot.role, EspPartRole.bootloader);
      expect(boot.chip, EspChip.esp32);
      expect(boot.offset, 0x1000);

      expect(guessEspPart('sketch.ino.partitions.bin', table()).offset, 0x8000);
      expect(guessEspPart('sketch.ino.partitions.bin', table()).role, EspPartRole.partitionTable);

      final app = guessEspPart('sketch.ino.bin', image(length: 0x40000, appDesc: true));
      expect(app.role, EspPartRole.app);
      expect(app.offset, 0x10000);
      expect(app.fromTable, isFalse);

      final ota = guessEspPart('boot_app0.bin', Uint8List(0x2000)..fillRange(0, 0x2000, 0xFF));
      expect(ota.role, EspPartRole.otaData);
      expect(ota.offset, 0xE000);
    });

    test('ESP32-S3 : le bootloader va à 0x0', () {
      final boot = guessEspPart('bootloader.bin', image(chipId: 0x09));
      expect(boot.chip, EspChip.esp32s3);
      expect(boot.offset, 0x0);
    });

    test('avec la table de partitions, l\'application et les données OTA vont là où elle le dit', () {
      final entries = parsePartitionTable(table(otaData: 0xD000, app: 0x20000));
      final app = guessEspPart('firmware.bin', image(length: 0x40000, appDesc: true), table: entries);
      expect(app.offset, 0x20000);
      expect(app.fromTable, isTrue);
      final ota = guessEspPart('ota_data_initial.bin', Uint8List(0x2000), table: entries);
      expect(ota.offset, 0xD000);
      expect(ota.fromTable, isTrue);
    });

    test('une image sans description d\'application mais trop grande pour un bootloader est une application', () {
      final guess = guessEspPart('firmware.bin', image(length: 0x30000));
      expect(guess.role, EspPartRole.app);
      expect(guess.offset, 0x10000);
    });

    test('un fichier inconnu n\'a pas d\'adresse devinée', () {
      final guess = guessEspPart('data.bin', Uint8List.fromList([1, 2, 3, 4]));
      expect(guess.role, EspPartRole.unknown);
      expect(guess.offset, isNull);
    });
  });

  group('findOverlap', () {
    EspFlashPart part(String name, int offset, int length) => EspFlashPart(name: name, offset: offset, data: Uint8List(length));

    test('des fichiers bout à bout ne se recouvrent pas', () {
      expect(findOverlap([part('app', 0x10000, 0x1000), part('boot', 0x1000, 0x7000), part('table', 0x8000, 0xC00)]), isNull);
    });

    test('deux fichiers qui se recouvrent sont signalés, quel que soit leur ordre', () {
      final overlap = findOverlap([part('app', 0x10000, 0x1000), part('trop gros', 0x1000, 0x7400), part('table', 0x8000, 0xC00)]);
      expect(overlap, isNotNull);
      expect({overlap!.$1.name, overlap.$2.name}, {'trop gros', 'table'});
    });

    test('deux fichiers à la même adresse se recouvrent', () {
      expect(findOverlap([part('a', 0x10000, 1), part('b', 0x10000, 1)]), isNotNull);
    });
  });
}
