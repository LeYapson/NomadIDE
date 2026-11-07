import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nomad_cloud_compiler/nomad_cloud_compiler.dart';
import 'package:path/path.dart' as p;

import 'local_toolchain.dart';

/// Compile avec l'`arduino-cli` installé dans l'app (voir [LocalToolchain]), sans conteneur.
///
/// Pas de bac à sable ici : c'est le code de l'utilisateur sur sa propre machine, comme dans l'Arduino IDE.
/// La sécurité du service (extraction du zip, bibliothèques vérifiées) reste celle de [JobManager].
class LocalBuildRunner extends BuildRunner {
  LocalBuildRunner(this.toolchain, {this.timeout = const Duration(minutes: 20)});

  final LocalToolchain toolchain;

  /// Plus long que sur le serveur : la toute première compilation d'un cœur construit tout son cache.
  final Duration timeout;

  @override
  List<String> sourceRoots(RunRequest request) {
    final path = request.sketchDir.path.replaceAll('\\', '/');
    return [path, request.sketchDir.absolute.path.replaceAll('\\', '/')];
  }

  /// Arguments de `arduino-cli compile`.
  List<String> arguments(RunRequest request, Directory buildDir) => [
        'compile',
        '--fqbn', request.board.fqbn,
        '--build-path', buildDir.path,
        '--output-dir', request.outDir.path,
        for (final library in request.libraries) ...['--library', library.path],
        request.sketchDir.path,
      ];

  @override
  Future<RunOutcome> run(RunRequest request, {required void Function(String text) onOutput, required CancelToken cancel}) async {
    if (!toolchain.cliInstalled) {
      onOutput("L'outillage de compilation n'est pas installé.\n");
      return const RunOutcome(exitCode: 1);
    }
    // Chemin court : sous Windows, les chemins de compilation du cœur ESP32 dépassent vite 260 caractères.
    final buildDir = Directory(p.join(toolchain.root.path, 'b', request.id.substring(0, 8)));
    await buildDir.create(recursive: true);
    final process = await Process.start(
      toolchain.cli.path,
      arguments(request, buildDir),
      environment: toolchain.environment,
      includeParentEnvironment: true,
    );
    final streams = [
      process.stdout.transform(utf8.decoder).forEach(onOutput),
      process.stderr.transform(utf8.decoder).forEach(onOutput),
    ];

    var timedOut = false;
    var cancelled = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      killProcessTree(process);
    });
    unawaited(cancel.whenCancelled.then((_) {
      cancelled = true;
      killProcessTree(process);
    }));

    final exitCode = await process.exitCode;
    timer.cancel();
    await Future.wait(streams);
    try {
      await buildDir.delete(recursive: true);
    } on FileSystemException {
      // fichier encore verrouillé (antivirus) : sans conséquence, le dossier est dans le dossier de l'app
    }
    return RunOutcome(exitCode: exitCode, timedOut: timedOut, cancelled: cancelled);
  }
}
