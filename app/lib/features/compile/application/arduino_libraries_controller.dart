import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_compile_api/nomad_compile_api.dart';

import '../../../app/providers.dart';
import '../../projects/data/storage_exception.dart';
import '../data/compile_api.dart';
import '../data/include_scanner.dart';
import '../data/project_config.dart';
import 'compile_controller.dart';

const Object _unset = Object();

@immutable
class ArduinoLibrariesState {
  const ArduinoLibrariesState({
    this.project,
    this.board = CompileBoard.esp32,
    this.libraries = const [],
    this.roots = const [],
    this.query = '',
    this.results,
    this.searching = false,
    this.working = false,
    this.scanning = false,
    this.suggestions = const [],
    this.problem,
    this.detail,
  });

  final String? project;
  final CompileBoard board;

  /// Bibliothèques du projet, chacune à une version précise (dépendances comprises).
  final List<LibraryRef> libraries;

  /// Noms de celles que l'utilisateur a choisies ; les autres de [libraries] sont des dépendances.
  final List<String> roots;
  final String query;
  final LibrarySearchResult? results;
  final bool searching;

  /// Une modification de la liste est en cours (le service résout les dépendances).
  final bool working;
  final bool scanning;

  /// En-têtes que le projet inclut sans qu'aucune de ses bibliothèques ne les fournisse.
  final List<IncludeResolution> suggestions;
  final CompileProblem? problem;
  final String? detail;

  bool get busy => searching || working || scanning;

  /// Bibliothèques choisies par l'utilisateur, avec leur version.
  List<LibraryRef> get chosen => [for (final l in libraries) if (roots.contains(l.name)) l];

  /// Dépendances (installées parce qu'une bibliothèque choisie en a besoin).
  List<LibraryRef> get dependencies => [for (final l in libraries) if (!roots.contains(l.name)) l];

  bool has(String name) => libraries.any((l) => l.name.toLowerCase() == name.toLowerCase());

  ArduinoLibrariesState copyWith({
    Object? project = _unset,
    CompileBoard? board,
    List<LibraryRef>? libraries,
    List<String>? roots,
    String? query,
    Object? results = _unset,
    bool? searching,
    bool? working,
    bool? scanning,
    List<IncludeResolution>? suggestions,
    Object? problem = _unset,
    Object? detail = _unset,
  }) =>
      ArduinoLibrariesState(
        project: identical(project, _unset) ? this.project : project as String?,
        board: board ?? this.board,
        libraries: libraries ?? this.libraries,
        roots: roots ?? this.roots,
        query: query ?? this.query,
        results: identical(results, _unset) ? this.results : results as LibrarySearchResult?,
        searching: searching ?? this.searching,
        working: working ?? this.working,
        scanning: scanning ?? this.scanning,
        suggestions: suggestions ?? this.suggestions,
        problem: identical(problem, _unset) ? this.problem : problem as CompileProblem?,
        detail: identical(detail, _unset) ? this.detail : detail as String?,
      );
}

final arduinoLibrariesProvider = NotifierProvider<ArduinoLibrariesController, ArduinoLibrariesState>(ArduinoLibrariesController.new);

/// Bibliothèques Arduino d'un projet : recherche, ajout, retrait, version, et suggestions d'après les `#include`.
///
/// La liste est enregistrée dans le `nomad.json` du projet, chaque bibliothèque à une version précise (dépendances
/// comprises, résolues par le service) : le service compile avec exactement celles-là.
class ArduinoLibrariesController extends Notifier<ArduinoLibrariesState> {
  int _run = 0;

  @override
  ArduinoLibrariesState build() => const ArduinoLibrariesState();

  CompileApi? get _api => ref.read(compileApiProvider);

  /// Charge les bibliothèques de [project] (et mémorise [board], qui filtre les recherches).
  Future<void> load(String project, CompileBoard board) async {
    if (state.project != project) {
      _run++;
      state = ArduinoLibrariesState(project: project, board: board);
    } else {
      state = state.copyWith(board: board);
    }
    try {
      final store = await ref.read(projectStoreProvider.future);
      final config = await ProjectConfig.read(store, project);
      if (state.project != project) return;
      state = state.copyWith(libraries: config.libraries, roots: config.chosenNames, problem: null, detail: null);
    } on StorageException catch (e) {
      state = state.copyWith(problem: CompileProblem.readFailed, detail: e.name);
    }
  }

  void clearProblem() => state = state.copyWith(problem: null, detail: null);

  Future<void> search(String query) async {
    final text = query.trim();
    final run = ++_run;
    if (text.length < 2) {
      state = state.copyWith(query: text, results: null, searching: false, problem: null, detail: null);
      return;
    }
    final api = _api;
    if (api == null) {
      state = state.copyWith(query: text, problem: CompileProblem.notConfigured, detail: null);
      return;
    }
    state = state.copyWith(query: text, searching: true, problem: null, detail: null);
    try {
      final results = await api.searchLibraries(text, board: state.board);
      if (run != _run) return;
      state = state.copyWith(results: results, searching: false);
    } on CompileApiException catch (e) {
      if (run != _run) return;
      state = state.copyWith(searching: false, results: null, problem: problemFor(e.kind), detail: e.detail);
    }
  }

  /// Versions d'une bibliothèque, pour en choisir une. Null (et un problème posé) si le service ne répond pas.
  Future<LibraryDetail?> detailOf(String name) async {
    final api = _api;
    if (api == null) {
      state = state.copyWith(problem: CompileProblem.notConfigured, detail: null);
      return null;
    }
    try {
      return await api.libraryDetail(name);
    } on CompileApiException catch (e) {
      state = state.copyWith(problem: problemFor(e.kind), detail: e.detail);
      return null;
    }
  }

  /// Ajoute [name] (à [version], sinon la dernière) avec ses dépendances. Faux si le service refuse.
  Future<bool> add(String name, {String? version}) async {
    final existing = state.libraries.where((l) => l.name.toLowerCase() == name.toLowerCase()).firstOrNull;
    if (existing != null && (version == null || existing.version == version) && state.roots.contains(existing.name)) return true;
    final roots = [...state.roots.where((r) => r.toLowerCase() != name.toLowerCase()), name];
    return _apply(roots, pin: {name: version ?? ''});
  }

  /// Change la version de [name] (une bibliothèque choisie), les dépendances sont recalculées.
  Future<bool> setVersion(String name, String version) => _apply(state.roots, pin: {name: version});

  /// Retire [name] et les dépendances que plus aucune bibliothèque choisie n'exige.
  Future<bool> remove(String name) => _apply([for (final r in state.roots) if (r != name) r]);

  /// Calcule la liste complète pour [roots] : chacune garde sa version actuelle, sauf [pin] qui impose la sienne.
  Future<bool> _apply(List<String> roots, {Map<String, String> pin = const {}}) async {
    final project = state.project;
    final api = _api;
    if (project == null) return false;
    if (api == null) {
      state = state.copyWith(problem: CompileProblem.notConfigured, detail: null);
      return false;
    }
    state = state.copyWith(working: true, problem: null, detail: null);
    try {
      var libraries = <LibraryRef>[];
      if (roots.isNotEmpty) {
        final request = [
          for (final root in roots)
            LibraryRef(
              name: root,
              version: pin[root] ?? state.libraries.where((l) => l.name == root).firstOrNull?.version ?? '',
            ),
        ];
        libraries = (await api.libraryClosure(request, state.board)).libraries;
      }
      final store = await ref.read(projectStoreProvider.future);
      await ProjectConfig.writeLibraries(store, project, libraries, roots);
      if (state.project != project) return false;
      state = state.copyWith(
        libraries: libraries,
        roots: roots,
        working: false,
        suggestions: [for (final s in state.suggestions) if (!_satisfied(s, libraries)) s],
      );
      return true;
    } on CompileApiException catch (e) {
      state = state.copyWith(working: false, problem: problemFor(e.kind), detail: e.detail);
      return false;
    } on StorageException catch (e) {
      state = state.copyWith(working: false, problem: CompileProblem.saveFailed, detail: e.name);
      return false;
    }
  }

  /// Cherche une bibliothèque pour chaque `#include` du projet que ni le cœur de la carte ni les bibliothèques déjà
  /// ajoutées ne fournissent.
  Future<void> scan() async {
    final project = state.project;
    final api = _api;
    if (project == null) return;
    if (api == null) {
      state = state.copyWith(problem: CompileProblem.notConfigured, detail: null);
      return;
    }
    state = state.copyWith(scanning: true, problem: null, detail: null);
    try {
      final store = await ref.read(projectStoreProvider.future);
      final headers = await externalIncludes(store, project);
      final resolutions = headers.isEmpty ? <IncludeResolution>[] : await api.resolveIncludes(headers, state.board);
      if (state.project != project) return;
      state = state.copyWith(scanning: false, suggestions: _unsatisfied(resolutions));
    } on CompileApiException catch (e) {
      state = state.copyWith(scanning: false, problem: problemFor(e.kind), detail: e.detail);
    } on StorageException catch (e) {
      state = state.copyWith(scanning: false, problem: CompileProblem.readFailed, detail: e.name);
    }
  }

  /// Suggestions pour les en-têtes que la compilation n'a pas trouvés ([messages] : messages d'erreur du compilateur).
  Future<void> suggestForMessages(Iterable<String> messages) async {
    final headers = missingHeadersIn(messages);
    final api = _api;
    if (headers.isEmpty || api == null) {
      state = state.copyWith(suggestions: const []);
      return;
    }
    try {
      final resolutions = await api.resolveIncludes(headers, state.board);
      state = state.copyWith(suggestions: _unsatisfied(resolutions));
    } on CompileApiException {
      // Une suggestion est un plus : sans réponse du service, l'erreur de compilation reste affichée telle quelle.
      state = state.copyWith(suggestions: const []);
    }
  }

  void clearSuggestions() => state = state.copyWith(suggestions: const []);

  List<IncludeResolution> _unsatisfied(List<IncludeResolution> resolutions) =>
      [for (final r in resolutions) if (!r.builtin && !_satisfied(r, state.libraries)) r];

  /// Vrai si l'un des candidats de [resolution] est déjà dans [libraries] (l'en-tête est donc fourni).
  static bool _satisfied(IncludeResolution resolution, List<LibraryRef> libraries) =>
      resolution.candidates.any((c) => libraries.any((l) => l.name.toLowerCase() == c.name.toLowerCase()) && resolution.confirmed.contains(c.name));

  /// Le problème d'affichage qui correspond à une erreur du service.
  static CompileProblem problemFor(CompileErrorKind kind) => switch (kind) {
        CompileErrorKind.badUrl => CompileProblem.badUrl,
        CompileErrorKind.unreachable => CompileProblem.unreachable,
        CompileErrorKind.timeout => CompileProblem.timeout,
        CompileErrorKind.unauthorized => CompileProblem.unauthorized,
        CompileErrorKind.rejected => CompileProblem.rejected,
        CompileErrorKind.tooLarge => CompileProblem.tooLarge,
        CompileErrorKind.queueFull => CompileProblem.queueFull,
        CompileErrorKind.unavailable => CompileProblem.librariesUnavailable,
        CompileErrorKind.notFound => CompileProblem.expired,
        CompileErrorKind.badResponse => CompileProblem.badResponse,
      };
}
