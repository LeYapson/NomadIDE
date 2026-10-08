import 'dart:convert';
import 'dart:typed_data';

import 'package:nomad_protocols/nomad_protocols.dart';
import 'package:test/test.dart';

import 'support/fake_fs_program.dart';
import 'support/fake_raw_repl_board.dart';

const fast = RawReplOptions(
  settleDelay: Duration.zero,
  enterTimeout: Duration(milliseconds: 100),
  ackTimeout: Duration(milliseconds: 200),
  interruptTimeout: Duration(milliseconds: 200),
  chunkDelay: Duration.zero,
);

void main() {
  late FakeDisk disk;
  late FakeRawReplBoard board;
  late RawRepl repl;
  late MicroPythonFs fs;

  setUp(() async {
    disk = FakeDisk();
    board = FakeRawReplBoard(run: disk.run);
    repl = RawRepl(board, options: fast);
    fs = MicroPythonFs(repl, chunkSize: 100);
    await repl.enter();
  });

  tearDown(() => repl.dispose());

  // Tous les octets, y compris Ctrl-C / Ctrl-D que le raw REPL ne laisserait pas passer.
  Uint8List binary(int length) => Uint8List.fromList(List.generate(length, (i) => i % 256));

  test('write puis read restituent des octets arbitraires, sur plusieurs morceaux', () async {
    final data = binary(1000);
    final progress = <int>[];

    await fs.write('/main.py', data, onProgress: (sent, _) => progress.add(sent));
    final back = await fs.read('/main.py');

    expect(back, data);
    expect(disk.files['/main.py'], data);
    expect(progress.first, 100);
    expect(progress.last, 1000);
    expect(progress, hasLength(10));
  });

  test('write remplace le contenu existant', () async {
    await fs.write('/a.txt', binary(250));
    await fs.write('/a.txt', Uint8List.fromList(utf8.encode('court')));

    expect(utf8.decode(await fs.read('/a.txt')), 'court');
  });

  test("un fichier vide s'écrit et se relit", () async {
    await fs.write('/vide', Uint8List(0));

    expect(disk.files['/vide'], isEmpty);
    expect(await fs.read('/vide'), isEmpty);
  });

  test('read signale la progression', () async {
    disk.files['/g'] = binary(600);
    final seen = <int>[];

    await fs.read('/g', onProgress: seen.add);

    expect(seen, isNotEmpty);
    expect(seen.last, greaterThan(0));
  });

  test('list distingue fichiers et dossiers', () async {
    disk.dirs.add('/lib');
    disk.files['/main.py'] = binary(42);

    final entries = await fs.list('/');

    expect(entries.map((e) => e.name), unorderedEquals(['lib', 'main.py']));
    expect(entries.firstWhere((e) => e.name == 'lib').isDirectory, isTrue);
    final main = entries.firstWhere((e) => e.name == 'main.py');
    expect(main.isDirectory, isFalse);
    expect(main.size, 42);
  });

  test('exists renvoie vrai/faux sans lever pour un fichier absent', () async {
    disk.files['/x'] = Uint8List(1);

    expect(await fs.exists('/x'), isTrue);
    expect(await fs.exists('/absent'), isFalse);
  });

  test("read d'un fichier absent lève ProtocolRemoteException ENOENT", () async {
    await expectLater(
      fs.read('/absent'),
      throwsA(isA<ProtocolRemoteException>()
          .having((e) => e.errno, 'errno', 2)
          .having((e) => e.isNotFound, 'isNotFound', isTrue)
          .having((e) => e.message, 'message', contains('ENOENT'))),
    );
    expect(repl.state, RawReplState.ready);
  });

  test('mkdir, rename, remove, rmdir', () async {
    await fs.mkdir('/data');
    await fs.write('/data/a', binary(10));
    await fs.rename('/data/a', '/data/b');

    expect(disk.files.keys, ['/data/b']);

    await fs.remove('/data/b');
    await fs.rmdir('/data');

    expect(disk.files, isEmpty);
    expect(disk.dirs, {'/'});
  });

  test('mkdir sur un dossier existant lève EEXIST (errno 17)', () async {
    await fs.mkdir('/d');

    await expectLater(fs.mkdir('/d'), throwsA(isA<ProtocolRemoteException>().having((e) => e.errno, 'errno', 17)));
  });

  test('les chemins avec apostrophe, antislash et accents sont échappés', () async {
    const path = r"/l'été\x.txt";
    final data = Uint8List.fromList(utf8.encode('ok'));

    await fs.write(path, data);

    expect(disk.files.keys, [path]);
    expect(await fs.read(path), data);
  });

  group('intégrité', () {
    test('crc32 correspond au vecteur de référence de binascii.crc32', () {
      expect(MicroPythonFs.crc32(utf8.encode('123456789')), 0xCBF43926);
      expect(MicroPythonFs.crc32(const []), 0);
    });

    test('checksum renvoie la taille et le CRC calculés par la carte', () async {
      disk.files['/f'] = binary(700);

      final sum = await fs.checksum('/f');

      expect(sum.size, 700);
      expect(sum.crc32, MicroPythonFs.crc32(binary(700)));
    });

    test('write avec verify réussit sur un lien sain', () async {
      await fs.write('/ok.bin', binary(450), verify: true, retries: 0);

      expect(disk.files['/ok.bin'], binary(450));
    });

    test('un octet altéré est détecté, puis corrigé par une nouvelle tentative', () async {
      disk.corruptWrites = 1;

      await fs.write('/retry.bin', binary(450), verify: true, retries: 1);

      expect(disk.files['/retry.bin'], binary(450));
    });

    test('sans tentative restante, ProtocolIntegrityException est levée', () async {
      disk.corruptWrites = 1;

      await expectLater(
        fs.write('/bad.bin', binary(450), verify: true, retries: 0),
        throwsA(isA<ProtocolIntegrityException>()
            .having((e) => e.expectedCrc, 'expectedCrc', MicroPythonFs.crc32(binary(450)))),
      );
    });

    test('sans verify, la corruption passe inaperçue (comportement de base)', () async {
      disk.corruptWrites = 1;

      await fs.write('/silent.bin', binary(450));

      expect(disk.files['/silent.bin'], isNot(binary(450)));
    });

    test('une erreur Python sans errno (base64 altéré) est retentée', () async {
      disk.garbledWrites = 1;

      await fs.write('/g.bin', binary(450), retries: 1);

      expect(disk.files['/g.bin'], binary(450));
    });

    test("une erreur d'OS (errno) n'est pas retentée", () async {
      var calls = 0;
      final failing = FakeRawReplBoard(run: (code) {
        calls++;
        return (stdout: '', stderr: 'Traceback\r\nOSError: [Errno 28] ENOSPC\r\n', hang: false);
      });
      final r = RawRepl(failing, options: fast);
      await r.enter();

      await expectLater(
        MicroPythonFs(r).write('/x', binary(10), retries: 3),
        throwsA(isA<ProtocolRemoteException>().having((e) => e.errno, 'errno', 28)),
      );
      expect(calls, 1);
      await r.dispose();
    });
  });
}
