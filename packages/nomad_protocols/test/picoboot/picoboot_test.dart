import 'dart:typed_data';

import 'package:nomad_protocols/nomad_protocols.dart';
import 'package:nomad_protocols/testing.dart';
import 'package:test/test.dart';

const _flash = 0x10000000;

/// UF2 de blocs (adresse, taille de données) ; le contenu de chaque octet dépend de son adresse.
Uint8List uf2(List<(int, int)> blocks) {
  final out = Uint8List(blocks.length * 512);
  final d = ByteData.sublistView(out);
  for (var i = 0; i < blocks.length; i++) {
    final (address, size) = blocks[i];
    final o = i * 512;
    d.setUint32(o, 0x0A324655, Endian.little);
    d.setUint32(o + 4, 0x9E5D5157, Endian.little);
    d.setUint32(o + 8, 0x2000, Endian.little);
    d.setUint32(o + 12, address, Endian.little);
    d.setUint32(o + 16, size, Endian.little);
    d.setUint32(o + 20, i, Endian.little);
    d.setUint32(o + 24, blocks.length, Endian.little);
    d.setUint32(o + 28, 0xE48BFF56, Endian.little);
    for (var j = 0; j < size; j++) {
      out[o + 32 + j] = ((address + j) * 7 + 3) & 0xFE; // jamais 0xFF : une page non écrite se voit
    }
    d.setUint32(o + 508, 0x0AB16F30, Endian.little);
  }
  return out;
}

/// Blocs contigus de 256 octets : [count] blocs à partir de [address].
List<(int, int)> contiguous(int address, int count) => [for (var i = 0; i < count; i++) (address + i * 256, 256)];

/// Canal qui enregistre les paquets envoyés avant de les transmettre à la fausse ROM.
class RecordingChannel implements PicobootChannel {
  RecordingChannel(this.inner);

  final FakePicoboot inner;
  final List<Uint8List> sent = [];

  @override
  Future<void> bulkOut(Uint8List data, {required Duration timeout}) {
    sent.add(Uint8List.fromList(data));
    return inner.bulkOut(data, timeout: timeout);
  }

  @override
  Future<Uint8List> bulkIn(int length, {required Duration timeout}) => inner.bulkIn(length, timeout: timeout);

  @override
  Future<void> interfaceReset() => inner.interfaceReset();

  @override
  Future<Uint8List> commandStatus() => inner.commandStatus();
}

void main() {
  late FakePicoboot rom;
  late PicobootClient client;
  late PicobootFlasher flasher;

  setUp(() {
    rom = FakePicoboot();
    client = PicobootClient(rom);
    flasher = PicobootFlasher(client);
  });

  group('PicobootClient', () {
    test('le paquet de commande : marque, jeton croissant, identifiant, arguments en petit-boutiste', () async {
      final recording = RecordingChannel(rom);
      final c = PicobootClient(recording);
      await c.exclusiveAccess();
      await c.exitXip();
      await c.flashErase(_flash + 0x1000, 0x2000);

      final commands = recording.sent.where((p) => p.length == 32).toList();
      expect(commands, hasLength(3));
      for (final p in commands) {
        expect(ByteData.sublistView(p).getUint32(0, Endian.little), 0x431FD10B);
      }
      expect(commands.map((p) => ByteData.sublistView(p).getUint32(4, Endian.little)), [1, 2, 3]);
      expect(commands.map((p) => p[8]), [0x01, 0x06, 0x03]);
      expect(commands[0][9], 1); // taille des arguments : un octet
      expect(commands[0][16], 1); // exclusif
      expect(commands[2][9], 8);
      final erase = ByteData.sublistView(commands[2]);
      expect(erase.getUint32(16, Endian.little), _flash + 0x1000);
      expect(erase.getUint32(20, Endian.little), 0x2000);
    });

    test('écriture : longueur de transfert dans l\'en-tête, données puis accusé de réception', () async {
      final recording = RecordingChannel(rom);
      final c = PicobootClient(recording);
      await c.exitXip();
      await c.write(_flash, Uint8List(512)..fillRange(0, 512, 0x11));

      final header = recording.sent[1];
      expect(header[8], 0x05);
      expect(ByteData.sublistView(header).getUint32(12, Endian.little), 512);
      expect(recording.sent[2], hasLength(512));
      expect(rom.flash.sublist(0, 512), everyElement(0x11));
    });

    test('lecture : renvoie les octets de la flash et envoie l\'accusé d\'un octet', () async {
      await client.exitXip();
      await client.write(_flash, Uint8List(256)..fillRange(0, 256, 0x42));
      await client.enterCmdXip();
      final back = await client.read(_flash, 256);
      expect(back, everyElement(0x42));
      expect(back, hasLength(256));
    });

    test('redémarrage : pc, sp et délai', () async {
      final recording = RecordingChannel(rom);
      await PicobootClient(recording).reboot(delayMs: 250);
      final p = ByteData.sublistView(recording.sent.first);
      expect(recording.sent.first[8], 0x02);
      expect(p.getUint32(16, Endian.little), 0);
      expect(p.getUint32(20, Endian.little), 0);
      expect(p.getUint32(24, Endian.little), 250);
      expect(rom.rebooted, isTrue);
    });

    test('une commande refusée par la ROM remonte avec son code d\'état et son nom', () async {
      await client.exitXip();
      await expectLater(
        client.flashErase(_flash + 100, 4096), // mauvais alignement
        throwsA(isA<ProtocolPicobootException>()
            .having((e) => e.status, 'status', 5)
            .having((e) => e.command, 'command', 0x03)
            .having((e) => e.params['statusName'], 'statusName', 'mauvais alignement')),
      );
    });

    test('après un refus, la suite fonctionne (l\'interface a été réinitialisée)', () async {
      await client.exitXip();
      await expectLater(client.flashErase(_flash + 100, 4096), throwsA(isA<ProtocolPicobootException>()));
      await client.flashErase(_flash, 4096);
      expect(rom.commands.last, 0x03);
    });
  });

  group('PicobootFlasher', () {
    test('écrit le fichier à la bonne adresse, vérifie, puis redémarre', () async {
      final bytes = uf2(contiguous(_flash, 40)); // 10 Ko
      final file = Uf2File.parse(bytes);
      await flasher.flashUf2(file);

      for (final block in file.flashBlocks) {
        expect(rom.flash.sublist(block.address - _flash, block.address - _flash + block.data.length), block.data);
      }
      expect(rom.flash[40 * 256], 0xFF, reason: 'rien au-delà du fichier');
      expect(rom.rebooted, isTrue);
      expect(rom.commands.first, PicobootCommand.exclusiveAccess);
      expect(rom.commands.last, PicobootCommand.reboot);
    });

    test('ordre des commandes : accès exclusif, XIP coupé, effacement, écriture, XIP rétabli, lecture, redémarrage', () async {
      await flasher.flashUf2(Uf2File.parse(uf2(contiguous(_flash, 2))));
      expect(rom.commands, [
        PicobootCommand.exclusiveAccess,
        PicobootCommand.exitXip,
        PicobootCommand.flashErase,
        PicobootCommand.write,
        PicobootCommand.enterCmdXip,
        PicobootCommand.read,
        PicobootCommand.reboot,
      ]);
    });

    test('efface les secteurs entiers avant d\'écrire (une flash non effacée donnerait un ET binaire)', () async {
      rom.flash.fillRange(0, 0x3000, 0x00); // ancien contenu
      await flasher.flashUf2(Uf2File.parse(uf2(contiguous(_flash + 0x1000, 4))));
      expect(rom.flash.sublist(0x1000, 0x1400), isNot(everyElement(0)));
      // Le secteur 0x1000-0x1FFF est effacé en entier, ses 3 Ko non utilisés sont à 0xFF ; les autres secteurs ne sont pas touchés.
      expect(rom.flash.sublist(0x1400, 0x2000), everyElement(0xFF));
      expect(rom.flash.sublist(0, 0x1000), everyElement(0));
      expect(rom.flash.sublist(0x2000, 0x3000), everyElement(0));
    });

    test('deux zones séparées : deux effacements, rien entre les deux', () async {
      final file = Uf2File.parse(uf2([...contiguous(_flash, 4), ...contiguous(_flash + 0x10000, 4)]));
      await flasher.flashUf2(file);
      expect(rom.commands.where((c) => c == PicobootCommand.flashErase), hasLength(2));
      expect(rom.flash.sublist(0x1000, 0x10000), everyElement(0xFF));
      expect(rom.flash.sublist(0x10000, 0x10400), isNot(everyElement(0xFF)));
    });

    test('un bloc plus court qu\'une page est complété par 0xFF', () async {
      final file = Uf2File.parse(uf2([(_flash, 100)]));
      await flasher.flashUf2(file);
      expect(rom.flash.sublist(100, 256), everyElement(0xFF));
      expect(rom.flash[99], isNot(0xFF));
    });

    test('progression : effacement, écriture, vérification, redémarrage, chacune croissante jusqu\'à son total', () async {
      final events = <(PicobootPhase, int, int)>[];
      await flasher.flashUf2(
        Uf2File.parse(uf2(contiguous(_flash, 40))),
        onProgress: (phase, done, total) => events.add((phase, done, total)),
      );
      expect(events.map((e) => e.$1).toSet(), PicobootPhase.values.toSet());
      for (final phase in [PicobootPhase.erasing, PicobootPhase.writing, PicobootPhase.verifying]) {
        final of = events.where((e) => e.$1 == phase).toList();
        expect(of.first.$2, 0);
        expect(of.last.$2, of.last.$3, reason: phase.name);
        expect(of.map((e) => e.$2), orderedEquals([...of.map((e) => e.$2)]..sort()));
      }
      expect(events.last.$1, PicobootPhase.rebooting);
    });

    test('flash défaillante : la vérification détecte l\'octet altéré et ne redémarre pas', () async {
      rom.corruptWriteAt = 0x500;
      await expectLater(
        flasher.flashUf2(Uf2File.parse(uf2(contiguous(_flash, 16)))),
        throwsA(isA<ProtocolStateException>()
            .having((e) => e.code, 'code', ProtocolErrorCode.picobootVerifyFailed)
            .having((e) => e.params['address'], 'address', '10000500')),
      );
      expect(rom.rebooted, isFalse);
    });

    test('verify: false ne relit rien', () async {
      await flasher.flashUf2(Uf2File.parse(uf2(contiguous(_flash, 4))), verify: false);
      expect(rom.commands, isNot(contains(PicobootCommand.read)));
      expect(rom.commands, isNot(contains(PicobootCommand.enterCmdXip)));
    });

    test('la ROM refuse l\'écriture : erreur PICOBOOT avec le code, pas de redémarrage', () async {
      rom.failing[PicobootCommand.write] = 4;
      await expectLater(
        flasher.flashUf2(Uf2File.parse(uf2(contiguous(_flash, 4)))),
        throwsA(isA<ProtocolPicobootException>().having((e) => e.status, 'status', 4)),
      );
      expect(rom.rebooted, isFalse);
    });

    test('câble débranché en cours de route : ProtocolClosedException, pas une erreur PICOBOOT', () async {
      rom.unplugAfterCommands = 5;
      await expectLater(
        flasher.flashUf2(Uf2File.parse(uf2(contiguous(_flash, 40)))),
        throwsA(isA<ProtocolClosedException>()),
      );
    });

    test('refuse un fichier qui vise la RAM ou une adresse mal alignée, avant d\'envoyer quoi que ce soit', () async {
      final ram = Uf2File.parse(uf2([(0x20000000, 256)]));
      final unaligned = Uf2File.parse(uf2([(_flash + 100, 256)]));
      for (final file in [ram, unaligned]) {
        await expectLater(
          flasher.flashUf2(file),
          throwsA(isA<ProtocolStateException>().having((e) => e.code, 'code', ProtocolErrorCode.picobootBadImage)),
        );
      }
      expect(rom.commands, isEmpty);
    });
  });

  group('Uf2File.flashBlocks', () {
    test('renvoie adresse et données de chaque bloc, dans l\'ordre du fichier', () {
      final file = Uf2File.parse(uf2([(_flash + 256, 256), (_flash, 100)]));
      final blocks = file.flashBlocks.toList();
      expect(blocks.map((b) => b.address), [_flash + 256, _flash]);
      expect(blocks.map((b) => b.data.length), [256, 100]);
    });
  });
}
