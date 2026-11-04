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
import 'package:nomad_mcu/features/projects/data/project_store.dart';

import '../support/compile_fakes.dart';
import '../support/locale.dart';

class _Settings extends SettingsController {
  _Settings({required this.configured, this.approved = false});

  final bool configured;

  /// Le serveur a déjà été approuvé : la confirmation d'envoi n'est plus demandée.
  final bool approved;

  @override
  AppSettings build() => AppSettings(
        compileServerUrl: configured ? 'https://compile.example.com' : '',
        compileToken: configured ? 'secret-token' : '',
        compileApprovedServer: approved ? 'https://compile.example.com' : '',
        onboardingDone: true,
        loaded: true,
      );
}

void main() {
  late Directory storage;
  late FakeCompileApi api;
  late ProviderContainer container;

  setUp(() {
    storage = Directory.systemTemp.createTempSync('nomad_sheet_test');
    api = FakeCompileApi(script: [
      buildStatus(BuildState.queued, queuePosition: 1),
      buildStatus(BuildState.succeeded, durationMs: 22400, artifacts: const [
        BuildArtifact(name: 'blink.ino.merged.bin', role: ArtifactRole.merged, size: 4, sha256: 'x'),
      ]),
    ]);
  });

  tearDown(() {
    container.dispose();
    storage.deleteSync(recursive: true);
  });

  void newContainer({required bool configured, bool approved = false}) {
    container = ProviderContainer(overrides: [
      frenchLocale,
      serialTransportProvider.overrideWithValue(FakeSerialTransport()),
      storageRootProvider.overrideWith((ref) => storage),
      settingsProvider.overrideWith(() => _Settings(configured: configured, approved: approved)),
      compileApiProvider.overrideWithValue(configured ? api : null),
      compilePollIntervalProvider.overrideWithValue(const Duration(milliseconds: 20)),
    ]);
  }

  /// Fait avancer le temps réel (accès disque) et l'horloge simulée (délais du suivi) en alternance,
  /// sans `pumpAndSettle` : la barre de progression d'une compilation en cours ne s'arrête jamais.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openEditorWithSketch(WidgetTester tester, {bool sketch = true}) async {
    await tester.runAsync(() async {
      final store = ProjectStore(storage);
      await store.createProject('blink');
      await store.writeText('blink', sketch ? 'blink.ino' : 'main.py', 'void setup(){}');
    });
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const NomadApp()));
    await settle(tester);
    container.read(homeTabProvider.notifier).show(HomeTab.editor);
    await settle(tester);
  }

  testWidgets('le bouton n\'apparaît que pour un projet avec un croquis .ino', (tester) async {
    newContainer(configured: true);
    await openEditorWithSketch(tester, sketch: false);

    expect(find.byTooltip('Compiler dans le cloud'), findsNothing);
  });

  testWidgets('service non configuré : la feuille renvoie vers les réglages', (tester) async {
    newContainer(configured: false);
    await openEditorWithSketch(tester);

    await tester.tap(find.byTooltip('Compiler dans le cloud'));
    await settle(tester);

    expect(find.text('Service non configuré'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Ouvrir les réglages'));
    await settle(tester);
    expect(container.read(homeTabProvider), HomeTab.settings);
  });

  testWidgets('compiler : confirmation la première fois, puis résultat et envoi au Flasher', (tester) async {
    newContainer(configured: true);
    await openEditorWithSketch(tester);

    await tester.tap(find.byTooltip('Compiler dans le cloud'));
    await settle(tester);
    expect(find.text('Compiler le projet'), findsOneWidget);
    expect(find.text('Projet : blink'), findsOneWidget);
    expect(find.text('compile.example.com'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Compiler'));
    await settle(tester);

    // Première fois pour ce serveur : le code ne part qu'après confirmation explicite.
    expect(find.text('Envoyer ce code au serveur ?'), findsOneWidget);
    expect(find.textContaining('compile.example.com pour être compilé'), findsOneWidget);
    expect(api.submitted, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Envoyer et compiler'));
    await settle(tester);

    expect(api.submitted.single.board, CompileBoard.esp32);
    expect(find.text('Compilation réussie en 22 s'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Envoyer vers le Flasher'), findsOneWidget);
    expect(container.read(settingsProvider).compileApprovedServer, 'https://compile.example.com');
  });

  testWidgets('serveur déjà approuvé : pas de nouvelle confirmation ; les erreurs du code sont listées', (tester) async {
    newContainer(configured: true, approved: true);
    api.script = [
      buildStatus(BuildState.failed, diagnostics: const [
        Diagnostic(file: 'blink.ino', line: 3, column: 5, severity: DiagnosticSeverity.error, message: "'pinModee' was not declared"),
      ]),
    ];
    await openEditorWithSketch(tester);

    await tester.tap(find.byTooltip('Compiler dans le cloud'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Compiler'));
    await settle(tester);

    expect(find.text('Envoyer ce code au serveur ?'), findsNothing);
    expect(find.text('La compilation a échoué'), findsOneWidget);
    expect(find.text("'pinModee' was not declared"), findsOneWidget);
    expect(find.text('blink.ino:3:5'), findsOneWidget);

    await tester.tap(find.text("'pinModee' was not declared"));
    await settle(tester);
    expect(find.text('Compiler le projet'), findsNothing, reason: 'la feuille se ferme et le fichier s\'ouvre');
  });
}
