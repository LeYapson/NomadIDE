import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_mcu/app/theme.dart';
import 'package:nomad_mcu/l10n/l10n.dart';
import 'package:nomad_mcu/ui/ui.dart';

Widget _host(Widget child, {Brightness brightness = Brightness.dark}) => MaterialApp(
      theme: buildTheme(brightness),
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('HardwareButton', () {
    testWidgets('Solar Amber, texte sombre, au moins 48 dp de haut', (tester) async {
      await tester.pumpWidget(_host(HardwareButton(onPressed: () {}, icon: Icons.bolt, label: 'Flasher')));

      final button = tester.widget<FilledButton>(find.bySubtype<FilledButton>());
      expect(button.style!.backgroundColor!.resolve({}), solarAmber);
      expect(button.style!.foregroundColor!.resolve({}), obsidianDark);
      expect(tester.getSize(find.bySubtype<FilledButton>()).height, greaterThanOrEqualTo(48));
    });

    testWidgets('désactivé sans action', (tester) async {
      await tester.pumpWidget(_host(const HardwareButton(onPressed: null, icon: Icons.bolt, label: 'Flasher')));
      expect(tester.widget<FilledButton>(find.bySubtype<FilledButton>()).onPressed, isNull);
    });
  });

  group('StatusBanner', () {
    testWidgets('chaque état a une icône en plus de sa couleur, et est annoncé au lecteur d\'écran', (tester) async {
      final handle = tester.ensureSemantics();
      for (final (kind, icon) in [
        (StatusKind.success, Icons.check_circle),
        (StatusKind.error, Icons.error_outline),
        (StatusKind.info, Icons.info_outline),
      ]) {
        await tester.pumpWidget(_host(StatusBanner(message: 'Message ${kind.name}', kind: kind)));
        expect(find.byIcon(icon), findsOneWidget, reason: kind.name);
        expect(find.text('Message ${kind.name}'), findsOneWidget);
        final semantics = tester.getSemantics(find.byType(StatusBanner));
        expect(semantics.getSemanticsData().flagsCollection.isLiveRegion, isTrue, reason: kind.name);
      }
      handle.dispose();
    });
  });

  group('StepCard', () {
    Widget card({required bool done, bool collapsible = true}) => _host(StepCard(
          number: 2,
          total: 3,
          title: 'Carte',
          done: done,
          collapsible: collapsible,
          summary: const Text('Badger 2040'),
          children: const [Text('contenu de l’étape')],
        ));

    testWidgets('étape à faire : ouverte, sans résumé', (tester) async {
      await tester.pumpWidget(card(done: false));
      expect(find.text('contenu de l’étape'), findsOneWidget);
      expect(find.text('Badger 2040'), findsNothing);
      expect(find.byIcon(Icons.expand_less), findsNothing);
    });

    testWidgets('étape terminée : repliée sur son résumé, rouverte par un toucher', (tester) async {
      await tester.pumpWidget(card(done: true));
      expect(find.text('contenu de l’étape'), findsNothing);
      expect(find.text('Badger 2040'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);

      await tester.tap(find.text('Carte'));
      await tester.pumpAndSettle();
      expect(find.text('contenu de l’étape'), findsOneWidget);
      expect(find.text('Badger 2040'), findsNothing);
    });

    testWidgets('quand l\'étape passe de terminée à à faire, elle se rouvre malgré un repli manuel', (tester) async {
      await tester.pumpWidget(card(done: true));
      await tester.pumpWidget(card(done: false));
      await tester.pumpAndSettle();
      expect(find.text('contenu de l’étape'), findsOneWidget);
    });

    testWidgets('étape non repliable : toujours ouverte, même terminée', (tester) async {
      await tester.pumpWidget(card(done: true, collapsible: false));
      expect(find.text('contenu de l’étape'), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsNothing);
    });

    testWidgets('l\'en-tête mesure au moins 48 dp', (tester) async {
      await tester.pumpWidget(card(done: true));
      expect(tester.getSize(find.byType(InkWell)).height, greaterThanOrEqualTo(48));
    });
  });

  group('Disclosure', () {
    testWidgets('repliée par défaut, ouverte par un toucher, avec un résumé quand elle est fermée', (tester) async {
      await tester.pumpWidget(_host(const Disclosure(title: 'Options avancées', summary: 'Adresse 0x1000', children: [Text('détail')])));
      expect(find.text('détail'), findsNothing);
      expect(find.text('Adresse 0x1000'), findsOneWidget);
      expect(tester.getSize(find.byType(InkWell)).height, greaterThanOrEqualTo(48));

      await tester.tap(find.text('Options avancées'));
      await tester.pumpAndSettle();
      expect(find.text('détail'), findsOneWidget);
      expect(find.text('Adresse 0x1000'), findsNothing);
    });

    testWidgets('son état déplié est annoncé au lecteur d\'écran', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(const Disclosure(title: 'Options avancées', children: [Text('détail')])));
      expect(
        tester.getSemantics(find.bySemanticsLabel('Options avancées')),
        matchesSemantics(label: 'Options avancées', isButton: true, hasTapAction: true, hasExpandedState: true, isExpanded: false),
      );
      handle.dispose();
    });
  });

  group('ProgressStatus', () {
    testWidgets('le texte porte l\'information, la barre est ignorée du lecteur d\'écran', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(const ProgressStatus(label: 'Écriture… 40 %', value: 0.4)));
      expect(find.bySemanticsLabel('Écriture… 40 %'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      handle.dispose();
    });
  });
}
