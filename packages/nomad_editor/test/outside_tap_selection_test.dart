import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_editor/nomad_editor.dart';

/// re_editor annule la sélection dès que l'éditeur perd le focus, c'est-à-dire dès
/// qu'on touche un widget extérieur (ex. le bouton « Exécuter » de la barre
/// d'outils) : il lirait alors une sélection déjà vide. Les boutons d'action doivent
/// être déclarés dans la zone de l'éditeur (`CodeEditorTapRegion`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const text = 'print("un")\nprint("deux")';

  Future<(NomadEditorController, FocusNode)> pump(WidgetTester tester, Widget Function(VoidCallback onTap) button, void Function(String) onRun) async {
    final controller = NomadEditorController(text: text, language: CodeLanguage.python);
    addTearDown(controller.dispose);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            button(() => onRun(controller.runnableText)),
            Expanded(child: NomadCodeEditor(controller: controller, focusNode: focus)),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    focus.requestFocus();
    await tester.pumpAndSettle();
    // Sélection de la première ligne.
    controller.code.selection = const CodeLineSelection(baseIndex: 0, baseOffset: 0, extentIndex: 0, extentOffset: 11);
    await tester.pumpAndSettle();
    expect(controller.runnableText, 'print("un")', reason: 'préparation : la sélection est prise en compte');
    return (controller, focus);
  }

  testWidgets('un bouton hors de l\'éditeur fait perdre la sélection (comportement de re_editor)', (tester) async {
    String? sent;
    await pump(tester, (onTap) => ElevatedButton(onPressed: onTap, child: const Text('Run')), (t) => sent = t);

    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();

    expect(sent, text, reason: 'la sélection est déjà annulée : c\'est tout le fichier qui partirait');
  });

  testWidgets('un bouton rangé dans CodeEditorTapRegion conserve la sélection', (tester) async {
    String? sent;
    final (controller, focus) = await pump(
      tester,
      (onTap) => CodeEditorTapRegion(child: ElevatedButton(onPressed: onTap, child: const Text('Run'))),
      (t) => sent = t,
    );

    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();

    expect(sent, 'print("un")');
    expect(controller.code.selection.isCollapsed, isFalse);
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('toucher vraiment ailleurs retire toujours la sélection', (tester) async {
    final (controller, focus) = await pump(tester, (onTap) => const Text('ailleurs'), (_) {});

    await tester.tap(find.text('ailleurs'));
    await tester.pumpAndSettle();

    expect(focus.hasFocus, isFalse);
    expect(controller.code.selection.isCollapsed, isTrue);
  });
}
