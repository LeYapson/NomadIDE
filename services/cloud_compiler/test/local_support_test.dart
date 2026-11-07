import 'dart:io';

import 'package:nomad_cloud_compiler/nomad_cloud_compiler.dart';
import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

/// Runner « local » : le compilateur parle avec les vrais chemins du disque, pas ceux d'un conteneur.
class _LocalPathsRunner extends BuildRunner {
  @override
  List<String> sourceRoots(RunRequest request) => [request.sketchDir.path.replaceAll(r'\', '/')];

  @override
  Future<RunOutcome> run(RunRequest request, {required void Function(String text) onOutput, required CancelToken cancel}) async {
    final path = p.join(request.sketchDir.path, '${request.sketchName}.ino');
    onOutput("$path:3:5: error: 'foo' was not declared in this scope\n");
    return const RunOutcome(exitCode: 1);
  }
}

void main() {
  late Directory work;

  setUp(() => work = Directory.systemTemp.createTempSync('nomad_local_'));
  tearDown(() => work.deleteSync(recursive: true));

  test('un runner qui travaille sur le disque : les diagnostics sont relatifs au projet', () async {
    final jobs = JobManager(config: testConfig(work), runner: _LocalPathsRunner());
    final submitted = jobs.submit(board: CompileBoard.esp32, zipBytes: zipOf({'blink.ino': 'void setup(){}\nvoid loop(){}'}));
    await eventually(() => jobs.status(submitted.id)!.state.isFinished);

    final status = jobs.status(submitted.id)!;
    expect(status.state, BuildState.failed);
    expect(status.diagnostics.single.file, 'blink.ino');
    expect(status.diagnostics.single.line, 3);
    await jobs.dispose();
  });

  test('par défaut (conteneur) : le croquis est monté sous /work/sketch', () {
    final request = RunRequest(id: 'x', board: CompileBoard.esp32, sketchName: 'blink', sketchDir: work, outDir: work);
    expect(succeedingRunner().sourceRoots(request), ['/work/sketch/blink']);
  });

  group('cœurs lus dans le dossier packages d\'arduino-cli', () {
    void touch(String path) {
      File(p.join(work.path, path)).createSync(recursive: true);
    }

    test('bibliothèques et en-têtes par famille', () async {
      touch('packages/esp32/hardware/esp32/3.3.12/libraries/Wire/src/Wire.h');
      touch('packages/esp32/hardware/esp32/3.3.12/libraries/WiFi/src/WiFi.h');
      touch('packages/esp32/hardware/esp32/3.3.12/libraries/WiFi/src/WiFi.cpp');
      touch('packages/esp32/hardware/esp32/3.3.12/cores/esp32/Arduino.h');
      touch('packages/rp2040/hardware/rp2040/4.4.2/libraries/Wire/src/Wire.h');
      touch('packages/esp32/tools/xtensa/bin/gcc.h'); // hors cœur : ignoré

      final catalog = await DirectoryBuiltinLoader(Directory(p.join(work.path, 'packages'))).load();

      final esp = catalog.forFamily(CompileFamily.esp);
      expect(esp.libraries, {'Wire', 'WiFi'});
      expect(esp.headers, containsAll(['Wire.h', 'WiFi.h', 'Arduino.h']));
      expect(esp.headers, isNot(contains('gcc.h')));
      expect(catalog.forFamily(CompileFamily.rp2040).libraries, {'Wire'});
    });

    test('dossier absent ou vide : rien de fourni', () async {
      expect((await DirectoryBuiltinLoader(Directory(p.join(work.path, 'absent'))).load()).forFamily(CompileFamily.esp).headers, isEmpty);
      expect((await DirectoryBuiltinLoader(Directory(p.join(work.path, 'packages'))).load()).forFamily(CompileFamily.esp).libraries, isEmpty);
    });
  });
}
