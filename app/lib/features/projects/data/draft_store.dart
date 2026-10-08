import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'file_utils.dart';

/// Contenu non enregistré d'un onglet de l'éditeur, conservé pour être proposé
/// à la réouverture de l'application après une fermeture brutale.
class Draft {
  const Draft({
    required this.id,
    required this.name,
    required this.text,
    required this.updatedAt,
    this.project,
    this.path,
    this.boardPath,
  });

  final String id;
  final String name;
  final String text;
  final DateTime updatedAt;

  /// Fichier local d'origine (projet et chemin relatif), s'il y en a un.
  final String? project;
  final String? path;

  /// Fichier d'origine sur la carte, s'il y en a un.
  final String? boardPath;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'text': text,
        'updatedAt': updatedAt.toIso8601String(),
        'project': project,
        'path': path,
        'boardPath': boardPath,
      };

  static Draft? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final text = json['text'];
    final updated = DateTime.tryParse('${json['updatedAt']}');
    if (id is! String || name is! String || text is! String || updated == null) return null;
    return Draft(
      id: id,
      name: name,
      text: text,
      updatedAt: updated,
      project: json['project'] as String?,
      path: json['path'] as String?,
      boardPath: json['boardPath'] as String?,
    );
  }
}

/// Brouillons sous `<racine>/drafts`, un fichier JSON par onglet, écrits de façon atomique.
class DraftStore {
  DraftStore(this.root);

  final Directory root;

  Directory get _dir => Directory(p.join(root.path, 'drafts'));

  static final RegExp _safeId = RegExp(r'^[A-Za-z0-9_-]{1,80}$');

  File _file(String id) {
    if (!_safeId.hasMatch(id)) throw ArgumentError.value(id, 'id', 'identifiant de brouillon invalide');
    return File(p.join(_dir.path, '$id.json'));
  }

  Future<void> save(Draft draft) async {
    await atomicWrite(_file(draft.id), utf8.encode(jsonEncode(draft.toJson())));
  }

  Future<void> delete(String id) async {
    final file = _file(id);
    if (await file.exists()) await file.delete();
  }

  /// Brouillons lisibles, du plus récent au plus ancien. Un fichier corrompu est ignoré.
  Future<List<Draft>> list() async {
    if (!await _dir.exists()) return const [];
    final drafts = <Draft>[];
    await for (final entity in _dir.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final draft = Draft.fromJson(jsonDecode(await entity.readAsString()));
        if (draft != null) drafts.add(draft);
      } on FormatException {
        // Écriture interrompue ou fichier étranger : ignoré.
      } on FileSystemException {
        // Illisible : ignoré.
      }
    }
    return drafts..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> clear() async {
    if (await _dir.exists()) await _dir.delete(recursive: true);
  }
}
