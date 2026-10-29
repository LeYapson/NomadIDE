import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_mcu/app/app.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:nomad_mcu/app/theme.dart';
import 'package:nomad_mcu/features/editor/application/editor_controller.dart';
import 'package:nomad_mcu/features/flash/application/flash_controller.dart';

import 'support/locale.dart';

/// Rapport de contraste WCAG entre deux couleurs opaques.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    final name = brightness == Brightness.dark ? 'sombre' : 'clair';
    final theme = buildTheme(brightness);
    final s = theme.colorScheme;
    final n = theme.extension<NomadColors>()!;

    group('thème $name', () {
      test('chaque texte atteint 4,5:1 sur son fond (WCAG AA)', () {
        final pairs = <String, (Color, Color)>{
          'texte / fond': (s.onSurface, s.surface),
          'texte / panneau': (s.onSurface, s.surfaceContainer),
          'texte / panneau haut': (s.onSurface, s.surfaceContainerHigh),
          'texte secondaire / fond': (s.onSurfaceVariant, s.surface),
          'texte secondaire / panneau': (s.onSurfaceVariant, s.surfaceContainer),
          'bouton principal': (s.onPrimary, s.primary),
          'conteneur principal': (s.onPrimaryContainer, s.primaryContainer),
          'conteneur secondaire (navigation)': (s.onSecondaryContainer, s.secondaryContainer),
          'bouton d\'erreur': (s.onError, s.error),
          'erreur / fond': (s.error, s.surface),
          'erreur / panneau': (s.error, s.surfaceContainer),
          'bannière d\'erreur': (s.onErrorContainer, s.errorContainer),
          'bouton d\'action matérielle': (n.onHardware, n.hardware),
          'succès / fond': (n.success, s.surface),
          'succès / panneau': (n.success, s.surfaceContainer),
          'bouton de succès': (n.onSuccess, n.success),
          'bannière de succès': (n.onSuccessContainer, n.successContainer),
          'message système (journal)': (s.tertiary, s.surface),
          'message système / panneau': (s.tertiary, s.surfaceContainer),
          'action matérielle / fond': (n.hardware, s.surface),
        };
        for (final entry in pairs.entries) {
          // Le texte coloré posé directement sur un fond clair n'existe qu'en thème sombre pour l'ambre.
          if (brightness == Brightness.light && entry.key == 'action matérielle / fond') continue;
          expect(contrast(entry.value.$1, entry.value.$2), greaterThanOrEqualTo(4.5), reason: entry.key);
        }
      });

      test('le focus et les contours atteignent 3:1 (composants d\'interface)', () {
        expect(contrast(s.primary, s.surface), greaterThanOrEqualTo(3), reason: 'focus et sélection / fond');
        expect(contrast(s.primary, s.surfaceContainer), greaterThanOrEqualTo(3), reason: 'focus / panneau');
        expect(contrast(s.outline, s.surface), greaterThanOrEqualTo(3), reason: 'contour / fond');
        expect(contrast(s.outline, s.surfaceContainer), greaterThanOrEqualTo(3), reason: 'contour / panneau');
      });
    });
  }

  test('le thème sombre suit la palette de la marque', () {
    final s = buildTheme(Brightness.dark).colorScheme;
    expect(s.surface, const Color(0xFF111318)); // Obsidian Dark
    expect(s.surfaceContainer, const Color(0xFF1B1E28)); // Deep Slate
    expect(s.onSurface, const Color(0xFFF3F4F6)); // Soft Chalk
    expect(buildTheme(Brightness.dark).extension<NomadColors>()!.hardware, const Color(0xFFFF6B35)); // Solar Amber
    expect(buildTheme(Brightness.dark).extension<NomadColors>()!.success, const Color(0xFF00E5A3)); // Cyber Mint
  });

  test('le blanc sur Solar Amber est interdit : le texte des boutons d\'action est sombre', () {
    expect(contrast(Colors.white, solarAmber), lessThan(3));
    final n = NomadColors.dark;
    expect(n.onHardware, isNot(Colors.white));
    expect(contrast(n.onHardware, n.hardware), greaterThanOrEqualTo(4.5));
  });

  group('écrans', () {
    for (final brightness in Brightness.values) {
      for (final tab in HomeTab.values) {
        testWidgets('${tab.name} en thème ${brightness.name} : contraste du texte et libellés', (tester) async {
          final handle = tester.ensureSemantics();
          tester.view.physicalSize = const Size(1200, 2400);
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

          final storage = Directory.systemTemp.createTempSync('nomad_theme_test');
          final container = ProviderContainer(overrides: [
            frenchLocale,
            serialTransportProvider.overrideWithValue(FakeSerialTransport()),
            storageRootProvider.overrideWith((ref) => storage),
            uf2DrivePollProvider.overrideWithValue(null),
          ]);
          addTearDown(() {
            container.dispose();
            storage.deleteSync(recursive: true);
          });
          container.read(editorProvider.notifier).newDocument(text: 'print("bonjour")  # commentaire');

          await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const NomadApp()));
          await tester.pumpAndSettle();
          container.read(homeTabProvider.notifier).show(tab);
          await tester.pumpAndSettle();

          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await tester.runAsync(() => container.read(editorProvider.notifier).flushDrafts());
          handle.dispose();
        });
      }
    }
  });
}
