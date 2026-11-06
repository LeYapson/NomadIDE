import 'dart:typed_data';

import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:nomad_mcu/features/compile/data/compile_api.dart';

/// Faux service de compilation : renvoie les états de [script] l'un après l'autre.
class FakeCompileApi implements CompileApi {
  FakeCompileApi({this.script = const [], this.artifact, this.maxUploadBytes = 1024 * 1024});

  /// États renvoyés par `submit` (le premier) puis `status` (les suivants ; le dernier se répète).
  List<BuildStatus> script;
  Uint8List? artifact;
  int maxUploadBytes;

  Object? healthError;
  Object? submitError;
  Object? statusError;
  Object? downloadError;

  final List<({Uint8List zip, CompileBoard board, String? sketch})> submitted = [];
  final List<String> cancelled = [];
  final List<String> downloaded = [];
  int statusCalls = 0;
  int tokenChecks = 0;

  @override
  Future<CompileServerInfo> health() async {
    if (healthError != null) throw healthError!;
    return CompileServerInfo(version: '0.1.0', boards: CompileBoard.values, maxUploadBytes: maxUploadBytes);
  }

  @override
  Future<void> checkToken() async {
    tokenChecks++;
    if (healthError != null) throw healthError!;
  }

  @override
  Future<BuildStatus> submit(Uint8List zip, CompileBoard board, {String? sketch}) async {
    if (submitError != null) throw submitError!;
    submitted.add((zip: zip, board: board, sketch: sketch));
    return script.first;
  }

  @override
  Future<BuildStatus> status(String id) async {
    statusCalls++;
    if (statusError != null) throw statusError!;
    final index = statusCalls < script.length ? statusCalls : script.length - 1;
    return script[index];
  }

  @override
  Future<Uint8List> downloadArtifact(String id, String name) async {
    if (downloadError != null) throw downloadError!;
    downloaded.add(name);
    return artifact!;
  }

  @override
  Future<void> cancel(String id) async => cancelled.add(id);

  // --- bibliothèques Arduino ---------------------------------------------------------------------------

  /// Catalogue du faux service : résultat de la recherche, versions, en-têtes et fermeture.
  LibrarySearchResult searchResult = const LibrarySearchResult(total: 0, libraries: []);
  final Map<String, LibraryDetail> details = {};
  final Map<String, IncludeResolution> includes = {};

  /// Dépendances de chaque bibliothèque (nom, puis les dépendances qui s'ajoutent).
  final Map<String, List<LibraryRef>> dependencies = {};

  /// Dernière version connue de chaque bibliothèque (pour « la dernière »).
  final Map<String, String> latestVersion = {};
  Object? libraryError;
  final List<String> searches = [];
  final List<List<String>> resolved = [];
  final List<List<LibraryRef>> closures = [];

  @override
  Future<LibrarySearchResult> searchLibraries(String query, {CompileBoard? board, int limit = 20}) async {
    if (libraryError != null) throw libraryError!;
    searches.add(query);
    return searchResult;
  }

  @override
  Future<LibraryDetail> libraryDetail(String name) async {
    if (libraryError != null) throw libraryError!;
    return details[name] ?? (throw const CompileApiException(CompileErrorKind.notFound));
  }

  @override
  Future<List<IncludeResolution>> resolveIncludes(List<String> headers, CompileBoard board) async {
    if (libraryError != null) throw libraryError!;
    resolved.add(headers);
    return [for (final h in headers) includes[h] ?? IncludeResolution(header: h)];
  }

  @override
  Future<LibraryClosure> libraryClosure(List<LibraryRef> libraries, CompileBoard board) async {
    if (libraryError != null) throw libraryError!;
    closures.add(libraries);
    final out = <LibraryRef>[];
    void add(LibraryRef ref) {
      if (out.any((o) => o.name == ref.name)) return;
      final version = ref.version.isEmpty ? (latestVersion[ref.name] ?? '1.0.0') : ref.version;
      out.add(LibraryRef(name: ref.name, version: version));
      for (final dep in dependencies[ref.name] ?? const <LibraryRef>[]) {
        add(dep);
      }
    }

    libraries.forEach(add);
    return LibraryClosure(libraries: out);
  }
}

BuildStatus buildStatus(
  BuildState state, {
  String board = 'esp32',
  String log = '',
  List<Diagnostic> diagnostics = const [],
  List<BuildArtifact> artifacts = const [],
  String? message,
  int? queuePosition,
  int? durationMs,
}) =>
    BuildStatus(
      id: 'b1',
      state: state,
      board: board,
      log: log,
      diagnostics: diagnostics,
      artifacts: artifacts,
      message: message,
      queuePosition: queuePosition,
      durationMs: durationMs,
    );
