import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_editor/nomad_editor.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_mcu/app/app.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:nomad_mcu/app/settings.dart';
import 'package:nomad_mcu/features/editor/application/editor_controller.dart';
import 'package:nomad_mcu/features/serial_monitor/application/serial_monitor_controller.dart';
import 'package:nomad_mcu/features/serial_monitor/application/serial_monitor_state.dart';
import 'package:nomad_mcu/features/settings/application/diagnostics.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'support/locale.dart';

/// Réglages imposés, sans lire ni écrire de fichier.
class FixedSettings extends SettingsController {
  FixedSettings(this.initial);

  final AppSettings initial;

  @override
  AppSettings build() => initial;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSettings.fromJson', () {
    test('fichier vide : valeurs par défaut', () {
      final s = AppSettings.fromJson({});
      expect(s.themeMode, ThemeMode.system);
      expect(s.editorFontSize, 14);
      expect(s.monitorBaud, 115200);
      expect(s.monitorLineEnding, LineEnding.cr);
      expect(s.monitorTimestamps, isTrue);
    });

    test('valeurs invalides ignorées, une par une', () {
      final s = AppSettings.fromJson({
        'theme': 'fluo',
        'editorFontSize': 200,
        'editorWordWrap': 'oui',
        'monitorBaud': -5,
        'monitorLineEnding': 'crlf',
        'monitorTimestamps': false,
      });
      expect(s.themeMode, ThemeMode.system);
      expect(s.editorFontSize, 14);
      expect(s.editorWordWrap, isFalse);
      expect(s.monitorBaud, 115200);
      expect(s.monitorLineEnding, LineEnding.crlf);
      expect(s.monitorTimestamps, isFalse);
    });
  });

  group('fichier settings.json', () {
    late Directory storage;
    late ProviderContainer container;

    setUp(() {
      storage = Directory.systemTemp.createTempSync('nomad_settings_test');
      container = ProviderContainer(overrides: [storageRootProvider.overrideWith((ref) => storage)]);
      container.listen(settingsProvider, (_, __) {});
    });

    tearDown(() {
      container.dispose();
      storage.deleteSync(recursive: true);
    });

    Map<String, Object?> file() => jsonDecode(File('${storage.path}/settings.json').readAsStringSync()) as Map<String, Object?>;

    test('chaque réglage n\'écrit que sa clé : la langue n\'est jamais effacée', () async {
      await container.read(localeProvider.notifier).setLocale(const Locale('en'));
      final settings = container.read(settingsProvider.notifier);
      await Future.wait([
        settings.setThemeMode(ThemeMode.dark),
        settings.setEditorFontSize(18.4),
        settings.setMonitorBaud(9600),
      ]);

      expect(file(), {'locale': 'en', 'theme': 'dark', 'editorFontSize': 18.0, 'monitorBaud': 9600});
    });

    test('les réglages sont relus au démarrage suivant', () async {
      File('${storage.path}/settings.json').writeAsStringSync('{"theme":"light","editorWordWrap":true,"monitorLineEnding":"lf"}');
      final next = ProviderContainer(overrides: [storageRootProvider.overrideWith((ref) => storage)]);
      addTearDown(next.dispose);
      next.listen(settingsProvider, (_, __) {});
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final s = next.read(settingsProvider);
      expect(s.themeMode, ThemeMode.light);
      expect(s.editorWordWrap, isTrue);
      expect(s.monitorLineEnding, LineEnding.lf);
    });

    test('taille du code bornée entre 10 et 28', () async {
      final settings = container.read(settingsProvider.notifier);
      await settings.setEditorFontSize(4);
      expect(container.read(settingsProvider).editorFontSize, 10);
      await settings.setEditorFontSize(99);
      expect(container.read(settingsProvider).editorFontSize, 28);
    });
  });

  group('effets dans l\'app', () {
    test('valeurs par défaut du moniteur appliquées quand elles changent, sans toucher aux autres', () async {
      final storage = Directory.systemTemp.createTempSync('nomad_settings_monitor');
      addTearDown(() => storage.deleteSync(recursive: true));
      final container = ProviderContainer(overrides: [
        frenchLocale,
        storageRootProvider.overrideWith((ref) => storage),
        serialTransportProvider.overrideWithValue(FakeSerialTransport()),
      ]);
      addTearDown(container.dispose);
      container.listen(serialMonitorProvider, (_, __) {});
      final monitor = container.read(serialMonitorProvider.notifier);
      final settings = container.read(settingsProvider.notifier);

      await settings.setMonitorBaud(9600);
      await settings.setMonitorLineEnding(LineEnding.crlf);
      await settings.setMonitorTimestamps(false);
      var state = container.read(serialMonitorProvider);
      expect(state.config.baudRate, 9600);
      expect(state.lineEnding, LineEnding.crlf);
      expect(state.showTimestamps, isFalse);

      // Un choix fait dans la session survit au changement d'un autre réglage.
      monitor.setLineEnding(LineEnding.lf);
      await settings.setThemeMode(ThemeMode.dark);
      state = container.read(serialMonitorProvider);
      expect(state.lineEnding, LineEnding.lf);
    });

    testWidgets('thème sombre forcé et taille du code appliqués', (tester) async {
      final storage = Directory.systemTemp.createTempSync('nomad_settings_ui');
      addTearDown(() => storage.deleteSync(recursive: true));
      final container = ProviderContainer(overrides: [
        frenchLocale,
        storageRootProvider.overrideWith((ref) => storage),
        serialTransportProvider.overrideWithValue(FakeSerialTransport()),
        settingsProvider.overrideWith(
          () => FixedSettings(const AppSettings(themeMode: ThemeMode.dark, editorFontSize: 20, editorWordWrap: true)),
        ),
      ]);
      addTearDown(container.dispose);
      container.read(editorProvider.notifier).newDocument(text: 'x = 1');

      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const NomadApp()));
      await tester.pumpAndSettle();
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);

      container.read(homeTabProvider.notifier).show(HomeTab.editor);
      await tester.pumpAndSettle();
      final editor = tester.widget<NomadCodeEditor>(find.byType(NomadCodeEditor));
      expect(editor.fontSize, 20);
      expect(editor.wordWrap, isTrue);
      await tester.runAsync(() => container.read(editorProvider.notifier).flushDrafts());
    });
  });

  group('diagnostic', () {
    test('le rapport donne versions, réglages, cartes et état, sans le flux série', () async {
      PackageInfo.setMockInitialValues(
        appName: 'NomadIDE',
        packageName: 'dev.nomadmcu.nomad_mcu',
        version: '0.1.0',
        buildNumber: '7',
        buildSignature: '',
      );
      final storage = Directory.systemTemp.createTempSync('nomad_diag_test');
      addTearDown(() => storage.deleteSync(recursive: true));
      final container = ProviderContainer(overrides: [
        frenchLocale,
        storageRootProvider.overrideWith((ref) => storage),
        serialTransportProvider.overrideWithValue(FakeSerialTransport()),
      ]);
      addTearDown(container.dispose);
      container.listen(serialMonitorProvider, (_, __) {});
      final monitor = container.read(serialMonitorProvider.notifier);
      await monitor.refreshDevices();
      await monitor.connect();
      await monitor.send('secret_utilisateur');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final report = await buildDiagnosticReport(container.read, now: DateTime(2026, 10, 30, 9, 5, 7));
      expect(report, contains('Version : 0.1.0 (7)'));
      expect(report, contains('Système : ${Platform.operatingSystem}'));
      expect(report, contains('Moniteur : 115200 bauds'));
      expect(report, contains('Carte simulée'));
      expect(report, contains('État : connected'));
      expect(report, isNot(contains('secret_utilisateur')), reason: 'le flux série ne doit pas y figurer');

      final file = await saveDiagnosticReport(container.read, report, now: DateTime(2026, 10, 30, 9, 5, 7));
      expect(file.path, endsWith('nomadide-diagnostic-20261030-090507.txt'));
      expect(file.readAsStringSync(), report);
    });

    test('taille d\'un dossier : 0 s\'il n\'existe pas, somme des fichiers sinon', () async {
      final dir = Directory.systemTemp.createTempSync('nomad_size_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      expect(await directorySize(Directory('${dir.path}/absent')), 0);
      File('${dir.path}/a').writeAsBytesSync(List.filled(100, 1));
      Directory('${dir.path}/sous').createSync();
      File('${dir.path}/sous/b').writeAsBytesSync(List.filled(50, 1));
      expect(await directorySize(dir), 150);
    });
  });
}
