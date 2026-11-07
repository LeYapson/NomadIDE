import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_compile_api/nomad_compile_api.dart';

import '../../../app/providers.dart';
import '../../../app/settings.dart';
import '../../editor/application/editor_controller.dart';
import '../../flash/application/esp_flash_controller.dart';
import '../../flash/application/flash_controller.dart';
import '../../projects/data/storage_exception.dart';
import '../data/compile_api.dart';
import '../data/project_archiver.dart';
import '../data/project_config.dart';

enum CompilePhase { idle, packaging, uploading, queued, running, succeeded, failed, cancelled }

/// Pourquoi on n'a pas pu compiler, hors erreurs du code lui-même (celles-là sont des diagnostics).
enum CompileProblem {
  notConfigured,
  badUrl,
  unreachable,
  timeout,
  unauthorized,
  rejected,
  tooLarge,
  queueFull,
  librariesUnavailable,
  expired,
  badResponse,
  noSketch,
  severalSketches,
  saveFailed,
  readFailed,
  downloadFailed,
  checksum,
}

const Object _unset = Object();

@immutable
class CompileState {
  const CompileState({
    this.phase = CompilePhase.idle,
    this.project,
    this.board,
    this.status,
    this.problem,
    this.detail,
  });

  final CompilePhase phase;
  final String? project;
  final CompileBoard? board;

  /// Dernière réponse du service : journal, diagnostics, artefacts.
  final BuildStatus? status;
  final CompileProblem? problem;

  /// Précision du problème (explication du service, nom de fichier…).
  final String? detail;

  bool get working =>
      phase == CompilePhase.packaging ||
      phase == CompilePhase.uploading ||
      phase == CompilePhase.queued ||
      phase == CompilePhase.running;

  List<Diagnostic> get errors => [
        for (final d in status?.diagnostics ?? const <Diagnostic>[])
          if (d.severity == DiagnosticSeverity.error) d,
      ];

  List<Diagnostic> get warnings => [
        for (final d in status?.diagnostics ?? const <Diagnostic>[])
          if (d.severity == DiagnosticSeverity.warning) d,
      ];

  /// Le fichier à envoyer au flash : l'image complète (ESP) ou le UF2 (RP2040).
  BuildArtifact? get flashable {
    final role = board?.family == CompileFamily.rp2040 ? ArtifactRole.uf2 : ArtifactRole.merged;
    for (final a in status?.artifacts ?? const <BuildArtifact>[]) {
      if (a.role == role) return a;
    }
    return null;
  }

  CompileState copyWith({
    CompilePhase? phase,
    Object? project = _unset,
    Object? board = _unset,
    Object? status = _unset,
    Object? problem = _unset,
    Object? detail = _unset,
  }) =>
      CompileState(
        phase: phase ?? this.phase,
        project: identical(project, _unset) ? this.project : project as String?,
        board: identical(board, _unset) ? this.board : board as CompileBoard?,
        status: identical(status, _unset) ? this.status : status as BuildStatus?,
        problem: identical(problem, _unset) ? this.problem : problem as CompileProblem?,
        detail: identical(detail, _unset) ? this.detail : detail as String?,
      );
}

/// Client du service de compilation, ou null tant que l'adresse et le jeton ne sont pas réglés.
final compileApiProvider = Provider<CompileApi?>((ref) {
  final settings = ref.watch(settingsProvider);
  if (!settings.compileConfigured) return null;
  return HttpCompileApi(baseUrl: settings.compileServerUrl, token: settings.compileToken);
});

/// Délai entre deux demandes d'état pendant une compilation. Remplaçable dans les tests.
final compilePollIntervalProvider = Provider<Duration>((ref) => const Duration(milliseconds: 1500));

final compileProvider = NotifierProvider<CompileController, CompileState>(CompileController.new);

/// Compilation cloud d'un projet : empaquetage, envoi, suivi, résultat, passage au flash.
///
/// En deux temps volontairement : [prepare] dit ce qui va partir (fichiers, taille, serveur), puis
/// [start] l'envoie une fois que l'utilisateur a confirmé.
class CompileController extends Notifier<CompileState> {
  Timer? _poll;
  String? _buildId;
  int _failedPolls = 0;
  int _run = 0;

  static const int _maxFailedPolls = 5;

  @override
  CompileState build() {
    ref.onDispose(() => _poll?.cancel());
    return const CompileState();
  }

  CompileApi? get _api => ref.read(compileApiProvider);

  void reset() {
    _poll?.cancel();
    _run++;
    state = const CompileState();
  }

  /// Enregistre les fichiers modifiés du projet, les empaquette et renvoie le paquet ; null si impossible
  /// ([CompileState.problem] explique pourquoi).
  Future<ProjectPackage?> prepare(String project) async {
    final api = _api;
    if (api == null) {
      state = CompileState(phase: CompilePhase.failed, project: project, problem: CompileProblem.notConfigured);
      return null;
    }
    final run = ++_run;
    _poll?.cancel();
    state = CompileState(phase: CompilePhase.packaging, project: project, board: state.board);
    try {
      final info = await api.health();
      if (run != _run) return null;

      final editor = ref.read(editorProvider.notifier);
      for (final document in ref.read(editorProvider).documents) {
        if (document.dirty && document.localProject == project && !await editor.saveLocal(document)) {
          return _fail(CompileProblem.saveFailed, run: run);
        }
      }
      if (run != _run) return null;

      final store = await ref.read(projectStoreProvider.future);
      final package = await packageProject(store, project, maxZipBytes: info.maxUploadBytes);
      if (run != _run) return null;
      if (package.sketches.isEmpty) return _fail(CompileProblem.noSketch, run: run);
      if (package.sketches.length > 1) {
        return _fail(CompileProblem.severalSketches, run: run, detail: package.sketches.join(', '));
      }
      state = state.copyWith(phase: CompilePhase.idle);
      return package;
    } on ProjectTooLargeException catch (e) {
      return _fail(CompileProblem.tooLarge, run: run, detail: '${e.limit}');
    } on StorageException catch (e) {
      return _fail(CompileProblem.readFailed, run: run, detail: e.name);
    } on CompileApiException catch (e) {
      return _failFor(e, run: run);
    }
  }

  /// Envoie [package] et suit la compilation jusqu'au bout.
  Future<void> start(ProjectPackage package, CompileBoard board) async {
    final api = _api;
    if (api == null) return;
    final run = ++_run;
    _failedPolls = 0;
    state = CompileState(phase: CompilePhase.uploading, project: package.project, board: board);
    try {
      final store = await ref.read(projectStoreProvider.future);
      await ProjectConfig.writeBoard(store, package.project, board).catchError((_) {});
      final status = await api.submit(package.zip, board, sketch: package.mainSketch);
      if (run != _run) return;
      _buildId = status.id;
      _apply(status);
      _schedule(run);
    } on CompileApiException catch (e) {
      _failFor(e, run: run);
    }
  }

  /// Annule la compilation en cours (ou abandonne le suivi).
  Future<void> cancel() async {
    final id = _buildId;
    _poll?.cancel();
    _run++;
    if (state.working) state = state.copyWith(phase: CompilePhase.cancelled);
    if (id != null) await _api?.cancel(id);
  }

  /// Ouvre dans l'éditeur le fichier d'une erreur.
  Future<void> openDiagnostic(Diagnostic diagnostic) async {
    final project = state.project;
    if (project == null) return;
    await ref.read(editorProvider.notifier).openLocalFile(project, diagnostic.file, show: true);
  }

  /// Télécharge le binaire, vérifie son empreinte et le prépare dans l'écran Flasher. Faux si impossible.
  Future<bool> sendToFlash() async {
    final api = _api;
    final artifact = state.flashable;
    final id = _buildId;
    final board = state.board;
    if (api == null || artifact == null || id == null || board == null) return false;
    try {
      final bytes = await api.downloadArtifact(id, artifact.name);
      if (sha256.convert(bytes).toString() != artifact.sha256) {
        state = state.copyWith(problem: CompileProblem.checksum, detail: artifact.name);
        return false;
      }
      final file = (name: artifact.name, bytes: bytes);
      if (board.family == CompileFamily.rp2040) {
        ref.read(flashProvider.notifier).useFile(file);
      } else {
        ref.read(espFlashProvider.notifier).useFile(file);
      }
      ref.read(homeTabProvider.notifier).show(HomeTab.flash);
      state = state.copyWith(problem: null, detail: null);
      return true;
    } on CompileApiException catch (e) {
      state = state.copyWith(
        problem: e.kind == CompileErrorKind.notFound ? CompileProblem.expired : CompileProblem.downloadFailed,
        detail: e.detail,
      );
      return false;
    }
  }

  // ---------------------------------------------------------------------------

  void _schedule(int run) {
    _poll?.cancel();
    _poll = Timer(ref.read(compilePollIntervalProvider), () => _tick(run));
  }

  Future<void> _tick(int run) async {
    final id = _buildId;
    final api = _api;
    if (run != _run || id == null || api == null) return;
    try {
      final status = await api.status(id);
      if (run != _run) return;
      _failedPolls = 0;
      _apply(status);
      if (!status.state.isFinished) _schedule(run);
    } on CompileApiException catch (e) {
      if (run != _run) return;
      if (e.kind == CompileErrorKind.notFound || e.kind == CompileErrorKind.unauthorized || ++_failedPolls >= _maxFailedPolls) {
        _failFor(e, run: run);
      } else {
        _schedule(run);
      }
    }
  }

  void _apply(BuildStatus status) {
    final phase = switch (status.state) {
      BuildState.queued => CompilePhase.queued,
      BuildState.running => CompilePhase.running,
      BuildState.succeeded => CompilePhase.succeeded,
      BuildState.cancelled => CompilePhase.cancelled,
      BuildState.failed || BuildState.timedOut => CompilePhase.failed,
    };
    state = state.copyWith(phase: phase, status: status, problem: null, detail: status.message);
  }

  ProjectPackage? _fail(CompileProblem problem, {required int run, String? detail}) {
    if (run == _run) state = state.copyWith(phase: CompilePhase.failed, problem: problem, detail: detail);
    return null;
  }

  ProjectPackage? _failFor(CompileApiException e, {required int run}) {
    final problem = switch (e.kind) {
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
    return _fail(problem, run: run, detail: e.detail);
  }
}
