import 'dart:convert';
import 'dart:io';

import 'package:nomad_cloud_compiler/nomad_cloud_compiler.dart';
import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'libraries_support.dart';
import 'support.dart';

void main() {
  late Directory work;
  late ServerConfig config;
  late JobManager jobs;

  setUp(() {
    work = Directory.systemTemp.createTempSync('nomad_libapi_');
    config = testConfig(work);
    jobs = JobManager(config: config, runner: succeedingRunner());
  });
  tearDown(() async {
    await jobs.dispose();
    work.deleteSync(recursive: true);
  });

  Future<Handler> handlerWith({bool loaded = true}) async {
    final service = LibraryService(
      indexFile: File('${work.path}/library_index_${loaded ? 'ok' : 'ko'}.json'),
      fetch: () async => loaded ? indexJson(sampleReleases()) : throw const SocketException('hors ligne'),
      cache: LibraryCache(root: Directory('${work.path}/libs'), download: (url, {required maxBytes}) async => throw UnimplementedError()),
      builtin: BuiltinCatalog.parse('''
/opt/arduino/data/packages/esp32/hardware/esp32/3.3.12/libraries/Wire/src/Wire.h
/opt/arduino/data/packages/esp32/hardware/esp32/3.3.12/libraries/SPI/src/SPI.h
/opt/arduino/data/packages/esp32/hardware/esp32/3.3.12/cores/esp32/Arduino.h
'''),
    );
    await service.start();
    service.dispose();
    return buildHandler(config: config, jobs: jobs, libraries: service);
  }

  Map<String, String> authHeaders() => {'authorization': 'Bearer ${config.token}', 'content-type': 'application/json'};

  Future<Response> call(Handler handler, String method, String path, {Object? json, bool authorized = true}) =>
      Future.sync(() async => handler(Request(
            method,
            Uri.parse('http://x$path'),
            headers: authorized ? authHeaders() : null,
            body: json == null ? null : utf8.encode(jsonEncode(json)),
          )));

  Future<Map<String, Object?>> bodyOf(Response r) async => jsonDecode(await r.readAsString()) as Map<String, Object?>;

  test('health annonce la disponibilité du catalogue', () async {
    final ready = await bodyOf(await call(await handlerWith(), 'GET', '/v1/health'));
    expect((ready['libraries'] as Map)['available'], isTrue);
    expect((ready['libraries'] as Map)['count'], greaterThan(5));

    final notReady = await bodyOf(await call(await handlerWith(loaded: false), 'GET', '/v1/health'));
    expect((notReady['libraries'] as Map)['available'], isFalse);
  });

  test('toutes les routes demandent le jeton', () async {
    final handler = await handlerWith();
    for (final (method, path) in [
      ('GET', '/v1/libraries/search?q=dht'),
      ('GET', '/v1/libraries/DHT'),
      ('POST', '/v1/libraries/resolve'),
      ('POST', '/v1/libraries/closure'),
    ]) {
      expect((await call(handler, method, path, authorized: false)).statusCode, 401, reason: path);
    }
  });

  test('catalogue pas encore chargé : 503 avec un message', () async {
    final handler = await handlerWith(loaded: false);
    final r = await call(handler, 'GET', '/v1/libraries/search?q=dht');
    expect(r.statusCode, 503);
    expect((await bodyOf(r))['error'], 'libraries_unavailable');
  });

  group('recherche et détail', () {
    test('recherche filtrée par carte', () async {
      final handler = await handlerWith();
      final result = LibrarySearchResult.fromJson(await bodyOf(await call(handler, 'GET', '/v1/libraries/search?q=dht&board=esp32s3')));
      expect(result.libraries.map((l) => l.name), containsAll(['DHT', 'DHT sensor library']));

      final avr = LibrarySearchResult.fromJson(await bodyOf(await call(handler, 'GET', '/v1/libraries/search?q=avronly&board=esp32')));
      expect(avr.total, 0);
    });

    test('limite bornée et recherche vide', () async {
      final handler = await handlerWith();
      final many = LibrarySearchResult.fromJson(await bodyOf(await call(handler, 'GET', '/v1/libraries/search?q=a&limit=1')));
      expect(many.libraries.length, 1);
      final empty = LibrarySearchResult.fromJson(await bodyOf(await call(handler, 'GET', '/v1/libraries/search')));
      expect(empty.total, 0);
    });

    test('détail d\'une bibliothèque dont le nom contient des espaces', () async {
      final handler = await handlerWith();
      final r = await call(handler, 'GET', '/v1/libraries/${Uri.encodeComponent('DHT sensor library')}');
      expect(r.statusCode, 200);
      final detail = LibraryDetail.fromJson(await bodyOf(r));
      expect(detail.summary.latest, '1.4.6');
      expect(detail.versions.map((v) => v.version), ['1.4.6', '1.4.4', '1.3.10']);
      expect((await call(handler, 'GET', '/v1/libraries/inconnue')).statusCode, 404);
    });
  });

  group('resolve (#include)', () {
    test('en-tête du cœur, en-tête d\'une bibliothèque, en-tête inconnu', () async {
      final handler = await handlerWith();
      final r = await call(handler, 'POST', '/v1/libraries/resolve', json: {'includes': ['Wire.h', 'DHT.h', 'Zzz.h'], 'board': 'esp32'});
      final results = [for (final i in (await bodyOf(r))['includes'] as List) IncludeResolution.fromJson((i as Map).cast())];

      expect(results[0].builtin, isTrue);
      expect(results[0].candidates, isEmpty);
      expect(results[1].builtin, isFalse);
      expect(results[1].candidates.first.name, 'DHT', reason: 'nom égal à l\'en-tête d\'abord');
      expect(results[1].confirmed, contains('DHT'), reason: 'déclaré par l\'index');
      expect(results[2].builtin, isFalse);
      expect(results[2].candidates, isEmpty);
    });

    test('sans carte : pas de notion de « fourni par le cœur »', () async {
      final r = await call(await handlerWith(), 'POST', '/v1/libraries/resolve', json: {'includes': ['Wire.h']});
      final first = IncludeResolution.fromJson(((await bodyOf(r))['includes'] as List).first as Map<String, Object?>);
      expect(first.builtin, isFalse);
    });

    test('corps invalide ou trop grand : 400', () async {
      final handler = await handlerWith();
      expect((await call(handler, 'POST', '/v1/libraries/resolve')).statusCode, 400);
      expect((await call(handler, 'POST', '/v1/libraries/resolve', json: {'includes': 'DHT.h'})).statusCode, 400);
      expect((await call(handler, 'POST', '/v1/libraries/resolve', json: {'includes': List.filled(101, 'A.h')})).statusCode, 400);
    });
  });

  group('closure', () {
    test('renvoie la bibliothèque et ses dépendances à des versions précises', () async {
      final r = await call(await handlerWith(), 'POST', '/v1/libraries/closure', json: {
        'libraries': [
          {'name': 'DHT sensor library'}
        ],
        'board': 'esp32',
      });
      expect(r.statusCode, 200);
      final closure = LibraryClosure.fromJson(await bodyOf(r));
      expect(closure.libraries.map((l) => l.toString()), ['DHT sensor library@1.4.6', 'Adafruit Unified Sensor@1.1.9']);
    });

    test('dépendances fournies par le cœur ignorées pour la carte donnée', () async {
      final handler = await handlerWith();
      Future<int> status(Map<String, Object?> body) async => (await call(handler, 'POST', '/v1/libraries/closure', json: body)).statusCode;
      final libs = [
        {'name': 'Adafruit BusIO'}
      ];
      expect(await status({'libraries': libs, 'board': 'esp32'}), 200);
      expect(await status({'libraries': libs}), 400, reason: 'sans carte, Wire et SPI sont introuvables');
    });

    test('inconnue : 400 avec l\'explication', () async {
      final r = await call(await handlerWith(), 'POST', '/v1/libraries/closure', json: {
        'libraries': [
          {'name': 'Nope'}
        ],
      });
      expect(r.statusCode, 400);
      final body = await bodyOf(r);
      expect(body['error'], 'unresolvable');
      expect(body['message'], contains('Nope'));
    });

    test('corps invalide', () async {
      final handler = await handlerWith();
      expect((await call(handler, 'POST', '/v1/libraries/closure', json: {'libraries': []})).statusCode, 400);
      expect((await call(handler, 'POST', '/v1/libraries/closure', json: {'libraries': [1]})).statusCode, 400);
    });
  });
}
