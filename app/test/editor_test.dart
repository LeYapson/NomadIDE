import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_editor/nomad_editor.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_mcu/app/app.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:nomad_mcu/features/editor/application/editor_controller.dart';
import 'support/locale.dart';

ProviderContainer newContainer() {
  final storage = Directory.systemTemp.createTempSync('nomad_editor_test');
  final container = ProviderContainer(
    overrides: [frenchLocale, 
      serialTransportProvider.overrideWithValue(FakeSerialTransport()),
      storageRootProvider.overrideWith((ref) => storage),
    ],
  );
  addTearDown(() {
    container.dispose();
    storage.deleteSync(recursive: true);
  });
  return container;
}

Widget app(ProviderContainer container) =>
    UncontrolledProviderScope(container: container, child: const NomadApp());

void main() {
  group('EditorController', () {
    test('un nouveau document est un main.py Python non modifié', () {
      final container = newContainer();

      container.read(editorProvider.notifier).newDocument();

      final doc = container.read(editorProvider).active!;
      expect(doc.name, 'main.py');
      expect(doc.controller.language, CodeLanguage.python);
      expect(doc.dirty, isFalse);
      expect(doc.boardPath, isNull);
    });

    test('dirty suit les modifications et leur annulation', () {
      final container = newContainer();
      container.read(editorProvider.notifier).newDocument(text: 'x = 1');
      final doc = container.read(editorProvider).active!;

      doc.controller.text = 'x = 2';
      expect(doc.dirty, isTrue);

      doc.controller.text = 'x = 1';
      expect(doc.dirty, isFalse);
    });

    test('ouvrir deux fois le même fichier de la carte réutilise l\'onglet', () {
      final container = newContainer();
      final editor = container.read(editorProvider.notifier);

      editor.openBoardFile('/lib/a.py', 'a');
      editor.openBoardFile('/b.c', 'b');
      editor.openBoardFile('/lib/a.py', 'a');

      final state = container.read(editorProvider);
      expect(state.documents, hasLength(2));
      expect(state.active!.boardPath, '/lib/a.py');
      expect(state.documents[1].controller.language, CodeLanguage.c);
    });

    test('openAndShow affiche l\'onglet Éditeur', () {
      final container = newContainer();

      container.read(editorProvider.notifier).openAndShow('/main.py', 'print(1)');

      expect(container.read(homeTabProvider), HomeTab.editor);
    });

    test('fermer un onglet garde un onglet actif valide', () {
      final container = newContainer();
      final editor = container.read(editorProvider.notifier);
      editor.openBoardFile('/a.py', 'a');
      editor.openBoardFile('/b.py', 'b');
      editor.openBoardFile('/c.py', 'c');

      editor.close(container.read(editorProvider).documents[2]);
      expect(container.read(editorProvider).active!.boardPath, '/b.py');

      editor.close(container.read(editorProvider).documents[0]);
      expect(container.read(editorProvider).active!.boardPath, '/b.py');

      editor.close(container.read(editorProvider).documents[0]);
      expect(container.read(editorProvider).active, isNull);
    });

    test('enregistrer un document sans chemin ne fait rien', () async {
      final container = newContainer();
      container.read(editorProvider.notifier).newDocument();

      final saved = await container.read(editorProvider.notifier).saveToBoard(container.read(editorProvider).active!);

      expect(saved, isFalse);
    });
  });

  group('page Éditeur', () {
    testWidgets('état vide puis création d\'un fichier avec coloration', (tester) async {
      final container = newContainer();
      await tester.pumpWidget(app(container));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Éditeur').last);
      await tester.pumpAndSettle();
      expect(find.text('Aucun fichier ouvert.'), findsOneWidget);

      await tester.tap(find.text('Nouveau fichier').last);
      await tester.pumpAndSettle();

      expect(find.byType(CodeEditor), findsOneWidget);
      expect(find.text('main.py'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Exécuter et Envoyer sont désactivés sans carte, Enregistrer reste actif', (tester) async {
      final container = newContainer();
      container.read(editorProvider.notifier).newDocument();
      await tester.pumpWidget(app(container));
      await tester.pumpAndSettle();
      container.read(homeTabProvider.notifier).show(HomeTab.editor);
      await tester.pumpAndSettle();

      final run = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.play_arrow));
      final send = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.upload_file));
      final save = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.save_outlined));

      expect(run.onPressed, isNull);
      expect(send.onPressed, isNull);
      expect(save.onPressed, isNotNull);
    });

    testWidgets('sur Android, la barre de symboles insère dans le fichier actif', (tester) async {
      final container = newContainer();
      container.read(editorProvider.notifier).newDocument(text: 'if x');
      final doc = container.read(editorProvider).active!;
      doc.controller.code.selection = const CodeLineSelection.collapsed(index: 0, offset: 4);
      await tester.pumpWidget(app(container));
      await tester.pumpAndSettle();
      container.read(homeTabProvider.notifier).show(HomeTab.editor);
      await tester.pumpAndSettle();

      expect(find.byType(SymbolBar), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, ':'));
      await tester.pump();

      expect(doc.controller.text, 'if x:');
      expect(doc.dirty, isTrue);
      expect(find.text('● main.py'), findsOneWidget);
      // Le brouillon automatique est programmé : on l'écrit pour ne laisser aucun minuteur.
      await tester.runAsync(() => container.read(editorProvider.notifier).flushDrafts());
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('sur desktop, pas de barre de symboles', (tester) async {
      final container = newContainer();
      container.read(editorProvider.notifier).newDocument();
      await tester.pumpWidget(app(container));
      await tester.pumpAndSettle();
      container.read(homeTabProvider.notifier).show(HomeTab.editor);
      await tester.pumpAndSettle();

      expect(find.byType(SymbolBar), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('s\'affiche sans débordement sur un téléphone, sortie dépliée', (tester) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final container = newContainer();
      container.read(editorProvider.notifier).newDocument(text: 'print("salut")\n' * 40);
      await tester.pumpWidget(app(container));
      await tester.pumpAndSettle();
      container.read(homeTabProvider.notifier).show(HomeTab.editor);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Afficher la sortie'));
      await tester.pumpAndSettle();

      expect(find.byType(CodeEditor), findsOneWidget);
      expect(find.byType(SymbolBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('clavier virtuel ouvert : la barre de navigation laisse la place à la barre de symboles', (tester) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final container = newContainer();
      container.read(editorProvider.notifier).newDocument();
      await tester.pumpWidget(app(container));
      await tester.pumpAndSettle();
      container.read(homeTabProvider.notifier).show(HomeTab.editor);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);

      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(SymbolBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });
}
