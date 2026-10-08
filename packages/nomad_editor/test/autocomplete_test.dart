import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_editor/nomad_editor.dart';
import 'package:nomad_editor/src/autocomplete.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Suggestions pour le curseur placé à la fin de la ligne [line] du texte [text].
  Future<List<String>> suggest(
    WidgetTester tester,
    String text,
    CodeLanguage language, {
    int? line,
    int? caret,
  }) async {
    final controller = NomadEditorController(text: text, language: language);
    addTearDown(controller.dispose);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final lines = text.split('\n');
    final index = line ?? lines.length - 1;
    final offset = caret ?? lines[index].length;
    final value = NomadPromptsBuilder(controller).build(
      tester.element(find.byType(SizedBox)),
      CodeLine(lines[index]),
      CodeLineSelection.collapsed(index: index, offset: offset),
    );
    return [for (final prompt in value?.prompts ?? const <CodePrompt>[]) prompt.word];
  }

  group('suggestions', () {
    testWidgets('Python : mots-clés et fonctions natives', (tester) async {
      expect(await suggest(tester, 'pri', CodeLanguage.python), contains('print'));
      expect(await suggest(tester, 'imp', CodeLanguage.python), contains('import'));
      expect(await suggest(tester, 'whi', CodeLanguage.python), ['while']);
    });

    testWidgets('Python : noms MicroPython courants', (tester) async {
      final words = await suggest(tester, 'from machine import Pi', CodeLanguage.python);
      expect(words, contains('Pin'));
      expect(await suggest(tester, 'time.sle', CodeLanguage.python), containsAll(['sleep', 'sleep_ms', 'sleep_us']));
    });

    testWidgets('symboles du fichier ouvert', (tester) async {
      final words = await suggest(tester, 'compteur = 0\nco', CodeLanguage.python);
      expect(words, contains('compteur'));
      expect(words, contains('continue'));
    });

    testWidgets('les symboles suivent les modifications du fichier', (tester) async {
      final controller = NomadEditorController(text: 'alpha_value = 1', language: CodeLanguage.python);
      addTearDown(controller.dispose);
      expect(controller.documentSymbols, contains('alpha_value'));

      controller.text = 'beta_value = 2';

      expect(controller.documentSymbols, contains('beta_value'));
      expect(controller.documentSymbols, isNot(contains('alpha_value')));
    });

    testWidgets('rien avant 2 caractères, ni pour un mot déjà complet', (tester) async {
      expect(await suggest(tester, 'p', CodeLanguage.python), isEmpty);
      expect(await suggest(tester, 'print', CodeLanguage.python), isNot(contains('print')));
      expect(await suggest(tester, 'x = ', CodeLanguage.python), isEmpty);
    });

    testWidgets('rien dans un commentaire ni dans une chaîne', (tester) async {
      expect(await suggest(tester, '# pri', CodeLanguage.python), isEmpty);
      expect(await suggest(tester, 'print("pri', CodeLanguage.python), isEmpty);
      expect(await suggest(tester, 'int x; // whi', CodeLanguage.c), isEmpty);
    });

    testWidgets('C et C++ : listes distinctes', (tester) async {
      expect(await suggest(tester, 'uin', CodeLanguage.c), contains('uint8_t'));
      expect(await suggest(tester, 'pinM', CodeLanguage.cpp), contains('pinMode'));
      expect(await suggest(tester, 'pinM', CodeLanguage.c), isEmpty);
    });

    testWidgets('texte brut : uniquement les symboles du fichier', (tester) async {
      expect(await suggest(tester, 'whi', CodeLanguage.plain), isEmpty);
      expect(await suggest(tester, 'bonjour\nbon', CodeLanguage.plain), ['bonjour']);
    });

    testWidgets('au plus 12 suggestions, les plus courtes d\'abord', (tester) async {
      final text = [for (var i = 0; i < 30; i++) 'valeur_$i'].join('\n');
      final words = await suggest(tester, '$text\nval', CodeLanguage.python);

      expect(words, hasLength(NomadPromptsBuilder.maxPrompts));
      expect(words.first.length, lessThanOrEqualTo(words.last.length));
    });
  });

  group('runnableText', () {
    NomadEditorController create(String text) {
      final controller = NomadEditorController(text: text, language: CodeLanguage.python);
      addTearDown(controller.dispose);
      return controller;
    }

    CodeLineSelection range(int fromLine, int fromOffset, int toLine, int toOffset) => CodeLineSelection(
          baseIndex: fromLine,
          baseOffset: fromOffset,
          extentIndex: toLine,
          extentOffset: toOffset,
        );

    test('sans sélection : tout le fichier', () {
      expect(create('a = 1\nprint(a)').runnableText, 'a = 1\nprint(a)');
    });

    test('une sélection étend aux lignes entières', () {
      final controller = create('a = 1\nb = 2\nprint(a + b)');
      controller.code.selection = range(1, 2, 1, 4);

      expect(controller.runnableText, 'b = 2');
    });

    test('plusieurs lignes, indentation commune retirée', () {
      final controller = create('def f():\n    x = 1\n    if x:\n        print(x)\nf()');
      controller.code.selection = range(1, 0, 3, 14);

      expect(controller.runnableText, 'x = 1\nif x:\n    print(x)');
    });

    test('une sélection finissant en début de ligne n\'inclut pas cette ligne', () {
      final controller = create('a = 1\nb = 2\nc = 3');
      controller.code.selection = range(0, 0, 2, 0);

      expect(controller.runnableText, 'a = 1\nb = 2');
    });

    test('sélection vide de contenu : tout le fichier', () {
      final controller = create('a = 1\n\n\nb = 2');
      controller.code.selection = range(1, 0, 2, 0);

      expect(controller.runnableText, 'a = 1\n\n\nb = 2');
    });

    test('selectedText reflète la sélection', () {
      final controller = create('hello world');
      controller.code.selection = range(0, 0, 0, 5);

      expect(controller.selectedText, 'hello');
    });
  });

  group('PromptListView', () {
    testWidgets('toucher une suggestion la sélectionne', (tester) async {
      final notifier = ValueNotifier(const CodeAutocompleteEditingValue(
        input: 'pr',
        prompts: [CodeKeywordPrompt(word: 'print'), CodeKeywordPrompt(word: 'property')],
        index: 0,
      ));
      addTearDown(notifier.dispose);
      CodeAutocompleteResult? picked;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PromptListView(notifier: notifier, onSelected: (r) => picked = r)),
      ));
      await tester.tap(find.text('property'));

      expect(picked?.word, 'property');
      expect(picked?.input, 'pr');
    });

    testWidgets('la taille suit le nombre de suggestions, plafonnée à 5 lignes', (tester) async {
      final many = [for (var i = 0; i < 12; i++) CodeKeywordPrompt(word: 'mot$i')];
      final notifier = ValueNotifier(CodeAutocompleteEditingValue(input: 'mo', prompts: many, index: 0));
      addTearDown(notifier.dispose);
      final view = PromptListView(notifier: notifier, onSelected: (_) {});

      expect(view.preferredSize.height, PromptListView.visibleItems * PromptListView.itemHeight + 2);

      notifier.value = notifier.value.copyWith(prompts: many.take(2).toList());
      expect(view.preferredSize.height, 2 * PromptListView.itemHeight + 2);
    });
  });

  testWidgets('NomadCodeEditor avec autocomplétion se construit pour chaque langage', (tester) async {
    for (final language in CodeLanguage.values) {
      final controller = NomadEditorController(text: 'x = 1', language: language);
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: NomadCodeEditor(controller: controller))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: language.label);
    }
  });
}
