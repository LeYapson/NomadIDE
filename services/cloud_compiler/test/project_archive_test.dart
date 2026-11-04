import 'dart:io';

import 'package:archive/archive.dart';
import 'package:nomad_cloud_compiler/nomad_cloud_compiler.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Directory dest;

  setUp(() => dest = Directory.systemTemp.createTempSync('nomad_archive_'));
  tearDown(() => dest.deleteSync(recursive: true));

  ExtractedProject extract(List<int> zip, {String? name}) =>
      extractProject(zip, dest, name: name, maxFiles: 50, maxBytes: 1024 * 1024);

  test('un .ino à la racine donne le nom du croquis', () {
    final project = extract(zipOf({'blink.ino': 'void setup(){}', 'util.h': '#pragma once'}));
    expect(project.sketchName, 'blink');
    expect(File('${project.sketchDir.path}/util.h').existsSync(), isTrue);
  });

  test('un dossier englobant unique est retiré', () {
    final project = extract(zipOf({'mon_projet/mon_projet.ino': 'x', 'mon_projet/src/a.cpp': 'y'}));
    expect(project.sketchName, 'mon_projet');
    expect(File('${project.sketchDir.path}/src/a.cpp').existsSync(), isTrue);
  });

  test('plusieurs .ino : le nom doit être indiqué', () {
    final zip = zipOf({'a.ino': '1', 'b.ino': '2'});
    expect(() => extract(zip), throwsA(isA<ProjectException>()));
    expect(extract(zip, name: 'b').sketchName, 'b');
  });

  test('aucun .ino : refusé', () {
    expect(() => extract(zipOf({'main.cpp': 'int main(){}'})), throwsA(isA<ProjectException>()));
  });

  test('chemins qui sortent du dossier : refusés', () {
    expect(() => extract(zipOf({'a.ino': 'x', '../evil.txt': 'y'})), throwsA(isA<ProjectException>()));
    expect(() => extract(zipOf({'a.ino': 'x', '/etc/passwd': 'y'})), throwsA(isA<ProjectException>()));
    expect(() => extract(zipOf({'a.ino': 'x', r'..\evil.txt': 'y'})), throwsA(isA<ProjectException>()));
  });

  test('lien symbolique : refusé', () {
    final archive = Archive()
      ..add(ArchiveFile.bytes('a.ino', [120]))
      ..add(ArchiveFile.symlink('lien', '/etc/passwd'));
    expect(() => extract(ZipEncoder().encode(archive)), throwsA(isA<ProjectException>()));
  });

  test('limites de fichiers et de taille', () {
    expect(
      () => extractProject(zipOf({'a.ino': 'x', 'b.h': 'y', 'c.h': 'z'}), dest, maxFiles: 2, maxBytes: 1000),
      throwsA(isA<ProjectException>()),
    );
    expect(
      () => extractProject(zipOf({'a.ino': 'x' * 100}), dest, maxFiles: 5, maxBytes: 50),
      throwsA(isA<ProjectException>()),
    );
  });

  test('nom de croquis invalide et zip corrompu', () {
    expect(() => extract(zipOf({'mon projet.ino': 'x'})), throwsA(isA<ProjectException>()));
    expect(() => extract([1, 2, 3, 4]), throwsA(isA<ProjectException>()));
  });
}
