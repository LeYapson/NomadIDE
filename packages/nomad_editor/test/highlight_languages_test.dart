import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_editor/nomad_editor.dart';

void main() {
  test('chaque langage a au moins un mode de coloration, y compris le texte brut', () {
    // re_editor calcule `languages.map(...).reduce(min)` dans un isolate : avec une liste vide il plante
    // (« Bad state: No element ») et la coloration s'arrête pour toute l'application.
    for (final language in CodeLanguage.values) {
      for (final brightness in Brightness.values) {
        expect(
          NomadCodeEditor.highlightTheme(language, brightness).languages,
          isNotEmpty,
          reason: '$language / $brightness',
        );
      }
    }
  });
}
