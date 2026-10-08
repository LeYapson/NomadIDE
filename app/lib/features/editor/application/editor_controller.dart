import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_editor/nomad_editor.dart';

import '../../../app/providers.dart';
import '../../micropython/application/micropython_controller.dart';

/// Un fichier ouvert dans l'éditeur.
class EditorDocument {
  EditorDocument({required this.id, required this.name, this.boardPath, String text = ''})
      : controller = NomadEditorController(text: text, language: CodeLanguage.fromFileName(name)),
        savedText = text;

  final int id;
  String name;

  /// Chemin sur la carte ; null tant que le fichier n'y a pas été enregistré.
  String? boardPath;

  /// Dernier contenu connu de la carte, pour détecter les modifications.
  String savedText;

  final NomadEditorController controller;

  bool get dirty => controller.text != savedText;
}

@immutable
class EditorState {
  const EditorState({this.documents = const [], this.activeIndex = 0});

  final List<EditorDocument> documents;
  final int activeIndex;

  EditorDocument? get active => documents.isEmpty ? null : documents[activeIndex.clamp(0, documents.length - 1)];

  EditorState copyWith({List<EditorDocument>? documents, int? activeIndex}) =>
      EditorState(documents: documents ?? this.documents, activeIndex: activeIndex ?? this.activeIndex);
}

final editorProvider = NotifierProvider<EditorController, EditorState>(EditorController.new);

/// Documents ouverts dans l'éditeur, enregistrement et exécution sur la carte.
class EditorController extends Notifier<EditorState> {
  int _nextId = 1;

  /// Contrôleurs à libérer ; l'état n'est pas lisible depuis `onDispose`.
  final List<EditorDocument> _owned = [];

  @override
  EditorState build() {
    ref.onDispose(() {
      for (final document in _owned) {
        document.controller.dispose();
      }
      _owned.clear();
    });
    return const EditorState();
  }

  EditorDocument _create({required String name, String? boardPath, String text = ''}) {
    final document = EditorDocument(id: _nextId++, name: name, boardPath: boardPath, text: text);
    _owned.add(document);
    return document;
  }

  void newDocument({String name = 'main.py', String text = ''}) {
    final document = _create(name: name, text: text);
    state = EditorState(documents: [...state.documents, document], activeIndex: state.documents.length);
  }

  /// Ouvre un fichier de la carte (ou revient sur son onglet s'il est déjà ouvert).
  void openBoardFile(String path, String text) {
    final existing = state.documents.indexWhere((d) => d.boardPath == path);
    if (existing >= 0) {
      state = state.copyWith(activeIndex: existing);
      return;
    }
    final name = path.split('/').last;
    final document = _create(name: name, boardPath: path, text: text);
    state = EditorState(documents: [...state.documents, document], activeIndex: state.documents.length);
  }

  /// Ouvre un fichier de la carte et affiche l'éditeur.
  void openAndShow(String path, String text) {
    openBoardFile(path, text);
    ref.read(homeTabProvider.notifier).show(HomeTab.editor);
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
    state = EditorState(documents: remaining, activeIndex: active);
    _owned.remove(document);
    document.controller.dispose();
  }

  /// Enregistre sur la carte, sous [path] (celui du document par défaut). Faux si l'écriture échoue.
  Future<bool> saveToBoard(EditorDocument document, {String? path}) async {
    final target = path ?? document.boardPath;
    if (target == null) return false;
    final written = await ref.read(microPythonProvider.notifier).writeFile(target, document.controller.text);
    if (!written) return false;
    document
      ..boardPath = target
      ..name = target.split('/').last
      ..savedText = document.controller.text;
    state = state.copyWith(documents: [...state.documents]);
    return true;
  }

  /// Envoie le contenu tel quel à la carte, sans l'enregistrer (script temporaire).
  Future<void> run(EditorDocument document) =>
      ref.read(microPythonProvider.notifier).run(document.controller.text, label: 'run ${document.name}');
}
