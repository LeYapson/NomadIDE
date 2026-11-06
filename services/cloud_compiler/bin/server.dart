import 'dart:async';
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
  final cacheRoot = Directory(config.libraryCacheDir ?? '${config.workDir}/libraries');
  final libraries = LibraryService(
    indexFile: defaultIndexFile(config.workDir),
    fetch: httpIndexFetcher(Uri.parse(config.libraryIndexUrl)),
    cache: LibraryCache(root: cacheRoot, download: httpLibraryDownloader()),
  );
  final jobs = JobManager(config: config, runner: DockerBuildRunner(config), libraries: libraries);
  final handler = const Pipeline()
      .addMiddleware(logRequests(logger: (message, isError) => stdout.writeln(message)))
      .addHandler(buildHandler(config: config, jobs: jobs, libraries: libraries));

  // Le catalogue et la liste de ce que les cœurs fournissent se chargent en arrière-plan : le service répond tout de suite.
  unawaited(libraries.start().then((_) {
    stdout.writeln('Catalogue de bibliothèques : ${libraries.index?.libraryCount ?? 0}');
  }).catchError((Object e) {
    stderr.writeln('Catalogue de bibliothèques indisponible : $e');
  }));
  unawaited(DockerBuiltinLoader(config).load().then((catalog) {
    libraries.builtin = catalog;
  }).catchError((Object e) {
    stderr.writeln('Liste des bibliothèques du cœur indisponible : $e');
  }));

  final server = await io.serve(handler, config.host, config.port);
  server.autoCompress = true;
  stdout.writeln('nomad-compiler $serviceVersion sur http://${server.address.host}:${server.port} '
      '(${config.maxConcurrentBuilds} builds simultanés, image ${config.dockerImage})');

  Future<void> stop(ProcessSignal signal) async {
    stdout.writeln('Arrêt ($signal)…');
    await server.close(force: true);
    libraries.dispose();
    await jobs.dispose();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(stop);
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(stop);
}
