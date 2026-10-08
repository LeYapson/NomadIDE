import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_mcu/features/projects/data/draft_store.dart';
import 'package:nomad_mcu/features/projects/data/file_utils.dart';
import 'package:nomad_mcu/features/projects/data/project_store.dart';
import 'package:nomad_mcu/features/projects/data/storage_exception.dart';

Matcher throwsStorage(StorageError error) =>
    throwsA(isA<StorageException>().having((e) => e.error, 'error', error));

void main() {
  late Directory temp;
  late ProjectStore store;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('nomad_projects_test');
    store = ProjectStore(temp);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  group('validateName', () {
    test('accepte les noms usuels et retire les espaces autour', () {
      expect(validateName('  main.py '), 'main.py');
      expect(validateName('Mon projet (v2)'), 'Mon projet (v2)');
      expect(validateName('capteur_température.py'), 'capteur_température.py');
    });

    test('refuse vide, trop long, points, séparateurs et caractères interdits', () {
      for (final name in ['', '   ', '.', '..', 'a/b', r'a\b', 'a:b', 'a*b', 'a?b', 'a"b', 'a<b', 'a|b', 'fin.', 'x' * 81, 'ta\tb']) {
        expect(() => validateName(name), throwsStorage(StorageError.invalidName), reason: 'nom : "$name"');
      }
    });

    test('refuse les noms réservés de Windows, avec ou sans extension', () {
      for (final name in ['con', 'NUL', 'Com1', 'lpt9.txt', 'aux.py']) {
        expect(() => validateName(name), throwsStorage(StorageError.invalidName), reason: name);
      }
      expect(validateName('console.py'), 'console.py');
    });

    test('refuse le suffixe réservé aux fichiers temporaires', () {
      expect(() => validateName('a$tempSuffix'), throwsStorage(StorageError.invalidName));
    });
  });

  group('projets', () {
    test('création, liste triée sans casse, doublon refusé', () async {
      await store.createProject('beta');
      await store.createProject('Alpha');

      expect(await store.listProjects(), ['Alpha', 'beta']);
      await expectLater(store.createProject('alpha'.toUpperCase().replaceFirst('LPHA', 'lpha')), throwsStorage(StorageError.alreadyExists));
    });

    test('sans aucun projet, la liste est vide', () async {
      expect(await store.listProjects(), isEmpty);
    });

    test('renommer conserve le contenu', () async {
      await store.createProject('ancien');
      await store.writeText('ancien', 'main.py', 'print(1)');

      final name = await store.renameProject('ancien', 'nouveau');

      expect(name, 'nouveau');
      expect(await store.listProjects(), ['nouveau']);
      expect(await store.readText('nouveau', 'main.py'), 'print(1)');
    });

    test('renommer vers un projet existant est refusé', () async {
      await store.createProject('a');
      await store.createProject('b');

      await expectLater(store.renameProject('a', 'b'), throwsStorage(StorageError.alreadyExists));
    });

    test('supprimer retire le projet et son contenu', () async {
      await store.createProject('p');
      await store.writeText('p', 'dir/a.py', 'x');

      await store.deleteProject('p');

      expect(await store.listProjects(), isEmpty);
      await expectLater(store.deleteProject('p'), throwsStorage(StorageError.notFound));
    });
  });

  group('fichiers', () {
    setUp(() => store.createProject('p'));

    test('écrire puis lire, UTF-8 compris', () async {
      await store.writeText('p', 'main.py', 'print("héllo ✓")');

      expect(await store.readText('p', 'main.py'), 'print("héllo ✓")');
    });

    test('les octets arbitraires sont conservés', () async {
      final data = List<int>.generate(1000, (i) => i % 256);

      await store.writeBytes('p', 'img.bin', data);

      expect(await store.readBytes('p', 'img.bin'), data);
    });

    test('écrire crée les dossiers intermédiaires', () async {
      await store.writeText('p', 'lib/capteurs/dht.py', '# dht');

      expect((await store.listEntries('p')).single.name, 'lib');
      expect((await store.listEntries('p', 'lib/capteurs')).single.name, 'dht.py');
    });

    test('remplacer un fichier ne laisse aucun fichier temporaire', () async {
      await store.writeText('p', 'a.py', 'v1');
      await store.writeText('p', 'a.py', 'version 2');

      final names = (await store.listEntries('p')).map((e) => e.name);
      expect(names, ['a.py']);
      expect(await store.readText('p', 'a.py'), 'version 2');
      final onDisk = temp.listSync(recursive: true).whereType<File>().map((f) => f.path);
      expect(onDisk.where((path) => path.endsWith(tempSuffix)), isEmpty);
    });

    test('un temporaire abandonné par une coupure n\'apparaît pas dans la liste ni ne remplace le fichier', () async {
      await store.writeText('p', 'a.py', 'bon');
      File('${temp.path}/projects/p/a.py$tempSuffix').writeAsStringSync('à moitié écr');

      expect((await store.listEntries('p')).map((e) => e.name), ['a.py']);
      expect(await store.readText('p', 'a.py'), 'bon');
    });

    test('la liste donne taille, dossiers d\'abord, tri sans casse', () async {
      await store.writeText('p', 'b.py', '12345');
      await store.writeText('p', 'A.py', '1');
      await store.createDirectory('p', 'zdir');

      final entries = await store.listEntries('p');

      expect(entries.map((e) => e.name), ['zdir', 'A.py', 'b.py']);
      expect(entries.first.isDirectory, isTrue);
      expect(entries[2].size, 5);
      expect(entries[2].path, 'b.py');
    });

    test('createFile échoue si le fichier existe', () async {
      await store.createFile('p', 'new.py');

      expect(await store.readText('p', 'new.py'), '');
      await expectLater(store.createFile('p', 'new.py'), throwsStorage(StorageError.alreadyExists));
    });

    test('renommer un fichier ou un dossier', () async {
      await store.writeText('p', 'dir/a.py', 'a');

      await store.renameEntry('p', 'dir/a.py', 'dir/b.py');
      await store.renameEntry('p', 'dir', 'lib');

      expect(await store.readText('p', 'lib/b.py'), 'a');
      expect(await store.exists('p', 'dir'), isFalse);
    });

    test('renommer vers un nom pris est refusé et ne touche à rien', () async {
      await store.writeText('p', 'a.py', 'a');
      await store.writeText('p', 'b.py', 'b');

      await expectLater(store.renameEntry('p', 'a.py', 'b.py'), throwsStorage(StorageError.alreadyExists));
      expect(await store.readText('p', 'b.py'), 'b');
    });

    test('supprimer un fichier puis un dossier non vide', () async {
      await store.writeText('p', 'dir/a.py', 'a');

      await store.deleteEntry('p', 'dir/a.py');
      await store.deleteEntry('p', 'dir');

      expect(await store.listEntries('p'), isEmpty);
      await expectLater(store.deleteEntry('p', 'dir'), throwsStorage(StorageError.notFound));
    });

    test('lire un fichier absent ou dans un projet absent', () async {
      await expectLater(store.readText('p', 'absent.py'), throwsStorage(StorageError.notFound));
      await expectLater(store.readText('fantome', 'a.py'), throwsStorage(StorageError.notFound));
    });
  });

  group('sécurité des chemins', () {
    setUp(() async {
      await store.createProject('p');
      await store.createProject('secret');
      await store.writeText('secret', 'mdp.txt', 'confidentiel');
    });

    test('.. est refusé en lecture, écriture, renommage et suppression', () async {
      await expectLater(store.readText('p', '../secret/mdp.txt'), throwsStorage(StorageError.outsideProject));
      await expectLater(store.writeText('p', '../x.py', 'x'), throwsStorage(StorageError.outsideProject));
      await expectLater(store.renameEntry('p', '../secret/mdp.txt', 'mdp.txt'), throwsStorage(StorageError.outsideProject));
      await expectLater(store.deleteEntry('p', 'a/../../secret'), throwsStorage(StorageError.outsideProject));
      await expectLater(store.listEntries('p', '..'), throwsStorage(StorageError.outsideProject));
      expect(await store.readText('secret', 'mdp.txt'), 'confidentiel');
    });

    test('un nom de projet ne peut pas contenir de séparateur', () async {
      await expectLater(store.createProject('../evasion'), throwsStorage(StorageError.invalidName));
      await expectLater(store.readText('../secret', 'mdp.txt'), throwsStorage(StorageError.invalidName));
    });

    test('les segments d\'un chemin d\'écriture sont validés', () async {
      await expectLater(store.writeText('p', 'dir/a:b.py', 'x'), throwsStorage(StorageError.invalidName));
      await expectLater(store.writeText('p', 'con/a.py', 'x'), throwsStorage(StorageError.invalidName));
    });
  });

  group('DraftStore', () {
    late DraftStore drafts;

    setUp(() => drafts = DraftStore(temp));

    Draft draft(String id, {String text = 'x', DateTime? at}) => Draft(
          id: id,
          name: 'main.py',
          text: text,
          updatedAt: at ?? DateTime(2026, 10, 8),
          project: 'p',
          path: 'main.py',
        );

    test('sans dossier de brouillons, la liste est vide', () async {
      expect(await drafts.list(), isEmpty);
    });

    test('enregistrer, relire, remplacer, supprimer', () async {
      await drafts.save(draft('a', text: 'v1'));
      await drafts.save(draft('a', text: 'v2'));

      final list = await drafts.list();
      expect(list.single.text, 'v2');
      expect(list.single.project, 'p');
      expect(list.single.boardPath, isNull);

      await drafts.delete('a');
      expect(await drafts.list(), isEmpty);
      await drafts.delete('a');
    });

    test('du plus récent au plus ancien', () async {
      await drafts.save(draft('vieux', at: DateTime(2026, 1, 1)));
      await drafts.save(draft('recent', at: DateTime(2026, 10, 1)));

      expect((await drafts.list()).map((d) => d.id), ['recent', 'vieux']);
    });

    test('un fichier corrompu ou étranger est ignoré sans bloquer les autres', () async {
      await drafts.save(draft('bon'));
      File('${temp.path}/drafts/casse.json').writeAsStringSync('{"id": "casse", "na');
      File('${temp.path}/drafts/etranger.json').writeAsStringSync(jsonEncode({'autre': 1}));
      File('${temp.path}/drafts/notes.txt').writeAsStringSync('rien');

      expect((await drafts.list()).map((d) => d.id), ['bon']);
    });

    test('un identifiant dangereux est refusé', () async {
      await expectLater(drafts.save(draft('../evasion')), throwsArgumentError);
      await expectLater(drafts.delete('a/b'), throwsArgumentError);
    });

    test('le contenu des brouillons survit au « redémarrage » (nouvel objet, même dossier)', () async {
      await drafts.save(draft('a', text: 'perdu sans brouillon'));

      expect((await DraftStore(temp).list()).single.text, 'perdu sans brouillon');
    });

    test('clear supprime tout', () async {
      await drafts.save(draft('a'));
      await drafts.save(draft('b'));

      await drafts.clear();

      expect(await drafts.list(), isEmpty);
    });
  });
}
