import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:nomad_mcu/features/editor/application/editor_controller.dart';
import 'package:nomad_mcu/features/projects/application/projects_controller.dart';
import 'package:nomad_mcu/features/projects/data/storage_exception.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory storage;

  setUp(() => storage = Directory.systemTemp.createTempSync('nomad_ctrl_test'));
  tearDown(() => storage.deleteSync(recursive: true));

  ProviderContainer newContainer({Duration draftDelay = const Duration(hours: 1)}) {
    final container = ProviderContainer(overrides: [
      storageRootProvider.overrideWith((ref) => storage),
      draftDelayProvider.overrideWithValue(draftDelay),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  /// Laisse passer le chargement initial (microtâches et lectures disque).
  Future<ProjectsController> loadedProjects(ProviderContainer container) async {
    final controller = container.read(projectsProvider.notifier);
    await controller.refresh();
    return controller;
  }

  group('ProjectsController', () {
    test('sans projet : chargé, rien de sélectionné', () async {
      final container = newContainer();
      await loadedProjects(container);

      final state = container.read(projectsProvider);
      expect(state.loaded, isTrue);
      expect(state.projects, isEmpty);
      expect(state.current, isNull);
      expect(state.error, isNull);
    });

    test('créer un projet le sélectionne', () async {
      final container = newContainer();
      final controller = await loadedProjects(container);

      final name = await controller.createProject(' Mon projet ');

      expect(name, 'Mon projet');
      final state = container.read(projectsProvider);
      expect(state.projects, ['Mon projet']);
      expect(state.current, 'Mon projet');
      expect(state.entries, isEmpty);
    });

    test('un nom invalide laisse l\'état intact et signale l\'erreur', () async {
      final container = newContainer();
      final controller = await loadedProjects(container);
      await controller.createProject('p');

      final name = await controller.createProject('a/b');

      expect(name, isNull);
      final state = container.read(projectsProvider);
      expect(state.error?.error, StorageError.invalidName);
      expect(state.projects, ['p']);
      expect(state.current, 'p');

      controller.clearError();
      expect(container.read(projectsProvider).error, isNull);
    });

    test('fichiers et dossiers : créer, entrer, remonter', () async {
      final container = newContainer();
      final controller = await loadedProjects(container);
      await controller.createProject('p');

      await controller.createFile('main.py');
      await controller.createFolder('lib');
      expect(container.read(projectsProvider).entries.map((e) => e.name), ['lib', 'main.py']);

      await controller.openDirectory('lib');
      expect(container.read(projectsProvider).directory, 'lib');
      expect(await controller.createFile('dht.py'), 'lib/dht.py');
      expect(container.read(projectsProvider).entries.single.path, 'lib/dht.py');

      await controller.goUp();
      expect(container.read(projectsProvider).directory, '');
      await controller.goUp();
      expect(container.read(projectsProvider).directory, '');
    });

    test('un fichier existant est signalé, pas écrasé', () async {
      final container = newContainer();
      final controller = await loadedProjects(container);
      await controller.createProject('p');
      await controller.createFile('a.py');

      expect(await controller.createFile('a.py'), isNull);

      expect(container.read(projectsProvider).error?.error, StorageError.alreadyExists);
    });

    test('renommer et supprimer une entrée', () async {
      final container = newContainer();
      final controller = await loadedProjects(container);
      await controller.createProject('p');
      await controller.createFile('a.py');
      final entry = container.read(projectsProvider).entries.single;

      expect(await controller.renameEntry(entry, 'b.py'), 'b.py');
      expect(container.read(projectsProvider).entries.single.name, 'b.py');

      await controller.deleteEntry(container.read(projectsProvider).entries.single);
      expect(container.read(projectsProvider).entries, isEmpty);
    });

    test('renommer un projet suit le projet courant', () async {
      final container = newContainer();
      final controller = await loadedProjects(container);
      await controller.createProject('ancien');
      await controller.createFile('a.py');

      await controller.renameProject('ancien', 'nouveau');

      final state = container.read(projectsProvider);
      expect(state.projects, ['nouveau']);
      expect(state.current, 'nouveau');
      expect(state.entries.single.name, 'a.py');
    });

    test('supprimer le projet courant bascule sur un autre, ou sur aucun', () async {
      final container = newContainer();
      final controller = await loadedProjects(container);
      await controller.createProject('a');
      await controller.createProject('b');

      await controller.deleteProject('b');
      expect(container.read(projectsProvider).current, 'a');

      await controller.deleteProject('a');
      final state = container.read(projectsProvider);
      expect(state.current, isNull);
      expect(state.projects, isEmpty);
      expect(state.entries, isEmpty);
    });

    test('changer de projet remet le dossier à la racine', () async {
      final container = newContainer();
      final controller = await loadedProjects(container);
      await controller.createProject('a');
      await controller.createFolder('lib');
      await controller.openDirectory('lib');
      await controller.createProject('b');

      await controller.selectProject('a');

      expect(container.read(projectsProvider).directory, '');
      expect(container.read(projectsProvider).entries.single.name, 'lib');
    });

    test('un stockage indisponible ne plante pas : l\'erreur est signalée', () async {
      final container = ProviderContainer(overrides: [
        storageRootProvider.overrideWith((ref) => throw StateError('plugin absent')),
      ]);
      addTearDown(container.dispose);

      await container.read(projectsProvider.notifier).refresh();

      final state = container.read(projectsProvider);
      expect(state.loaded, isTrue);
      expect(state.error?.error, StorageError.io);
    });
  });

  group('éditeur : fichiers locaux', () {
    Future<EditorController> editorWithProject(ProviderContainer container) async {
      final projects = await loadedProjects(container);
      await projects.createProject('p');
      return container.read(editorProvider.notifier);
    }

    test('enregistrer sous crée le fichier et remet le document à neuf', () async {
      final container = newContainer();
      final editor = await editorWithProject(container);
      editor.newDocument(text: 'print(1)');
      final doc = container.read(editorProvider).active!;
      doc.controller.text = 'print(2)';
      expect(doc.dirty, isTrue);

      final saved = await editor.saveLocal(doc, project: 'p', path: 'main.py');

      expect(saved, isTrue);
      expect(doc.dirty, isFalse);
      expect(doc.localProject, 'p');
      expect(doc.localPath, 'main.py');
      expect(File('${storage.path}/projects/p/main.py').readAsStringSync(), 'print(2)');
      expect(container.read(projectsProvider).entries.single.name, 'main.py');
    });

    test('enregistrer sans emplacement ne fait rien', () async {
      final container = newContainer();
      final editor = await editorWithProject(container);
      editor.newDocument();

      expect(await editor.saveLocal(container.read(editorProvider).active!), isFalse);
    });

    test('un nom invalide à l\'enregistrement est signalé et rien n\'est écrit', () async {
      final container = newContainer();
      final editor = await editorWithProject(container);
      editor.newDocument(text: 'x');
      final doc = container.read(editorProvider).active!;

      final saved = await editor.saveLocal(doc, project: 'p', path: 'a:b.py');

      expect(saved, isFalse);
      expect(container.read(projectsProvider).error?.error, StorageError.invalidName);
      expect(doc.localPath, isNull);
      expect(Directory('${storage.path}/projects/p').listSync(), isEmpty);
    });

    test('ouvrir un fichier local, puis le rouvrir réutilise l\'onglet', () async {
      final container = newContainer();
      final editor = await editorWithProject(container);
      File('${storage.path}/projects/p/a.py').writeAsStringSync('a = 1');

      expect(await editor.openLocalFile('p', 'a.py'), isTrue);
      expect(await editor.openLocalFile('p', 'a.py'), isTrue);

      final state = container.read(editorProvider);
      expect(state.documents, hasLength(1));
      expect(state.active!.controller.text, 'a = 1');
      expect(state.active!.dirty, isFalse);
    });

    test('ouvrir un fichier absent signale l\'erreur', () async {
      final container = newContainer();
      final editor = await editorWithProject(container);

      expect(await editor.openLocalFile('p', 'absent.py'), isFalse);

      expect(container.read(projectsProvider).error?.error, StorageError.notFound);
      expect(container.read(editorProvider).documents, isEmpty);
    });

    test('modifier puis enregistrer écrase le fichier de façon atomique', () async {
      final container = newContainer();
      final editor = await editorWithProject(container);
      File('${storage.path}/projects/p/a.py').writeAsStringSync('v1');
      await editor.openLocalFile('p', 'a.py');
      final doc = container.read(editorProvider).active!;

      doc.controller.text = 'v2';
      await editor.saveLocal(doc);

      expect(File('${storage.path}/projects/p/a.py').readAsStringSync(), 'v2');
      expect(doc.dirty, isFalse);
      expect(Directory('${storage.path}/projects/p').listSync().map((e) => e.path).where((p) => p.endsWith('.nomad-tmp')), isEmpty);
    });
  });

  group('brouillons', () {
    File draftFile(String id) => File('${storage.path}/drafts/$id.json');

    test('une modification est écrite en brouillon après le délai', () async {
      final container = newContainer(draftDelay: const Duration(milliseconds: 20));
      final editor = container.read(editorProvider.notifier);
      editor.newDocument(text: 'départ');
      final doc = container.read(editorProvider).active!;

      doc.controller.text = 'modifié';
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(draftFile(doc.id).existsSync(), isTrue);
      expect(draftFile(doc.id).readAsStringSync(), contains('modifié'));
    });

    test('rien n\'est écrit tant que le document n\'a pas changé', () async {
      final container = newContainer(draftDelay: const Duration(milliseconds: 20));
      final editor = container.read(editorProvider.notifier);
      editor.newDocument(text: 'inchangé');
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(Directory('${storage.path}/drafts').existsSync(), isFalse);
    });

    test('revenir au texte enregistré supprime le brouillon', () async {
      final container = newContainer(draftDelay: const Duration(milliseconds: 10));
      final editor = container.read(editorProvider.notifier);
      editor.newDocument(text: 'a');
      final doc = container.read(editorProvider).active!;
      doc.controller.text = 'b';
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(draftFile(doc.id).existsSync(), isTrue);

      doc.controller.text = 'a';
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(draftFile(doc.id).existsSync(), isFalse);
    });

    test('enregistrer supprime le brouillon', () async {
      final container = newContainer();
      await loadedProjects(container).then((c) => c.createProject('p'));
      final editor = container.read(editorProvider.notifier);
      editor.newDocument(text: 'a');
      final doc = container.read(editorProvider).active!;
      doc.controller.text = 'b';
      await editor.flushDrafts();
      expect(draftFile(doc.id).existsSync(), isTrue);

      await editor.saveLocal(doc, project: 'p', path: 'a.py');

      expect(draftFile(doc.id).existsSync(), isFalse);
    });

    test('fermer un onglet supprime son brouillon', () async {
      final container = newContainer();
      final editor = container.read(editorProvider.notifier);
      editor.newDocument(text: 'a');
      final doc = container.read(editorProvider).active!;
      doc.controller.text = 'b';
      await editor.flushDrafts();

      editor.close(doc);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(draftFile(doc.id).existsSync(), isFalse);
    });

    test('fermeture brutale : les brouillons sont proposés puis restaurés au démarrage suivant', () async {
      final first = newContainer();
      await loadedProjects(first).then((c) => c.createProject('p'));
      File('${storage.path}/projects/p/main.py').writeAsStringSync('disque');
      final editor = first.read(editorProvider.notifier);
      await editor.openLocalFile('p', 'main.py');
      editor.newDocument();
      first.read(editorProvider).documents[1].controller.text = 'jamais enregistré';
      first.read(editorProvider).documents[0].controller.text = 'modifié sans enregistrer';
      await editor.flushDrafts();
      // Pas de close() ni de dispose propre de l'éditeur : l'application « plante ».

      final second = newContainer();
      second.read(editorProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final pending = second.read(editorProvider).pendingDrafts;
      expect(pending, hasLength(2));
      expect(second.read(editorProvider).documents, isEmpty);

      await second.read(editorProvider.notifier).restoreDrafts();

      final state = second.read(editorProvider);
      expect(state.pendingDrafts, isEmpty);
      expect(state.documents.map((d) => d.controller.text), unorderedEquals(['modifié sans enregistrer', 'jamais enregistré']));
      final restoredLocal = state.documents.firstWhere((d) => d.localPath == 'main.py');
      expect(restoredLocal.localProject, 'p');
      expect(restoredLocal.dirty, isTrue);
      expect(File('${storage.path}/projects/p/main.py').readAsStringSync(), 'disque',
          reason: 'le fichier enregistré n\'est pas touché par la restauration');
    });

    test('un brouillon identique au fichier sur disque n\'est pas restauré', () async {
      final first = newContainer();
      await loadedProjects(first).then((c) => c.createProject('p'));
      final editor = first.read(editorProvider.notifier);
      await first.read(editorProvider.notifier).saveLocal(
            (() {
              editor.newDocument(text: 'contenu');
              return first.read(editorProvider).active!;
            })(),
            project: 'p',
            path: 'a.py',
          );
      final doc = first.read(editorProvider).active!;
      doc.controller.text = 'différent';
      await editor.flushDrafts();
      // Le fichier est ensuite remplacé par le même texte que le brouillon (ex. sauvegarde hors app).
      File('${storage.path}/projects/p/a.py').writeAsStringSync('différent');

      final second = newContainer();
      second.read(editorProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await second.read(editorProvider.notifier).restoreDrafts();

      expect(second.read(editorProvider).documents, isEmpty);
      expect(draftFile(doc.id).existsSync(), isFalse);
    });

    test('abandonner supprime les brouillons', () async {
      final first = newContainer();
      final editor = first.read(editorProvider.notifier);
      editor.newDocument(text: 'a');
      first.read(editorProvider).active!.controller.text = 'b';
      await editor.flushDrafts();

      final second = newContainer();
      second.read(editorProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(second.read(editorProvider).pendingDrafts, hasLength(1));

      await second.read(editorProvider.notifier).discardDrafts();

      expect(second.read(editorProvider).pendingDrafts, isEmpty);
      expect(second.read(editorProvider).documents, isEmpty);
      expect(Directory('${storage.path}/drafts').listSync(), isEmpty);
    });

    test('un brouillon corrompu n\'empêche pas de proposer les autres', () async {
      final first = newContainer();
      final editor = first.read(editorProvider.notifier);
      editor.newDocument(text: 'a');
      first.read(editorProvider).active!.controller.text = 'bon brouillon';
      await editor.flushDrafts();
      File('${storage.path}/drafts/casse.json').writeAsStringSync('{"id":');

      final second = newContainer();
      second.read(editorProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(second.read(editorProvider).pendingDrafts.single.text, 'bon brouillon');
    });
  });
}
