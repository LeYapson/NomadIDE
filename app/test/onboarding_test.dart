import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_mcu/app/app.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:nomad_mcu/app/settings.dart';
import 'package:nomad_mcu/features/onboarding/onboarding_page.dart';

import 'support/locale.dart';

/// Réglages imposés : rien n'est lu ; `setOnboardingDone` ne fait que changer l'état.
class FixedSettings extends SettingsController {
  FixedSettings(this.initial);

  final AppSettings initial;

  @override
  AppSettings build() => initial;

  @override
  Future<void> setOnboardingDone(bool done) async => state = state.copyWith(onboardingDone: done);
}

void main() {
  late Directory storage;
  late ProviderContainer container;

  setUp(() {
    debugSkipOnboarding = false;
    storage = Directory.systemTemp.createTempSync('nomad_onboarding_test');
  });

  tearDown(() {
    debugSkipOnboarding = true;
    container.dispose();
    storage.deleteSync(recursive: true);
  });

  Future<void> launch(WidgetTester tester, AppSettings settings, {Size size = const Size(1080, 2200), double scale = 1.0}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    container = ProviderContainer(overrides: [
      frenchLocale,
      storageRootProvider.overrideWith((ref) => storage),
      serialTransportProvider.overrideWithValue(FakeSerialTransport()),
      settingsProvider.overrideWith(() => FixedSettings(settings)),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const NomadApp()));
    await tester.pumpAndSettle();
  }

  bool done() => container.read(settingsProvider).onboardingDone;

  testWidgets('premier lancement : le tutoriel s\'ouvre sur l\'étape 1', (tester) async {
    await launch(tester, const AppSettings(loaded: true));
    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(find.text('Étape 1 sur 4'), findsOneWidget);
    expect(find.text('Bienvenue dans NomadIDE'), findsOneWidget);
  });

  testWidgets('tutoriel déjà suivi : rien ne s\'ouvre', (tester) async {
    await launch(tester, const AppSettings(loaded: true, onboardingDone: true));
    expect(find.byType(OnboardingPage), findsNothing);
  });

  testWidgets('réglages pas encore lus : rien ne s\'ouvre (pas d\'apparition éclair)', (tester) async {
    await launch(tester, const AppSettings());
    expect(find.byType(OnboardingPage), findsNothing);
  });

  testWidgets('suivant jusqu\'à la fin, puis « Ouvrir l\'onglet Python »', (tester) async {
    await launch(tester, const AppSettings(loaded: true));
    expect(find.text('Précédent'), findsNothing);
    for (final title in ['Branchez votre carte', 'Cinq onglets', 'Votre premier programme']) {
      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Étape 4 sur 4'), findsOneWidget);
    expect(find.text('Suivant'), findsNothing);

    await tester.tap(find.text('Ouvrir l’onglet Python'));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingPage), findsNothing);
    expect(container.read(homeTabProvider), HomeTab.micropython);
    expect(done(), isTrue);
  });

  testWidgets('précédent revient en arrière ; passer ferme et n\'affiche plus le tutoriel', (tester) async {
    await launch(tester, const AppSettings(loaded: true));
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Précédent'));
    await tester.pumpAndSettle();
    expect(find.text('Étape 1 sur 4'), findsOneWidget);

    await tester.tap(find.text('Passer'));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingPage), findsNothing);
    expect(done(), isTrue);
  });

  testWidgets('revoir le tutoriel depuis Réglages → Aide', (tester) async {
    await launch(tester, const AppSettings(loaded: true, onboardingDone: true));
    container.read(homeTabProvider.notifier).show(HomeTab.settings);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Revoir le tutoriel'), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Revoir le tutoriel'));
    await tester.pumpAndSettle();
    expect(find.text('Étape 1 sur 4'), findsOneWidget);
  });

  testWidgets('accessibilité : cibles de 48 dp, libellés, contraste ; la position est annoncée', (tester) async {
    final handle = tester.ensureSemantics();
    await launch(tester, const AppSettings(loaded: true));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    final progress = tester.getSemantics(find.text('Étape 1 sur 4'));
    expect(progress.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    expect(tester.getSemantics(find.text('Bienvenue dans NomadIDE')).getSemanticsData().flagsCollection.isHeader, isTrue);
    handle.dispose();
  });

  testWidgets('téléphone de 360 dp, texte à 200 % : aucune étape ne déborde', (tester) async {
    await launch(tester, const AppSettings(loaded: true), scale: 2.0);
    for (var i = 0; i < 3; i++) {
      expect(tester.takeException(), isNull, reason: 'étape ${i + 1}');
      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull, reason: 'étape 4');
  });
}
