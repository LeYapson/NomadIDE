import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_cloud_compiler/nomad_cloud_compiler.dart';
import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:nomad_mcu/features/compile/local/local_build_runner.dart';
import 'package:nomad_mcu/features/compile/local/local_compile_api.dart';
import 'package:nomad_mcu/features/compile/local/local_toolchain.dart';
import 'package:path/path.dart' as p;

Uint8List zipOf(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, content) => archive.add(ArchiveFile.bytes(name, utf8.encode(content))));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('nomad_toolchain_'));
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  group('archive officielle', () {
    test('nom selon le système', () {
      expect(arduinoCliArchiveName(os: 'windows', arch: 'x64'), 'arduino-cli_${arduinoCliVersion}_Windows_64bit.zip');
      expect(arduinoCliArchiveName(os: 'macos', arch: 'arm64'), 'arduino-cli_${arduinoCliVersion}_macOS_ARM64.tar.gz');
      expect(arduinoCliArchiveName(os: 'linux', arch: 'x64'), 'arduino-cli_${arduinoCliVersion}_Linux_64bit.tar.gz');
      expect(arduinoCliArchiveName(os: 'windows', arch: 'arm64'), isNull);
    });

    test('empreinte lue dans le fichier de la version', () {
      const text = 'aaa111  arduino-cli_1.5.1_Linux_64bit.tar.gz\nBBB222 *arduino-cli_1.5.1_Windows_64bit.zip\n';
      expect(checksumFor(text, 'arduino-cli_1.5.1_Windows_64bit.zip'), 'bbb222');
      expect(checksumFor(text, 'arduino-cli_1.5.1_Linux_64bit.tar.gz'), 'aaa111');
      expect(checksumFor(text, 'inconnu.zip'), isNull);
    });
  });

  group('installation d\'arduino-cli', () {
    Downloader serving(Uint8List archive, {String? checksum}) => (url, {required maxBytes, onProgress}) async {
          if (url.path.endsWith('checksums.txt')) {
            final name = arduinoCliArchiveName(os: 'windows', arch: 'x64')!;
            return Uint8List.fromList(utf8.encode('${checksum ?? sha256.convert(archive)}  $name\n'));
          }
          return archive;
        };

    test('empreinte différente : refusé, rien n\'est installé', () async {
      final archive = zipOf({'arduino-cli.exe': 'MZ'});
      final toolchain = LocalToolchain(root, os: 'windows', arch: 'x64', download: serving(archive, checksum: '0' * 64));

      await expectLater(toolchain.install().drain<void>(), throwsA(isA<ToolchainException>().having((e) => e.message, 'message', contains('empreinte'))));
      expect(toolchain.cliInstalled, isFalse);
    });

    test('archive sans l\'exécutable attendu : refusée', () async {
      final archive = zipOf({'autre.txt': 'x'});
      final toolchain = LocalToolchain(root, os: 'windows', arch: 'x64', download: serving(archive));
      await expectLater(toolchain.install().drain<void>(), throwsA(isA<ToolchainException>()));
      expect(toolchain.cliInstalled, isFalse);
    });

    test('empreinte juste : l\'exécutable est installé (sans fichier partiel)', () async {
      final archive = zipOf({'arduino-cli.exe': 'MZ', 'LICENSE.txt': 'x'});
      final toolchain = LocalToolchain(root, os: 'windows', arch: 'x64', download: serving(archive));
      // L'exécutable de ce test n'est pas un vrai programme : l'étape suivante échoue, ce qui nous suffit.
      await toolchain.install().drain<void>().then((_) {}, onError: (Object _) {});
      expect(toolchain.cliInstalled, isTrue);
      expect(File('${toolchain.cli.path}.part').existsSync(), isFalse);
    });
  });

  group('cœurs', () {
    test('un cœur est installé quand il a une version sur le disque', () {
      final toolchain = LocalToolchain(root, os: 'windows', arch: 'x64');
      expect(toolchain.missingCores, ['esp32:esp32', 'rp2040:rp2040']);
      Directory(p.join(toolchain.packagesDir.path, 'esp32', 'hardware', 'esp32', '3.3.12')).createSync(recursive: true);
      expect(toolchain.coreInstalled('esp32:esp32'), isTrue);
      expect(toolchain.missingCores, ['rp2040:rp2040']);
      expect(toolchain.ready, isFalse);
    });

    test('tout reste dans le dossier de l\'app', () {
      final env = LocalToolchain(root, os: 'windows', arch: 'x64').environment;
      for (final key in ['ARDUINO_DIRECTORIES_DATA', 'ARDUINO_DIRECTORIES_USER', 'ARDUINO_DIRECTORIES_DOWNLOADS', 'ARDUINO_BUILD_CACHE_PATH']) {
        expect(p.isWithin(root.path, env[key]!), isTrue, reason: key);
      }
    });
  });

  test('commande de compilation : carte, dossier de build, bibliothèques et croquis', () {
    final toolchain = LocalToolchain(root, os: 'linux', arch: 'x64');
    final request = RunRequest(
      id: 'abcdef0123456789',
      board: CompileBoard.esp32s3,
      sketchName: 'blink',
      sketchDir: Directory(p.join(root.path, 'sketch')),
      outDir: Directory(p.join(root.path, 'out')),
      libraries: [Directory(p.join(root.path, 'libs', 'DHT'))],
    );
    final args = LocalBuildRunner(toolchain).arguments(request, Directory(p.join(root.path, 'b')));
    expect(args.take(3), ['compile', '--fqbn', CompileBoard.esp32s3.fqbn]);
    expect(args, containsAllInOrder(['--build-path', p.join(root.path, 'b')]));
    expect(args, containsAllInOrder(['--library', p.join(root.path, 'libs', 'DHT')]));
    expect(args.last, request.sketchDir.path);
  });

  test('service local : répond comme un serveur, et sans outillage explique pourquoi la compilation ne part pas', () async {
    final toolchain = LocalToolchain(root, os: 'windows', arch: 'x64');
    final api = LocalCompileApi(toolchain);
    addTearDown(api.close);

    final info = await api.health();
    expect(info.boards, containsAll(CompileBoard.values));

    final status = await api.submit(zipOf({'blink/blink.ino': 'void setup(){}\nvoid loop(){}'}), CompileBoard.esp32);
    var current = status;
    for (var i = 0; i < 100 && !current.state.isFinished; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      current = await api.status(status.id);
    }
    expect(current.state, BuildState.failed);
    expect(current.log, contains("n'est pas installé"));
  });
}
