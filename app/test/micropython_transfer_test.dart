import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:nomad_mcu/features/micropython/application/micropython_controller.dart';
import 'package:nomad_mcu/features/projects/application/projects_controller.dart';
import 'package:nomad_mcu/features/projects/data/project_store.dart';
import 'package:nomad_protocols/nomad_protocols.dart' show RemoteEntry;
import 'package:nomad_protocols/testing.dart';

import 'support/board_transport.dart';
import 'support/locale.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory storage;
  late FakeDisk disk;
  late FakeRawReplBoard board;
  late ProviderContainer container;
  late ProjectStore store;

  Uint8List bytes(int length, [int seed = 0]) => Uint8List.fromList(List.generate(length, (i) => (i * 7 + seed) % 256));

  setUp(() async {
    storage = Directory.systemTemp.createTempSync('nomad_transfer_test');
    disk = FakeDisk();
    board = FakeRawReplBoard(run: disk.run, outputChunkSize: 64);
    store = ProjectStore(storage);
    container = ProviderContainer(overrides: [frenchLocale, 
      serialTransportProvider.overrideWithValue(BoardTransport(board)),
      storageRootProvider.overrideWith((ref) => storage),
    ]);
    await store.createProject('p');
  });

  tearDown(() {
    container.dispose();
    storage.deleteSync(recursive: true);
  });

  MicroPythonController micro() => container.read(microPythonProvider.notifier);
  MicroPythonState state() => container.read(microPythonProvider);

  Future<void> connect() async {
    await micro().refreshDevices();
    await micro().connect();
    expect(state().isReady, isTrue, reason: 'connexion raw REPL : ${state().log.map((e) => e.text).join(' | ')}');
  }

  bool logged(String fragment) => state().log.any((e) => e.text.contains(fragment));

  group('envoi vers la carte', () {
    test('un fichier de projet arrive intact, avec progression puis barre effacée', () async {
      final data = bytes(1000);
      await store.writeBytes('p', 'lib/capteur.bin', data);
      await connect();
      final seen = <TransferProgress>[];
      container.listen(microPythonProvider.select((s) => s.transfer), (_, next) {
        if (next != null) seen.add(next);
      });

      final ok = await micro().uploadFromProject('p', 'lib/capteur.bin');

      expect(ok, isTrue);
      expect(disk.files['/capteur.bin'], data);
      expect(seen, isNotEmpty);
      expect(seen.first.direction, TransferDirection.upload);
      expect(seen.first.name, 'capteur.bin');
      expect(seen.last.done, 1000);
      expect(seen.last.fraction, 1.0);
      expect([for (var i = 1; i < seen.length; i++) seen[i].done >= seen[i - 1].done].every((x) => x), isTrue);
      expect(state().transfer, isNull);
      expect(state().files.map((f) => f.name), contains('capteur.bin'));
      expect(logged('CRC32 vérifié'), isTrue);
    });

    test('un fichier de 100 Ko est envoyé, vérifié et relu à l\'identique', () async {
      final data = bytes(100 * 1024, 3);
      await store.writeBytes('p', 'gros.bin', data);
      await connect();

      expect(await micro().uploadFromProject('p', 'gros.bin'), isTrue);

      expect(disk.files['/gros.bin'], data);
      expect(await micro().readBytes('gros.bin'), data);
    });

    test('un octet altéré en route est détecté et l\'envoi est refait', () async {
      final data = bytes(900, 5);
      await store.writeBytes('p', 'a.bin', data);
      await connect();
      disk.corruptWrites = 1;

      expect(await micro().uploadFromProject('p', 'a.bin'), isTrue);

      expect(disk.files['/a.bin'], data);
    });

    test('un fichier local absent est signalé sans toucher la carte', () async {
      await connect();

      expect(await micro().uploadFromProject('p', 'absent.py'), isFalse);

      expect(disk.files, isEmpty);
      expect(state().errorMessage, contains('absent.py'));
    });

    test('un envoi dans un sous-dossier de la carte utilise le dossier courant', () async {
      await store.writeText('p', 'main.py', 'print(1)');
      disk.dirs.add('/lib');
      await connect();
      await micro().openDirectory('lib');

      await micro().uploadFromProject('p', 'main.py');

      expect(disk.files.keys, ['/lib/main.py']);
    });

    test('câble arraché pendant l\'envoi : signalé, jamais présenté comme réussi', () async {
      final data = bytes(8000, 9);
      await store.writeBytes('p', 'long.bin', data);
      await connect();
      var unplugged = false;
      container.listen(microPythonProvider.select((s) => s.transfer), (_, next) {
        if (next != null && next.done >= 800 && !unplugged) {
          unplugged = true;
          board.unplug();
        }
      });

      final ok = await micro().uploadFromProject('p', 'long.bin');

      expect(ok, isFalse);
      expect(unplugged, isTrue);
      expect(state().transfer, isNull);
      expect(logged('Écrit /long.bin'), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(state().status, ReplStatus.disconnected);
      expect(state().errorMessage, isNotNull);
      expect(disk.files['/long.bin']?.length ?? 0, lessThan(data.length), reason: 'le fichier est incomplet, et l\'app le sait');
    });
  });

  group('téléchargement depuis la carte', () {
    Future<RemoteEntry> remoteEntry(String name) async {
      await micro().refreshFiles();
      return state().files.firstWhere((f) => f.name == name);
    }

    test('le fichier est enregistré dans le projet, avec progression et CRC vérifié', () async {
      final data = bytes(1500, 11);
      disk.files['/photo.bin'] = data;
      await connect();
      final seen = <TransferProgress>[];
      container.listen(microPythonProvider.select((s) => s.transfer), (_, next) {
        if (next != null) seen.add(next);
      });

      final ok = await micro().downloadToProject(await remoteEntry('photo.bin'), 'p', 'recu/photo.bin');

      expect(ok, isTrue);
      expect(await store.readBytes('p', 'recu/photo.bin'), data);
      expect(seen.first.direction, TransferDirection.download);
      expect(seen.last.done, 1500);
      expect(state().transfer, isNull);
      expect(logged('CRC32 vérifié'), isTrue);
    });

    test('un nom local invalide est refusé et rien n\'est écrit', () async {
      disk.files['/a.py'] = bytes(10);
      await connect();

      final ok = await micro().downloadToProject(await remoteEntry('a.py'), 'p', 'a:b.py');

      expect(ok, isFalse);
      expect(Directory('${storage.path}/projects/p').listSync(), isEmpty);
      expect(state().errorMessage, contains('a:b.py'));
    });

    test('le téléchargement vers un projet absent est refusé', () async {
      disk.files['/a.py'] = bytes(10);
      await connect();

      expect(await micro().downloadToProject(await remoteEntry('a.py'), 'fantome', 'a.py'), isFalse);
    });

    test('un fichier disparu de la carte est signalé', () async {
      disk.files['/a.py'] = bytes(10);
      await connect();
      final entry = await remoteEntry('a.py');
      disk.files.remove('/a.py');

      expect(await micro().downloadToProject(entry, 'p', 'a.py'), isFalse);

      expect(state().errorMessage, isNotNull);
      expect(await store.exists('p', 'a.py'), isFalse);
    });

    test('câble arraché pendant le téléchargement : rien d\'enregistré', () async {
      disk.files['/long.bin'] = bytes(60000, 2);
      await connect();
      final entry = await remoteEntry('long.bin');
      var unplugged = false;
      container.listen(microPythonProvider.select((s) => s.transfer), (_, next) {
        if (next != null && next.done > 0 && !unplugged) {
          unplugged = true;
          board.unplug();
        }
      });

      final ok = await micro().downloadToProject(entry, 'p', 'long.bin');

      expect(ok, isFalse);
      expect(await store.exists('p', 'long.bin'), isFalse, reason: 'un fichier tronqué ne doit jamais être enregistré');
      expect(state().transfer, isNull);
    });
  });

  group('renommage sur la carte', () {
    test('renomme un fichier et rafraîchit la liste', () async {
      disk.files['/ancien.py'] = bytes(5);
      await connect();
      await micro().refreshFiles();

      await micro().renameEntry(state().files.single, 'nouveau.py');

      expect(disk.files.keys, ['/nouveau.py']);
      expect(state().files.map((f) => f.name), ['nouveau.py']);
    });

    test('renommer un fichier absent est signalé', () async {
      disk.files['/a.py'] = bytes(5);
      await connect();
      await micro().refreshFiles();
      final entry = state().files.single;
      disk.files.remove('/a.py');

      await micro().renameEntry(entry, 'b.py');

      expect(state().errorMessage, isNotNull);
    });
  });

  group('intégration projets', () {
    test('télécharger vers un nouveau projet puis le retrouver dans la liste', () async {
      disk.files['/main.py'] = Uint8List.fromList('print("salut")'.codeUnits);
      await connect();
      await micro().refreshFiles();
      final projects = container.read(projectsProvider.notifier);

      await projects.createProject('Depuis la carte');
      final ok = await micro().downloadToProject(state().files.single, 'Depuis la carte', 'main.py');
      await projects.refresh();

      expect(ok, isTrue);
      expect(container.read(projectsProvider).current, 'Depuis la carte');
      expect(container.read(projectsProvider).entries.single.name, 'main.py');
    });
  });
}
