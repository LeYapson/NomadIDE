// Remplace le test « compteur » généré par `flutter create` (qui ne l'écrase pas s'il existe).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_mcu/app/app.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'support/locale.dart';

void main() {
  testWidgets('le moniteur série démarre et liste la carte simulée', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [frenchLocale, serialTransportProvider.overrideWithValue(FakeSerialTransport())],
        child: const NomadApp(),
      ),
    );
    await tester.pumpAndSettle(); // laisse passer le refreshDevices() initial

    expect(find.text('NomadMCU · Moniteur série'), findsOneWidget);
    expect(find.text('Déconnecté'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('Connecter'), matching: find.bySubtype<FilledButton>()),
      findsOneWidget,
    );
    expect(find.textContaining('Carte simulée'), findsOneWidget);
  });

  testWidgets("l'onglet MicroPython liste la carte simulée et propose la connexion raw REPL", (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [frenchLocale, serialTransportProvider.overrideWithValue(FakeSerialTransport())],
        child: const NomadApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('MicroPython').last);
    await tester.pumpAndSettle();

    expect(find.text('NomadMCU · MicroPython'), findsOneWidget);
    expect(find.text('Connecter (raw REPL)'), findsOneWidget);
    expect(find.textContaining('Carte simulée'), findsWidgets);
  });

  testWidgets("la page MicroPython s'affiche sans débordement sur un écran de téléphone", (tester) async {
    tester.view.physicalSize = const Size(1080, 2200); // ≈ 360 × 733 dp
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [frenchLocale, serialTransportProvider.overrideWithValue(FakeSerialTransport())],
        child: const NomadApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('MicroPython').last);
    await tester.pumpAndSettle();

    expect(find.text('Console'), findsOneWidget);
    expect(find.text('Fichiers'), findsOneWidget);
    await tester.tap(find.text('Fichiers'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Test de transfert (débit et intégrité)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
