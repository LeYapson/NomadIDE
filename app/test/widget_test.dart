// Remplace le test « compteur » généré par `flutter create` (qui ne l'écrase pas s'il existe).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_mcu/app/app.dart';
import 'package:nomad_mcu/app/providers.dart';

void main() {
  testWidgets('le moniteur série démarre et liste la carte simulée', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [serialTransportProvider.overrideWithValue(FakeSerialTransport())],
        child: const NomadApp(),
      ),
    );
    await tester.pumpAndSettle(); // laisse passer le refreshDevices() initial

    expect(find.text('NomadMCU · Moniteur série'), findsOneWidget);
    expect(find.text('Déconnecté'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Connecter'), findsOneWidget);
    expect(find.textContaining('Carte simulée'), findsOneWidget);
  });
}
