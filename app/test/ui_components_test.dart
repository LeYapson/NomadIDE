import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_hal/nomad_hal.dart' show SerialDeviceInfo;
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

  group('annonces au lecteur d’écran', () {
    test('le pourcentage annoncé avance par paliers de 25 %', () {
      expect(announcedPercent(null), 0);
      expect(announcedPercent(0), 0);
      expect(announcedPercent(0.24), 0);
      expect(announcedPercent(0.25), 25);
      expect(announcedPercent(0.49), 25);
      expect(announcedPercent(0.5), 50);
      expect(announcedPercent(0.99), 75);
      expect(announcedPercent(1), 100);
      expect(announcedPercent(7), 100);
    });

    testWidgets('la progression est une région vivante qui lit le palier, pas chaque pourcent', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(const ProgressStatus(label: 'Écriture… 43 %', spokenLabel: 'Écriture… 25 %', value: 0.43)));

      expect(find.text('Écriture… 43 %'), findsOneWidget); // le texte visible reste exact
      expect(find.bySemanticsLabel('Écriture… 25 %'), findsOneWidget);
      expect(find.bySemanticsLabel('Écriture… 43 %'), findsNothing);
      final data = tester.getSemantics(find.bySemanticsLabel('Écriture… 25 %')).getSemanticsData();
      expect(data.flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });
  });

  group('SectionHeader', () {
    testWidgets('déclaré comme titre au lecteur d\'écran, en couleur de marque', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(const SectionHeader('Apparence')));
      expect(tester.getSemantics(find.text('Apparence')).getSemanticsData().flagsCollection.isHeader, isTrue);
      final style = tester.widget<Text>(find.text('Apparence')).style!;
      expect(style.color, Theme.of(tester.element(find.text('Apparence'))).colorScheme.primary);
      handle.dispose();
    });

    testWidgets('marge réglable : celle d\'une liste pleine largeur par défaut', (tester) async {
      await tester.pumpWidget(_host(const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [SectionHeader('A'), SectionHeader('B', padding: EdgeInsets.zero)])));
      expect(tester.getTopLeft(find.text('A')).dx, 16);
      expect(tester.getTopLeft(find.text('B')).dx, 0);
    });
  });

  group('BoardDropdown', () {
    const badger = SerialDeviceInfo(id: 'COM5', displayName: 'Badger 2040', systemPath: 'COM5', vendorId: 0x2E8A, productId: 0x0005);
    const esp = SerialDeviceInfo(id: 'COM7', displayName: 'ESP32', systemPath: 'COM7');

    Widget dropdown({List<SerialDeviceInfo> devices = const [badger, esp], SerialDeviceInfo? selected, bool enabled = true, ValueChanged<SerialDeviceInfo>? onSelected}) =>
        _host(BoardDropdown(devices: devices, selected: selected, enabled: enabled, onSelected: onSelected ?? (_) {}));

    testWidgets('sans carte : le dit ; avec des cartes mais aucune choisie : invite à choisir', (tester) async {
      await tester.pumpWidget(dropdown(devices: const []));
      expect(find.text('Aucune carte détectée'), findsOneWidget);
      await tester.pumpWidget(dropdown());
      expect(find.text('Choisir une carte'), findsOneWidget);
      expect(find.text('Carte'), findsOneWidget);
    });

    testWidgets('choisir une carte dans la liste appelle onSelected', (tester) async {
      SerialDeviceInfo? chosen;
      await tester.pumpWidget(dropdown(onSelected: (d) => chosen = d));
      await tester.tap(find.byType(DropdownButton<SerialDeviceInfo>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('ESP32').last);
      await tester.pumpAndSettle();
      expect(chosen, esp);
    });

    testWidgets('carte choisie affichée ; une carte absente de la liste est ignorée plutôt que de planter', (tester) async {
      await tester.pumpWidget(dropdown(selected: badger));
      expect(find.textContaining('Badger 2040'), findsOneWidget);
      await tester.pumpWidget(dropdown(selected: const SerialDeviceInfo(id: 'COM9', displayName: 'Inconnue')));
      expect(tester.takeException(), isNull);
      expect(find.text('Choisir une carte'), findsOneWidget);
    });

    testWidgets('champ fermé : le nom seul ; liste ouverte : le détail sous le nom', (tester) async {
      final details = badger.details;
      expect(details, isNotEmpty);
      await tester.pumpWidget(dropdown(selected: badger));
      expect(find.textContaining('Badger 2040'), findsOneWidget);
      expect(find.text(details), findsNothing);

      await tester.tap(find.byType(DropdownButton<SerialDeviceInfo>));
      await tester.pumpAndSettle();
      expect(find.text(details), findsOneWidget);
      expect(tester.getTopLeft(find.text(details).last).dy, greaterThan(tester.getTopLeft(find.text('Badger 2040').last).dy));
    });

    testWidgets('liste figée (carte connectée) : elle ne s\'ouvre pas', (tester) async {
      await tester.pumpWidget(dropdown(selected: badger, enabled: false));
      await tester.tap(find.byType(DropdownButton<SerialDeviceInfo>), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.textContaining('ESP32'), findsNothing);
    });

    testWidgets('largeur : écran moins les marges, plafonnée à 380 dp', (tester) async {
      Future<double> widthAt(double screen) async {
        tester.view.physicalSize = Size(screen, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(dropdown());
        return tester.getSize(find.byType(BoardDropdown)).width;
      }

      expect(await widthAt(360), 328);
      expect(await widthAt(1200), 380);
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
