import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:nomad_cloud_compiler/nomad_cloud_compiler.dart';
import 'package:nomad_compile_api/nomad_compile_api.dart';

List<int> zipOf(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, content) => archive.add(ArchiveFile.bytes(name, utf8.encode(content))));
  return ZipEncoder().encode(archive);
}

ServerConfig testConfig(Directory work, {int concurrent = 2, int queue = 8, Duration retention = const Duration(minutes: 30)}) =>
    ServerConfig(
      token: 'test-token-test-token-test-token',
      workDir: work.path,
      maxConcurrentBuilds: concurrent,
      maxQueuedBuilds: queue,
      jobRetention: retention,
    );

/// Runner de test : appelle [script], qui peut écrire des fichiers dans `request.outDir`.
class ScriptedRunner implements BuildRunner {
  ScriptedRunner(this.script);

  final Future<RunOutcome> Function(RunRequest request, void Function(String) onOutput, CancelToken cancel) script;
  final List<RunRequest> started = [];

  @override
  Future<RunOutcome> run(RunRequest request, {required void Function(String text) onOutput, required CancelToken cancel}) {
    started.add(request);
    return script(request, onOutput, cancel);
  }
}

/// Runner qui réussit en produisant un binaire adapté à la carte.
ScriptedRunner succeedingRunner() => ScriptedRunner((request, onOutput, cancel) async {
      onOutput('Sketch uses 1000 bytes\n');
      final name = request.sketchName;
      if (request.board.family == CompileFamily.rp2040) {
        File('${request.outDir.path}/$name.ino.uf2').writeAsBytesSync([1, 2, 3]);
      } else {
        File('${request.outDir.path}/$name.ino.merged.bin').writeAsBytesSync([1, 2, 3, 4]);
        File('${request.outDir.path}/$name.ino.bin').writeAsBytesSync([5, 6]);
        File('${request.outDir.path}/$name.ino.bootloader.bin').writeAsBytesSync([7]);
      }
      File('${request.outDir.path}/$name.ino.elf').writeAsBytesSync([9]);
      return const RunOutcome(exitCode: 0);
    });

Future<void> eventually(bool Function() check, {Duration timeout = const Duration(seconds: 5)}) async {
  final clock = Stopwatch()..start();
  while (!check()) {
    if (clock.elapsed > timeout) throw TimeoutException('condition jamais atteinte');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
