import 'dart:convert';
import 'dart:io';

import 'package:nomad_cloud_compiler/nomad_cloud_compiler.dart';
import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Directory work;
  late JobManager jobs;
  late Handler handler;
  late ServerConfig config;

  setUp(() {
    work = Directory.systemTemp.createTempSync('nomad_http_');
    config = testConfig(work);
    jobs = JobManager(config: config, runner: succeedingRunner());
    handler = buildHandler(config: config, jobs: jobs);
  });
  tearDown(() async {
    await jobs.dispose();
    if (work.existsSync()) work.deleteSync(recursive: true);
  });

  Map<String, String> auth([String? token]) => {'authorization': 'Bearer ${token ?? config.token}'};

  Future<Response> send(String method, String path, {Map<String, String>? headers, List<int>? body}) =>
      Future.sync(() async => handler(Request(method, Uri.parse('http://x$path'), headers: headers, body: body)));

  Future<Map<String, Object?>> jsonOf(Response r) async => jsonDecode(await r.readAsString()) as Map<String, Object?>;

  final blink = zipOf({'blink.ino': 'void setup(){}\nvoid loop(){}'});

  test('health est public et liste les cartes', () async {
    final r = await send('GET', '/v1/health');
    expect(r.statusCode, 200);
    final body = await jsonOf(r);
    expect(body['status'], 'ok');
    expect((body['boards'] as List).map((b) => (b as Map)['id']), contains('rp2040'));
  });

  test('sans jeton ou avec un mauvais jeton : 401', () async {
    expect((await send('POST', '/v1/builds?board=esp32', body: blink)).statusCode, 401);
    expect((await send('POST', '/v1/builds?board=esp32', headers: auth('mauvais'), body: blink)).statusCode, 401);
    expect((await send('GET', '/v1/builds/abc')).statusCode, 401);
    expect(work.listSync(), isEmpty);
  });

  test('cycle complet : envoi, attente, état, téléchargement, suppression', () async {
    final created = await send('POST', '/v1/builds?board=esp32s3', headers: auth(), body: blink);
    expect(created.statusCode, 202);
    final id = (await jsonOf(created))['id'] as String;
    expect(created.headers['location'], '/v1/builds/$id');

    await eventually(() => jobs.status(id)!.state.isFinished);
    final status = BuildStatus.fromJson(await jsonOf(await send('GET', '/v1/builds/$id', headers: auth())));
    expect(status.state, BuildState.succeeded);
    final merged = status.artifacts.firstWhere((a) => a.role == ArtifactRole.merged);

    final download = await send('GET', '/v1/builds/$id/artifacts/${merged.name}', headers: auth());
    expect(download.statusCode, 200);
    expect(await download.read().expand((c) => c).toList(), [1, 2, 3, 4]);

    expect((await send('GET', '/v1/builds/$id/artifacts/inconnu.bin', headers: auth())).statusCode, 404);
    expect((await send('DELETE', '/v1/builds/$id', headers: auth())).statusCode, 204);
    expect((await send('GET', '/v1/builds/$id', headers: auth())).statusCode, 404);
  });

  test('carte inconnue, projet invalide, taille excessive', () async {
    final board = await send('POST', '/v1/builds?board=avr', headers: auth(), body: blink);
    expect(board.statusCode, 400);
    expect((await jsonOf(board))['error'], 'unknown_board');

    final invalid = await send('POST', '/v1/builds?board=esp32', headers: auth(), body: [1, 2, 3]);
    expect(invalid.statusCode, 400);
    expect((await jsonOf(invalid))['error'], 'invalid_project');

    final big = await send('POST', '/v1/builds?board=esp32', headers: auth(), body: List.filled(config.maxUploadBytes + 1, 0));
    expect(big.statusCode, 413);
  });

  test("le jeton n'apparaît dans aucune réponse d'erreur", () async {
    final r = await send('POST', '/v1/builds?board=esp32', headers: auth('x' * 30), body: blink);
    expect(await r.readAsString(), isNot(contains(config.token)));
  });
}
