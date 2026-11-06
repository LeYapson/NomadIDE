import '../../projects/data/project_store.dart';

/// Extensions de fichiers qui contiennent du code C/C++.
const List<String> _sourceExtensions = ['.ino', '.cpp', '.c', '.cc', '.h', '.hpp', '.hh'];

final RegExp _include = RegExp(r'^\s*#\s*include\s*([<"])\s*([^>"\n]+?)\s*[>"]', multiLine: true);

/// En-têtes inclus par [source] (`#include <DHT.h>` ou `#include "DHT.h"`), dans l'ordre, sans doublon.
List<String> includesOf(String source) {
  final seen = <String>{};
  return [
    for (final match in _include.allMatches(source))
      if (seen.add(match.group(2)!)) match.group(2)!,
  ];
}

/// En-têtes que le projet inclut et qui ne sont pas l'un de ses propres fichiers : ceux-là viennent d'une bibliothèque
/// ou du cœur de la carte. Un `#include "capteur.h"` qui désigne un fichier du projet n'est pas à chercher ailleurs.
Future<List<String>> externalIncludes(ProjectStore store, String project) async {
  final files = <String>[];
  Future<void> walk(String directory) async {
    for (final entry in await store.listEntries(project, directory)) {
      if (entry.name.startsWith('.') || entry.name == 'build') continue;
      if (entry.isDirectory) {
        await walk(entry.path);
      } else {
        files.add(entry.path);
      }
    }
  }

  await walk('');
  final own = {for (final f in files) f.split('/').last.toLowerCase()};
  final found = <String>{};
  for (final path in files) {
    if (!_sourceExtensions.any(path.toLowerCase().endsWith)) continue;
    found.addAll(includesOf(await store.readText(project, path)));
  }
  return [
    for (final header in found)
      if (!own.contains(header.split('/').last.toLowerCase())) header,
  ]..sort();
}

/// En-têtes manquants d'après un message du compilateur (`fatal error: DHT.h: No such file or directory`).
List<String> missingHeadersIn(Iterable<String> messages) {
  final pattern = RegExp(r'([\w./+-]+\.(?:h|hpp|hh)):\s*No such file or directory');
  final found = <String>{};
  for (final message in messages) {
    final match = pattern.firstMatch(message);
    if (match != null) found.add(match.group(1)!);
  }
  return found.toList();
}
