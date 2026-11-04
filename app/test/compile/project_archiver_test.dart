import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:nomad_mcu/features/compile/data/project_archiver.dart';
import 'package:nomad_mcu/features/compile/data/project_config.dart';
import 'package:nomad_mcu/features/projects/data/project_store.dart';

void main() {
  late Directory storage;
  late ProjectStore store;

  setUp(() {
    storage = Directory.systemTemp.createTempSync('nomad_archiver_test');
    store = ProjectStore(storage);
  });
  tearDown(() => storage.deleteSync(recursive: true));

  test('isExcludedFromBuild : dossiers cachés et build', () {
    expect(isExcludedFromBuild('.git/config'), isTrue);
    expect(isExcludedFromBuild('src/.cache/x'), isTrue);
    expect(isExcludedFromBuild('build/a.bin'), isTrue);
    expect(isExcludedFromBuild('src/build/a.o'), isTrue);
    expect(isExcludedFromBuild('src/builder.cpp'), isFalse);
    expect(isExcludedFromBuild('blink.ino'), isFalse);
  });

  test('le contenu du zip est celui des fichiers du projet', () async {
    await store.createProject('p');
    await store.writeText('p', 'p.ino', 'void setup(){}');
    await store.writeText('p', 'lib/Util.h', '#pragma once');

    final package = await packageProject(store, 'p', maxZipBytes: 1 << 20);

    final files = {for (final f in ZipDecoder().decodeBytes(package.zip).files) f.name: String.fromCharCodes(f.content as List<int>)};
    expect(files, {'p.ino': 'void setup(){}', 'lib/Util.h': '#pragma once'});
    expect(package.rawBytes, 'void setup(){}'.length + '#pragma once'.length);
    expect(package.mainSketch, 'p');
  });

  test('zip plus gros que la limite du service', () async {
    await store.createProject('p');
    await store.writeText('p', 'p.ino', List.generate(2000, (i) => 'int v$i = ${i * 7919};').join('\n'));
    await expectLater(packageProject(store, 'p', maxZipBytes: 64), throwsA(isA<ProjectTooLargeException>()));
  });

  group('ProjectConfig', () {
    test('sans fichier, ou illisible : pas de carte', () async {
      await store.createProject('p');
      expect((await ProjectConfig.read(store, 'p')).board, isNull);
      await store.writeText('p', 'nomad.json', '{ pas du json');
      expect((await ProjectConfig.read(store, 'p')).board, isNull);
    });

    test('écrire la carte garde les autres clés du fichier', () async {
      await store.createProject('p');
      await store.writeText('p', 'nomad.json', '{"autre": 42, "board": "esp32"}');

      await ProjectConfig.writeBoard(store, 'p', CompileBoard.rp2040);

      expect((await ProjectConfig.read(store, 'p')).board, CompileBoard.rp2040);
      expect(await store.readText('p', 'nomad.json'), contains('"autre": 42'));
    });
  });
}
