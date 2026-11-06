import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../project_archive.dart';
import 'library_index.dart';

/// Une bibliothèque qui n'a pas pu être installée (le message est montré à l'utilisateur).
class LibraryInstallException implements Exception {
  LibraryInstallException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Télécharge [url] (au plus [maxBytes] octets).
typedef LibraryDownloader = Future<Uint8List> Function(Uri url, {required int maxBytes});

/// Bibliothèques installées sur le serveur, une fois pour toutes : `<racine>/<nom>@<version>/<Nom_de_la_bibliothèque>/`.
///
/// Rien n'est installé qu'à partir de l'index officiel : l'adresse vient de l'index, doit être en HTTPS sur un
/// hôte autorisé, et l'archive doit avoir la taille et l'empreinte SHA-256 annoncées. L'extraction refuse les
/// chemins sortants et les liens symboliques. Les compilations n'y accèdent qu'en lecture seule.
class LibraryCache {
  LibraryCache({
    required this.root,
    required this.download,
    this.allowedHosts = const {'downloads.arduino.cc'},
    this.maxArchiveBytes = 64 * 1024 * 1024,
    this.maxFiles = 5000,
    this.maxExtractedBytes = 160 * 1024 * 1024,
  });

  final Directory root;
  final LibraryDownloader download;
  final Set<String> allowedHosts;
  final int maxArchiveBytes;
  final int maxFiles;
  final int maxExtractedBytes;

  final Map<String, Future<Directory>> _inFlight = {};

  /// Dossier de la bibliothèque [release], installée au besoin. Plusieurs demandes simultanées pour la même
  /// version ne téléchargent qu'une fois.
  Future<Directory> ensure(LibraryRelease release) {
    final key = _key(release);
    return _inFlight[key] ??= _install(release, key).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  /// Dossier de [release] s'il est déjà installé, sans rien télécharger.
  Directory? installed(LibraryRelease release) {
    final dir = Directory(p.join(root.path, _key(release), libraryDirName(release.name)));
    return File(p.join(dir.parent.path, '.complete')).existsSync() ? dir : null;
  }

  Future<Directory> _install(LibraryRelease release, String key) async {
    final ready = installed(release);
    if (ready != null) return ready;

    final url = Uri.tryParse(release.url);
    if (url == null || url.scheme != 'https' || !allowedHosts.contains(url.host)) {
      throw LibraryInstallException('Adresse de téléchargement refusée pour ${release.name} ${release.version}.');
    }
    final Uint8List bytes;
    try {
      bytes = await download(url, maxBytes: maxArchiveBytes);
    } on LibraryInstallException {
      rethrow;
    } catch (_) {
      throw LibraryInstallException('Téléchargement impossible : ${release.name} ${release.version}.');
    }
    if (release.size > 0 && bytes.length != release.size) {
      throw LibraryInstallException('Taille inattendue pour ${release.name} ${release.version} : archive refusée.');
    }
    if (sha256.convert(bytes).toString() != release.sha256) {
      throw LibraryInstallException('Empreinte incorrecte pour ${release.name} ${release.version} : archive refusée.');
    }

    root.createSync(recursive: true);
    final temp = Directory(p.join(root.path, '.tmp-${DateTime.now().microsecondsSinceEpoch}-${key.hashCode.abs()}'))
      ..createSync(recursive: true);
    try {
      final libDir = Directory(p.join(temp.path, libraryDirName(release.name)))..createSync();
      _extract(bytes, libDir, release);
      final target = Directory(p.join(root.path, key));
      if (target.existsSync()) target.deleteSync(recursive: true);
      Directory(p.join(temp.path)).renameSync(target.path);
      File(p.join(target.path, '.complete')).writeAsStringSync(release.sha256);
      return Directory(p.join(target.path, libraryDirName(release.name)));
    } on FileSystemException {
      throw LibraryInstallException('Installation impossible : ${release.name} ${release.version}.');
    } finally {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    }
  }

  void _extract(Uint8List bytes, Directory libDir, LibraryRelease release) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw LibraryInstallException('Archive illisible : ${release.name} ${release.version}.');
    }
    final files = archive.files.where((f) => f.isFile).toList();
    if (files.isEmpty || files.length > maxFiles) {
      throw LibraryInstallException('Archive de bibliothèque invalide : ${release.name} ${release.version}.');
    }
    final entries = <String, ArchiveFile>{};
    var total = 0;
    for (final file in files) {
      if (file.isSymbolicLink) throw LibraryInstallException('Lien symbolique interdit dans ${release.name}.');
      total += file.size;
      if (total > maxExtractedBytes) throw LibraryInstallException('Bibliothèque trop volumineuse : ${release.name}.');
      try {
        entries[safeArchivePath(file.name)] = file;
      } on ProjectException {
        throw LibraryInstallException('Chemin interdit dans l\'archive de ${release.name}.');
      }
    }

    // Les archives de l'index ont un dossier englobant (`DHT-sensor-library-1.4.6/`) : on le retire.
    final prefix = _commonDirectory(entries.keys);
    final relative = {for (final e in entries.entries) e.key.substring(prefix.length): e.value};
    if (!relative.containsKey('library.properties')) {
      throw LibraryInstallException('Archive de bibliothèque invalide (pas de library.properties) : ${release.name}.');
    }
    for (final entry in relative.entries) {
      final target = File(p.join(libDir.path, entry.key));
      if (!p.isWithin(libDir.path, target.path)) {
        throw LibraryInstallException('Chemin interdit dans l\'archive de ${release.name}.');
      }
      target.parent.createSync(recursive: true);
      target.writeAsBytesSync(entry.value.content as List<int>);
    }
  }

  static String _key(LibraryRelease r) => '${_safe(r.name)}@${_safe(r.version)}';

  static String _safe(String text) => text.replaceAll(RegExp(r'[^A-Za-z0-9._+-]+'), '_');

  /// Nom du dossier d'une bibliothèque : son nom avec des `_` à la place des caractères que les systèmes
  /// de fichiers n'aiment pas (« DHT sensor library » devient `DHT_sensor_library`), comme le fait Arduino.
  static String libraryDirName(String name) => _safe(name).replaceAll(RegExp(r'^[._]+'), 'L');
}

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
