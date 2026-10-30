import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_mcu/app/app.dart';
import 'package:nomad_mcu/app/providers.dart';

import 'support/locale.dart';

Future<void> _open(WidgetTester tester, HomeTab tab) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [frenchLocale, serialTransportProvider.overrideWithValue(FakeSerialTransport())],
    child: const NomadApp(),
  ));
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(tester.element(find.byType(NomadApp)));
  container.read(homeTabProvider.notifier).show(tab);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('réglages : chaque langue est un choix exclusif annoncé coché ou non, activable par le lecteur d\'écran', (tester) async {
    final handle = tester.ensureSemantics();
    await _open(tester, HomeTab.settings);

    expect(
      tester.getSemantics(find.bySemanticsLabel('Français')),
      matchesSemantics(
        label: 'Français',
        isButton: true,
        hasTapAction: true,
        hasCheckedState: true,
        isChecked: true,
        isInMutuallyExclusiveGroup: true,
      ),
    );

    // Choisir l'anglais par la sémantique (comme TalkBack) change la langue et déplace la coche.
    tester.semantics.tap(find.semantics.byLabel('English'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.bySemanticsLabel('English')),
      matchesSemantics(
        label: 'English',
        isButton: true,
        hasTapAction: true,
        hasCheckedState: true,
        isChecked: true,
        isInMutuallyExclusiveGroup: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('moniteur : l\'état de connexion est une région vivante, annoncée quand il change', (tester) async {
    final handle = tester.ensureSemantics();
    await _open(tester, HomeTab.monitor);

    final node = tester.getSemantics(find.bySemanticsLabel('Déconnecté'));
    expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });
}
