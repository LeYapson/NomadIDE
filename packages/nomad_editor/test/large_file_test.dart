import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_editor/nomad_editor.dart';

/// PRD B1 : un fichier de 5 000 lignes doit rester utilisable. Ces tests ne
/// mesurent pas les images par seconde d'un téléphone (à vérifier sur appareil) ;
/// ils bornent grossièrement les coûts pour repérer une régression.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final source = [
    for (var i = 0; i < 5000; i++) 'valeur_$i = compute($i) + helper_${i % 50}(value_$i)  # ligne $i',
  ].join('\n');

  testWidgets('5 000 lignes : affichage et défilement sans exception', (tester) async {
    final controller = NomadEditorController(text: source, language: CodeLanguage.python);
    addTearDown(controller.dispose);
    final clock = Stopwatch()..start();

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: NomadCodeEditor(controller: controller))));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(NomadCodeEditor), const Offset(0, -4000));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(clock.elapsed, lessThan(const Duration(seconds: 20)));
  });

  test('5 000 lignes : symboles du fichier calculés vite, puis mis en cache', () {
    final controller = NomadEditorController(text: source, language: CodeLanguage.python);
    addTearDown(controller.dispose);

    final first = Stopwatch()..start();
    final symbols = controller.documentSymbols;
    first.stop();
    final second = Stopwatch()..start();
    controller.documentSymbols;
    second.stop();

    expect(symbols, contains('valeur_4999'));
    expect(first.elapsedMilliseconds, lessThan(1000));
    expect(second.elapsedMicroseconds, lessThan(first.elapsedMicroseconds));
  });

  test('5 000 lignes : une insertion reste instantanée', () {
    final controller = NomadEditorController(text: source, language: CodeLanguage.python);
    addTearDown(controller.dispose);
    final clock = Stopwatch()..start();

    for (var i = 0; i < 50; i++) {
      controller.insert('x');
    }

    expect(clock.elapsedMilliseconds, lessThan(2000));
  });
}
