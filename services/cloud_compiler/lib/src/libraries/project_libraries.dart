import 'dart:convert';
import 'dart:io';

import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:path/path.dart' as p;

/// Nombre maximal de bibliothèques par projet.
const int maxProjectLibraries = 40;

/// Bibliothèques demandées par un projet : la clé `libraries` de son fichier `nomad.json`
/// (`[{"name": "DHT sensor library", "version": "1.4.6"}]`). Un fichier absent, illisible ou sans cette clé
/// donne une liste vide ; les entrées incomplètes sont ignorées.
List<LibraryRef> readProjectLibraries(Directory sketchDir) {
  final file = File(p.join(sketchDir.path, 'nomad.json'));
  if (!file.existsSync()) return const [];
  try {
    final json = jsonDecode(file.readAsStringSync());
    final list = json is Map ? json['libraries'] : null;
    if (list is! List) return const [];
    final seen = <String>{};
    final refs = <LibraryRef>[];
    for (final entry in list) {
      if (entry is Map && entry['name'] is String && entry['version'] is String) {
        final ref = LibraryRef(name: entry['name'] as String, version: entry['version'] as String);
        if (seen.add(ref.name.toLowerCase())) refs.add(ref);
      }
    }
    return refs;
  } on Object {
    return const [];
  }
}
