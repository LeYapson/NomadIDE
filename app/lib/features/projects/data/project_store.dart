import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'file_utils.dart';
import 'storage_exception.dart';

/// Un fichier ou un dossier d'un projet.
class ProjectEntry {
  const ProjectEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size = 0,
    this.modified,
  });

  final String name;

  /// Chemin relatif à la racine du projet, séparé par `/`.
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime? modified;
}

/// Projets locaux : un dossier par projet sous `<racine>/projects`.
///
/// Ne dépend ni de Flutter ni d'un plugin : la racine est fournie par l'appelant,
/// ce qui permet de le tester sur un dossier temporaire.
class ProjectStore {
  ProjectStore(this.root);

  final Directory root;

  Directory get _projects => Directory(p.join(root.path, 'projects'));

  // ---------------------------------------------------------------------------
  // Projets
  // ---------------------------------------------------------------------------

  Future<List<String>> listProjects() async {
    if (!await _projects.exists()) return const [];
    final names = <String>[];
    await for (final entity in _projects.list(followLinks: false)) {
      if (entity is Directory) names.add(p.basename(entity.path));
    }
    return names..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  Future<String> createProject(String name) async {
    final clean = validateName(name);
    final dir = Directory(p.join(_projects.path, clean));
    if (await dir.exists()) throw StorageException(StorageError.alreadyExists, name: clean);
    await _guardIo(clean, () => dir.create(recursive: true));
    return clean;
  }

  Future<String> renameProject(String from, String to) async {
    final clean = validateName(to);
    final source = await _projectDir(from);
    final target = Directory(p.join(_projects.path, clean));
    if (clean != from && await target.exists()) throw StorageException(StorageError.alreadyExists, name: clean);
    await _guardIo(from, () => source.rename(target.path));
    return clean;
  }

  Future<void> deleteProject(String name) async {
    final dir = await _projectDir(name);
    await _guardIo(name, () => dir.delete(recursive: true));
  }

  // ---------------------------------------------------------------------------
  // Fichiers et dossiers
  // ---------------------------------------------------------------------------

  /// Contenu d'un dossier du projet (non récursif) : dossiers d'abord, puis fichiers.
  Future<List<ProjectEntry>> listEntries(String project, [String directory = '']) async {
    final dir = Directory((await _resolve(project, directory, mustExist: true)).path);
    final entries = <ProjectEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (name.endsWith(tempSuffix)) continue;
      final stat = await entity.stat();
      final relative = directory.isEmpty ? name : '$directory/$name';
      entries.add(ProjectEntry(
        name: name,
        path: relative,
        isDirectory: entity is Directory,
        size: entity is File ? stat.size : 0,
        modified: stat.modified,
      ));
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  Future<bool> exists(String project, String path) async {
    final entity = await _resolve(project, path);
    return FileSystemEntity.type(entity.path).then((t) => t != FileSystemEntityType.notFound);
  }

  Future<Uint8List> readBytes(String project, String path) async {
    final file = File((await _resolve(project, path, mustExist: true)).path);
    return _guardIo(path, file.readAsBytes);
  }

  Future<String> readText(String project, String path) async =>
      utf8.decode(await readBytes(project, path), allowMalformed: true);

  /// Écrit (crée ou remplace) un fichier, de façon atomique.
  Future<void> writeBytes(String project, String path, List<int> bytes) async {
    await _projectDir(project);
    final target = await _resolve(project, path, validateSegments: true);
    await atomicWrite(File(target.path), bytes);
  }

  Future<void> writeText(String project, String path, String text) => writeBytes(project, path, utf8.encode(text));

  /// Crée un fichier vide ; échoue s'il existe déjà.
  Future<void> createFile(String project, String path) async {
    final target = await _resolve(project, path, validateSegments: true);
    if (await FileSystemEntity.type(target.path) != FileSystemEntityType.notFound) {
      throw StorageException(StorageError.alreadyExists, name: path);
    }
    await atomicWrite(File(target.path), const []);
  }

  Future<void> createDirectory(String project, String path) async {
    final target = await _resolve(project, path, validateSegments: true);
    if (await FileSystemEntity.type(target.path) != FileSystemEntityType.notFound) {
      throw StorageException(StorageError.alreadyExists, name: path);
    }
    await _guardIo(path, () => Directory(target.path).create(recursive: true));
  }

  /// Renomme (ou déplace dans le projet) un fichier ou un dossier.
  Future<void> renameEntry(String project, String from, String to) async {
    final source = await _resolve(project, from, mustExist: true);
    final target = await _resolve(project, to, validateSegments: true);
    if (from != to && await FileSystemEntity.type(target.path) != FileSystemEntityType.notFound) {
      throw StorageException(StorageError.alreadyExists, name: to);
    }
    await Directory(target.path).parent.create(recursive: true);
    await _guardIo(from, () => source.rename(target.path));
  }

  Future<void> deleteEntry(String project, String path) async {
    final entity = await _resolve(project, path, mustExist: true);
    await _guardIo(path, () => entity.delete(recursive: true));
  }

  // ---------------------------------------------------------------------------
  // Résolution des chemins
  // ---------------------------------------------------------------------------

  Future<Directory> _projectDir(String name) async {
    final clean = validateName(name);
    final dir = Directory(p.join(_projects.path, clean));
    if (!await dir.exists()) throw StorageException(StorageError.notFound, name: clean);
    return dir;
  }

  /// Transforme un chemin relatif `a/b/c.py` en entité du disque, en refusant
  /// tout ce qui sortirait du projet.
  Future<FileSystemEntity> _resolve(
    String project,
    String path, {
    bool mustExist = false,
    bool validateSegments = false,
  }) async {
    final dir = await _projectDir(project);
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.any((s) => s == '..' || s == '.')) {
      throw StorageException(StorageError.outsideProject, name: path);
    }
    if (validateSegments) {
      for (final segment in segments) {
        validateName(segment);
      }
    }
    final resolved = segments.isEmpty ? dir.path : p.joinAll([dir.path, ...segments]);
    if (!p.equals(resolved, dir.path) && !p.isWithin(dir.path, resolved)) {
      throw StorageException(StorageError.outsideProject, name: path);
    }
    final type = await FileSystemEntity.type(resolved);
    if (mustExist && type == FileSystemEntityType.notFound) {
      throw StorageException(StorageError.notFound, name: path);
    }
    return type == FileSystemEntityType.directory || segments.isEmpty ? Directory(resolved) : File(resolved);
  }

  Future<T> _guardIo<T>(String name, Future<T> Function() action) async {
    try {
      return await action();
    } on FileSystemException catch (e) {
      throw StorageException(StorageError.io, name: name, cause: e);
    }
  }
}
