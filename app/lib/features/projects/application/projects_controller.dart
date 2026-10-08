import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../data/project_store.dart';
import '../data/storage_exception.dart';

const Object _unset = Object();

@immutable
class ProjectsState {
  const ProjectsState({
    this.loaded = false,
    this.projects = const [],
    this.current,
    this.directory = '',
    this.entries = const [],
    this.error,
  });

  /// Faux tant que la liste initiale n'a pas été lue sur le disque.
  final bool loaded;
  final List<String> projects;

  /// Projet affiché ; null s'il n'y en a aucun.
  final String? current;

  /// Dossier affiché, relatif au projet (`''` = racine).
  final String directory;
  final List<ProjectEntry> entries;

  /// Dernière erreur de stockage, à montrer une fois à l'utilisateur.
  final StorageException? error;

  ProjectsState copyWith({
    bool? loaded,
    List<String>? projects,
    Object? current = _unset,
    String? directory,
    List<ProjectEntry>? entries,
    Object? error = _unset,
  }) {
    return ProjectsState(
      loaded: loaded ?? this.loaded,
      projects: projects ?? this.projects,
      current: identical(current, _unset) ? this.current : current as String?,
      directory: directory ?? this.directory,
      entries: entries ?? this.entries,
      error: identical(error, _unset) ? this.error : error as StorageException?,
    );
  }
}

final projectsProvider = NotifierProvider<ProjectsController, ProjectsState>(ProjectsController.new);

/// Projets locaux : liste, dossier courant, création, renommage, suppression.
class ProjectsController extends Notifier<ProjectsState> {
  @override
  ProjectsState build() {
    Future.microtask(refresh);
    return const ProjectsState();
  }

  Future<ProjectStore> get _store => ref.read(projectStoreProvider.future);

  /// Relit le disque : projets, puis contenu du dossier courant.
  Future<void> refresh() => _run(() async {
        final store = await _store;
        final projects = await store.listProjects();
        final current = projects.contains(state.current) ? state.current : projects.firstOrNull;
        state = state.copyWith(loaded: true, projects: projects, current: current);
        await _loadEntries();
      });

  Future<void> selectProject(String name) => _run(() async {
        state = state.copyWith(current: name, directory: '');
        await _loadEntries();
      });

  /// Crée un projet et l'affiche. Renvoie son nom, ou null en cas d'échec.
  Future<String?> createProject(String name) => _run(() async {
        final store = await _store;
        final created = await store.createProject(name);
        state = state.copyWith(projects: await store.listProjects(), current: created, directory: '');
        await _loadEntries();
        return created;
      });

  Future<void> renameProject(String from, String to) => _run(() async {
        final store = await _store;
        final renamed = await store.renameProject(from, to);
        state = state.copyWith(
          projects: await store.listProjects(),
          current: state.current == from ? renamed : state.current,
        );
        await _loadEntries();
      });

  Future<void> deleteProject(String name) => _run(() async {
        final store = await _store;
        await store.deleteProject(name);
        final projects = await store.listProjects();
        state = state.copyWith(
          projects: projects,
          current: state.current == name ? projects.firstOrNull : state.current,
          directory: state.current == name ? '' : state.directory,
        );
        await _loadEntries();
      });

  Future<void> openDirectory(String path) => _run(() async {
        state = state.copyWith(directory: path);
        await _loadEntries();
      });

  Future<void> goUp() => _run(() async {
        if (state.directory.isEmpty) return;
        final parts = state.directory.split('/')..removeLast();
        state = state.copyWith(directory: parts.join('/'));
        await _loadEntries();
      });

  /// Crée un fichier vide dans le dossier courant. Renvoie son chemin relatif, ou null.
  Future<String?> createFile(String name) => _run(() async {
        final project = _requireProject();
        final path = _child(name);
        await (await _store).createFile(project, path);
        await _loadEntries();
        return path;
      });

  Future<void> createFolder(String name) => _run(() async {
        await (await _store).createDirectory(_requireProject(), _child(name));
        await _loadEntries();
      });

  /// Renomme [entry] dans son dossier. Renvoie le nouveau chemin relatif, ou null.
  Future<String?> renameEntry(ProjectEntry entry, String newName) => _run(() async {
        final project = _requireProject();
        final parent = entry.path.contains('/') ? entry.path.substring(0, entry.path.lastIndexOf('/')) : '';
        final target = parent.isEmpty ? newName.trim() : '$parent/${newName.trim()}';
        await (await _store).renameEntry(project, entry.path, target);
        await _loadEntries();
        return target;
      });

  Future<void> deleteEntry(ProjectEntry entry) => _run(() async {
        await (await _store).deleteEntry(_requireProject(), entry.path);
        await _loadEntries();
      });

  void clearError() => state = state.copyWith(error: null);

  /// Signale une erreur de stockage survenue ailleurs (éditeur) pour l'afficher une fois.
  void reportError(StorageException error) => state = state.copyWith(error: error);

  // ---------------------------------------------------------------------------

  String _requireProject() {
    final project = state.current;
    if (project == null) throw const StorageException(StorageError.notFound);
    return project;
  }

  String _child(String name) => state.directory.isEmpty ? name.trim() : '${state.directory}/${name.trim()}';

  Future<void> _loadEntries() async {
    final project = state.current;
    if (project == null) {
      state = state.copyWith(entries: const [], directory: '');
      return;
    }
    try {
      state = state.copyWith(entries: await (await _store).listEntries(project, state.directory));
    } on StorageException catch (e) {
      // Dossier disparu entre-temps : retour à la racine plutôt qu'une liste cassée.
      if (e.error != StorageError.notFound || state.directory.isEmpty) rethrow;
      state = state.copyWith(directory: '', entries: await (await _store).listEntries(project));
    }
  }

  /// Exécute [action] ; en cas d'échec de stockage, mémorise l'erreur et renvoie null.
  /// Si le fournisseur est détruit pendant l'opération, le résultat est abandonné.
  Future<T?> _run<T>(Future<T> Function() action) async {
    try {
      final result = await action();
      if (!ref.mounted) return null;
      if (state.error != null) state = state.copyWith(error: null);
      return result;
    } on StorageException catch (e) {
      if (!ref.mounted) return null;
      state = state.copyWith(error: e);
      return null;
    } catch (e) {
      if (!ref.mounted) return null;
      // Stockage indisponible (plugin absent, permission…) : l'app reste utilisable.
      state = state.copyWith(loaded: true, error: StorageException(StorageError.io, cause: e));
      return null;
    }
  }
}
