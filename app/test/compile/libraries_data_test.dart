import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:nomad_mcu/features/compile/data/include_scanner.dart';
import 'package:nomad_mcu/features/compile/data/project_config.dart';
import 'package:nomad_mcu/features/projects/data/project_store.dart';

void main() {
  group('includesOf', () {
    test('chevrons et guillemets, espaces, doublons', () {
      const source = '''
#include <DHT.h>
#include "capteur.h"
  #  include   <Wire.h>
#include <DHT.h>
// #include <Commentaire.h>
#include<Adafruit_Sensor.h>
int x = 1; // #include <Pas.h>
''';
      expect(includesOf(source), ['DHT.h', 'capteur.h', 'Wire.h', 'Adafruit_Sensor.h'], reason: 'un include en commentaire ne compte pas');
    });

    test('sans include', () => expect(includesOf('void setup(){}'), isEmpty));
  });

  group('externalIncludes', () {
    late Directory storage;
    late ProjectStore store;

    setUp(() {
      storage = Directory.systemTemp.createTempSync('nomad_scan_test');
      store = ProjectStore(storage);
    });
    tearDown(() => storage.deleteSync(recursive: true));

    test('ignore les fichiers du projet, les dossiers cachés et build, regarde les sous-dossiers', () async {
      await store.createProject('p');
      await store.writeText('p', 'p.ino', '#include <DHT.h>\n#include "capteur.h"\n#include <Wire.h>\n');
      await store.writeText('p', 'capteur.h', '#include <Adafruit_Sensor.h>\n');
      await store.writeText('p', 'src/util.cpp', '#include <ArduinoJson.h>\n#include "capteur.h"\n');
      await store.writeText('p', '.git/x.h', '#include <Cache.h>\n');
      await store.writeText('p', 'build/y.cpp', '#include <Build.h>\n');
      await store.writeText('p', 'notes.txt', '#include <Texte.h>\n');

      expect(await externalIncludes(store, 'p'), ['Adafruit_Sensor.h', 'ArduinoJson.h', 'DHT.h', 'Wire.h']);
    });

    test('un en-tête avec un chemin désigne le fichier du même nom dans le projet', () async {
      await store.createProject('p');
      await store.writeText('p', 'p.ino', '#include "lib/capteur.h"\n#include <Servo.h>\n');
      await store.writeText('p', 'lib/capteur.h', '// ici\n');
      expect(await externalIncludes(store, 'p'), ['Servo.h']);
    });
  });

  group('missingHeadersIn', () {
    test('messages du compilateur', () {
      expect(
        missingHeadersIn([
          'DHT.h: No such file or directory',
          'fatal error: Adafruit_SSD1306.h: No such file or directory',
          'autre erreur',
          'sub/Dir/Thing.hpp: No such file or directory',
          'DHT.h: No such file or directory',
        ]),
        ['DHT.h', 'Adafruit_SSD1306.h', 'sub/Dir/Thing.hpp'],
      );
      expect(missingHeadersIn(['\'foo\' was not declared in this scope']), isEmpty);
    });
  });

  group('nomad.json : bibliothèques', () {
    late Directory storage;
    late ProjectStore store;

    setUp(() {
      storage = Directory.systemTemp.createTempSync('nomad_cfg_test');
      store = ProjectStore(storage);
    });
    tearDown(() => storage.deleteSync(recursive: true));

    const dht = LibraryRef(name: 'DHT sensor library', version: '1.4.7');
    const unified = LibraryRef(name: 'Adafruit Unified Sensor', version: '1.1.15');

    test('écrire puis relire, en gardant la carte et les autres clés', () async {
      await store.createProject('p');
      await store.writeText('p', 'nomad.json', '{"board": "esp32s3", "autre": 1}');

      await ProjectConfig.writeLibraries(store, 'p', [dht, unified], ['DHT sensor library']);

      final config = await ProjectConfig.read(store, 'p');
      expect(config.board, CompileBoard.esp32s3);
      expect(config.libraries, [dht, unified]);
      expect(config.roots, ['DHT sensor library']);
      expect(config.chosenNames, ['DHT sensor library']);
      final raw = jsonDecode(await store.readText('p', 'nomad.json')) as Map;
      expect(raw['autre'], 1);
    });

    test('sans roots (fichier écrit à la main) : toutes les bibliothèques comptent comme choisies', () async {
      await store.createProject('p');
      await store.writeText('p', 'nomad.json', '{"libraries": [{"name": "A", "version": "1.0"}, {"name": "B", "version": "2.0"}]}');
      final config = await ProjectConfig.read(store, 'p');
      expect(config.chosenNames, ['A', 'B']);
    });

    test('liste vide : les clés disparaissent du fichier', () async {
      await store.createProject('p');
      await ProjectConfig.writeLibraries(store, 'p', [dht], ['DHT sensor library']);
      await ProjectConfig.writeBoard(store, 'p', CompileBoard.rp2040);
      await ProjectConfig.writeLibraries(store, 'p', [], []);

      final raw = jsonDecode(await store.readText('p', 'nomad.json')) as Map;
      expect(raw.containsKey('libraries'), isFalse);
      expect(raw.containsKey('librariesRoots'), isFalse);
      expect(raw['board'], 'rp2040');
    });

    test('écrire la carte garde les bibliothèques', () async {
      await store.createProject('p');
      await ProjectConfig.writeLibraries(store, 'p', [dht], ['DHT sensor library']);
      await ProjectConfig.writeBoard(store, 'p', CompileBoard.esp32s2);
      final config = await ProjectConfig.read(store, 'p');
      expect(config.libraries, [dht]);
      expect(config.board, CompileBoard.esp32s2);
    });

    test('entrées incomplètes ignorées, fichier illisible : rien', () async {
      await store.createProject('p');
      await store.writeText('p', 'nomad.json', '{"libraries": [{"name": "A"}, {"version": "1"}, 3, {"name": "B", "version": "2"}]}');
      expect((await ProjectConfig.read(store, 'p')).libraries, [const LibraryRef(name: 'B', version: '2')]);
      await store.writeText('p', 'nomad.json', '{ pas du json');
      expect((await ProjectConfig.read(store, 'p')).libraries, isEmpty);
    });
  });
}
