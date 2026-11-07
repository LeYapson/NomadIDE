import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Projet refusé : le message est montré tel quel à l'utilisateur.
class ProjectException implements Exception {
  ProjectException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Résultat de l'extraction : le croquis est dans `<dest>/<sketchName>/`.
class ExtractedProject {
  const ExtractedProject({required this.sketchName, required this.sketchDir, required this.fileCount});

  final String sketchName;
  final Directory sketchDir;
  final int fileCount;
}

final RegExp _sketchName = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}$');

/// Décompresse [zipBytes] dans `<dest>/<nom du croquis>/` en refusant tout ce qui pourrait sortir
/// du dossier (chemins absolus ou avec `..`, liens symboliques) et en bornant la taille.
///
/// `arduino-cli` impose que le dossier du croquis porte le nom du fichier `.ino` principal : ce nom
/// vient de [name] s'il est fourni (projets à plusieurs `.ino`), sinon de l'unique `.ino` à la racine.
/// Un zip qui contient un seul dossier englobant (ce que font la plupart des outils d'archivage) est
/// accepté : le dossier est retiré.
ExtractedProject extractProject(
  List<int> zipBytes,
  Directory dest, {
  String? name,
  required int maxFiles,
  required int maxBytes,
}) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(zipBytes);
  } catch (_) {
    throw ProjectException("Le fichier envoyé n'est pas une archive zip valide.");
  }

  final files = archive.files.where((f) => f.isFile).toList();
  if (files.isEmpty) throw ProjectException('Le projet est vide.');
  if (files.length > maxFiles) throw ProjectException('Trop de fichiers : $maxFiles au maximum.');

  final entries = <String, ArchiveFile>{};
  var total = 0;
  for (final file in files) {
    if (file.isSymbolicLink) throw ProjectException('Les liens symboliques sont interdits (${file.name}).');
    total += file.size;
    if (total > maxBytes) throw ProjectException('Projet trop volumineux : ${maxBytes ~/ (1024 * 1024)} Mo au maximum.');
    entries[safeArchivePath(file.name)] = file;
  }

  final prefix = _commonDirectory(entries.keys);
  final relative = {for (final e in entries.entries) e.key.substring(prefix.length): e.value};

  final rootInos = relative.keys.where((k) => !k.contains('/') && k.toLowerCase().endsWith('.ino')).toList();
  final String sketchName;
  if (name != null && name.isNotEmpty) {
    if (!relative.containsKey('$name.ino')) throw ProjectException('Le fichier $name.ino est introuvable à la racine du projet.');
    sketchName = name;
  } else if (rootInos.length == 1) {
    sketchName = rootInos.single.substring(0, rootInos.single.length - '.ino'.length);
  } else if (rootInos.isEmpty) {
    throw ProjectException('Aucun fichier .ino à la racine du projet.');
  } else {
    throw ProjectException('Plusieurs fichiers .ino à la racine : indiquez lequel est le principal.');
  }
  if (!_sketchName.hasMatch(sketchName)) {
    throw ProjectException(
      'Nom de croquis invalide « $sketchName » : lettres, chiffres, « _ », « - » et « . » seulement (64 caractères).',
    );
  }

  final sketchDir = Directory(p.join(dest.path, sketchName))..createSync(recursive: true);
  for (final entry in relative.entries) {
    final target = File(p.join(sketchDir.path, entry.key));
    if (!p.isWithin(sketchDir.path, target.path)) throw ProjectException('Chemin refusé : ${entry.key}.');
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(entry.value.content as List<int>);
  }
  return ExtractedProject(sketchName: sketchName, sketchDir: sketchDir, fileCount: relative.length);
}

/// Chemin normalisé en `a/b/c`, ou [ProjectException] s'il sort de la racine.
String safeArchivePath(String raw) {
  final slashed = raw.replaceAll('\\', '/');
  if (slashed.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(slashed)) {
    throw ProjectException('Chemin absolu interdit : $raw.');
  }
  final parts = <String>[];
  for (final part in slashed.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') throw ProjectException('Chemin interdit : $raw.');
    if (part.contains('\x00')) throw ProjectException('Nom de fichier invalide.');
    parts.add(part);
  }
  if (parts.isEmpty) throw ProjectException('Nom de fichier vide.');
  return parts.join('/');
}

/// `dossier/` si tous les fichiers sont dans le même dossier de premier niveau, sinon vide.
String _commonDirectory(Iterable<String> paths) {
  String? first;
  for (final path in paths) {
    final slash = path.indexOf('/');
    if (slash < 0) return '';
    final top = path.substring(0, slash);
    first ??= top;
    if (top != first) return '';
  }
  return first == null ? '' : '$first/';
}
