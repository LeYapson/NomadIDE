import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// G6 : l'identité visuelle vient du thème (`lib/app/theme.dart`), pas des écrans. Un écran qui écrit une couleur
/// en dur échapperait au thème clair/sombre et aux contrastes vérifiés (G5).
void main() {
  /// Couleurs admises hors du thème : le voile de la visite guidée n'est pas une couleur de marque.
  const allowedFiles = {'tour_overlay.dart'};

  test('les écrans et composants n\'écrivent aucune couleur en dur', () {
    final offenders = <String>[];
    for (final root in ['lib/features', 'lib/ui']) {
      for (final file in Directory(root).listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final name = file.uri.pathSegments.last;
        if (allowedFiles.contains(name)) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          final hardCoded = RegExp(r'Color\(0x').hasMatch(line) || RegExp(r'\bColors\.(?!transparent)\w+').hasMatch(line);
          if (hardCoded) offenders.add('${file.path}:${i + 1}: ${line.trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'Utiliser le thème (colorScheme, nomadColors) :\n${offenders.join('\n')}');
  });
}
