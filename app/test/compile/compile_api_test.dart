import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:nomad_mcu/features/compile/data/compile_api.dart';

/// Vraie socket locale : vérifie ce que le client envoie (jeton, corps, paramètres) et ce qu'il comprend.
class _Server {
  late HttpServer http;
  final requests = <({String method, String path, Map<String, String> query, String? auth, String? type, List<int> body})>[];
  FutureOr<void> Function(HttpRequest request)? handler;

  Future<void> start() async {
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    http.listen((request) async {
      final body = await request.fold<List<int>>([], (a, b) => a..addAll(b));
      requests.add((
        method: request.method,
        path: request.uri.path,
        query: request.uri.queryParameters,
        auth: request.headers.value('authorization'),
        type: request.headers.contentType?.mimeType,
        body: body,
      ));
      await handler!(request);
      await request.response.close();
    });
  }

  String get url => 'http://127.0.0.1:${http.port}';

  Future<void> stop() => http.close(force: true);
}

void reply(HttpRequest request, int status, [Object? json, List<int>? bytes]) {
  request.response.statusCode = status;
  if (json != null) {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(json));
  }
  if (bytes != null) request.response.add(bytes);
}

void main() {
  late _Server server;

  setUp(() async => server = _Server()..start());
  tearDown(() => server.stop());

  HttpCompileApi api({String token = 'tok'}) => HttpCompileApi(baseUrl: server.url, token: token, timeout: const Duration(seconds: 2));

  test('health : sans jeton, lit la version, les cartes et la limite', () async {
    server.handler = (r) => reply(r, 200, {
          'status': 'ok',
          'version': '0.1.0',
          'boards': [
            {'id': 'esp32', 'label': 'ESP32'},
            {'id': 'inconnue', 'label': 'X'},
          ],
          'maxUploadBytes': 8388608,
        });

    final info = await api().health();

    expect(info.version, '0.1.0');
    expect(info.boards, [CompileBoard.esp32], reason: 'une carte que l\'app ne connaît pas est ignorée');
    expect(info.maxUploadBytes, 8388608);
    expect(server.requests.single.auth, isNull);
  });

  test('checkToken : 404 = jeton accepté, 401 = refusé', () async {
    server.handler = (r) => reply(r, 404, {'error': 'not_found'});
    await api().checkToken();
    expect(server.requests.single.auth, 'Bearer tok');

    server.handler = (r) => reply(r, 401, {'error': 'unauthorized'});
    await expectLater(
      api(token: 'mauvais').checkToken(),
      throwsA(isA<CompileApiException>().having((e) => e.kind, 'kind', CompileErrorKind.unauthorized)),
    );
  });

  test('submit : envoie le zip avec le jeton, la carte et le croquis', () async {
    server.handler = (r) => reply(r, 202, {'id': 'abc', 'state': 'queued', 'board': 'esp32s3', 'queuePosition': 0});
    final zip = Uint8List.fromList([80, 75, 3, 4, 1, 2, 3]);

    final status = await api().submit(zip, CompileBoard.esp32s3, sketch: 'blink');

    expect(status.id, 'abc');
    expect(status.state, BuildState.queued);
    final request = server.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/v1/builds');
    expect(request.query, {'board': 'esp32s3', 'sketch': 'blink'});
    expect(request.auth, 'Bearer tok');
    expect(request.type, 'application/zip');
    expect(request.body, zip);
  });

  test('erreurs du service : explication, taille, file pleine', () async {
    Future<CompileApiException> submitError(int status, Object body) async {
      server.handler = (r) => reply(r, status, body);
      try {
        await api().submit(Uint8List(1), CompileBoard.esp32);
      } on CompileApiException catch (e) {
        return e;
      }
      fail('aucune erreur');
    }

    final rejected = await submitError(400, {'error': 'invalid_project', 'message': 'Aucun fichier .ino'});
    expect(rejected.kind, CompileErrorKind.rejected);
    expect(rejected.detail, 'Aucun fichier .ino');
    expect((await submitError(413, {'message': 'trop gros'})).kind, CompileErrorKind.tooLarge);
    expect((await submitError(429, {'message': 'pleine'})).kind, CompileErrorKind.queueFull);
    expect((await submitError(500, {'message': 'boom'})).kind, CompileErrorKind.badResponse);
  });

  test('réponse qui n\'est pas du JSON attendu', () async {
    server.handler = (r) {
      r.response.statusCode = 200;
      r.response.write('<html>Cloudflare</html>');
    };
    await expectLater(
      api().status('abc'),
      throwsA(isA<CompileApiException>().having((e) => e.kind, 'kind', CompileErrorKind.badResponse)),
    );
  });

  test('téléchargement d\'un artefact et build expiré', () async {
    server.handler = (r) => reply(r, 200, null, [1, 2, 3, 4]);
    expect(await api().downloadArtifact('abc', 'blink.ino.merged.bin'), [1, 2, 3, 4]);
    expect(server.requests.single.path, '/v1/builds/abc/artifacts/blink.ino.merged.bin');

    server.handler = (r) => reply(r, 404, {'error': 'not_found'});
    await expectLater(
      api().downloadArtifact('abc', 'x.bin'),
      throwsA(isA<CompileApiException>().having((e) => e.kind, 'kind', CompileErrorKind.notFound)),
    );
  });

  test('annuler ignore les erreurs', () async {
    server.handler = (r) => reply(r, 500);
    await api().cancel('abc');
    expect(server.requests.single.method, 'DELETE');
  });

  test('service injoignable (nom qui ne se résout pas)', () async {
    await expectLater(
      HttpCompileApi(baseUrl: 'https://nomad-test.invalid', token: 'tok', timeout: const Duration(seconds: 5)).health(),
      throwsA(isA<CompileApiException>().having((e) => e.kind, 'kind', CompileErrorKind.unreachable)),
    );
  });

  test('adresse en clair vers un hôte public : refusée avant tout envoi', () async {
    await expectLater(
      HttpCompileApi(baseUrl: 'http://example.com', token: 'secret').status('abc'),
      throwsA(isA<CompileApiException>().having((e) => e.kind, 'kind', CompileErrorKind.badUrl)),
    );
  });

  test('isAcceptableServerUrl', () {
    for (final ok in [
      'https://compile.exemple.com',
      'https://compile.exemple.com/',
      'http://localhost:8787',
      'http://127.0.0.1:8787',
      'http://192.168.1.20:8787',
      'http://10.0.0.5',
      'http://172.16.4.1:8787',
      'http://nas.local:8787',
    ]) {
      expect(isAcceptableServerUrl(ok), isTrue, reason: ok);
    }
    for (final bad in [
      '',
      'compile.exemple.com',
      'http://compile.exemple.com',
      'http://8.8.8.8',
      'http://172.32.0.1',
      'ftp://compile.exemple.com',
      'https://',
    ]) {
      expect(isAcceptableServerUrl(bad), isFalse, reason: bad);
    }
  });

  group('bibliothèques Arduino', () {
    test('recherche : paramètres, jeton et résultat', () async {
      server.handler = (r) => reply(r, 200, {
            'total': 57,
            'libraries': [
              {'name': 'DHT sensor library', 'latest': '1.4.7', 'author': 'Adafruit', 'sentence': 's', 'category': 'Sensors', 'versionCount': 31},
            ],
          });

      final result = await api().searchLibraries('dht sensor', board: CompileBoard.esp32s3, limit: 5);

      expect(result.total, 57);
      expect(result.libraries.single.name, 'DHT sensor library');
      final request = server.requests.single;
      expect(request.path, '/v1/libraries/search');
      expect(request.query, {'q': 'dht sensor', 'limit': '5', 'board': 'esp32s3'});
      expect(request.auth, 'Bearer tok');
    });

    test('détail d\'une bibliothèque dont le nom contient des espaces', () async {
      server.handler = (r) => reply(r, 200, {
            'summary': {'name': 'DHT sensor library', 'latest': '1.4.7'},
            'paragraph': 'long',
            'versions': [
              {'version': '1.4.7', 'dependencies': ['Adafruit Unified Sensor']},
            ],
          });

      final detail = await api().libraryDetail('DHT sensor library');

      expect(detail.versions.single.dependencies, ['Adafruit Unified Sensor']);
      expect(server.requests.single.path, '/v1/libraries/DHT%20sensor%20library');
    });

    test('résolution des #include : corps JSON avec la carte', () async {
      server.handler = (r) => reply(r, 200, {
            'includes': [
              {'header': 'Wire.h', 'builtin': true, 'candidates': []},
              {
                'header': 'DHT.h',
                'builtin': false,
                'candidates': [
                  {'name': 'DHT sensor library', 'latest': '1.4.7'},
                ],
                'confirmed': ['DHT sensor library'],
              },
            ],
          });

      final results = await api().resolveIncludes(['Wire.h', 'DHT.h'], CompileBoard.esp32);

      expect(results.first.builtin, isTrue);
      expect(results.last.confirmed, ['DHT sensor library']);
      final request = server.requests.single;
      expect(request.method, 'POST');
      expect(request.type, 'application/json');
      expect(jsonDecode(utf8.decode(request.body)), {'includes': ['Wire.h', 'DHT.h'], 'board': 'esp32'});
    });

    test('fermeture : la version vide n\'est pas envoyée', () async {
      server.handler = (r) => reply(r, 200, {
            'libraries': [
              {'name': 'DHT sensor library', 'version': '1.4.7'},
              {'name': 'Adafruit Unified Sensor', 'version': '1.1.15'},
            ],
          });

      final closure = await api().libraryClosure(
        [const LibraryRef(name: 'DHT sensor library', version: ''), const LibraryRef(name: 'Servo', version: '1.2.1')],
        CompileBoard.rp2040,
      );

      expect(closure.libraries, hasLength(2));
      expect(jsonDecode(utf8.decode(server.requests.single.body)), {
        'libraries': [
          {'name': 'DHT sensor library'},
          {'name': 'Servo', 'version': '1.2.1'},
        ],
        'board': 'rp2040',
      });
    });

    test('catalogue pas chargé (503) et fermeture impossible (400)', () async {
      server.handler = (r) => reply(r, 503, {'error': 'libraries_unavailable', 'message': 'pas prêt'});
      await expectLater(
        api().searchLibraries('dht'),
        throwsA(isA<CompileApiException>().having((e) => e.kind, 'kind', CompileErrorKind.unavailable)),
      );

      server.handler = (r) => reply(r, 400, {'error': 'unresolvable', 'message': 'Bibliothèque inconnue : Nope.'});
      await expectLater(
        api().libraryClosure([const LibraryRef(name: 'Nope', version: '')], CompileBoard.esp32),
        throwsA(isA<CompileApiException>().having((e) => e.kind, 'kind', CompileErrorKind.rejected).having((e) => e.detail, 'detail', contains('Nope'))),
      );
    });

    test('bibliothèque inconnue (404) et réponse inattendue', () async {
      server.handler = (r) => reply(r, 404, {'error': 'not_found'});
      await expectLater(api().libraryDetail('Nope'), throwsA(isA<CompileApiException>().having((e) => e.kind, 'kind', CompileErrorKind.notFound)));

      server.handler = (r) => reply(r, 200, {'inattendu': true});
      await expectLater(api().searchLibraries('dht'), throwsA(isA<CompileApiException>().having((e) => e.kind, 'kind', CompileErrorKind.badResponse)));
    });
  });
}
