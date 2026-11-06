import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_mcu/app/app.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:nomad_mcu/app/settings.dart';
import 'package:nomad_mcu/features/compile/application/compile_controller.dart';
import 'package:nomad_mcu/features/compile/data/compile_api.dart';
import 'package:nomad_mcu/features/compile/data/project_config.dart';
import 'package:nomad_mcu/features/projects/data/project_store.dart';

import '../support/compile_fakes.dart';
import '../support/locale.dart';

class _Settings extends SettingsController {
  @override
  AppSettings build() => const AppSettings(
        compileServerUrl: 'https://compile.example.com',
        compileToken: 'secret-token',
        compileApprovedServer: 'https://compile.example.com',
        onboardingDone: true,
        loaded: true,
      );
}

void main() {
  late Directory storage;
  late FakeCompileApi api;
  late ProviderContainer container;

  const dhtSummary = LibrarySummary(
    name: 'DHT sensor library',
    latest: '1.4.7',
    author: 'Adafruit',
    sentence: 'Arduino library for DHT11, DHT22',
    versionCount: 3,
  );

  setUp(() {
    storage = Directory.systemTemp.createTempSync('nomad_libsheet_test');
    api = FakeCompileApi(script: [buildStatus(BuildState.succeeded)])
      ..latestVersion.addAll({'DHT sensor library': '1.4.7', 'Adafruit Unified Sensor': '1.1.15'})
      ..dependencies['DHT sensor library'] = [const LibraryRef(name: 'Adafruit Unified Sensor', version: '1.1.15')]
      ..searchResult = const LibrarySearchResult(total: 57, libraries: [dhtSummary])
      ..details['DHT sensor library'] = const LibraryDetail(
        summary: dhtSummary,
        paragraph: 'Temperature and humidity.',
        versions: [
          LibraryVersion(version: '1.4.7', dependencies: ['Adafruit Unified Sensor']),
          LibraryVersion(version: '1.4.6'),
          LibraryVersion(version: '1.3.10'),
        ],
      )
      ..includes['DHT.h'] = const IncludeResolution(header: 'DHT.h', candidates: [dhtSummary], confirmed: ['DHT sensor library']);
    container = ProviderContainer(overrides: [
      frenchLocale,
      serialTransportProvider.overrideWithValue(FakeSerialTransport()),
      storageRootProvider.overrideWith((ref) => storage),
      settingsProvider.overrideWith(_Settings.new),
      compileApiProvider.overrideWithValue(api),
      compilePollIntervalProvider.overrideWithValue(const Duration(milliseconds: 20)),
    ]);
  });

  tearDown(() {
    container.dispose();
    storage.deleteSync(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> settleUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 320 && !done(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openCompileSheet(WidgetTester tester, {String sketch = 'void setup(){}', String? nomadJson}) async {
    await tester.runAsync(() async {
      final store = ProjectStore(storage);
      await store.createProject('blink');
      await store.writeText('blink', 'blink.ino', sketch);
      if (nomadJson != null) await store.writeText('blink', 'nomad.json', nomadJson);
    });
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const NomadApp()));
    await settle(tester);
    container.read(homeTabProvider.notifier).show(HomeTab.editor);
    await settle(tester);
    await tester.tap(find.byTooltip('Compiler dans le cloud'));
    await settle(tester);
  }

  Future<void> openLibraries(WidgetTester tester) async {
    await tester.tap(find.textContaining('Bibliothèques'));
    await settle(tester);
  }

  Future<ProjectConfig> savedConfig(WidgetTester tester) async =>
      (await tester.runAsync(() => ProjectConfig.read(ProjectStore(storage), 'blink')))!;

  testWidgets('la feuille de compilation propose les bibliothèques, vides au départ', (tester) async {
    await openCompileSheet(tester);

    expect(find.text('Bibliothèques'), findsOneWidget);
    await openLibraries(tester);
    expect(find.text('Bibliothèques Arduino'), findsOneWidget);
    expect(find.textContaining('Aucune bibliothèque ajoutée'), findsOneWidget);
  });

  testWidgets('recherche, ajout avec dépendances, enregistrement dans nomad.json, puis retrait', (tester) async {
    await openCompileSheet(tester);
    await openLibraries(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Chercher une bibliothèque'), 'dht');
    await tester.pump(const Duration(milliseconds: 600)); // délai de saisie
    await settleUntil(tester, () => find.textContaining('57 résultats').evaluate().isNotEmpty);

    expect(find.text('1 sur 57 résultats'), findsOneWidget);
    expect(find.text('DHT sensor library 1.4.7'), findsOneWidget);
    expect(find.textContaining('Licence non précisée'), findsOneWidget);
    expect(api.searches, ['dht']);

    await tester.tap(find.widgetWithText(FilledButton, 'Ajouter'));
    await settleUntil(tester, () => find.text('Ajoutée').evaluate().isNotEmpty);

    expect(find.text('Version 1.4.7'), findsOneWidget);
    expect(find.text('Dépendances : Adafruit Unified Sensor 1.1.15'), findsOneWidget);
    final config = await savedConfig(tester);
    expect(config.libraries.map((l) => l.toString()), ['DHT sensor library@1.4.7', 'Adafruit Unified Sensor@1.1.15']);
    expect(config.roots, ['DHT sensor library']);

    await tester.tap(find.byTooltip('Retirer DHT sensor library'));
    await settleUntil(tester, () => find.textContaining('Aucune bibliothèque ajoutée').evaluate().isNotEmpty);
    expect(find.text('Dépendances : Adafruit Unified Sensor 1.1.15'), findsNothing);
    expect((await savedConfig(tester)).libraries, isEmpty);
  });

  testWidgets('ouvrir le détail pour choisir une version, puis la changer', (tester) async {
    await openCompileSheet(tester);
    await openLibraries(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Chercher une bibliothèque'), 'dht');
    await tester.pump(const Duration(milliseconds: 600));
    await settleUntil(tester, () => find.text('DHT sensor library 1.4.7').evaluate().isNotEmpty);

    // Détail : description, licence, versions ; on ajoute une version plus ancienne.
    await tester.tap(find.text('DHT sensor library 1.4.7'));
    await settleUntil(tester, () => find.text('Temperature and humidity.').evaluate().isNotEmpty);
    expect(find.textContaining('Licence non précisée'), findsWidgets);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await settle(tester);
    await tester.tap(find.text('1.3.10').last);
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Ajouter').last);
    await settleUntil(tester, () => find.text('Version 1.3.10').evaluate().isNotEmpty);
    expect((await savedConfig(tester)).libraries.first.version, '1.3.10');

    // Changer de version depuis la liste du projet.
    await tester.tap(find.text('Version 1.3.10'));
    await settleUntil(tester, () => find.text('Temperature and humidity.').evaluate().isNotEmpty);
    expect(find.widgetWithText(FilledButton, 'Changer de version'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await settle(tester);
    await tester.tap(find.text('1.4.6').last);
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Changer de version'));
    await settleUntil(tester, () => find.text('Version 1.4.6').evaluate().isNotEmpty);
    expect((await savedConfig(tester)).libraries.first.version, '1.4.6');
  });

  testWidgets('analyser les #include : suggestion confirmée, ajout, la suggestion disparaît', (tester) async {
    await openCompileSheet(tester, sketch: '#include <DHT.h>\n#include <Wire.h>\nvoid setup(){}\n');
    await openLibraries(tester);

    await tester.tap(find.text('Analyser les #include du projet'));
    await settleUntil(tester, () => find.textContaining('Le projet inclut DHT.h').evaluate().isNotEmpty);

    expect(find.text('Le projet inclut DHT.h, qu’aucune bibliothèque ajoutée ne fournit.'), findsOneWidget);
    expect(find.textContaining('Contient bien cet en-tête'), findsOneWidget);
    expect(api.resolved.single, ['DHT.h', 'Wire.h']);

    await tester.tap(find.widgetWithText(FilledButton, 'Ajouter'));
    await settleUntil(tester, () => find.textContaining('Le projet inclut DHT.h').evaluate().isEmpty);
    expect(find.text('Version 1.4.7'), findsOneWidget);
  });

  testWidgets('tous les #include fournis : message rassurant après l\'analyse', (tester) async {
    await openCompileSheet(tester, sketch: '#include <Wire.h>\nvoid setup(){}\n');
    api.includes['Wire.h'] = const IncludeResolution(header: 'Wire.h', builtin: true);
    await openLibraries(tester);

    await tester.tap(find.text('Analyser les #include du projet'));
    await settleUntil(tester, () => find.textContaining('Tous les #include').evaluate().isNotEmpty);
    expect(find.textContaining('Tous les #include du projet sont fournis'), findsOneWidget);
  });

  testWidgets('catalogue pas chargé : message explicite dans la feuille', (tester) async {
    await openCompileSheet(tester);
    await openLibraries(tester);
    api.libraryError = const CompileApiException(CompileErrorKind.unavailable);

    await tester.enterText(find.widgetWithText(TextField, 'Chercher une bibliothèque'), 'dht');
    await tester.pump(const Duration(milliseconds: 600));
    await settleUntil(tester, () => find.textContaining('pas encore chargé').evaluate().isNotEmpty);

    expect(find.textContaining('catalogue de bibliothèques du service n’est pas encore chargé'), findsOneWidget);
  });

  testWidgets('compilation échouée sur un en-tête introuvable : « Ajouter et compiler »', (tester) async {
    api.script = [
      buildStatus(BuildState.failed, diagnostics: const [
        Diagnostic(file: 'blink.ino', line: 1, severity: DiagnosticSeverity.error, message: 'DHT.h: No such file or directory'),
      ]),
    ];
    await openCompileSheet(tester, sketch: '#include <DHT.h>\nvoid setup(){}\n');

    await tester.tap(find.text('Compiler'));
    await settleUntil(tester, () => find.text('Bibliothèque manquante ?').evaluate().isNotEmpty);
    expect(find.text('DHT.h est introuvable.'), findsOneWidget);
    expect(find.text('DHT sensor library 1.4.7'), findsOneWidget);
    expect(api.submitted, hasLength(1));

    // Le même service renvoie maintenant un succès : la compilation relancée réussit.
    api.script = [buildStatus(BuildState.succeeded, durationMs: 21000)];
    api.statusCalls = 0;
    await tester.tap(find.text('Ajouter et compiler'));
    await settleUntil(tester, () => api.submitted.length == 2);

    final config = await savedConfig(tester);
    expect(config.libraries.map((l) => l.name), ['DHT sensor library', 'Adafruit Unified Sensor']);
    expect(api.submitted, hasLength(2));
  });

  testWidgets('un projet qui a déjà des bibliothèques affiche leur nombre sur le bouton', (tester) async {
    await openCompileSheet(
      tester,
      nomadJson: '{"board": "esp32", "libraries": [{"name": "DHT sensor library", "version": "1.4.7"}], "librariesRoots": ["DHT sensor library"]}',
    );
    await settleUntil(tester, () => find.text('Bibliothèques (1)').evaluate().isNotEmpty);
    expect(find.text('Bibliothèques (1)'), findsOneWidget);
  });
}
