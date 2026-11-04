import 'dart:io';

import 'package:nomad_cloud_compiler/nomad_cloud_compiler.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main() async {
  final ServerConfig config;
  try {
    config = ServerConfig.fromEnvironment(Platform.environment);
  } on ConfigException catch (e) {
    stderr.writeln('Configuration invalide : $e');
    exit(64);
  }

  Directory(config.workDir).createSync(recursive: true);
  final jobs = JobManager(config: config, runner: DockerBuildRunner(config));
  final handler = const Pipeline()
      .addMiddleware(logRequests(logger: (message, isError) => stdout.writeln(message)))
      .addHandler(buildHandler(config: config, jobs: jobs));

  final server = await io.serve(handler, config.host, config.port);
  server.autoCompress = true;
  stdout.writeln('nomad-compiler $serviceVersion sur http://${server.address.host}:${server.port} '
      '(${config.maxConcurrentBuilds} builds simultanés, image ${config.dockerImage})');

  Future<void> stop(ProcessSignal signal) async {
    stdout.writeln('Arrêt ($signal)…');
    await server.close(force: true);
    await jobs.dispose();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(stop);
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(stop);
}
