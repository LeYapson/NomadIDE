import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../projects/data/project_store.dart';

/// Le projet empaqueté pour l'envoi, avec de quoi dire à l'utilisateur ce qui part.
class ProjectPackage {
  const ProjectPackage({required this.project, required this.zip, required this.files, required this.rawBytes, required this.sketches});

  final String project;
  final Uint8List zip;
  final List<String> files;

  /// Taille des fichiers avant compression.
  final int rawBytes;

  /// Fichiers `.ino` à la racine : le service en veut un (ou plusieurs avec un principal indiqué).
  final List<String> sketches;

  /// Nom du croquis principal, ou null s'il y en a zéro ou plusieurs.
  String? get mainSketch => sketches.length == 1 ? sketches.single.substring(0, sketches.single.length - '.ino'.length) : null;
}

class ProjectTooLargeException implements Exception {
  const ProjectTooLargeException(this.size, this.limit);

  final int size;
  final int limit;
}

/// Dossiers et fichiers qui ne partent jamais : cachés (`.git`…) et sorties de compilation.
bool isExcludedFromBuild(String path) {
  for (final part in path.split('/')) {
    if (part.startsWith('.') || part == 'build') return true;
  }
  return false;
}

/// Empaquette [project] en zip. [maxZipBytes] est la limite annoncée par le service.
Future<ProjectPackage> packageProject(ProjectStore store, String project, {required int maxZipBytes}) async {
  final files = <String>[];
  Future<void> walk(String directory) async {
    for (final entry in await store.listEntries(project, directory)) {
      if (isExcludedFromBuild(entry.path)) continue;
      if (entry.isDirectory) {
        await walk(entry.path);
      } else {
        files.add(entry.path);
      }
    }
  }

  await walk('');
  files.sort();

  final archive = Archive();
  var raw = 0;
  for (final path in files) {
    final bytes = await store.readBytes(project, path);
    raw += bytes.length;
    archive.add(ArchiveFile.bytes(path, bytes));
  }
  final zip = Uint8List.fromList(ZipEncoder().encode(archive));
  if (zip.length > maxZipBytes) throw ProjectTooLargeException(zip.length, maxZipBytes);
  return ProjectPackage(
    project: project,
    zip: zip,
    files: files,
    rawBytes: raw,
    sketches: [
      for (final f in files)
        if (!f.contains('/') && f.toLowerCase().endsWith('.ino')) f,
    ],
  );
}
