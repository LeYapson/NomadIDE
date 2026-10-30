import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_mcu/app/app.dart';
import 'package:nomad_mcu/app/links.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:nomad_mcu/app/settings.dart';
import 'package:nomad_mcu/features/flash/application/firmware_controller.dart';
import 'package:nomad_mcu/features/settings/application/update_checker.dart';

import 'support/fake_web.dart';
import 'support/locale.dart';

class FixedSettings extends SettingsController {
  FixedSettings(this.initial);

  final AppSettings initial;

  @override
  AppSettings build() => initial;
}

const _releases = '''
[
 {"tag_name":"v0.3.0-rc.1","html_url":"https://github.com/LeYapson/NomadIDE/releases/tag/v0.3.0-rc.1","draft":true,"prerelease":true},
 {"tag_name":"v0.2.0","html_url":"https://github.com/LeYapson/NomadIDE/releases/tag/v0.2.0","draft":false,"prerelease":true},
 {"tag_name":"v0.1.0","html_url":"https://github.com/LeYapson/NomadIDE/releases/tag/v0.1.0","draft":false,"prerelease":true}
]''';

void main() {
  group('compareVersions', () {
    test('ordre des versions sémantiques', () {
      expect(compareVersions('0.1.0', '0.2.0'), lessThan(0));
      expect(compareVersions('0.10.0', '0.9.9'), greaterThan(0));
      expect(compareVersions('v1.0', '1.0.0'), 0);
      expect(compareVersions('0.2.0-beta.1', '0.2.0'), lessThan(0), reason: 'une pré-version précède la version finale');
      expect(compareVersions('0.2.0-beta.2', '0.2.0-beta.1'), greaterThan(0));
      expect(compareVersions('0.2.0+5', '0.2.0'), 0, reason: 'le numéro de compilation ne compte pas');
    });
  });

  group('vérification', () {
    late FakeWeb web;
    late ProviderContainer container;

    ProviderContainer make({String installed = '0.1.0', bool checkUpdates = true}) => ProviderContainer(overrides: [
          firmwareSourceProvider.overrideWithValue(web),
          installedVersionProvider.overrideWith((ref) async => installed),
          settingsProvider.overrideWith(() => FixedSettings(AppSettings(loaded: true, checkUpdates: checkUpdates))),
        ]);

    setUp(() {
      debugSkipUpdateCheck = false;
      web = FakeWeb()..text(UpdateChecker.releasesUrl.toString(), _releases);
    });

    tearDown(() {
      debugSkipUpdateCheck = true;
      container.dispose();
    });

    test('une version plus récente est trouvée (les brouillons sont ignorés)', () async {
      container = make();
      await container.read(updateProvider.notifier).check();
      final state = container.read(updateProvider);
      expect(state.status, UpdateStatus.available);
      expect(state.release!.version, '0.2.0');
      expect(state.release!.url.toString(), endsWith('/v0.2.0'));
    });

    test('déjà à jour', () async {
      container = make(installed: '0.2.0');
      await container.read(updateProvider.notifier).check();
      expect(container.read(updateProvider).status, UpdateStatus.upToDate);
      expect(container.read(updateProvider).installed, '0.2.0');
    });

    test('hors ligne : échec silencieux', () async {
      web.offline = true;
      container = make();
      await container.read(updateProvider.notifier).check();
      expect(container.read(updateProvider).status, UpdateStatus.failed);
    });

    test('réglage désactivé : aucune requête au démarrage', () async {
      container = make(checkUpdates: false);
      await container.read(updateProvider.notifier).checkAtStartup();
      expect(web.requested, isEmpty);
      expect(container.read(updateProvider).status, UpdateStatus.unknown);
    });

    test('au démarrage, une seule vérification par session', () async {
      container = make();
      await container.read(updateProvider.notifier).checkAtStartup();
      await container.read(updateProvider.notifier).checkAtStartup();
      expect(web.requested, hasLength(1));
    });
  });

  testWidgets('au démarrage, une nouvelle version est signalée une fois, avec un lien vers sa page', (tester) async {
    debugSkipUpdateCheck = false;
    addTearDown(() => debugSkipUpdateCheck = true);
    final storage = Directory.systemTemp.createTempSync('nomad_update_ui');
    addTearDown(() => storage.deleteSync(recursive: true));
    final opened = <Uri>[];
    final web = FakeWeb()..text(UpdateChecker.releasesUrl.toString(), _releases);
    final container = ProviderContainer(overrides: [
      frenchLocale,
      storageRootProvider.overrideWith((ref) => storage),
      serialTransportProvider.overrideWithValue(FakeSerialTransport()),
      firmwareSourceProvider.overrideWithValue(web),
      installedVersionProvider.overrideWith((ref) async => '0.1.0'),
      settingsProvider.overrideWith(() => FixedSettings(const AppSettings(loaded: true, onboardingDone: true))),
      linkOpenerProvider.overrideWithValue((url) async {
        opened.add(url);
        return true;
      }),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const NomadApp()));
    await tester.pumpAndSettle();

    expect(find.text('NomadIDE 0.2.0 est disponible.'), findsOneWidget);
    await tester.tap(find.text('Voir'));
    await tester.pumpAndSettle();
    expect(opened.single.toString(), endsWith('/v0.2.0'));

    // Réglages → À propos : l'état est repris, et la page s'ouvre d'un toucher.
    container.read(homeTabProvider.notifier).show(HomeTab.settings);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('NomadIDE 0.2.0 est disponible :'), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.textContaining('NomadIDE 0.2.0 est disponible :'));
    await tester.pumpAndSettle();
    expect(opened, hasLength(2));
    expect(web.requested, hasLength(1), reason: 'une seule vérification au démarrage');
  });
}
