import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_mcu/app/app.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:nomad_mcu/features/editor/application/editor_controller.dart';
import 'package:nomad_mcu/features/projects/application/projects_controller.dart';
import 'package:nomad_mcu/features/projects/data/draft_store.dart';
import 'package:nomad_mcu/features/projects/data/project_store.dart';

void main() {
  late Directory storage;
  late ProviderContainer container;

  setUp(() {
    storage = Directory.systemTemp.createTempSync('nomad_ui_test');
    container = ProviderContainer(overrides: [
      serialTransportProvider.overrideWithValue(FakeSerialTransport()),
      storageRootProvider.overrideWith((ref) => storage),
    ]);
  });

  tearDown(() {
    container.dispose();
    storage.deleteSync(recursive: true);
  });

  /// Les E/S fichiers sont réelles : elles n'avancent qu'en laissant tourner la vraie
  /// boucle d'événements, en alternance avec l'horloge simulée. Plusieurs allers-retours
  /// couvrent les opérations enchaînées (lire la liste, puis le dossier, puis le fichier…).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const NomadApp()));
    await settle(tester);
    container.read(homeTabProvider.notifier).show(HomeTab.editor);
    await settle(tester);
  }

  Future<void> prepare(WidgetTester tester, Future<void> Function(ProjectStore store) setup) async {
    await tester.runAsync(() => setup(ProjectStore(storage)));
  }

  testWidgets('sans projet : proposer d\'en créer un, puis l\'afficher', (tester) async {
    await pumpEditor(tester);
    expect(find.text('Aucun projet.'), findsOneWidget);

    await tester.tap(find.text('Nouveau projet'));
    await tester.pumpAndSettle();
    expect(find.text('Mon projet'), findsOneWidget); // valeur par défaut du champ
    await tester.tap(find.widgetWithText(FilledButton, 'Créer'));
    await settle(tester);

    expect(find.text('Aucun projet.'), findsNothing);
    expect(find.text('Projet vide'), findsOneWidget);
    expect(container.read(projectsProvider).current, 'Mon projet');
    expect(Directory('${storage.path}/projects/Mon projet').existsSync(), isTrue);
  });

  testWidgets('toucher un fichier du projet l\'ouvre dans l\'éditeur, avec son contenu', (tester) async {
    await prepare(tester, (store) async {
      await store.createProject('p');
      await store.writeText('p', 'capteur.py', 'import machine');
    });
    await pumpEditor(tester);

    await tester.tap(find.text('capteur.py'));
    await settle(tester);

    final doc = container.read(editorProvider).active!;
    expect(doc.name, 'capteur.py');
    expect(doc.controller.text, 'import machine');
    expect(doc.dirty, isFalse);
    expect(find.text('capteur.py'), findsNWidgets(2)); // liste du projet + onglet
  });

  testWidgets('enregistrer un nouveau fichier demande l\'emplacement puis écrit sur le disque', (tester) async {
    await prepare(tester, (store) => store.createProject('p'));
    container.read(editorProvider.notifier).newDocument(text: 'print("salut")');
    await pumpEditor(tester);

    await tester.tap(find.byTooltip('Enregistrer sur l\'appareil (Ctrl+S)'));
    await tester.pumpAndSettle();
    expect(find.text('Enregistrer sur cet appareil'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'main.py'), 'blink.py');
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await settle(tester);

    expect(File('${storage.path}/projects/p/blink.py').readAsStringSync(), 'print("salut")');
    final doc = container.read(editorProvider).active!;
    expect(doc.name, 'blink.py');
    expect(doc.dirty, isFalse);
  });

  testWidgets('enregistrer sous un nom déjà pris demande confirmation avant d\'écraser', (tester) async {
    await prepare(tester, (store) async {
      await store.createProject('p');
      await store.writeText('p', 'main.py', 'ancien contenu');
    });
    container.read(editorProvider.notifier).newDocument(text: 'nouveau contenu');
    await pumpEditor(tester);

    await tester.tap(find.byTooltip('Enregistrer sur l\'appareil (Ctrl+S)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await settle(tester);

    expect(find.text('Remplacer le fichier ?'), findsOneWidget);
    expect(File('${storage.path}/projects/p/main.py').readAsStringSync(), 'ancien contenu');

    await tester.tap(find.widgetWithText(TextButton, 'Annuler'));
    await settle(tester);
    expect(File('${storage.path}/projects/p/main.py').readAsStringSync(), 'ancien contenu');
    expect(container.read(editorProvider).active!.localPath, isNull);
  });

  testWidgets('fermer un onglet modifié demande d\'enregistrer ; « Ne pas enregistrer » le ferme', (tester) async {
    container.read(editorProvider.notifier).newDocument(text: 'a');
    container.read(editorProvider).active!.controller.text = 'b';
    await pumpEditor(tester);

    await tester.tap(find.byTooltip('Fermer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Enregistrer « main.py »'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Ne pas enregistrer'));
    await settle(tester);

    expect(container.read(editorProvider).documents, isEmpty);
  });

  testWidgets('fermer un onglet modifié puis annuler le garde ouvert', (tester) async {
    container.read(editorProvider.notifier).newDocument(text: 'a');
    container.read(editorProvider).active!.controller.text = 'b';
    await pumpEditor(tester);

    await tester.tap(find.byTooltip('Fermer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Annuler'));
    await settle(tester);

    expect(container.read(editorProvider).documents, hasLength(1));
  });

  testWidgets('fermer un onglet intact ne demande rien', (tester) async {
    container.read(editorProvider.notifier).newDocument(text: 'a');
    await pumpEditor(tester);

    await tester.tap(find.byTooltip('Fermer'));
    await settle(tester);

    expect(container.read(editorProvider).documents, isEmpty);
  });

  testWidgets('après une fermeture brutale, les brouillons sont proposés puis restaurés', (tester) async {
    await prepare(tester, (store) async {
      await store.createProject('p');
      await DraftStore(storage).save(Draft(
        id: 'ancien-1',
        name: 'robot.py',
        text: 'print("travail perdu ?")',
        updatedAt: DateTime(2026, 10, 7),
        project: 'p',
        path: 'robot.py',
      ));
    });
    await pumpEditor(tester);

    expect(find.text('Reprendre le travail non enregistré ?'), findsOneWidget);
    expect(find.textContaining('robot.py'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Restaurer'));
    await settle(tester);

    final doc = container.read(editorProvider).active!;
    expect(doc.name, 'robot.py');
    expect(doc.controller.text, 'print("travail perdu ?")');
    expect(doc.dirty, isTrue);
    expect(doc.localProject, 'p');
    expect(container.read(homeTabProvider), HomeTab.editor);
    // Le document restauré est modifié : son brouillon est reprogrammé, on l'écrit avant la fin.
    await tester.runAsync(() => container.read(editorProvider.notifier).flushDrafts());
  });

  testWidgets('abandonner les brouillons les supprime', (tester) async {
    await prepare(tester, (store) async {
      await DraftStore(storage).save(Draft(id: 'x', name: 'a.py', text: 'a', updatedAt: DateTime(2026, 10, 7)));
    });
    await pumpEditor(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Abandonner'));
    await settle(tester);

    expect(container.read(editorProvider).documents, isEmpty);
    expect(Directory('${storage.path}/drafts').listSync(), isEmpty);
  });

  testWidgets('supprimer un fichier du projet demande confirmation', (tester) async {
    await prepare(tester, (store) async {
      await store.createProject('p');
      await store.writeText('p', 'a.py', 'a');
    });
    await pumpEditor(tester);

    await tester.tap(find.byTooltip('Actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer…'));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer le fichier ?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await settle(tester);

    expect(File('${storage.path}/projects/p/a.py').existsSync(), isFalse);
  });

  testWidgets('un nom invalide affiche un message clair', (tester) async {
    await prepare(tester, (store) => store.createProject('p'));
    await pumpEditor(tester);

    await tester.runAsync(() => container.read(projectsProvider.notifier).createFile('a:b.py'));
    await settle(tester);

    expect(find.textContaining('Nom invalide'), findsOneWidget);
  });
}
