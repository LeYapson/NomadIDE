import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:path/path.dart' as p;

import 'artifacts.dart';
import 'config.dart';
import 'libraries/library_cache.dart';
import 'libraries/library_index.dart';
import 'libraries/library_service.dart';
import 'libraries/project_libraries.dart';
import 'project_archive.dart';
import 'runner.dart';

/// La file est pleine : l'appelant doit réessayer plus tard.
class QueueFullException implements Exception {
  QueueFullException(this.limit);

  final int limit;
}

class _Job {
  _Job({
    required this.id,
    required this.board,
    required this.sketchName,
    required this.dir,
    required this.createdAt,
    this.libraries = const [],
  });

  final String id;
  final CompileBoard board;
  final String sketchName;
  final Directory dir;
  final DateTime createdAt;

  /// Bibliothèques demandées par le projet, déjà vérifiées dans l'index.
  final List<LibraryRelease> libraries;
  final CancelToken cancel = CancelToken();

  Directory get sketchDir => Directory(p.join(dir.path, 'sketch', sketchName));
  Directory get outDir => Directory(p.join(dir.path, 'out'));

  BuildState state = BuildState.queued;
  String log = '';
  String? message;
  List<Diagnostic> diagnostics = const [];
  List<CollectedArtifact> artifacts = const [];
  DateTime? startedAt;
  DateTime? finishedAt;
  Timer? expiry;
}

/// File de compilations : borne le nombre de builds simultanés, garde les résultats un temps limité
/// et supprime le code source dès la fin de chaque build.
class JobManager {
  JobManager({required this.config, required this.runner, this.libraries, DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  /// Taille maximale du journal gardé en mémoire (la fin est conservée).
  static const int maxLogChars = 256 * 1024;

  final ServerConfig config;
  final BuildRunner runner;

  /// Catalogue des bibliothèques Arduino ; null : les projets ne peuvent pas en demander.
  final LibraryService? libraries;
  final DateTime Function() _now;
  final Map<String, _Job> _jobs = {};
  final Queue<_Job> _queue = Queue();
  int _running = 0;
  bool _closed = false;

  int get runningCount => _running;
  int get queuedCount => _queue.length;

  /// Valide et extrait le projet, puis le met en file. Lève [ProjectException] si le projet est refusé
  /// et [QueueFullException] si la file est pleine.
  BuildStatus submit({required CompileBoard board, required List<int> zipBytes, String? sketchName}) {
    if (_queue.length >= config.maxQueuedBuilds) throw QueueFullException(config.maxQueuedBuilds);

    final id = _newId();
    final dir = Directory(p.join(config.workDir, id))..createSync(recursive: true);
    try {
      final project = extractProject(
        zipBytes,
        Directory(p.join(dir.path, 'sketch')),
        name: sketchName,
        maxFiles: config.maxProjectFiles,
        maxBytes: config.maxProjectBytes,
      );
      Directory(p.join(dir.path, 'out')).createSync();
      // Le conteneur tourne avec un autre utilisateur : il doit pouvoir écrire ses résultats.
      _makeWorldWritable(Directory(p.join(dir.path, 'out')));
      final job = _Job(
        id: id,
        board: board,
        sketchName: project.sketchName,
        dir: dir,
        createdAt: _now(),
        libraries: _projectLibraries(project.sketchDir),
      );
      _jobs[id] = job;
      _queue.add(job);
      _pump();
      return _status(job);
    } catch (_) {
      _deleteQuietly(dir);
      rethrow;
    }
  }

  /// Bibliothèques du projet, vérifiées dans l'index officiel (rien n'est téléchargé ici).
  List<LibraryRelease> _projectLibraries(Directory sketchDir) {
    final refs = readProjectLibraries(sketchDir);
    if (refs.isEmpty) return const [];
    if (refs.length > maxProjectLibraries) {
      throw ProjectException('Trop de bibliothèques : $maxProjectLibraries au maximum.');
    }
    final index = libraries?.index;
    if (index == null) {
      throw ProjectException("Le catalogue de bibliothèques n'est pas disponible pour le moment : réessayez plus tard.");
    }
    return [
      for (final ref in refs)
        index.release(ref.name, ref.version) ??
            (throw ProjectException('Bibliothèque introuvable : ${ref.name} ${ref.version}.')),
    ];
  }

  BuildStatus? status(String id) {
    final job = _jobs[id];
    return job == null ? null : _status(job);
  }

  /// Fichier d'un artefact d'un build réussi, `null` s'il n'existe pas.
  File? artifactFile(String id, String name) {
    final job = _jobs[id];
    if (job == null || job.state != BuildState.succeeded) return null;
    for (final artifact in job.artifacts) {
      if (artifact.info.name == name) return artifact.file;
    }
    return null;
  }

  /// Annule un build en cours ou en attente ; supprime un build terminé. `false` si l'id est inconnu.
  bool cancel(String id) {
    final job = _jobs[id];
    if (job == null) return false;
    if (job.state.isFinished) {
      _forget(job);
      return true;
    }
    job.cancel.cancel();
    if (job.state == BuildState.queued) {
      _queue.remove(job);
      _finish(job, BuildState.cancelled, message: 'Compilation annulée.');
    }
    return true;
  }

  Future<void> dispose() async {
    _closed = true;
    for (final job in _jobs.values.toList()) {
      job.cancel.cancel();
      job.expiry?.cancel();
      _deleteQuietly(job.dir);
    }
    _jobs.clear();
    _queue.clear();
  }

  // ---------------------------------------------------------------------------

  void _pump() {
    while (!_closed && _running < config.maxConcurrentBuilds && _queue.isNotEmpty) {
      final job = _queue.removeFirst();
      _running++;
      unawaited(_execute(job).whenComplete(() {
        _running--;
        _pump();
      }));
    }
  }

  Future<void> _execute(_Job job) async {
    job.state = BuildState.running;
    job.startedAt = _now();
    try {
      final libraryDirs = <Directory>[];
      for (final release in job.libraries) {
        if (job.cancel.isCancelled) break;
        job.log = _appendLog(job.log, 'Bibliothèque ${release.name} ${release.version}\n');
        try {
          libraryDirs.add(await libraries!.cache.ensure(release));
        } on LibraryInstallException catch (e) {
          _finish(job, BuildState.failed, message: e.message);
          return;
        }
      }
      if (job.cancel.isCancelled) {
        _finish(job, BuildState.cancelled, message: 'Compilation annulée.');
        return;
      }
      final outcome = await runner.run(
        RunRequest(
          id: job.id,
          board: job.board,
          sketchName: job.sketchName,
          sketchDir: job.sketchDir,
          outDir: job.outDir,
          libraries: libraryDirs,
        ),
        onOutput: (text) => job.log = _appendLog(job.log, text),
        cancel: job.cancel,
      );
      job.diagnostics = parseCompilerOutput(job.log, sourceRoots: ['/work/sketch/${job.sketchName}']);
      if (outcome.cancelled) {
        _finish(job, BuildState.cancelled, message: 'Compilation annulée.');
      } else if (outcome.timedOut) {
        _finish(job, BuildState.timedOut, message: 'Délai dépassé (${config.buildTimeout.inMinutes} min).');
      } else if (outcome.exitCode != 0) {
        _finish(job, BuildState.failed, message: job.diagnostics.any((d) => d.severity == DiagnosticSeverity.error) ? null : 'La compilation a échoué (code ${outcome.exitCode}).');
      } else {
        job.artifacts = await collectArtifacts(job.outDir, job.board);
        final flashable = job.artifacts.any((a) => a.info.role != ArtifactRole.debug);
        _finish(
          job,
          flashable ? BuildState.succeeded : BuildState.failed,
          message: flashable ? null : "La compilation a réussi mais n'a produit aucun binaire à flasher.",
        );
      }
    } catch (e) {
      _finish(job, BuildState.failed, message: 'Erreur interne du service de compilation.');
      job.log = _appendLog(job.log, '\n[service] $e\n');
    }
  }

  void _finish(_Job job, BuildState state, {String? message}) {
    job.state = state;
    job.message = message;
    job.finishedAt = _now();
    // Le code source n'est pas conservé au-delà de la compilation.
    _deleteQuietly(Directory(p.join(job.dir.path, 'sketch')));
    if (state != BuildState.succeeded) _deleteQuietly(job.outDir);
    job.expiry?.cancel();
    job.expiry = Timer(config.jobRetention, () => _forget(job));
  }

  void _forget(_Job job) {
    job.expiry?.cancel();
    _jobs.remove(job.id);
    _deleteQuietly(job.dir);
  }

  BuildStatus _status(_Job job) {
    final started = job.startedAt;
    final finished = job.finishedAt;
    return BuildStatus(
      id: job.id,
      state: job.state,
      board: job.board.id,
      log: job.log,
      diagnostics: job.diagnostics,
      artifacts: [for (final a in job.artifacts) a.info],
      message: job.message,
      queuePosition: job.state == BuildState.queued ? _queue.toList().indexOf(job) : null,
      durationMs: started != null && finished != null ? finished.difference(started).inMilliseconds : null,
    );
  }

  static String _appendLog(String log, String text) {
    final joined = log + text;
    return joined.length <= maxLogChars ? joined : joined.substring(joined.length - maxLogChars);
  }

  static String _newId() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  static void _makeWorldWritable(Directory dir) {
    if (Platform.isWindows) return;
    Process.runSync('chmod', ['777', dir.path]);
  }

  static void _deleteQuietly(Directory dir) {
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } on FileSystemException {
      // dossier déjà parti ou verrouillé : le prochain nettoyage réessaiera
    }
  }
}
