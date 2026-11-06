import 'dart:convert';

import 'package:nomad_compile_api/nomad_compile_api.dart';

import '../../projects/data/project_store.dart';
import '../../projects/data/storage_exception.dart';

/// Réglages d'un projet C/C++ : le fichier `nomad.json` à sa racine, qui voyage avec le projet.
class ProjectConfig {
  const ProjectConfig({this.board, this.libraries = const [], this.roots = const []});

  static const String fileName = 'nomad.json';

  final CompileBoard? board;

  /// Bibliothèques Arduino du projet, chacune à une version précise (dépendances comprises) : c'est ce que le service
  /// installe, donc deux compilations du même projet utilisent les mêmes versions.
  final List<LibraryRef> libraries;

  /// Noms de celles que l'utilisateur a choisies (les autres sont des dépendances). Sert à retirer une bibliothèque
  /// avec ses dépendances devenues inutiles ; absent d'un fichier écrit à la main : toutes comptent comme choisies.
  final List<String> roots;

  /// Noms des bibliothèques choisies par l'utilisateur, en retombant sur toutes les bibliothèques si [roots] est vide.
  List<String> get chosenNames => roots.isNotEmpty ? roots : [for (final l in libraries) l.name];

  /// Lit le fichier ; un projet sans fichier, ou avec un fichier illisible, n'a pas de carte choisie.
  static Future<ProjectConfig> read(ProjectStore store, String project) async {
    try {
      if (!await store.exists(project, fileName)) return const ProjectConfig();
      final json = jsonDecode(await store.readText(project, fileName));
      if (json is Map) {
        return ProjectConfig(
          board: CompileBoard.fromId(json['board'] as String?),
          libraries: _readLibraries(json['libraries']),
          roots: [for (final r in (json['librariesRoots'] is List ? json['librariesRoots'] as List : const [])) if (r is String) r],
        );
      }
    } on StorageException {
      // illisible : comme absent
    } on FormatException {
      // JSON invalide : comme absent
    }
    return const ProjectConfig();
  }

  static List<LibraryRef> _readLibraries(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final entry in raw)
        if (entry is Map && entry['name'] is String && entry['version'] is String)
          LibraryRef(name: entry['name'] as String, version: entry['version'] as String),
    ];
  }

  /// Écrit la carte choisie en gardant les autres clés du fichier.
  static Future<void> writeBoard(ProjectStore store, String project, CompileBoard board) =>
      _update(store, project, {'board': board.id});

  /// Écrit les bibliothèques du projet ([libraries] : liste complète à versions précises ; [roots] : celles que l'utilisateur
  /// a choisies) en gardant les autres clés. Une liste vide retire les deux clés.
  static Future<void> writeLibraries(ProjectStore store, String project, List<LibraryRef> libraries, List<String> roots) =>
      _update(store, project, {
        'libraries': libraries.isEmpty ? null : [for (final l in libraries) l.toJson()],
        'librariesRoots': libraries.isEmpty || roots.isEmpty ? null : roots,
      });

  static Future<void> _update(ProjectStore store, String project, Map<String, Object?> changes) async {
    var current = <String, Object?>{};
    try {
      if (await store.exists(project, fileName)) {
        final json = jsonDecode(await store.readText(project, fileName));
        if (json is Map<String, Object?>) current = json;
      }
    } on StorageException {
      // on repart d'un fichier neuf
    } on FormatException {
      // idem
    }
    final merged = {...current, ...changes}..removeWhere((key, value) => value == null);
    final text = const JsonEncoder.withIndent('  ').convert(merged);
    await store.writeText(project, fileName, '$text\n');
  }
}
