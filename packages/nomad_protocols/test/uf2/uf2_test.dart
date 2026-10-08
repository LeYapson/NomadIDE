import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:nomad_protocols/nomad_protocols.dart';
import 'package:test/test.dart';

/// Fabrique un fichier UF2 valide de [blocks] blocs de 256 octets utiles.
Uint8List makeUf2({int blocks = 4, int family = 0xE48BFF56, int flags = 0x00002000}) {
  final out = Uint8List(blocks * 512);
  final d = ByteData.sublistView(out);
  for (var i = 0; i < blocks; i++) {
    final o = i * 512;
    d.setUint32(o, 0x0A324655, Endian.little);
    d.setUint32(o + 4, 0x9E5D5157, Endian.little);
    d.setUint32(o + 8, flags, Endian.little);
    d.setUint32(o + 12, 0x10000000 + i * 256, Endian.little);
    d.setUint32(o + 16, 256, Endian.little);
    d.setUint32(o + 20, i, Endian.little);
    d.setUint32(o + 24, blocks, Endian.little);
    d.setUint32(o + 28, family, Endian.little);
    for (var j = 0; j < 256; j++) {
      out[o + 32 + j] = (i + j) & 0xFF;
    }
    d.setUint32(o + 508, 0x0AB16F30, Endian.little);
  }
  return out;
}

const infoText = 'UF2 Bootloader v3.0\r\nModel: Raspberry Pi RP2\r\nBoard-ID: RPI-RP2\r\n';

void main() {
  group('Uf2File', () {
    test('lit un fichier valide', () {
      final f = Uf2File.parse(makeUf2(blocks: 4));
      expect(f.blockCount, 4);
      expect(f.family, Uf2Family.rp2040);
      expect(f.payloadSize, 1024);
      expect(f.startAddress, 0x10000000);
      expect(f.endAddress, 0x10000400);
      expect(f.family.isRaspberryPi, isTrue);
    });

    test('reconnaît une autre famille', () {
      expect(Uf2File.parse(makeUf2(family: 0x1C5F21B0)).family, Uf2Family.esp32);
      expect(Uf2File.parse(makeUf2(family: 0x1C5F21B0)).family.isRaspberryPi, isFalse);
    });

    test('famille absente → inconnue', () {
      expect(Uf2File.parse(makeUf2(flags: 0)).family, Uf2Family.unknown);
    });

    test('refuse un fichier vide', () {
      expect(() => Uf2File.parse(Uint8List(0)), throwsA(isA<Uf2FormatException>()));
    });

    test('refuse une taille qui n\'est pas multiple de 512', () {
      expect(() => Uf2File.parse(Uint8List(700)), throwsA(isA<Uf2FormatException>()));
    });

    test('refuse un fichier qui n\'est pas un UF2 (un .bin par exemple)', () {
      final e = _catch(() => Uf2File.parse(Uint8List(1024)));
      expect(e.blockIndex, 0);
    });

    test('refuse un fichier tronqué : le total annoncé ne correspond pas', () {
      final full = makeUf2(blocks: 4);
      final cut = Uint8List.sublistView(full, 0, 3 * 512);
      expect(() => Uf2File.parse(cut), throwsA(isA<Uf2FormatException>()));
    });

    test('désigne le bloc dont la marque de fin est abîmée', () {
      final bytes = makeUf2(blocks: 4);
      bytes[2 * 512 + 509] ^= 0xFF;
      expect(_catch(() => Uf2File.parse(bytes)).blockIndex, 2);
    });

    test('refuse des blocs dans le désordre', () {
      final bytes = makeUf2(blocks: 4);
      ByteData.sublistView(bytes).setUint32(1 * 512 + 20, 7, Endian.little);
      expect(_catch(() => Uf2File.parse(bytes)).blockIndex, 1);
    });

    test('refuse un mélange de familles de puces', () {
      final bytes = makeUf2(blocks: 4);
      ByteData.sublistView(bytes).setUint32(3 * 512 + 28, 0x1C5F21B0, Endian.little);
      expect(_catch(() => Uf2File.parse(bytes)).blockIndex, 3);
    });
  });

  group('Uf2Drive', () {
    test('lit INFO_UF2.TXT', () {
      final d = Uf2Drive.parseInfo('E:\\', infoText)!;
      expect(d.boardId, 'RPI-RP2');
      expect(d.model, 'Raspberry Pi RP2');
      expect(d.version, 'v3.0');
      expect(d.isRaspberryPi, isTrue);
    });

    test('un autre texte n\'est pas un disque UF2', () {
      expect(Uf2Drive.parseInfo('E:\\', 'bonjour'), isNull);
    });
  });

  group('Uf2Flasher', () {
    late Directory tmp;
    late Directory pico;
    late Directory other;
    late Uf2Flasher flasher;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('nomad_uf2_');
      pico = await Directory('${tmp.path}/RPI-RP2').create();
      other = await Directory('${tmp.path}/USBKEY').create();
      await File('${other.path}/notes.txt').writeAsString('rien à voir');
      flasher = Uf2Flasher(roots: () async => [pico.path, other.path], chunkSize: 1024);
    });

    tearDown(() => tmp.delete(recursive: true));

    /// Simule le bootloader : dès que le .uf2 est complet, le disque se vide.
    Future<void> bootloaderReboots(int expectedSize) async {
      final uf2 = File('${pico.path}/firmware.uf2');
      while (!await uf2.exists() || await uf2.length() < expectedSize) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await File('${pico.path}/INFO_UF2.TXT').delete();
      await uf2.delete();
    }

    test('findDrives ignore les disques sans INFO_UF2.TXT', () async {
      expect(await flasher.findDrives(), isEmpty);
      await File('${pico.path}/INFO_UF2.TXT').writeAsString(infoText);
      final drives = await flasher.findDrives();
      expect(drives, hasLength(1));
      expect(drives.single.path, pico.path);
    });

    test('waitForDrive attend l\'apparition du disque', () async {
      Timer(const Duration(milliseconds: 150), () => File('${pico.path}/INFO_UF2.TXT').writeAsStringSync(infoText));
      final d = await flasher.waitForDrive(timeout: const Duration(seconds: 3), poll: const Duration(milliseconds: 30));
      expect(d?.boardId, 'RPI-RP2');
    });

    test('waitForDrive rend null au bout du délai', () async {
      final d = await flasher.waitForDrive(timeout: const Duration(milliseconds: 120), poll: const Duration(milliseconds: 30));
      expect(d, isNull);
    });

    test('copie le fichier, signale la progression et constate le redémarrage', () async {
      await File('${pico.path}/INFO_UF2.TXT').writeAsString(infoText);
      final file = Uf2File.parse(makeUf2(blocks: 8));
      final drive = (await flasher.findDrives()).single;
      final progress = <int>[];
      final reboot = bootloaderReboots(file.bytes.length);

      final result = await flasher.flash(
        file,
        drive,
        onProgress: (w, t) {
          expect(t, 4096);
          progress.add(w);
        },
        poll: const Duration(milliseconds: 30),
      );
      await reboot;

      expect(result, Uf2FlashResult.rebooted);
      expect(progress.first, 0);
      expect(progress.last, 4096);
      expect(progress, orderedEquals([...progress]..sort()));
    });

    test('contenu copié identique au fichier', () async {
      await File('${pico.path}/INFO_UF2.TXT').writeAsString(infoText);
      final file = Uf2File.parse(makeUf2(blocks: 3));
      final drive = (await flasher.findDrives()).single;
      Uint8List? copied;
      final watcher = () async {
        final uf2 = File('${pico.path}/firmware.uf2');
        while (!await uf2.exists() || await uf2.length() < file.bytes.length) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        copied = await uf2.readAsBytes();
        await File('${pico.path}/INFO_UF2.TXT').delete();
      }();
      await flasher.flash(file, drive, poll: const Duration(milliseconds: 30));
      await watcher;
      expect(copied, file.bytes);
    });

    test('copiedNoReboot si le disque reste là (fichier refusé)', () async {
      await File('${pico.path}/INFO_UF2.TXT').writeAsString(infoText);
      final file = Uf2File.parse(makeUf2(blocks: 2));
      final drive = (await flasher.findDrives()).single;
      final result = await flasher.flash(
        file,
        drive,
        rebootTimeout: const Duration(milliseconds: 150),
        poll: const Duration(milliseconds: 30),
      );
      expect(result, Uf2FlashResult.copiedNoReboot);
    });

    test('Uf2CopyException si le disque a disparu avant la copie', () async {
      await File('${pico.path}/INFO_UF2.TXT').writeAsString(infoText);
      final file = Uf2File.parse(makeUf2(blocks: 2));
      final drive = (await flasher.findDrives()).single;
      await pico.delete(recursive: true);
      await expectLater(flasher.flash(file, drive), throwsA(isA<Uf2CopyException>()));
    });
  });
}

Uf2FormatException _catch(void Function() body) {
  try {
    body();
  } on Uf2FormatException catch (e) {
    return e;
  }
  fail('Uf2FormatException attendue');
}
