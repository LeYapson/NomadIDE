import 'dart:io';

import 'storage_exception.dart';

/// Suffixe des fichiers temporaires d'écriture atomique (masqués des listes).
const String tempSuffix = '.nomad-tmp';

/// Écrit [bytes] dans [file] sans jamais laisser un fichier à moitié écrit : les
/// données sont écrites et vidées sur disque dans un fichier voisin, qui remplace
/// ensuite l'original d'un seul renommage. Une coupure brutale laisse donc soit
/// l'ancien contenu, soit le nouveau.
Future<void> atomicWrite(File file, List<int> bytes) async {
  final temp = File('${file.path}$tempSuffix');
  try {
    await file.parent.create(recursive: true);
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
  } on FileSystemException catch (e) {
    try {
      if (await temp.exists()) await temp.delete();
    } on FileSystemException {
      // Rien de plus à faire : l'erreur d'origine est la seule utile.
    }
    throw StorageException(StorageError.io, name: file.uri.pathSegments.last, cause: e);
  }
}

final RegExp _forbidden = RegExp(r'[\\/:*?"<>|\x00-\x1F]');
final RegExp _windowsReserved = RegExp(r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\..*)?$', caseSensitive: false);

/// Valide un nom de projet, de fichier ou de dossier (un seul segment) et le
/// renvoie sans espaces superflus. Les règles sont celles de Windows, les plus
/// strictes, pour que les projets restent portables d'un système à l'autre.
String validateName(String name) {
  final trimmed = name.trim();
  final invalid = trimmed.isEmpty ||
      trimmed.length > 80 ||
      trimmed == '.' ||
      trimmed == '..' ||
      trimmed.endsWith('.') ||
      trimmed.endsWith(tempSuffix) ||
      _forbidden.hasMatch(trimmed) ||
      _windowsReserved.hasMatch(trimmed);
  if (invalid) throw StorageException(StorageError.invalidName, name: name);
  return trimmed;
}
