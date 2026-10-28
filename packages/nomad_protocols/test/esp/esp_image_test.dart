import 'dart:io';
import 'dart:typed_data';

import 'package:nomad_protocols/nomad_protocols.dart';
import 'package:test/test.dart';

/// En-tête d'image ESP étendu (24 octets) pour [chipId], suivi de [length] - 24 octets de données.
Uint8List image({int chipId = 0, int length = 0x20000, bool partitionTable = false, int? tableAt}) {
  final out = Uint8List(length);
  out[0] = 0xE9;
  out[1] = 3;
  ByteData.sublistView(out)
    ..setUint16(12, chipId, Endian.little)
    ..setUint16(17, 0x018F, Endian.little); // révision max. de la puce : non nulle, comme dans un vrai fichier
  out[23] = 1;
  if (partitionTable) {
    final at = tableAt ?? (chipId == 0 || chipId == 2 ? 0x7000 : 0x8000);
    out[at] = 0xAA;
    out[at + 1] = 0x50;
  }
  return out;
}

void main() {
  group('analyzeEspImage', () {
    test('image complète d\'ESP32 : à écrire à 0x1000', () {
      final info = analyzeEspImage(image(partitionTable: true))!;
      expect(info.chip, EspChip.esp32);
      expect(info.isFullImage, isTrue);
      expect(info.suggestedOffset, 0x1000);
    });

    test('image complète d\'ESP32-S3, C3 ou C6 : à écrire à 0x0', () {
      for (final (id, chip) in [(0x09, EspChip.esp32s3), (0x05, EspChip.esp32c3), (0x0D, EspChip.esp32c6)]) {
        final info = analyzeEspImage(image(chipId: id, partitionTable: true))!;
        expect(info.chip, chip);
        expect(info.isFullImage, isTrue);
        expect(info.suggestedOffset, 0x0, reason: chip.label);
      }
    });

    test('ESP32-S2 : comme l\'ESP32, à 0x1000', () {
      expect(analyzeEspImage(image(chipId: 0x02, partitionTable: true))!.suggestedOffset, 0x1000);
    });

    test('application seule : à écrire à 0x10000', () {
      final info = analyzeEspImage(image(chipId: 0x09))!;
      expect(info.isFullImage, isFalse);
      expect(info.suggestedOffset, 0x10000);
      expect(info.chip, EspChip.esp32s3);
    });

    test('une table de partitions à l\'adresse de l\'autre famille ne compte pas', () {
      // Un ESP32-S3 dont le fichier aurait la marque à 0x7000 (cas d\'une image ESP32) : pas une image complète S3.
      final info = analyzeEspImage(image(chipId: 0x09, partitionTable: true, tableAt: 0x7000))!;
      expect(info.isFullImage, isFalse);
    });

    test('fichier qui n\'est pas une image ESP32 : null', () {
      expect(analyzeEspImage(Uint8List(0)), isNull);
      expect(analyzeEspImage(Uint8List(5000)), isNull); // pas de 0xE9
      expect(analyzeEspImage(image(chipId: 0x7777)), isNull); // puce inconnue
      final esp8266 = image(partitionTable: true)..[20] = 0x12; // octets réservés non nuls
      expect(analyzeEspImage(esp8266), isNull);
      expect(analyzeEspImage(Uint8List.sublistView(image(), 0, 20)), isNull); // en-tête incomplet
    });

    test('le firmware MicroPython officiel de l\'ESP32, s\'il est présent sur la machine', () {
      final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      final file = home == null ? null : File('$home/Downloads/ESP32_GENERIC-20260824-v1.29.0.bin');
      if (file == null || !file.existsSync()) {
        markTestSkipped('firmware non téléchargé');
        return;
      }
      final info = analyzeEspImage(file.readAsBytesSync())!;
      expect(info.chip, EspChip.esp32);
      expect(info.isFullImage, isTrue);
      expect(info.suggestedOffset, 0x1000);
    });
  });
}
