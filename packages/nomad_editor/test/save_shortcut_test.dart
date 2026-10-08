import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_editor/nomad_editor.dart';

/// re_editor associe Ctrl+S à `CodeShortcutSaveIntent`, mais sa réponse par défaut ne
/// fait rien et avale la touche : sans gestionnaire fourni par l'application, Ctrl+S
/// n'enregistre jamais. Sur Android et iOS il n'installe aucun raccourci clavier ;
/// tous ces tests simulent donc un ordinateur.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final desktop = TargetPlatformVariant.only(TargetPlatform.windows);

  Future<FocusNode> pumpEditor(WidgetTester tester, NomadEditorController controller, {VoidCallback? onSave}) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NomadCodeEditor(controller: controller, focusNode: focus, onSave: onSave)),
    ));
    await tester.pumpAndSettle();
    focus.requestFocus();
    await tester.pumpAndSettle();
    return focus;
  }

  Future<void> pressCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('la frappe Ctrl+S dans l\'éditeur appelle le gestionnaire de l\'application', (tester) async {
    final controller = NomadEditorController(text: 'print(1)', language: CodeLanguage.python);
    addTearDown(controller.dispose);
    var saves = 0;
    await pumpEditor(tester, controller, onSave: () => saves++);

    await pressCtrl(tester, LogicalKeyboardKey.keyS);

    expect(saves, 1);
    expect(controller.text, 'print(1)');
  }, variant: desktop);

  testWidgets('témoin : les autres raccourcis de l\'éditeur fonctionnent (Ctrl+A sélectionne tout)', (tester) async {
    final controller = NomadEditorController(text: 'hello world', language: CodeLanguage.python);
    addTearDown(controller.dispose);
    await pumpEditor(tester, controller, onSave: () {});

    await pressCtrl(tester, LogicalKeyboardKey.keyA);

    expect(controller.code.selection.isCollapsed, isFalse);
    expect(controller.selectedText, 'hello world');
  }, variant: desktop);

  testWidgets('plusieurs Ctrl+S de suite enregistrent à chaque fois', (tester) async {
    final controller = NomadEditorController(text: 'x', language: CodeLanguage.python);
    addTearDown(controller.dispose);
    var saves = 0;
    await pumpEditor(tester, controller, onSave: () => saves++);

    await pressCtrl(tester, LogicalKeyboardKey.keyS);
    await pressCtrl(tester, LogicalKeyboardKey.keyS);

    expect(saves, 2);
  }, variant: desktop);

  testWidgets('sans gestionnaire, Ctrl+S ne plante pas et ne modifie rien', (tester) async {
    final controller = NomadEditorController(text: 'x', language: CodeLanguage.python);
    addTearDown(controller.dispose);
    await pumpEditor(tester, controller);

    await pressCtrl(tester, LogicalKeyboardKey.keyS);

    expect(tester.takeException(), isNull);
    expect(controller.text, 'x');
  }, variant: desktop);
}
