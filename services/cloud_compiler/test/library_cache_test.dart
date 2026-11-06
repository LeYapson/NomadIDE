import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:nomad_cloud_compiler/nomad_cloud_compiler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'libraries_support.dart';

void main() {
  late Directory root;
  late List<Uri> downloads;
  late Uint8List zip;

  setUp(() {
    root = Directory.systemTemp.createTempSync('nomad_libcache_');
    downloads = [];
    zip = libraryZip();
  });
  tearDown(() => root.deleteSync(recursive: true));

  LibraryCache cacheServing(Uint8List Function() bytes) => LibraryCache(
        root: root,
        download: (url, {required maxBytes}) async {
          downloads.add(url);
          return bytes();
        },
      );

  test('installe depuis l\'archive : dossier englobant retiré, nom de dossier sûr', () async {
    final cache = cacheServing(() => zip);
    final dir = await cache.ensure(releaseFor(zip));

    expect(p.basename(dir.path), 'DHT_sensor_library');
    expect(File(p.join(dir.path, 'library.properties')).existsSync(), isTrue);
    expect(File(p.join(dir.path, 'src', 'DHT.h')).readAsStringSync(), '#pragma once\n');
    expect(Directory(p.join(dir.path, 'DHT-sensor-library-1.4.6')).existsSync(), isFalse);
    expect(root.listSync().whereType<Directory>().where((d) => p.basename(d.path).startsWith('.tmp')), isEmpty);
  });

  test('une version déjà installée n\'est pas retéléchargée, même avec un nouveau cache sur le même dossier', () async {
    final release = releaseFor(zip);
    await cacheServing(() => zip).ensure(release);
    expect(downloads, hasLength(1));

    final again = cacheServing(() => zip);
    expect(again.installed(release), isNotNull);
    await again.ensure(release);
    expect(downloads, hasLength(1));
  });

  test('plusieurs demandes simultanées ne téléchargent qu\'une fois', () async {
    final cache = cacheServing(() => zip);
    final release = releaseFor(zip);
    final dirs = await Future.wait([cache.ensure(release), cache.ensure(release), cache.ensure(release)]);
    expect(downloads, hasLength(1));
    expect(dirs.map((d) => d.path).toSet(), hasLength(1));
  });

  test('empreinte différente : refusé, rien n\'est installé', () async {
    final tampered = Uint8List.fromList(zip)..[zip.length ~/ 2] ^= 0xFF; // même taille, contenu différent
    final release = releaseFor(zip); // annonce l'empreinte de l'archive d'origine
    final cache = cacheServing(() => tampered);

    await expectLater(cache.ensure(release), throwsA(isA<LibraryInstallException>().having((e) => e.message, 'message', contains('Empreinte'))));
    expect(cache.installed(release), isNull);
    expect(root.listSync().where((e) => !p.basename(e.path).startsWith('.tmp')), isEmpty);
  });

  test('taille différente de celle de l\'index : refusé', () async {
    final release = LibraryIndex.parse(indexJson([
      releaseJson('DHT sensor library', '1.4.6', size: zip.length + 5, checksum: 'SHA-256:${sha256Of(zip)}'),
    ])).release('DHT sensor library', '1.4.6')!;
    await expectLater(cacheServing(() => zip).ensure(release), throwsA(isA<LibraryInstallException>().having((e) => e.message, 'message', contains('Taille'))));
  });

  test('adresse hors de l\'hôte autorisé ou en clair : refusée avant tout téléchargement', () async {
    final cache = cacheServing(() => zip);
    for (final url in ['https://evil.example.com/x.zip', 'http://downloads.arduino.cc/x.zip', 'file:///etc/passwd']) {
      await expectLater(cache.ensure(releaseFor(zip, url: url)), throwsA(isA<LibraryInstallException>()), reason: url);
    }
    expect(downloads, isEmpty);
  });

  test('archive sans library.properties, chemins sortants, liens symboliques : refusés', () async {
    Future<void> rejects(Uint8List bad) async {
      final release = releaseFor(bad);
      await expectLater(cacheServing(() => bad).ensure(release), throwsA(isA<LibraryInstallException>()));
      expect(cacheServing(() => bad).installed(release), isNull);
    }

    await rejects(libraryZip(files: {'src/DHT.h': 'x'}));
    await rejects(libraryZip(top: '', files: {'library.properties': 'name=A\n', '../evil.txt': 'x'}));
    final withLink = Archive()
      ..add(ArchiveFile.bytes('lib/library.properties', [110]))
      ..add(ArchiveFile.symlink('lib/lien', '/etc/passwd'));
    await rejects(Uint8List.fromList(ZipEncoder().encode(withLink)));
    expect(File(p.join(root.parent.path, 'evil.txt')).existsSync(), isFalse);
  });

  test('archive sans dossier englobant', () async {
    final flat = libraryZip(top: '');
    final dir = await cacheServing(() => flat).ensure(releaseFor(flat));
    expect(File(p.join(dir.path, 'library.properties')).existsSync(), isTrue);
  });

  test('téléchargement qui échoue : message clair', () async {
    final cache = LibraryCache(root: root, download: (url, {required maxBytes}) async => throw const SocketException('hors ligne'));
    await expectLater(cache.ensure(releaseFor(zip)), throwsA(isA<LibraryInstallException>().having((e) => e.message, 'message', contains('Téléchargement impossible'))));
  });

  test('libraryDirName', () {
    expect(LibraryCache.libraryDirName('DHT sensor library'), 'DHT_sensor_library');
    expect(LibraryCache.libraryDirName('Adafruit GFX Library'), 'Adafruit_GFX_Library');
    expect(LibraryCache.libraryDirName('../évil'), isNot(contains('/')));
    expect(LibraryCache.libraryDirName('.hidden'), isNot(startsWith('.')));
  });
}
