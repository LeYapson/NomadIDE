import 'dart:convert';

import 'package:nomad_compile_api/nomad_compile_api.dart';

import '../../projects/data/project_store.dart';
import '../../projects/data/storage_exception.dart';

/// Réglages d'un projet C/C++ : le fichier `nomad.json` à sa racine, qui voyage avec le projet.
class ProjectConfig {
  const ProjectConfig({this.board});

  static const String fileName = 'nomad.json';

  final CompileBoard? board;

  /// Lit le fichier ; un projet sans fichier, ou avec un fichier illisible, n'a pas de carte choisie.
  static Future<ProjectConfig> read(ProjectStore store, String project) async {
    try {
      if (!await store.exists(project, fileName)) return const ProjectConfig();
      final json = jsonDecode(await store.readText(project, fileName));
      if (json is Map) return ProjectConfig(board: CompileBoard.fromId(json['board'] as String?));
    } on StorageException {
      // illisible : comme absent
    } on FormatException {
      // JSON invalide : comme absent
    }
    return const ProjectConfig();
  }

  /// Écrit la carte choisie en gardant les autres clés du fichier.
  static Future<void> writeBoard(ProjectStore store, String project, CompileBoard board) async {
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
    final text = const JsonEncoder.withIndent('  ').convert({...current, 'board': board.id});
    await store.writeText(project, fileName, '$text\n');
  }
}
