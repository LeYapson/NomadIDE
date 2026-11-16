import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nomad_cloud_compiler/nomad_cloud_compiler.dart';
import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'libraries_support.dart';
import 'support.dart';

void main() {
  late Directory work;
  late Uint8List dhtZip;
  late Uint8List plainZip;

  setUp(() {
    work = Directory.systemTemp.createTempSync('nomad_examples_');
    dhtZip = libraryZip(files: {
      'library.properties': 'name=DHT sensor library\n',
      'src/DHT.h': '#pragma once\n',
      'examples/DHTtester/DHTtester.ino': '#include <DHT.h>\nvoid setup() {}\nvoid loop() {}\n',
      'examples/DHTtester/helper.h': '#pragma once\n',
      'examples/DHTtester/notes.txt': 'pas un fichier de code',
      'examples/Sub/Nested/Nested.ino': 'void setup() {}\nvoid loop() {}\n',
      'examples/NoSketch/readme.txt': 'aucun croquis ici',
      'examples/Wrong/Other.ino': '// le nom ne correspond pas au dossier\n',
      'examples/apple/apple.ino': '// tri sans tenir compte de la casse\n',
    });
    plainZip = libraryZip(top: 'Plain-1.0.0', files: {'library.properties': 'name=Plain\n', 'Plain.h': '#pragma once\n'});
  });
  tearDown(() => work.deleteSync(recursive: true));

  LibraryService service() {
    final downloads = <String, Uint8List>{
      'DHT_sensor_library-1.4.6.zip': dhtZip,
      'Plain-1.0.0.zip': plainZip,
    };
    return LibraryService(
      indexFile: File(p.join(work.path, 'library_index.json')),
      fetch: () async => indexJson([
        entryFor('DHT sensor library', '1.4.6', dhtZip),
        entryFor('Plain', '1.0.0', plainZip),
      ]),
      cache: LibraryCache(
        root: Directory(p.join(work.path, 'libs')),
        download: (url, {required maxBytes}) async => downloads[url.pathSegments.last] ?? (throw StateError('inattendu : $url')),
      ),
    );
  }

  Future<LibraryService> started() async {
    final svc = service();
    await svc.start();
    svc.dispose();
    return svc;
  }

  group('LibraryService', () {
    test('liste les dossiers qui contiennent un croquis du même nom, triés sans tenir compte de la casse', () async {
      final found = await (await started()).examples('DHT sensor library');
      expect(found!.library, 'DHT sensor library');
      expect(found.version, '1.4.6');
      expect([for (final e in found.examples) e.path], ['apple', 'DHTtester', 'Sub/Nested']);
      expect(found.examples.last.name, 'Nested');
    });

    test('une bibliothèque sans exemples : liste vide, pas une erreur', () async {
      final found = await (await started()).examples('Plain');
      expect(found!.examples, isEmpty);
    });

    test('bibliothèque ou version inconnue : null', () async {
      final svc = await started();
      expect(await svc.examples('Nope'), isNull);
      expect(await svc.examples('DHT sensor library', version: '9.9.9'), isNull);
    });

    test('les fichiers d\'un exemple : code seulement, croquis compris', () async {
      final files = await (await started()).exampleFiles('DHT sensor library', path: 'DHTtester');
      expect([for (final f in files!.files) f.name], ['DHTtester.ino', 'helper.h']); // notes.txt n'est pas du code
      expect(files.files.first.content, contains('#include <DHT.h>'));
      expect(files.version, '1.4.6');
    });

    test('un exemple dans un sous-dossier se lit par son chemin', () async {
      final files = await (await started()).exampleFiles('DHT sensor library', path: 'Sub/Nested');
      expect([for (final f in files!.files) f.name], ['Nested.ino']);
    });

    test('un chemin qui n\'est pas dans la liste n\'est jamais lu', () async {
      final svc = await started();
      for (final path in ['../library.properties', '../../etc/passwd', 'NoSketch', 'Wrong', 'src', '', 'dhttester']) {
        expect(await svc.exampleFiles('DHT sensor library', path: path), isNull, reason: path);
      }
    });
  });

  group('routes', () {
    late ServerConfig config;
    late JobManager jobs;

    setUp(() {
      config = testConfig(work);
      jobs = JobManager(config: config, runner: succeedingRunner());
    });
    tearDown(() => jobs.dispose());

    Future<Response> call(Handler handler, String path, {bool authorized = true}) => Future.sync(() async => handler(Request(
          'GET',
          Uri.parse('http://x$path'),
          headers: authorized ? {'authorization': 'Bearer ${config.token}'} : null,
        )));

    Future<Handler> handler() async => buildHandler(config: config, jobs: jobs, libraries: await started());

    test('demandent le jeton', () async {
      final h = await handler();
      expect((await call(h, '/v1/libraries/Plain/examples', authorized: false)).statusCode, 401);
      expect((await call(h, '/v1/libraries/Plain/example?path=x', authorized: false)).statusCode, 401);
    });

    test('GET …/examples : la liste, avec la version utilisée', () async {
      final r = await call(await handler(), '/v1/libraries/${Uri.encodeComponent('DHT sensor library')}/examples');
      expect(r.statusCode, 200);
      final body = LibraryExamples.fromJson(jsonDecode(await r.readAsString()) as Map<String, Object?>);
      expect(body.version, '1.4.6');
      expect([for (final e in body.examples) e.path], ['apple', 'DHTtester', 'Sub/Nested']);
    });

    test('GET …/example?path= : les fichiers', () async {
      final r = await call(await handler(), '/v1/libraries/${Uri.encodeComponent('DHT sensor library')}/example?path=DHTtester');
      expect(r.statusCode, 200);
      final body = LibraryExampleFiles.fromJson(jsonDecode(await r.readAsString()) as Map<String, Object?>);
      expect(body.files.map((f) => f.name), ['DHTtester.ino', 'helper.h']);
    });

    test('bibliothèque inconnue, exemple inconnu, chemin absent : 404, 404, 400', () async {
      final h = await handler();
      expect((await call(h, '/v1/libraries/Nope/examples')).statusCode, 404);
      expect((await call(h, '/v1/libraries/Plain/example?path=Nope')).statusCode, 404);
      expect((await call(h, '/v1/libraries/Plain/example')).statusCode, 400);
    });

    test('catalogue pas encore chargé : 503', () async {
      final h = buildHandler(
        config: config,
        jobs: jobs,
        libraries: LibraryService(
          indexFile: File(p.join(work.path, 'vide.json')),
          fetch: () async => throw const SocketException('hors ligne'),
          cache: LibraryCache(root: Directory(p.join(work.path, 'x')), download: (url, {required maxBytes}) async => throw UnimplementedError()),
        ),
      );
      expect((await call(h, '/v1/libraries/Plain/examples')).statusCode, 503);
    });

    test('archive impossible à télécharger : 502 avec un message, pas un plantage', () async {
      final svc = LibraryService(
        indexFile: File(p.join(work.path, 'index2.json')),
        fetch: () async => indexJson([entryFor('Plain', '1.0.0', plainZip)]),
        cache: LibraryCache(
          root: Directory(p.join(work.path, 'libs2')),
          download: (url, {required maxBytes}) async => throw const SocketException('hors ligne'),
        ),
      );
      await svc.start();
      svc.dispose();
      final r = await call(buildHandler(config: config, jobs: jobs, libraries: svc), '/v1/libraries/Plain/examples');
      expect(r.statusCode, 502);
      expect((jsonDecode(await r.readAsString()) as Map)['message'], contains('Plain'));
    });
  });
}
