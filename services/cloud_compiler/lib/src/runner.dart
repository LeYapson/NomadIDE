import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nomad_compile_api/nomad_compile_api.dart';

import 'config.dart';

/// Annulation d'un build, partagée entre le gestionnaire de jobs et le runner.
class CancelToken {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

class RunRequest {
  const RunRequest({
    required this.id,
    required this.board,
    required this.sketchName,
    required this.sketchDir,
    required this.outDir,
  });

  final String id;
  final CompileBoard board;
  final String sketchName;

  /// Dossier du croquis (monté en lecture seule).
  final Directory sketchDir;

  /// Dossier de sortie (monté en écriture) : les binaires y arrivent.
  final Directory outDir;
}

class RunOutcome {
  const RunOutcome({required this.exitCode, this.timedOut = false, this.cancelled = false});

  final int exitCode;
  final bool timedOut;
  final bool cancelled;
}

/// Exécute une compilation. L'implémentation réelle est [DockerBuildRunner] ; les tests en injectent une fausse.
abstract class BuildRunner {
  Future<RunOutcome> run(RunRequest request, {required void Function(String text) onOutput, required CancelToken cancel});
}

/// Arguments de `docker run` pour une compilation : conteneur éphémère sans réseau, sans privilèges,
/// système de fichiers en lecture seule, ressources bornées.
List<String> dockerRunArguments(ServerConfig config, RunRequest request) {
  final sketchMount = '/work/sketch/${request.sketchName}';
  return [
    'run',
    '--rm',
    '--name', containerName(request.id),
    '--network', 'none',
    '--read-only',
    '--cap-drop', 'ALL',
    '--security-opt', 'no-new-privileges',
    '--pids-limit', '${config.containerPids}',
    '--memory', config.containerMemory,
    '--memory-swap', config.containerMemory,
    '--cpus', config.containerCpus,
    '--user', config.runAs,
    '--tmpfs', '/tmp:rw,exec,nosuid,size=2g',
    '-e', 'HOME=/tmp',
    // L'image est en lecture seule : arduino-cli doit créer son dossier de téléchargement ailleurs.
    '-e', 'ARDUINO_DIRECTORIES_DOWNLOADS=/tmp/staging',
    '--mount', 'type=bind,src=${request.sketchDir.path},dst=$sketchMount,readonly',
    '--mount', 'type=bind,src=${request.outDir.path},dst=/work/out',
    config.dockerImage,
    'arduino-cli', 'compile',
    '--fqbn', request.board.fqbn,
    '--build-path', '/tmp/build',
    '--output-dir', '/work/out',
    sketchMount,
  ];
}

String containerName(String id) => 'nomad-build-$id';

class DockerBuildRunner implements BuildRunner {
  DockerBuildRunner(this.config);

  final ServerConfig config;

  @override
  Future<RunOutcome> run(RunRequest request, {required void Function(String text) onOutput, required CancelToken cancel}) async {
    final process = await Process.start(config.dockerBinary, dockerRunArguments(config, request));
    final streams = [
      process.stdout.transform(utf8.decoder).forEach(onOutput),
      process.stderr.transform(utf8.decoder).forEach(onOutput),
    ];

    var timedOut = false;
    var cancelled = false;
    Future<void> stop() async {
      await Process.run(config.dockerBinary, ['kill', containerName(request.id)]);
      process.kill();
    }

    final timer = Timer(config.buildTimeout, () {
      timedOut = true;
      stop();
    });
    unawaited(cancel.whenCancelled.then((_) {
      cancelled = true;
      return stop();
    }));

    final exitCode = await process.exitCode;
    timer.cancel();
    await Future.wait(streams);
    return RunOutcome(exitCode: exitCode, timedOut: timedOut, cancelled: cancelled);
  }
}
