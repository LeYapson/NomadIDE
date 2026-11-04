import 'dart:async';
import 'dart:io';

import 'package:nomad_cloud_compiler/nomad_cloud_compiler.dart';
import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Directory work;

  setUp(() => work = Directory.systemTemp.createTempSync('nomad_jobs_'));
  tearDown(() {
    if (work.existsSync()) work.deleteSync(recursive: true);
  });

  final blink = zipOf({'blink.ino': 'void setup(){}\nvoid loop(){}'});

  test('compilation réussie : artefacts classés, source supprimée', () async {
    final jobs = JobManager(config: testConfig(work), runner: succeedingRunner());
    final submitted = jobs.submit(board: CompileBoard.esp32s3, zipBytes: blink);
    await eventually(() => jobs.status(submitted.id)!.state.isFinished);

    final status = jobs.status(submitted.id)!;
    expect(status.state, BuildState.succeeded);
    expect(status.log, contains('Sketch uses'));
    final roles = {for (final a in status.artifacts) a.name: a.role};
    expect(roles['blink.ino.merged.bin'], ArtifactRole.merged);
    expect(roles['blink.ino.bin'], ArtifactRole.app);
    expect(roles['blink.ino.elf'], ArtifactRole.debug);
    expect(roles.containsKey('blink.ino.bootloader.bin'), isFalse);
    expect(jobs.artifactFile(submitted.id, 'blink.ino.merged.bin')!.readAsBytesSync(), [1, 2, 3, 4]);
    expect(jobs.artifactFile(submitted.id, '../../etc/passwd'), isNull);
    expect(Directory('${work.path}/${submitted.id}/sketch').existsSync(), isFalse, reason: 'le code ne doit pas rester');
    await jobs.dispose();
  });

  test('RP2040 : un fichier UF2', () async {
    final jobs = JobManager(config: testConfig(work), runner: succeedingRunner());
    final id = jobs.submit(board: CompileBoard.rp2040, zipBytes: blink).id;
    await eventually(() => jobs.status(id)!.state.isFinished);
    expect(jobs.status(id)!.artifacts.map((a) => a.role), containsAll([ArtifactRole.uf2, ArtifactRole.debug]));
    await jobs.dispose();
  });

  test("échec du compilateur : diagnostics avec chemin relatif, pas d'artefact", () async {
    final runner = ScriptedRunner((request, onOutput, cancel) async {
      onOutput("/work/sketch/blink/blink.ino:3:1: error: 'foo' was not declared in this scope\n");
      return const RunOutcome(exitCode: 1);
    });
    final jobs = JobManager(config: testConfig(work), runner: runner);
    final id = jobs.submit(board: CompileBoard.esp32, zipBytes: blink).id;
    await eventually(() => jobs.status(id)!.state.isFinished);
    final status = jobs.status(id)!;
    expect(status.state, BuildState.failed);
    expect(status.diagnostics.single.file, 'blink.ino');
    expect(status.diagnostics.single.line, 3);
    expect(status.artifacts, isEmpty);
    expect(status.message, isNull, reason: "l'erreur du code est dans les diagnostics");
    await jobs.dispose();
  });

  test('succès sans binaire flashable : échec explicite', () async {
    final runner = ScriptedRunner((request, onOutput, cancel) async => const RunOutcome(exitCode: 0));
    final jobs = JobManager(config: testConfig(work), runner: runner);
    final id = jobs.submit(board: CompileBoard.esp32, zipBytes: blink).id;
    await eventually(() => jobs.status(id)!.state.isFinished);
    expect(jobs.status(id)!.state, BuildState.failed);
    expect(jobs.status(id)!.message, contains('aucun binaire'));
    await jobs.dispose();
  });

  test('délai dépassé', () async {
    final runner = ScriptedRunner((request, onOutput, cancel) async => const RunOutcome(exitCode: 137, timedOut: true));
    final jobs = JobManager(config: testConfig(work), runner: runner);
    final id = jobs.submit(board: CompileBoard.esp32, zipBytes: blink).id;
    await eventually(() => jobs.status(id)!.state.isFinished);
    expect(jobs.status(id)!.state, BuildState.timedOut);
    await jobs.dispose();
  });

  test('au plus N builds simultanés, les autres attendent avec leur rang', () async {
    final gate = Completer<void>();
    final runner = ScriptedRunner((request, onOutput, cancel) async {
      await gate.future;
      return const RunOutcome(exitCode: 1);
    });
    final jobs = JobManager(config: testConfig(work, concurrent: 1), runner: runner);
    final first = jobs.submit(board: CompileBoard.esp32, zipBytes: blink).id;
    final second = jobs.submit(board: CompileBoard.esp32, zipBytes: blink).id;
    final third = jobs.submit(board: CompileBoard.esp32, zipBytes: blink).id;
    await eventually(() => runner.started.length == 1);

    expect(jobs.status(first)!.state, BuildState.running);
    expect(jobs.status(second)!.queuePosition, 0);
    expect(jobs.status(third)!.queuePosition, 1);
    expect(jobs.runningCount, 1);

    gate.complete();
    await eventually(() => jobs.status(third)!.state.isFinished);
    expect(runner.started.length, 3);
    await jobs.dispose();
  });

  test('file pleine : refusée', () async {
    final gate = Completer<void>();
    final runner = ScriptedRunner((request, onOutput, cancel) async {
      await gate.future;
      return const RunOutcome(exitCode: 1);
    });
    final jobs = JobManager(config: testConfig(work, concurrent: 1, queue: 1), runner: runner);
    jobs.submit(board: CompileBoard.esp32, zipBytes: blink);
    await eventually(() => runner.started.length == 1);
    jobs.submit(board: CompileBoard.esp32, zipBytes: blink);
    expect(() => jobs.submit(board: CompileBoard.esp32, zipBytes: blink), throwsA(isA<QueueFullException>()));
    gate.complete();
    await jobs.dispose();
  });

  test('annulation : en attente et en cours', () async {
    final gate = Completer<void>();
    final runner = ScriptedRunner((request, onOutput, cancel) async {
      await Future.any([gate.future, cancel.whenCancelled]);
      return RunOutcome(exitCode: 137, cancelled: cancel.isCancelled);
    });
    final jobs = JobManager(config: testConfig(work, concurrent: 1), runner: runner);
    final running = jobs.submit(board: CompileBoard.esp32, zipBytes: blink).id;
    final waiting = jobs.submit(board: CompileBoard.esp32, zipBytes: blink).id;
    await eventually(() => runner.started.length == 1);

    expect(jobs.cancel(waiting), isTrue);
    expect(jobs.status(waiting)!.state, BuildState.cancelled);
    expect(jobs.cancel(running), isTrue);
    await eventually(() => jobs.status(running)!.state.isFinished);
    expect(jobs.status(running)!.state, BuildState.cancelled);
    expect(jobs.cancel('inconnu'), isFalse);
    await jobs.dispose();
  });

  test('un build terminé expire et son dossier est supprimé', () async {
    final jobs = JobManager(
      config: testConfig(work, retention: const Duration(milliseconds: 50)),
      runner: succeedingRunner(),
    );
    final id = jobs.submit(board: CompileBoard.esp32, zipBytes: blink).id;
    await eventually(() => jobs.status(id) == null);
    expect(Directory('${work.path}/$id').existsSync(), isFalse);
    await jobs.dispose();
  });

  test('projet refusé : rien ne reste sur le disque', () {
    final jobs = JobManager(config: testConfig(work), runner: succeedingRunner());
    expect(() => jobs.submit(board: CompileBoard.esp32, zipBytes: [1, 2, 3]), throwsA(isA<ProjectException>()));
    expect(work.listSync(), isEmpty);
  });

  test('arguments docker : réseau coupé, lecture seule, sans privilèges', () {
    final args = dockerRunArguments(
      testConfig(work),
      RunRequest(
        id: 'abc',
        board: CompileBoard.esp32s3,
        sketchName: 'blink',
        sketchDir: Directory('/srv/x/sketch/blink'),
        outDir: Directory('/srv/x/out'),
      ),
    );
    expect(args, containsAllInOrder(['--network', 'none']));
    expect(args, containsAll(['--read-only', '--cap-drop', 'ALL', 'no-new-privileges']));
    expect(args, containsAllInOrder(['--fqbn', 'esp32:esp32:esp32s3']));
    expect(args.where((a) => a.contains('dst=/work/sketch/blink,readonly')), hasLength(1));
    expect(args, contains('ARDUINO_DIRECTORIES_DOWNLOADS=/tmp/staging'));
    expect(args.contains('nomad-build-abc'), isTrue);
  });
}
