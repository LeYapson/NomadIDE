import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory documents;

  setUp(() => documents = Directory.systemTemp.createTempSync('nomad_docs_test'));
  tearDown(() => documents.deleteSync(recursive: true));

  test('première installation : le dossier NomadIDE est utilisé', () async {
    final root = await resolveStorageRoot(documents);
    expect(p.basename(root.path), 'NomadIDE');
  });

  test('l\'ancien dossier NomadMCU est renommé, projets et brouillons conservés', () async {
    final legacy = Directory(p.join(documents.path, 'NomadMCU', 'projects', 'p'))..createSync(recursive: true);
    File(p.join(legacy.path, 'main.py')).writeAsStringSync('print(1)');

    final root = await resolveStorageRoot(documents);

    expect(p.basename(root.path), 'NomadIDE');
    expect(File(p.join(root.path, 'projects', 'p', 'main.py')).readAsStringSync(), 'print(1)');
    expect(Directory(p.join(documents.path, 'NomadMCU')).existsSync(), isFalse);
  });

  test('si NomadIDE existe déjà, rien n\'est touché', () async {
    Directory(p.join(documents.path, 'NomadIDE')).createSync();
    Directory(p.join(documents.path, 'NomadMCU')).createSync();

    final root = await resolveStorageRoot(documents);

    expect(p.basename(root.path), 'NomadIDE');
    expect(Directory(p.join(documents.path, 'NomadMCU')).existsSync(), isTrue);
  });

  group('dossier de repli (Documents protégé)', () {
    late Directory support;

    setUp(() => support = Directory.systemTemp.createTempSync('nomad_support_test'));
    tearDown(() => support.deleteSync(recursive: true));

    Directory fallbackDir() => Directory(p.join(support.path, 'NomadIDE'));

    test('Documents utilisable : il est préféré et le repli n\'est pas créé', () async {
      final root = await resolveStorageRoot(documents, fallback: fallbackDir());
      expect(root.path, p.join(documents.path, 'NomadIDE'));
      expect(Directory(root.path).existsSync(), isTrue);
      expect(fallbackDir().existsSync(), isFalse);
    });

    test('création impossible dans Documents : le dossier de repli est créé et utilisé', () async {
      // Un fichier à la place de Documents : y créer un dossier échoue comme avec l'accès contrôlé de Windows.
      final blocked = File(p.join(documents.path, 'blocked'))..writeAsStringSync('');
      final root = await resolveStorageRoot(Directory(blocked.path), fallback: fallbackDir());
      expect(root.path, fallbackDir().path);
      expect(fallbackDir().existsSync(), isTrue);
    });

    test('un dossier de repli déjà utilisé reste utilisé, même si Documents redevient disponible', () async {
      fallbackDir().createSync(recursive: true);
      final root = await resolveStorageRoot(documents, fallback: fallbackDir());
      expect(root.path, fallbackDir().path);
    });

    test('NomadIDE déjà dans Documents : prioritaire sur le repli', () async {
      Directory(p.join(documents.path, 'NomadIDE')).createSync();
      fallbackDir().createSync(recursive: true);
      final root = await resolveStorageRoot(documents, fallback: fallbackDir());
      expect(root.path, p.join(documents.path, 'NomadIDE'));
    });
  });
}
