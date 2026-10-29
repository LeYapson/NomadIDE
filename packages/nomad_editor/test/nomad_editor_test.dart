import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_editor/nomad_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CodeLanguage.fromFileName', () {
    test('reconnaît Python, C et C++ par extension', () {
      expect(CodeLanguage.fromFileName('main.py'), CodeLanguage.python);
      expect(CodeLanguage.fromFileName('MAIN.PY'), CodeLanguage.python);
      expect(CodeLanguage.fromFileName('blink.c'), CodeLanguage.c);
      expect(CodeLanguage.fromFileName('pins.h'), CodeLanguage.c);
      expect(CodeLanguage.fromFileName('app.cpp'), CodeLanguage.cpp);
      expect(CodeLanguage.fromFileName('sketch.ino'), CodeLanguage.cpp);
    });

    test('retombe sur du texte brut sinon', () {
      expect(CodeLanguage.fromFileName('README'), CodeLanguage.plain);
      expect(CodeLanguage.fromFileName('notes.txt'), CodeLanguage.plain);
      expect(CodeLanguage.fromFileName('fichier.'), CodeLanguage.plain);
    });
  });

  group('NomadEditorController', () {
    late NomadEditorController controller;

    tearDown(() => controller.dispose());

    NomadEditorController create(String text, CodeLanguage language, {int? atLine, int? atOffset}) {
      controller = NomadEditorController(text: text, language: language);
      if (atLine != null) {
        controller.code.selection = CodeLineSelection.collapsed(index: atLine, offset: atOffset ?? 0);
      }
      return controller;
    }

    test('insert place le texte au curseur', () {
      create('print()', CodeLanguage.python, atLine: 0, atOffset: 6);

      controller.insert('"x"');

      expect(controller.text, 'print("x")');
    });

    test('insert remplace la sélection', () {
      create('abcdef', CodeLanguage.plain);
      controller.code.selection = const CodeLineSelection(
        baseIndex: 0,
        baseOffset: 1,
        extentIndex: 0,
        extentOffset: 4,
      );

      controller.insert('-');

      expect(controller.text, 'a-ef');
    });

    test('annuler et rétablir', () {
      create('a', CodeLanguage.plain, atLine: 0, atOffset: 1);
      controller.insert('b');
      expect(controller.text, 'ab');

      controller.undo();
      expect(controller.text, 'a');
      controller.redo();
      expect(controller.text, 'ab');
    });

    test('Python : Entrée après « : » indente d\'un niveau', () {
      create('if x:', CodeLanguage.python, atLine: 0, atOffset: 5);

      controller.code.applyNewLine();

      expect(controller.text, 'if x:\n    ');
      expect(controller.code.selection.startIndex, 1);
      expect(controller.code.selection.startOffset, 4);
    });

    test('Python : l\'indentation existante est conservée et complétée', () {
      create('def f():\n    if x:', CodeLanguage.python, atLine: 1, atOffset: 9);

      controller.code.applyNewLine();

      expect(controller.text, 'def f():\n    if x:\n        ');
    });

    test('Python : Entrée après une ligne sans « : » garde seulement l\'indentation', () {
      create('    x = 1', CodeLanguage.python, atLine: 0, atOffset: 9);

      controller.code.applyNewLine();

      expect(controller.text, '    x = 1\n    ');
    });

    test('Python : un « : » suivi d\'espaces compte aussi', () {
      create('else:  ', CodeLanguage.python, atLine: 0, atOffset: 7);

      controller.code.applyNewLine();

      expect(controller.text.split('\n').last, '    ');
    });

    test('Python : Entrée au milieu d\'une ligne ne rajoute rien', () {
      create('if x: pass', CodeLanguage.python, atLine: 0, atOffset: 5);

      controller.code.applyNewLine();

      expect(controller.text, 'if x:\n pass');
    });

    test('C : pas d\'indentation après « : » (ex. étiquette ou case)', () {
      create('case 1:', CodeLanguage.c, atLine: 0, atOffset: 7);

      controller.code.applyNewLine();

      expect(controller.text, 'case 1:\n');
    });

    test('C : Entrée entre accolades ouvre un bloc indenté', () {
      create('void f() {}', CodeLanguage.c, atLine: 0, atOffset: 10);

      controller.code.applyNewLine();

      expect(controller.text, 'void f() {\n  \n}');
    });

    test('une modification notifie les écouteurs', () {
      create('', CodeLanguage.plain);
      var notified = 0;
      controller.addListener(() => notified++);

      controller.insert('x');

      expect(notified, greaterThan(0));
    });
  });

  group('widgets', () {
    testWidgets('NomadCodeEditor affiche le texte et les numéros de ligne', (tester) async {
      final controller = NomadEditorController(text: 'import time\nprint(1)', language: CodeLanguage.python);
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: NomadCodeEditor(controller: controller))));
      await tester.pumpAndSettle();

      expect(find.byType(CodeEditor), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('NomadCodeEditor se construit en thème sombre, pour chaque langage', (tester) async {
      for (final language in CodeLanguage.values) {
        final controller = NomadEditorController(text: 'x', language: language);
        addTearDown(controller.dispose);
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(body: NomadCodeEditor(controller: controller)),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: language.label);
      }
    });

    testWidgets('SymbolBar insère le symbole touché au curseur', (tester) async {
      final controller = NomadEditorController(text: 'if x', language: CodeLanguage.python);
      addTearDown(controller.dispose);
      controller.code.selection = const CodeLineSelection.collapsed(index: 0, offset: 4);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SymbolBar(controller: controller))));

      await tester.tap(find.text(':'));
      await tester.pump();

      expect(controller.text, 'if x:');
    });

    testWidgets('SymbolBar : Tab indente et les flèches annulent / rétablissent', (tester) async {
      final controller = NomadEditorController(text: '', language: CodeLanguage.python);
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SymbolBar(controller: controller))));

      await tester.tap(find.text('Tab'));
      await tester.pump();
      expect(controller.text, '    ');

      await tester.tap(find.byIcon(Icons.undo));
      await tester.pump();
      expect(controller.text, '');
    });

    testWidgets('QuickKeyBar déclenche les actions personnalisées', (tester) async {
      var interrupts = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: QuickKeyBar(keys: [QuickKey(label: '^C', tooltip: 'Interrompre', onPressed: () => interrupts++)]),
        ),
      ));

      await tester.tap(find.text('^C'));

      expect(interrupts, 1);
    });

    group('accessibilité de la barre de symboles', () {
      Future<NomadEditorController> pumpBar(WidgetTester tester, {SymbolBarLabels labels = const SymbolBarLabels()}) async {
        final controller = NomadEditorController(text: '', language: CodeLanguage.python);
        addTearDown(controller.dispose);
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: SymbolBar(controller: controller, labels: labels))));
        return controller;
      }

      testWidgets('chaque touche mesure au moins 48 × 48 dp et porte un libellé', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpBar(tester);

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      });

      testWidgets('les touches sont des boutons lus avec leur nom parlé, la barre est nommée', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpBar(
          tester,
          labels: const SymbolBarLabels(
            bar: 'Typing shortcuts',
            insert: _insertEn,
            symbolNames: {':': 'colon', '{': 'opening brace'},
          ),
        );

        expect(tester.getSemantics(find.bySemanticsLabel('Insert colon')), matchesSemantics(label: 'Insert colon', isButton: true, hasTapAction: true, isEnabled: true, hasEnabledState: true));
        expect(find.bySemanticsLabel('Insert opening brace'), findsOneWidget);
        expect(find.bySemanticsLabel('Typing shortcuts'), findsOneWidget);
        handle.dispose();
      });

      testWidgets('une touche désactivée est annoncée comme telle', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: QuickKeyBar(keys: [QuickKey(label: '^C', tooltip: 'Interrompre', onPressed: null)])),
        ));

        expect(
          tester.getSemantics(find.bySemanticsLabel('Interrompre')),
          matchesSemantics(label: 'Interrompre', isButton: true, hasEnabledState: true, isEnabled: false),
        );
        handle.dispose();
      });

      testWidgets('le libellé vocal remplace le tooltip quand il est fourni', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: QuickKeyBar(keys: [QuickKey(label: ':', tooltip: 'Insérer :', semanticLabel: 'Insérer deux-points', onPressed: () {})]),
          ),
        ));

        expect(find.bySemanticsLabel('Insérer deux-points'), findsOneWidget);
        expect(find.bySemanticsLabel('Insérer :'), findsNothing);
        handle.dispose();
      });

      testWidgets('toucher le bouton par la sémantique (lecteur d\'écran) insère le symbole', (tester) async {
        final handle = tester.ensureSemantics();
        final controller = await pumpBar(tester);

        tester.semantics.tap(find.semantics.byLabel('Insérer :'));
        await tester.pump();

        expect(controller.text, ':');
        handle.dispose();
      });
    });

    testWidgets('toucher une touche ne retire pas le focus à l\'éditeur : le clavier reste ouvert', (tester) async {
      final controller = NomadEditorController(text: 'if x', language: CodeLanguage.python);
      addTearDown(controller.dispose);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(child: NomadCodeEditor(controller: controller, focusNode: focus)),
              SymbolBar(controller: controller),
            ],
          ),
        ),
      ));
      focus.requestFocus();
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);

      await tester.tap(find.text(':'));
      await tester.pumpAndSettle();

      expect(controller.text, contains(':'));
      expect(focus.hasFocus, isTrue, reason: 'le clavier virtuel se fermerait');
    });

    testWidgets('toucher en dehors de l\'éditeur et de la barre retire toujours le focus', (tester) async {
      final controller = NomadEditorController(text: '', language: CodeLanguage.python);
      addTearDown(controller.dispose);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(child: NomadCodeEditor(controller: controller, focusNode: focus)),
              SymbolBar(controller: controller),
              const SizedBox(height: 60, width: double.infinity, child: Text('ailleurs')),
            ],
          ),
        ),
      ));
      focus.requestFocus();
      await tester.pumpAndSettle();

      await tester.tap(find.text('ailleurs'));
      await tester.pumpAndSettle();

      expect(focus.hasFocus, isFalse);
    });
  });
}

String _insertEn(String name) => 'Insert $name';
