import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_mcu/app/app.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:nomad_mcu/features/editor/application/editor_controller.dart';
import 'package:nomad_mcu/features/flash/application/flash_controller.dart';

import 'support/locale.dart';

/// Accessibilité de chaque écran sur un téléphone : zones tactiles d'au moins 48 dp, libellé sur chaque
/// zone tactile, contraste du texte.
void main() {
  // La barre du bas : chaque libellé tient sur une seule ligne, donc toute la barre reste alignée.
  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('barre de navigation sur téléphone, texte à ${(scale * 100).round()} % : libellés sur une ligne, alignés', (tester) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(ProviderScope(
        overrides: [frenchLocale, serialTransportProvider.overrideWithValue(FakeSerialTransport())],
        child: const NomadApp(),
      ));
      await tester.pumpAndSettle();

      final nav = find.byType(NavigationBar);
      final heights = <String, double>{};
      for (final label in ['Moniteur', 'Python', 'Éditeur', 'Flasher', 'Réglages']) {
        final text = find.descendant(of: nav, matching: find.text(label));
        expect(text, findsOneWidget, reason: label);
        heights[label] = tester.getSize(text).height;
      }
      expect(heights.values.toSet().length, 1, reason: 'un libellé passe sur deux lignes : $heights');
    });
  }

  testWidgets('texte d\'attente du moniteur : centré, avec une marge, même à 200 %', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(ProviderScope(
      overrides: [frenchLocale, serialTransportProvider.overrideWithValue(FakeSerialTransport())],
      child: const NomadApp(),
    ));
    await tester.pumpAndSettle();

    final text = find.textContaining('Connectez une carte : le flux série');
    expect(text, findsOneWidget);
    expect(tester.widget<Text>(text).textAlign, TextAlign.center);
    final rect = tester.getRect(text);
    expect(rect.left, greaterThanOrEqualTo(24), reason: 'marge à gauche');
    expect(360 - rect.right, greaterThanOrEqualTo(24), reason: 'marge à droite');
  });

  // Texte agrandi dans les réglages du système : rien ne doit déborder (WCAG 1.4.4, RGAA 10.4).
  for (final tab in HomeTab.values) {
    for (final scale in [1.5, 2.0]) {
      testWidgets('${tab.name}, texte à ${(scale * 100).round()} % : rien ne déborde', (tester) async {
        tester.view.physicalSize = const Size(1080, 2200);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final storage = Directory.systemTemp.createTempSync('nomad_scale_test');
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
        container.read(editorProvider.notifier).newDocument(text: 'print("bonjour")');

        await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const NomadApp()));
        await tester.pumpAndSettle();
        container.read(homeTabProvider.notifier).show(tab);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        await tester.runAsync(() => container.read(editorProvider.notifier).flushDrafts());
      });
    }
  }

  for (final tab in HomeTab.values) {
    for (final brightness in Brightness.values) {
      testWidgets('${tab.name}, thème ${brightness.name} : cibles, libellés, contraste', (tester) async {
        final handle = tester.ensureSemantics();
        tester.view.physicalSize = const Size(1080, 2200); // ≈ 360 × 733 dp
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

        final storage = Directory.systemTemp.createTempSync('nomad_a11y_test');
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
        container.read(editorProvider.notifier).newDocument(text: 'print("bonjour")');

        await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const NomadApp()));
        await tester.pumpAndSettle();
        container.read(homeTabProvider.notifier).show(tab);
        await tester.pumpAndSettle();

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await tester.runAsync(() => container.read(editorProvider.notifier).flushDrafts());
        handle.dispose();
      });
    }
  }
}
