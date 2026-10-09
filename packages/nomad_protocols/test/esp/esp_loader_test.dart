import 'dart:math' as math;
import 'dart:typed_data';

import 'package:nomad_protocols/nomad_protocols.dart';
import 'package:nomad_protocols/testing.dart';
import 'package:test/test.dart';

/// Image de test : peu compressible au début, très au milieu, pour exercer les deux cas.
Uint8List image(int size, {int seed = 7}) {
  final random = math.Random(seed);
  final out = Uint8List(size);
  for (var i = 0; i < size; i++) {
    out[i] = i < size ~/ 3 ? random.nextInt(256) : (i ~/ 64) & 0xFF;
  }
  return out;
}

void main() {
  late FakeEspRom rom;
  late EspLoader loader;

  Future<void> start(FakeEspRom r) async {
    rom = r;
    loader = EspLoader(rom, commandTimeout: const Duration(milliseconds: 400));
  }

  tearDown(() => loader.dispose());

  group('synchronisation et détection', () {
    test('sync réussit et jette les réponses en trop', () async {
      await start(FakeEspRom());
      await loader.sync();
      expect(rom.commands, [EspLoader.opSync]);
    });

    test('sync réessaie tant que la carte démarre, malgré le texte de boot', () async {
      await start(FakeEspRom(silentSyncs: 3, bootText: 'ets Jun  8 2016 00:22:57\r\nrst:0x1 (POWERON_RESET)\r\n'));
      rom.boot();
      await loader.sync(timeout: const Duration(milliseconds: 60));
      expect(rom.commands.where((c) => c == EspLoader.opSync), hasLength(4));
    });

    test('sync échoue avec un code précis si la carte reste muette', () async {
      await start(FakeEspRom(silentSyncs: 100));
      await expectLater(
        loader.sync(attempts: 3, timeout: const Duration(milliseconds: 30)),
        throwsA(isA<ProtocolTimeoutException>().having((e) => e.code, 'code', ProtocolErrorCode.espSyncFailed)),
      );
    });

    for (final chip in [EspChip.esp32, EspChip.esp32s3, EspChip.esp32c3, EspChip.esp8266]) {
      test('détecte ${chip.label}', () async {
        await start(FakeEspRom(chip: chip));
        await loader.sync();
        expect(await loader.detectChip(), chip);
      });
    }
  });

  group('écriture brute', () {
    test('écrit à la bonne adresse, complète le dernier bloc par 0xFF, vérifie le MD5', () async {
      await start(FakeEspRom());
      await loader.sync();
      final data = image(2500); // 2 blocs pleins + 452 octets
      final progress = <int>[];
      await loader.writeFlash(0x10000, data, compress: false, onProgress: (d, t) {
        expect(t, 2500);
        progress.add(d);
      });

      expect(rom.flash.sublist(0x10000, 0x10000 + 2500), data);
      // Le reste du dernier bloc est à 0xFF, et rien n'a été écrit avant.
      expect(rom.flash[0x10000 + 2500], 0xFF);
      expect(rom.flash[0xFFFF], 0xFF);
      expect(progress.first, 0);
      expect(progress.last, 2500);
      expect(rom.spiAttached, isTrue);
      expect(rom.commands, contains(EspLoader.opSpiFlashMd5));
    });

    test('un octet altéré dans la flash est détecté par le MD5', () async {
      await start(FakeEspRom());
      await loader.sync();
      rom.corruptWriteAt = 0x1000 + 700;
      await expectLater(
        loader.writeFlash(0x1000, image(2048), compress: false),
        throwsA(isA<ProtocolFlashVerifyException>()),
      );
    });

    test('verify: false ne relit rien', () async {
      await start(FakeEspRom());
      await loader.sync();
      await loader.writeFlash(0x1000, image(1024), compress: false, verify: false);
      expect(rom.commands, isNot(contains(EspLoader.opSpiFlashMd5)));
    });

    test('un bloc perdu sur le lien est renvoyé', () async {
      await start(FakeEspRom());
      await loader.sync();
      rom.dropDataPackets = 1;
      final data = image(3000);
      await loader.writeFlash(0x0, data, compress: false);
      expect(rom.flash.sublist(0, 3000), data);
    });

    test('un refus de la ROM remonte avec la commande et le code d\'erreur', () async {
      await start(FakeEspRom());
      await loader.sync();
      rom.failing[EspLoader.opFlashData] = 0x08;
      await expectLater(
        loader.writeFlash(0x0, image(100), compress: false),
        throwsA(isA<ProtocolRomException>().having((e) => e.error, 'error', 0x08).having((e) => e.command, 'command', EspLoader.opFlashData)),
      );
    });
  });

  group('écriture compressée', () {
    test('le fichier arrive intact et la ROM reçoit moins de blocs que de blocs bruts', () async {
      await start(FakeEspRom());
      await loader.sync();
      final data = image(20000);
      await loader.writeFlash(0x10000, data);
      expect(rom.flash.sublist(0x10000, 0x10000 + data.length), data);
      final dataPackets = rom.commands.where((c) => c == EspLoader.opFlashDeflData).length;
      expect(dataPackets, greaterThan(0));
      expect(dataPackets, lessThan((20000 / EspLoader.blockSize).ceil()));
      expect(rom.commands, contains(EspLoader.opFlashDeflEnd));
    });

    test('la progression atteint la taille du fichier', () async {
      await start(FakeEspRom());
      await loader.sync();
      final progress = <int>[];
      await loader.writeFlash(0, image(8000), onProgress: (d, t) => progress.add(d));
      expect(progress.last, 8000);
      expect(progress, orderedEquals([...progress]..sort()));
    });

    test('ROM qui refuse la décompression : erreur 0x0b', () async {
      await start(FakeEspRom());
      await loader.sync();
      rom.failing[EspLoader.opFlashDeflEnd] = 0x0b;
      await expectLater(
        loader.writeFlash(0, image(4000)),
        throwsA(isA<ProtocolRomException>().having((e) => e.error, 'error', 0x0b)),
      );
    });
  });

  group('ESP8266', () {
    test('pas de SPI_ATTACH, pas de MD5, statut de 2 octets', () async {
      await start(FakeEspRom(chip: EspChip.esp8266));
      await loader.sync();
      final data = image(3000);
      await loader.writeFlash(0x0, data, compress: false);
      expect(rom.flash.sublist(0, 3000), data);
      expect(rom.commands, isNot(contains(EspLoader.opSpiAttach)));
      expect(rom.commands, isNot(contains(EspLoader.opSpiFlashMd5)));
    });
  });

  group('lecture de la flash et débit', () {
    test('flashMd5 renvoie le condensé de la zone', () async {
      await start(FakeEspRom());
      await loader.sync();
      rom.flash.setRange(0x2000, 0x2003, [0x61, 0x62, 0x63]);
      expect(await loader.flashMd5(0x2000, 3), '900150983cd24fb0d6963f7d28e17f72');
    });

    test('changeBaudRate envoie le débit puis laisse l\'hôte reconfigurer son port', () async {
      await start(FakeEspRom());
      await loader.sync();
      int? applied;
      await loader.changeBaudRate(460800, reconfigure: (b) async => applied = b);
      expect(rom.baudRate, 460800);
      expect(applied, 460800);
    });
  });

  group('lien', () {
    test('câble débranché pendant une commande', () async {
      await start(FakeEspRom());
      await loader.sync();
      rom.ignored.add(EspLoader.opReadReg);
      final pending = loader.readReg(0x40001000);
      rom.unplug();
      await expectLater(pending, throwsA(isA<ProtocolClosedException>()));
    });

    test('commande sans réponse : délai dépassé', () async {
      await start(FakeEspRom());
      await loader.sync();
      rom.ignored.add(EspLoader.opReadReg);
      await expectLater(loader.readReg(0x40001000), throwsA(isA<ProtocolTimeoutException>()));
    });
  });
}
