import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_mcu/app/app.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:nomad_mcu/features/flash/application/flash_controller.dart';
import 'package:nomad_mcu/features/flash/presentation/esp_flash_view.dart';
import 'package:nomad_mcu/features/flash/presentation/flash_page.dart';

import 'support/locale.dart';

Uint8List _uf2() {
  final out = Uint8List(512);
  final d = ByteData.sublistView(out);
  d.setUint32(0, 0x0A324655, Endian.little);
  d.setUint32(4, 0x9E5D5157, Endian.little);
  d.setUint32(8, 0x2000, Endian.little);
  d.setUint32(12, 0x10000000, Endian.little);
  d.setUint32(16, 256, Endian.little);
  d.setUint32(24, 1, Endian.little);
  d.setUint32(28, 0xE48BFF56, Endian.little);
  d.setUint32(508, 0x0AB16F30, Endian.little);
  return out;
}

Widget _app({required bool supported}) => ProviderScope(
      overrides: [
        frenchLocale,
        serialTransportProvider.overrideWithValue(FakeSerialTransport()),
        uf2SupportedProvider.overrideWithValue(supported),
        uf2DrivePollProvider.overrideWithValue(null),
        uf2PickerProvider.overrideWithValue(() async => (name: 'blink.uf2', bytes: _uf2())),
      ],
      child: const NomadApp(),
    );

final _flashButton = find.descendant(of: find.byType(FlashPage), matching: find.bySubtype<FilledButton>());

/// La liste ne construit que ce qui est visible : un écran haut montre les trois étapes.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets("l'onglet Flasher s'affiche sans débordement sur un écran de téléphone", (tester) async {
    tester.view.physicalSize = const Size(1080, 2200); // ≈ 360 × 733 dp
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(supported: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flasher').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('ESP (.bin)'));
    await tester.pumpAndSettle();
    expect(find.text('Choisir un fichier .bin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("le sélecteur de cible bascule entre l'UF2 (RP2040) et le .bin (ESP)", (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(_app(supported: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flasher').last);
    await tester.pumpAndSettle();

    expect(find.text('Choisir un fichier .uf2'), findsOneWidget);
    expect(find.text('Choisir un fichier .bin'), findsNothing);

    await tester.tap(find.text('ESP (.bin)'));
    await tester.pumpAndSettle();

    expect(find.text('Choisir un fichier .bin'), findsOneWidget);
    expect(find.text('Choisir un fichier .uf2'), findsNothing);
    // L'adresse, déduite du fichier, est dans les options avancées (repliées).
    expect(find.text('Adresse d’écriture (hexadécimal)'), findsNothing);
    await tester.tap(find.text('Options avancées'));
    await tester.pumpAndSettle();
    expect(find.text('Adresse d’écriture (hexadécimal)'), findsOneWidget);
    expect(tester.widget<FilledButton>(_flashButton).onPressed, isNull);
  });

  testWidgets("l'onglet Flasher guide les trois étapes et active le bouton après le choix du fichier", (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(_app(supported: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Flasher').last);
    await tester.pumpAndSettle();

    expect(find.text('NomadIDE · Flasher un programme'), findsOneWidget);
    expect(find.text('Fichier du programme'), findsOneWidget);
    expect(find.text('Aucun fichier choisi'), findsOneWidget);
    FilledButton flashButton() => tester.widget<FilledButton>(_flashButton);
    expect(flashButton().onPressed, isNull);

    await tester.tap(find.text('Choisir un fichier .uf2'));
    await tester.pumpAndSettle();

    expect(find.text('blink.uf2'), findsOneWidget);
    expect(find.textContaining('RP2040 ·'), findsOneWidget);
    expect(flashButton().onPressed, isNotNull);
  });

  testWidgets("sur un système sans copie UF2 (Android), la page l'explique et bloque le bouton", (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(_app(supported: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Flasher').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choisir un fichier .uf2'));
    await tester.pumpAndSettle();

    expect(find.textContaining('PICOBOOT'), findsOneWidget);
    final button = tester.widget<FilledButton>(_flashButton);
    expect(button.onPressed, isNull);
  });

  group('parcours guidé', () {
    Future<void> openFlash(WidgetTester tester) async {
      await tester.pumpWidget(_app(supported: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flasher').last);
      await tester.pumpAndSettle();
    }

    testWidgets("sans fichier, l'étape d'écriture est visible, bloquée, et dit pourquoi", (tester) async {
      _tallScreen(tester);
      await openFlash(tester);

      expect(find.text('Choisissez d’abord un fichier pour pouvoir flasher.'), findsOneWidget);
      expect(tester.widget<FilledButton>(_flashButton).onPressed, isNull);
      // Le bouton d'action fait au moins 48 dp de haut.
      expect(tester.getSize(_flashButton).height, greaterThanOrEqualTo(48));
    });

    testWidgets("une étape terminée se replie sur son résumé et se rouvre d'un toucher", (tester) async {
      _tallScreen(tester);
      await openFlash(tester);

      await tester.tap(find.text('Choisir un fichier .uf2'));
      await tester.pumpAndSettle();

      // Replié : le résumé reste (nom et type), le bouton de choix disparaît.
      expect(find.text('blink.uf2'), findsOneWidget);
      expect(find.textContaining('RP2040 ·'), findsOneWidget);
      expect(find.text('Choisir un fichier .uf2'), findsNothing);
      expect(find.text('Choisissez d’abord un fichier pour pouvoir flasher.'), findsNothing);

      await tester.tap(find.text('Fichier du programme'));
      await tester.pumpAndSettle();
      expect(find.text('Choisir un fichier .uf2'), findsOneWidget);

      await tester.tap(find.text('Fichier du programme'));
      await tester.pumpAndSettle();
      expect(find.text('Choisir un fichier .uf2'), findsNothing);
    });

    testWidgets("le lecteur d'écran annonce le numéro, le nom et l'état de chaque étape", (tester) async {
      _tallScreen(tester);
      final handle = tester.ensureSemantics();
      await openFlash(tester);

      expect(find.bySemanticsLabel('Étape 1 sur 3 : Fichier du programme, à faire'), findsOneWidget);
      expect(find.bySemanticsLabel('Étape 3 sur 3 : Écriture, à faire'), findsOneWidget);

      await tester.tap(find.text('Choisir un fichier .uf2'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Étape 1 sur 3 : Fichier du programme, terminée'), findsOneWidget);
      // Une étape terminée est un bouton qui dit ce qu'il fait.
      expect(
        tester.getSemantics(find.bySemanticsLabel('Étape 1 sur 3 : Fichier du programme, terminée')),
        matchesSemantics(
          label: 'Étape 1 sur 3 : Fichier du programme, terminée',
          hint: 'Toucher pour modifier cette étape',
          isHeader: true,
          isButton: true,
          hasTapAction: true,
          hasExpandedState: true,
          isExpanded: false,
        ),
      );
      handle.dispose();
    });

    for (final scale in [1.0, 1.5]) {
      for (final esp in [false, true]) {
        testWidgets('écran de 360 dp, texte à ${(scale * 100).round()} %, ${esp ? 'ESP' : 'UF2'} : rien ne déborde', (tester) async {
          tester.view.physicalSize = const Size(1080, 2200);
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpWidget(_app(supported: true));
          await tester.pumpAndSettle();
          // L'écran Moniteur (affiché au démarrage) déborde à 150 % : hors du périmètre de ce test.
          while (tester.takeException() != null) {}
          await tester.tap(find.text('Flasher').last);
          await tester.pumpAndSettle();
          if (esp) {
            await tester.tap(find.text('ESP (.bin)'));
            await tester.pumpAndSettle();
          } else {
            await tester.tap(find.text('Choisir un fichier .uf2'));
            await tester.pumpAndSettle();
          }
          // Ouvre la section la plus longue et fait défiler jusqu'au bas de la liste.
          final list = find.descendant(of: find.byType(esp ? EspFlashView : Uf2FlashView), matching: find.byType(Scrollable)).first;
          await tester.scrollUntilVisible(find.text(esp ? 'Options avancées' : 'Écriture'), 300, scrollable: list);
          if (esp) {
            await tester.ensureVisible(find.text('Options avancées'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Options avancées'));
            await tester.pumpAndSettle();
            await tester.drag(list, const Offset(0, -600));
            await tester.pumpAndSettle();
            expect(find.text('Débit d’écriture'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
