import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_mcu/app/app.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:nomad_mcu/app/settings.dart';
import 'package:nomad_mcu/features/onboarding/tour.dart';
import 'package:nomad_mcu/features/onboarding/tour_overlay.dart';

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
    storage = Directory.systemTemp.createTempSync('nomad_tour_test');
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
  int? step() => container.read(tourProvider);
  HomeTab tab() => container.read(homeTabProvider);
  Finder hole() => find.byKey(const ValueKey('tour-hole'));

  Future<void> next(WidgetTester tester, [String label = 'Suivant']) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  const total = 8;

  testWidgets('premier lancement : la visite démarre sur la bienvenue, sans élément éclairé', (tester) async {
    await launch(tester, const AppSettings(loaded: true));
    expect(find.byType(TourOverlay), findsOneWidget);
    expect(find.text('Étape 1 sur $total'), findsOneWidget);
    expect(find.text('Bienvenue dans NomadIDE'), findsOneWidget);
    expect(hole(), findsNothing);
    expect(find.text('Précédent'), findsNothing);
  });

  testWidgets('visite déjà suivie : rien ne s\'ouvre', (tester) async {
    await launch(tester, const AppSettings(loaded: true, onboardingDone: true));
    expect(find.byType(TourOverlay), findsNothing);
  });

  testWidgets('réglages pas encore lus : rien ne s\'ouvre (pas d\'apparition éclair)', (tester) async {
    await launch(tester, const AppSettings());
    expect(find.byType(TourOverlay), findsNothing);
  });

  testWidgets('chaque étape affiche son onglet et éclaire son élément ; « Terminer » clôt la visite', (tester) async {
    await launch(tester, const AppSettings(loaded: true));
    final expected = <(String, HomeTab, bool)>[
      ('Bienvenue dans NomadIDE', HomeTab.monitor, false),
      ('Branchez votre carte', HomeTab.micropython, true),
      ('Moniteur', HomeTab.monitor, true),
      ('MicroPython', HomeTab.micropython, true),
      ('Éditeur', HomeTab.editor, true),
      ('Flasher', HomeTab.flash, true),
      ('Réglages', HomeTab.settings, true),
      ('Votre premier programme', HomeTab.micropython, true),
    ];
    for (var i = 0; i < total; i++) {
      final (title, homeTab, lit) = expected[i];
      expect(step(), i);
      expect(find.text('Étape ${i + 1} sur $total'), findsOneWidget, reason: title);
      expect(find.descendant(of: find.byType(TourOverlay), matching: find.text(title)), findsOneWidget, reason: title);
      expect(tab(), homeTab, reason: title);
      expect(hole(), lit ? findsOneWidget : findsNothing, reason: title);
      expect(tester.takeException(), isNull, reason: title);
      if (i < total - 1) await next(tester);
    }
    expect(find.text('Passer'), findsNothing, reason: 'la dernière étape se termine');
    await next(tester, 'Terminer');
    expect(find.byType(TourOverlay), findsNothing);
    expect(step(), isNull);
    expect(done(), isTrue);
    expect(tab(), HomeTab.micropython);
  });

  testWidgets('l\'élément éclairé est bien celui de l\'étape (onglet de la barre de navigation)', (tester) async {
    await launch(tester, const AppSettings(loaded: true));
    await next(tester); // étape 2
    await next(tester); // étape 3 : l'onglet Moniteur
    final lit = tester.getRect(hole());
    final nav = tester.getRect(find.descendant(of: find.byType(NavigationBar), matching: find.text('Moniteur')));
    expect(lit.contains(nav.center), isTrue);
    expect(lit.bottom, lessThanOrEqualTo(tester.view.physicalSize.height / 3 + 1));
  });

  testWidgets('toucher l\'élément éclairé d\'un onglet passe à l\'étape suivante', (tester) async {
    await launch(tester, const AppSettings(loaded: true));
    await next(tester);
    await next(tester); // étape 3 : Moniteur
    expect(step(), 2);
    await tester.tapAt(tester.getCenter(hole()));
    await tester.pumpAndSettle();
    expect(step(), 3);
    expect(tab(), HomeTab.micropython);
  });

  testWidgets('élément à essayer : le toucher ne fait pas avancer la visite', (tester) async {
    await launch(tester, const AppSettings(loaded: true));
    await next(tester); // étape 2 : la liste des cartes
    expect(step(), 1);
    await tester.tapAt(tester.getCenter(hole()));
    await tester.pumpAndSettle();
    expect(step(), 1);
  });

  testWidgets('le reste de l\'app est inerte : un onglet de la barre ne change pas d\'onglet pendant la visite', (tester) async {
    await launch(tester, const AppSettings(loaded: true));
    await next(tester); // étape 2, onglet MicroPython
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Flasher')), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tab(), HomeTab.micropython);
    expect(step(), 1);
  });

  testWidgets('précédent revient en arrière ; passer ferme et n\'affiche plus la visite', (tester) async {
    await launch(tester, const AppSettings(loaded: true));
    await next(tester);
    await next(tester);
    await tester.tap(find.text('Précédent'));
    await tester.pumpAndSettle();
    expect(find.text('Étape 2 sur $total'), findsOneWidget);
    expect(tab(), HomeTab.micropython);

    await tester.tap(find.text('Passer'));
    await tester.pumpAndSettle();
    expect(find.byType(TourOverlay), findsNothing);
    expect(done(), isTrue);
  });

  testWidgets('touche « retour » : recule d\'une étape, puis ferme la visite depuis la première', (tester) async {
    await launch(tester, const AppSettings(loaded: true));
    await next(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(step(), 0);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(step(), isNull);
    expect(done(), isTrue);
  });

  testWidgets('revoir la visite depuis Réglages → Aide', (tester) async {
    await launch(tester, const AppSettings(loaded: true, onboardingDone: true));
    container.read(homeTabProvider.notifier).show(HomeTab.settings);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Revoir la visite guidée'), 200, scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
    await tester.tap(find.text('Revoir la visite guidée'));
    await tester.pumpAndSettle();
    expect(find.text('Étape 1 sur $total'), findsOneWidget);
    expect(tab(), HomeTab.monitor);
  });

  testWidgets('accessibilité : cibles de 48 dp, libellés, contraste ; position et titre annoncés', (tester) async {
    final handle = tester.ensureSemantics();
    await launch(tester, const AppSettings(loaded: true));
    for (var i = 0; i < 3; i++) {
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline), reason: 'étape ${i + 1}');
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline), reason: 'étape ${i + 1}');
      await expectLater(tester, meetsGuideline(textContrastGuideline), reason: 'étape ${i + 1}');
      final progress = tester.getSemantics(find.text('Étape ${i + 1} sur $total'));
      expect(progress.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      await next(tester);
    }
    handle.dispose();
  });

  testWidgets('pendant la visite, le lecteur d\'écran ne lit que la carte, pas l\'app derrière', (tester) async {
    final handle = tester.ensureSemantics();
    await launch(tester, const AppSettings(loaded: true));
    // Les libellés réellement présents dans l'arbre d'accessibilité (ce que TalkBack parcourt).
    List<String> announced() {
      final labels = <String>[];
      void visit(SemanticsNode node) {
        if (node.label.isNotEmpty) labels.add(node.label);
        node.visitChildren((child) {
          visit(child);
          return true;
        });
      }

      visit(tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
      return labels;
    }

    expect(announced().any((l) => l.contains('Étape 1 sur $total')), isTrue);
    expect(announced().any((l) => l.startsWith('Moniteur')), isFalse, reason: 'l\'app derrière la visite ne doit pas être lue');
    await tester.tap(find.text('Passer'));
    await tester.pumpAndSettle();
    expect(announced().any((l) => l.startsWith('Moniteur')), isTrue, reason: 'une fois la visite fermée, l\'app est de nouveau lue');
    handle.dispose();
  });

  testWidgets('téléphone de 360 dp, texte à 200 % : aucune étape ne déborde et chacune se termine', (tester) async {
    await launch(tester, const AppSettings(loaded: true), scale: 2.0);
    for (var i = 0; i < total; i++) {
      expect(tester.takeException(), isNull, reason: 'étape ${i + 1}');
      expect(find.text('Étape ${i + 1} sur $total'), findsOneWidget);
      if (i < total - 1) await next(tester);
    }
    await next(tester, 'Terminer');
    expect(find.byType(TourOverlay), findsNothing);
  });
}
