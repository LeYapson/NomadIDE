import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nomad_cloud_compiler/nomad_cloud_compiler.dart';
import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:test/test.dart';

import 'libraries_support.dart';
import 'support.dart';

void main() {
  late Directory work;
  late Uint8List zip;
  late List<Uri> downloads;
  late List<RunRequest> runs;

  setUp(() {
    work = Directory.systemTemp.createTempSync('nomad_joblib_');
    zip = libraryZip();
    downloads = [];
    runs = [];
  });
  tearDown(() => work.deleteSync(recursive: true));

  Future<LibraryService> service({Uint8List? served}) async {
    final svc = LibraryService(
      indexFile: File('${work.path}/library_index.json'),
      fetch: () async => indexJson([
        releaseJson('DHT sensor library', '1.4.6', size: zip.length, checksum: 'SHA-256:${sha256Of(zip)}', includes: ['DHT.h']),
      ]),
      cache: LibraryCache(
        root: Directory('${work.path}/libs'),
        download: (url, {required maxBytes}) async {
          downloads.add(url);
          return served ?? zip;
        },
      ),
    );
    await svc.start();
    svc.dispose();
    return svc;
  }

  JobManager manager(LibraryService? libraries) => JobManager(
        config: testConfig(work),
        runner: ScriptedRunner((request, onOutput, cancel) async {
          runs.add(request);
          onOutput('compilation\n');
          File('${request.outDir.path}/${request.sketchName}.ino.merged.bin').writeAsBytesSync([1]);
          return const RunOutcome(exitCode: 0);
        }),
        libraries: libraries,
      );

  List<int> project({List<Map<String, String>>? libraries}) => zipOf({
        'blink.ino': 'void setup(){}',
        if (libraries != null) 'nomad.json': jsonEncode({'board': 'esp32', 'libraries': libraries}),
      });

  final dht = [
    {'name': 'DHT sensor library', 'version': '1.4.6'}
  ];

  test('les bibliothèques de nomad.json sont installées puis montées dans la compilation', () async {
    final jobs = manager(await service());
    final id = jobs.submit(board: CompileBoard.esp32, zipBytes: project(libraries: dht)).id;
    await eventually(() => jobs.status(id)!.state.isFinished);

    final status = jobs.status(id)!;
    expect(status.state, BuildState.succeeded);
    expect(status.log, contains('Bibliothèque DHT sensor library 1.4.6'));
    expect(runs.single.libraries, hasLength(1));
    expect(File('${runs.single.libraries.single.path}/library.properties').existsSync(), isTrue);
    expect(downloads, hasLength(1));
    await jobs.dispose();
  });

  test('une deuxième compilation réutilise la bibliothèque installée', () async {
    final jobs = manager(await service());
    for (var i = 0; i < 2; i++) {
      final id = jobs.submit(board: CompileBoard.esp32, zipBytes: project(libraries: dht)).id;
      await eventually(() => jobs.status(id)!.state.isFinished);
    }
    expect(downloads, hasLength(1));
    expect(runs, hasLength(2));
    await jobs.dispose();
  });

  test('sans bibliothèque dans le projet : rien n\'est installé', () async {
    final jobs = manager(await service());
    final id = jobs.submit(board: CompileBoard.esp32, zipBytes: project()).id;
    await eventually(() => jobs.status(id)!.state.isFinished);
    expect(runs.single.libraries, isEmpty);
    expect(downloads, isEmpty);
    await jobs.dispose();
  });

  test('version ou bibliothèque absente de l\'index : refusé tout de suite, sans rien laisser sur le disque', () async {
    final jobs = manager(await service());
    final before = work.listSync().length;
    expect(
      () => jobs.submit(board: CompileBoard.esp32, zipBytes: project(libraries: [{'name': 'DHT sensor library', 'version': '9.9.9'}])),
      throwsA(isA<ProjectException>().having((e) => e.message, 'message', contains('introuvable'))),
    );
    expect(
      () => jobs.submit(board: CompileBoard.esp32, zipBytes: project(libraries: [{'name': 'Nope', 'version': '1.0'}])),
      throwsA(isA<ProjectException>()),
    );
    expect(work.listSync().length, before);
    await jobs.dispose();
  });

  test('catalogue indisponible ou service sans catalogue : le projet est refusé avec une explication', () async {
    final jobs = manager(null);
    expect(() => jobs.submit(board: CompileBoard.esp32, zipBytes: project(libraries: dht)),
        throwsA(isA<ProjectException>().having((e) => e.message, 'message', contains('catalogue'))));
    await jobs.dispose();
  });

  test('trop de bibliothèques', () async {
    final jobs = manager(await service());
    final many = [for (var i = 0; i < 41; i++) {'name': 'Lib$i', 'version': '1.0'}];
    expect(() => jobs.submit(board: CompileBoard.esp32, zipBytes: project(libraries: many)), throwsA(isA<ProjectException>()));
    await jobs.dispose();
  });

  test('installation impossible : la compilation échoue avec le message, sans lancer le compilateur', () async {
    final tampered = Uint8List.fromList(zip)..[zip.length ~/ 2] ^= 0xFF;
    final jobs = manager(await service(served: tampered));
    final id = jobs.submit(board: CompileBoard.esp32, zipBytes: project(libraries: dht)).id;
    await eventually(() => jobs.status(id)!.state.isFinished);

    final status = jobs.status(id)!;
    expect(status.state, BuildState.failed);
    expect(status.message, contains('Empreinte'));
    expect(runs, isEmpty);
    await jobs.dispose();
  });

  test('nomad.json illisible ou sans libraries : pas de bibliothèque, pas d\'erreur', () async {
    final jobs = manager(await service());
    final broken = zipOf({'blink.ino': 'x', 'nomad.json': '{ pas du json'});
    final id = jobs.submit(board: CompileBoard.esp32, zipBytes: broken).id;
    await eventually(() => jobs.status(id)!.state.isFinished);
    expect(jobs.status(id)!.state, BuildState.succeeded);
    await jobs.dispose();
  });

  test('arguments docker : bibliothèques en lecture seule et passées à arduino-cli', () {
    final args = dockerRunArguments(
      testConfig(work),
      RunRequest(
        id: 'abc',
        board: CompileBoard.esp32,
        sketchName: 'blink',
        sketchDir: Directory('/srv/x/sketch/blink'),
        outDir: Directory('/srv/x/out'),
        libraries: [Directory('/cache/DHT@1.4.6/DHT_sensor_library'), Directory('/cache/Adafruit@1.1.9/Adafruit_Unified_Sensor')],
      ),
    );
    expect(args, contains('type=bind,src=/cache/DHT@1.4.6/DHT_sensor_library,dst=/work/libs/lib0,readonly'));
    expect(args, contains('type=bind,src=/cache/Adafruit@1.1.9/Adafruit_Unified_Sensor,dst=/work/libs/lib1,readonly'));
    final firstLib = args.indexOf('--library');
    expect(args.sublist(firstLib, firstLib + 4), ['--library', '/work/libs/lib0', '--library', '/work/libs/lib1']);
    expect(args.last, '/work/sketch/blink', reason: 'le croquis reste le dernier argument');
    expect(args.indexOf('--network'), lessThan(args.indexOf('arduino-cli')));
    expect(args[args.indexOf('--network') + 1], 'none');
  });
}
