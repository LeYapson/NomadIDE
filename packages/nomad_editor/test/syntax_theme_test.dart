import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_editor/nomad_editor.dart';

/// Rapport de contraste WCAG entre deux couleurs opaques.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  void checkTheme(String name, Map<String, TextStyle> theme, Color background) {
    test('$name : fond de la marque et texte principal lisible', () {
      expect(theme['root']!.backgroundColor, background);
      expect(contrast(theme['root']!.color!, background), greaterThanOrEqualTo(7), reason: 'texte principal : AAA');
    });

    test('$name : chaque couleur de coloration a un contraste d\'au moins 4,5:1', () {
      for (final entry in theme.entries) {
        final color = entry.value.color;
        if (color == null) continue;
        expect(contrast(color, background), greaterThanOrEqualTo(4.5), reason: '$name / ${entry.key}');
      }
    });
  }

  checkTheme('thème sombre', nomadDarkSyntax, nomadDarkBackground);
  checkTheme('thème clair', nomadLightSyntax, nomadLightBackground);

  test('le fond sombre est Obsidian Dark, pas du noir pur', () {
    expect(nomadDarkBackground, const Color(0xFF111318));
  });
}
