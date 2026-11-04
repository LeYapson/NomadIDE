import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_mcu/app/app.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:nomad_mcu/app/settings.dart';
import 'package:nomad_mcu/features/compile/data/project_config.dart';
import 'package:nomad_mcu/features/compile/data/sketch_project.dart';
import 'package:nomad_mcu/features/editor/application/editor_controller.dart';
import 'package:nomad_mcu/features/projects/application/projects_controller.dart';
import 'package:nomad_mcu/features/projects/data/project_store.dart';

import '../support/locale.dart';

class _Settings extends SettingsController {
  @override
  AppSettings build() => const AppSettings(onboardingDone: true, loaded: true);
}

void main() {
  test('sketchNameFor : caractères acceptés par Arduino', () {
    expect(sketchNameFor('Mon projet'), 'Mon_projet');
    expect(sketchNameFor('  été  2026!! '), '_t_2026'.replaceFirst('_t_', 't_'));
    expect(sketchNameFor('***'), 'sketch');
    expect(sketchNameFor('a' * 100), hasLength(64));
  });

  test('defaultNewFileName suit le langage du dossier', () {
    expect(defaultNewFileName(const []), 'main.py');
    expect(defaultNewFileName(const ['boot.py', 'main.py']), 'main.py');
    expect(defaultNewFileName(const ['blink.ino']), 'helpers.h');
    expect(defaultNewFileName(const ['a.CPP', 'nomad.json']), 'helpers.h');
    expect(defaultNewFileName(const ['blink.ino', 'tools.py']), 'main.py');
  });

  test('blinkSketch commence par le commentaire donné', () {
    expect(blinkSketch('Blink'), startsWith('// Blink\nvoid setup()'));
  });

  group('Nouveau projet', () {
    late Directory storage;
    late ProviderContainer container;

    setUp(() {
      storage = Directory.systemTemp.createTempSync('nomad_newproject_test');
      container = ProviderContainer(overrides: [
        frenchLocale,
        serialTransportProvider.overrideWithValue(FakeSerialTransport()),
        storageRootProvider.overrideWith((ref) => storage),
        settingsProvider.overrideWith(_Settings.new),
      ]);
    });
    tearDown(() {
      container.dispose();
      storage.deleteSync(recursive: true);
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 80; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> openEditor(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const NomadApp()));
      await settle(tester);
      container.read(homeTabProvider.notifier).show(HomeTab.editor);
      await settle(tester);
    }

    testWidgets('type Arduino : croquis Blink, carte par défaut, fichier ouvert et bouton Compiler', (tester) async {
      await openEditor(tester);
      expect(find.byTooltip('Compiler dans le cloud'), findsNothing);

      await tester.tap(find.text('Nouveau projet'));
      await settle(tester);
      expect(find.text('Type de projet'), findsOneWidget);
      await tester.tap(find.text('Arduino C/C++'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Créer'));
      await settle(tester);

      expect(container.read(projectsProvider).current, 'Mon projet');
      final store = ProjectStore(storage);
      final dir = Directory('${storage.path}/projects/Mon projet');
      expect(dir.listSync().map((e) => e.path.split(Platform.pathSeparator).last).toSet(), {'Mon_projet.ino', 'nomad.json'});
      final sketch = File('${dir.path}/Mon_projet.ino').readAsStringSync();
      expect(sketch, startsWith('// Blink : fait clignoter la LED de la carte.'));
      final config = await tester.runAsync(() => ProjectConfig.read(store, 'Mon projet'));
      expect(config!.board, CompileBoard.esp32);
      expect(container.read(editorProvider).active!.name, 'Mon_projet.ino');
      expect(find.byTooltip('Compiler dans le cloud'), findsOneWidget);
    });

    testWidgets('type MicroPython (par défaut) : projet vide, comme avant', (tester) async {
      await openEditor(tester);

      await tester.tap(find.text('Nouveau projet'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Créer'));
      await settle(tester);

      expect(container.read(projectsProvider).current, 'Mon projet');
      expect(Directory('${storage.path}/projects/Mon projet').listSync(), isEmpty);
      expect(find.byTooltip('Compiler dans le cloud'), findsNothing);
    });
  });
}
