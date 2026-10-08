import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_editor/nomad_editor.dart';

import '../../../app/providers.dart';
import '../../micropython/application/micropython_controller.dart';
import '../../projects/application/projects_controller.dart';
import '../../projects/data/draft_store.dart';
import '../../projects/data/storage_exception.dart';

/// Un fichier ouvert dans l'éditeur.
class EditorDocument {
  EditorDocument({
    required this.id,
    required this.name,
    this.boardPath,
    this.localProject,
    this.localPath,
    String text = '',
    String? savedText,
  })  : controller = NomadEditorController(text: text, language: CodeLanguage.fromFileName(name)),
        savedText = savedText ?? text;

  final String id;
  String name;

  /// Chemin sur la carte ; null tant que le fichier n'y a pas été envoyé ni ouvert depuis elle.
  String? boardPath;

  /// Fichier local (projet et chemin relatif) ; null tant qu'il n'est pas enregistré sur l'appareil.
  String? localProject;
  String? localPath;

  /// Dernier contenu enregistré, pour détecter les modifications.
  String savedText;

  final NomadEditorController controller;

  bool get dirty => controller.text != savedText;

  bool get hasLocalTarget => localProject != null && localPath != null;

  bool isLocal(String project, String path) => localProject == project && localPath == path;
}

@immutable
class EditorState {
  const EditorState({this.documents = const [], this.activeIndex = 0, this.pendingDrafts = const []});

  final List<EditorDocument> documents;
  final int activeIndex;

  /// Brouillons d'une session précédente, à proposer à l'utilisateur.
  final List<Draft> pendingDrafts;

  EditorDocument? get active => documents.isEmpty ? null : documents[activeIndex.clamp(0, documents.length - 1)];

  EditorState copyWith({List<EditorDocument>? documents, int? activeIndex, List<Draft>? pendingDrafts}) => EditorState(
        documents: documents ?? this.documents,
        activeIndex: activeIndex ?? this.activeIndex,
        pendingDrafts: pendingDrafts ?? this.pendingDrafts,
      );
}

final editorProvider = NotifierProvider<EditorController, EditorState>(EditorController.new);

/// Documents ouverts dans l'éditeur : enregistrement local, envoi sur la carte,
/// exécution, brouillons automatiques.
class EditorController extends Notifier<EditorState> {
  int _sequence = 0;

  /// Contrôleurs à libérer ; l'état n'est pas lisible depuis `onDispose`.
  final List<EditorDocument> _owned = [];
  final Map<String, Timer> _draftTimers = {};
  final Map<String, VoidCallback> _listeners = {};
  bool _disposed = false;

  @override
  EditorState build() {
    ref.onDispose(() {
      _disposed = true;
      for (final timer in _draftTimers.values) {
        timer.cancel();
      }
      _draftTimers.clear();
      for (final document in _owned) {
        document.controller.removeListener(_listeners[document.id]!);
        document.controller.dispose();
      }
      _owned.clear();
    });
    Future.microtask(_loadPendingDrafts);
    return const EditorState();
  }

  String _newId() => '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${_sequence++}';

  EditorDocument _create({
    required String name,
    String? boardPath,
    String? localProject,
    String? localPath,
    String text = '',
    String? savedText,
    String? id,
  }) {
    final document = EditorDocument(
      id: id ?? _newId(),
      name: name,
      boardPath: boardPath,
      localProject: localProject,
      localPath: localPath,
      text: text,
      savedText: savedText,
    );
    void listener() => _onDocumentChanged(document);
    document.controller.addListener(listener);
    _listeners[document.id] = listener;
    _owned.add(document);
    return document;
  }

  void _add(EditorDocument document) {
    state = state.copyWith(documents: [...state.documents, document], activeIndex: state.documents.length);
  }

  void newDocument({String name = 'main.py', String text = ''}) => _add(_create(name: name, text: text));

  /// Ouvre un fichier de la carte (ou revient sur son onglet s'il est déjà ouvert).
  void openBoardFile(String path, String text) {
    final existing = state.documents.indexWhere((d) => d.boardPath == path && !d.hasLocalTarget);
    if (existing >= 0) {
      state = state.copyWith(activeIndex: existing);
      return;
    }
    _add(_create(name: path.split('/').last, boardPath: path, text: text));
  }

  /// Ouvre un fichier de la carte et affiche l'éditeur.
  void openAndShow(String path, String text) {
    openBoardFile(path, text);
    ref.read(homeTabProvider.notifier).show(HomeTab.editor);
  }

  /// Ouvre un fichier local (ou revient sur son onglet). Faux si la lecture échoue :
  /// l'erreur est alors portée par [projectsProvider].
  Future<bool> openLocalFile(String project, String path, {bool show = false}) async {
    final existing = state.documents.indexWhere((d) => d.isLocal(project, path));
    if (existing >= 0) {
      state = state.copyWith(activeIndex: existing);
      if (show) ref.read(homeTabProvider.notifier).show(HomeTab.editor);
      return true;
    }
    try {
      final text = await (await ref.read(projectStoreProvider.future)).readText(project, path);
      _add(_create(name: path.split('/').last, localProject: project, localPath: path, text: text));
      if (show) ref.read(homeTabProvider.notifier).show(HomeTab.editor);
      return true;
    } on StorageException catch (e) {
      ref.read(projectsProvider.notifier).reportError(e);
      return false;
    }
  }

  void select(int index) {
    if (index >= 0 && index < state.documents.length) state = state.copyWith(activeIndex: index);
  }

  void close(EditorDocument document) {
    final index = state.documents.indexOf(document);
    if (index < 0) return;
    final remaining = [...state.documents]..removeAt(index);
    final active = state.activeIndex > index || state.activeIndex >= remaining.length
        ? (state.activeIndex - 1).clamp(0, remaining.isEmpty ? 0 : remaining.length - 1)
        : state.activeIndex;
    state = state.copyWith(documents: remaining, activeIndex: active);
    _draftTimers.remove(document.id)?.cancel();
    _deleteDraft(document.id);
    _owned.remove(document);
    document.controller.removeListener(_listeners.remove(document.id)!);
    document.controller.dispose();
  }

  // ---------------------------------------------------------------------------
  // Enregistrement
  // ---------------------------------------------------------------------------

  /// Enregistre sur l'appareil, à l'emplacement du document ou sous ([project], [path]).
  /// Faux si le document n'a pas d'emplacement ou si l'écriture échoue.
  Future<bool> saveLocal(EditorDocument document, {String? project, String? path}) async {
    final targetProject = project ?? document.localProject;
    final targetPath = path ?? document.localPath;
    if (targetProject == null || targetPath == null) return false;
    final text = document.controller.text;
    try {
      await (await ref.read(projectStoreProvider.future)).writeText(targetProject, targetPath, text);
    } on StorageException catch (e) {
      ref.read(projectsProvider.notifier).reportError(e);
      return false;
    }
    document
      ..localProject = targetProject
      ..localPath = targetPath
      ..name = targetPath.split('/').last
      ..savedText = text;
    document.controller.language = CodeLanguage.fromFileName(document.name);
    _draftTimers.remove(document.id)?.cancel();
    await _deleteDraft(document.id);
    state = state.copyWith(documents: [...state.documents]);
    await ref.read(projectsProvider.notifier).refresh();
    return true;
  }

  /// Envoie sur la carte, sous [path] (celui du document par défaut). Faux si l'écriture échoue.
  Future<bool> saveToBoard(EditorDocument document, {String? path}) async {
    final target = path ?? document.boardPath;
    if (target == null) return false;
    final written = await ref.read(microPythonProvider.notifier).writeFile(target, document.controller.text);
    if (!written) return false;
    document.boardPath = target;
    // Sans copie locale, la carte est la seule destination : le document est alors à jour.
    if (!document.hasLocalTarget) {
      document
        ..name = target.split('/').last
        ..savedText = document.controller.text;
      _draftTimers.remove(document.id)?.cancel();
      await _deleteDraft(document.id);
    }
    state = state.copyWith(documents: [...state.documents]);
    return true;
  }

  /// Envoie à la carte la sélection (lignes entières) ou, sans sélection, tout le
  /// fichier, sans rien enregistrer (script temporaire).
  Future<void> run(EditorDocument document) {
    final selection = !document.controller.code.selection.isCollapsed;
    return ref.read(microPythonProvider.notifier).run(
          document.controller.runnableText,
          label: selection ? 'run ${document.name} (sélection)' : 'run ${document.name}',
        );
  }

  // ---------------------------------------------------------------------------
  // Brouillons
  // ---------------------------------------------------------------------------

  void _onDocumentChanged(EditorDocument document) {
    if (_disposed) return;
    _draftTimers.remove(document.id)?.cancel();
    if (!document.dirty) {
      _deleteDraft(document.id);
      return;
    }
    _draftTimers[document.id] = Timer(ref.read(draftDelayProvider), () {
      _draftTimers.remove(document.id);
      _writeDraft(document);
    });
  }

  /// Écrit tout de suite les brouillons en attente (fermeture de l'app, tests).
  Future<void> flushDrafts() async {
    for (final timer in _draftTimers.values) {
      timer.cancel();
    }
    _draftTimers.clear();
    for (final document in state.documents) {
      if (document.dirty) await _writeDraft(document);
    }
  }

  Future<void> _writeDraft(EditorDocument document) async {
    try {
      await (await ref.read(draftStoreProvider.future)).save(Draft(
        id: document.id,
        name: document.name,
        text: document.controller.text,
        updatedAt: DateTime.now(),
        project: document.localProject,
        path: document.localPath,
        boardPath: document.boardPath,
      ));
    } catch (e) {
      // Un brouillon manqué ne doit jamais gêner la frappe.
      debugPrint('[editor] brouillon non écrit : $e');
    }
  }

  Future<void> _deleteDraft(String id) async {
    try {
      await (await ref.read(draftStoreProvider.future)).delete(id);
    } catch (e) {
      debugPrint('[editor] brouillon non supprimé : $e');
    }
  }

  Future<void> _loadPendingDrafts() async {
    try {
      final drafts = await (await ref.read(draftStoreProvider.future)).list();
      if (_disposed || drafts.isEmpty) return;
      state = state.copyWith(pendingDrafts: drafts);
    } catch (e) {
      debugPrint('[editor] brouillons illisibles : $e');
    }
  }

  /// Rouvre les brouillons trouvés au démarrage, chacun dans son onglet.
  Future<void> restoreDrafts() async {
    final drafts = state.pendingDrafts;
    state = state.copyWith(pendingDrafts: const []);
    for (final draft in drafts) {
      var saved = '';
      if (draft.project != null && draft.path != null) {
        try {
          saved = await (await ref.read(projectStoreProvider.future)).readText(draft.project!, draft.path!);
        } on StorageException {
          // Fichier supprimé depuis : le brouillon redevient un document à enregistrer.
        }
      }
      if (draft.text == saved) {
        await _deleteDraft(draft.id);
        continue;
      }
      _add(_create(
        id: draft.id,
        name: draft.name,
        boardPath: draft.boardPath,
        localProject: draft.project,
        localPath: draft.path,
        text: draft.text,
        savedText: saved,
      ));
    }
  }

  /// Abandonne les brouillons trouvés au démarrage.
  Future<void> discardDrafts() async {
    final drafts = state.pendingDrafts;
    state = state.copyWith(pendingDrafts: const []);
    for (final draft in drafts) {
      await _deleteDraft(draft.id);
    }
  }
}
