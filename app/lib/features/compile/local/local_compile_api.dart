import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:nomad_cloud_compiler/nomad_cloud_compiler.dart';
import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as io;

import '../data/compile_api.dart';
import 'local_build_runner.dart';
import 'local_toolchain.dart';

/// Le service de compilation, lancé dans l'app sur cette machine uniquement (127.0.0.1, port libre, jeton aléatoire
/// propre à la session). C'est le même code que sur le serveur : les projets, les bibliothèques versionnées, les
/// diagnostics et les artefacts se comportent à l'identique en local et dans le cloud.
class LocalCompileServer {
  LocalCompileServer._(this.toolchain, this._server, this._jobs, this._libraries, this.token);

  Future<void>? _indexLoading;

  final LocalToolchain toolchain;
  final HttpServer _server;
  final JobManager _jobs;
  final LibraryService _libraries;
  final String token;

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  static Future<LocalCompileServer> start(LocalToolchain toolchain, {Duration buildTimeout = const Duration(minutes: 20)}) async {
    final token = _randomToken();
    final root = toolchain.root;
    final workDir = Directory(p.join(root.path, 'work'));
    // Les restes d'une session précédente (build interrompu) ne servent à rien.
    if (workDir.existsSync()) {
      try {
        workDir.deleteSync(recursive: true);
      } on FileSystemException {
        // verrouillé : le prochain démarrage réessaiera
      }
    }
    workDir.createSync(recursive: true);
    final config = ServerConfig(
      token: token,
      host: '127.0.0.1',
      port: 0,
      workDir: workDir.path,
      maxConcurrentBuilds: 1,
      buildTimeout: buildTimeout,
      libraryCacheDir: p.join(root.path, 'libraries'),
    );
    final libraries = LibraryService(
      indexFile: defaultIndexFile(root.path),
      fetch: httpIndexFetcher(Uri.parse(config.libraryIndexUrl)),
      cache: LibraryCache(root: Directory(config.libraryCacheDir!), download: httpLibraryDownloader()),
    );
    final jobs = JobManager(config: config, runner: LocalBuildRunner(toolchain, timeout: buildTimeout), libraries: libraries);
    final server = await io.serve(buildHandler(config: config, jobs: jobs, libraries: libraries), '127.0.0.1', 0);
    final local = LocalCompileServer._(toolchain, server, jobs, libraries, token);
    // Le catalogue se charge en arrière-plan (réseau possible ou non) : le service répond dès maintenant.
    // L'index des bibliothèques n'est téléchargé que le jour où un projet ou l'écran Bibliothèques en a besoin.
    // S'il est déjà sur le disque, il est relu tout de suite (sans réseau).
    if (defaultIndexFile(root.path).existsSync()) local._indexLoading = libraries.start().catchError((Object _) {});
    unawaited(local.refreshBuiltin());
    return local;
  }

  /// Attend le catalogue des bibliothèques (téléchargé au premier démarrage), en le retentant s'il a échoué.
  /// Sans réseau et sans copie sur le disque, on continue : seuls les projets avec bibliothèques seront refusés.
  Future<void> ensureIndex() async {
    try {
      await (_indexLoading ??= _libraries.start().catchError((Object _) {})).timeout(const Duration(minutes: 2));
      if (_libraries.index == null) await _libraries.refresh().timeout(const Duration(minutes: 2));
    } on Object {
      // le service donnera lui-même la raison du refus
    }
  }

  /// Relit ce que les cœurs installés fournissent (à refaire après une installation).
  Future<void> refreshBuiltin() async {
    try {
      _libraries.builtin = await DirectoryBuiltinLoader(toolchain.packagesDir).load();
    } on Object {
      // pas de liste : les suggestions d'en-têtes seront un peu moins précises
    }
  }

  Future<void> close() async {
    await _server.close(force: true);
    _libraries.dispose();
    await _jobs.dispose();
  }

  static String _randomToken() {
    final random = Random.secure();
    return List.generate(32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}

/// [CompileApi] qui compile sur cet ordinateur : lance le service local au premier appel puis lui parle comme à un serveur.
class LocalCompileApi implements CompileApi {
  LocalCompileApi(this.toolchain);

  final LocalToolchain toolchain;
  Future<(LocalCompileServer, HttpCompileApi)>? _started;

  Future<HttpCompileApi> get _api async {
    final started = _started ??= () async {
      final server = await LocalCompileServer.start(toolchain);
      return (server, HttpCompileApi(baseUrl: server.baseUrl, token: server.token));
    }();
    try {
      return (await started).$2;
    } catch (e) {
      _started = null; // la prochaine demande réessaie
      throw CompileApiException(CompileErrorKind.unreachable, cause: e);
    }
  }

  /// Le projet liste-t-il des bibliothèques dans son `nomad.json` ? Sinon, inutile de charger le catalogue.
  static bool _declaresLibraries(Uint8List zip) {
    try {
      for (final file in ZipDecoder().decodeBytes(zip).files) {
        if (!file.isFile || p.basename(file.name) != 'nomad.json') continue;
        final json = jsonDecode(utf8.decode(file.content));
        if (json is Map && json['libraries'] is List && (json['libraries'] as List).isNotEmpty) return true;
      }
    } on Object {
      return true; // illisible : on laisse le service juger
    }
    return false;
  }

  Future<HttpCompileApi> get _indexed async {
    final api = await _api;
    await (await _started!).$1.ensureIndex();
    return api;
  }

  /// Arrête le service local (fermeture de l'app, changement de mode).
  Future<void> close() async {
    final started = _started;
    _started = null;
    if (started != null) await (await started).$1.close();
  }

  /// À appeler après une installation de l'outillage.
  Future<void> toolchainChanged() async {
    final started = _started;
    if (started != null) await (await started).$1.refreshBuiltin();
  }

  @override
  Future<CompileServerInfo> health() async => (await _api).health();

  @override
  Future<void> checkToken() async => (await _api).checkToken();

  @override
  Future<BuildStatus> submit(Uint8List zip, CompileBoard board, {String? sketch}) async {
    final api = await _api;
    if (_declaresLibraries(zip)) await (await _started!).$1.ensureIndex();
    return api.submit(zip, board, sketch: sketch);
  }

  @override
  Future<BuildStatus> status(String id) async => (await _api).status(id);

  @override
  Future<Uint8List> downloadArtifact(String id, String name) async => (await _api).downloadArtifact(id, name);

  @override
  Future<void> cancel(String id) async => (await _api).cancel(id);

  @override
  Future<LibrarySearchResult> searchLibraries(String query, {CompileBoard? board, int limit = 20}) async {
    final api = await _indexed;
    return api.searchLibraries(query, board: board, limit: limit);
  }

  @override
  Future<LibraryDetail> libraryDetail(String name) async {
    final api = await _indexed;
    return api.libraryDetail(name);
  }

  @override
  Future<List<IncludeResolution>> resolveIncludes(List<String> headers, CompileBoard board) async {
    final api = await _indexed;
    return api.resolveIncludes(headers, board);
  }

  @override
  Future<LibraryClosure> libraryClosure(List<LibraryRef> libraries, CompileBoard board) async {
    final api = await _indexed;
    return api.libraryClosure(libraries, board);
  }
}
