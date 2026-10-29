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
}
