import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_mcu/app/app.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:nomad_mcu/app/settings.dart';
import 'package:nomad_mcu/features/projects/data/storage_exception.dart';
import 'package:nomad_mcu/l10n/error_messages.dart';
import 'package:nomad_mcu/l10n/l10n.dart';
import 'package:nomad_protocols/nomad_protocols.dart';

import 'support/locale.dart';

Map<String, Object?> readArb(String language) =>
    jsonDecode(File('lib/l10n/app_$language.arb').readAsStringSync()) as Map<String, Object?>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fr = lookupAppLocalizations(const Locale('fr'));
  final en = lookupAppLocalizations(const Locale('en'));

  group('fichiers de traduction', () {
    final french = readArb('fr');
    final english = readArb('en');

    Set<String> keysOf(Map<String, Object?> arb) => arb.keys.where((k) => !k.startsWith('@')).toSet();

    test('l\'anglais couvre exactement les mêmes textes que le français', () {
      expect(keysOf(english), keysOf(french));
    });

    test('aucune traduction vide', () {
      for (final arb in [french, english]) {
        for (final key in keysOf(arb)) {
          expect((arb[key] as String).trim(), isNotEmpty, reason: key);
        }
      }
    });

    test('les mêmes paramètres {…} dans les deux langues', () {
      final placeholder = RegExp(r'\{(\w+)');
      Set<String> names(Object? text) => placeholder.allMatches(text as String).map((m) => m.group(1)!).toSet();
      for (final key in keysOf(french)) {
        expect(names(english[key]), names(french[key]), reason: key);
      }
    });
  });

  group('langue effective', () {
    test('le choix de l\'utilisateur prime sur le système', () {
      expect(resolveAppLocale(const Locale('en'), const Locale('fr', 'FR')), const Locale('en'));
      expect(resolveAppLocale(const Locale('fr'), const Locale('de')), const Locale('fr'));
    });

    test('sans choix : français si le système est français, anglais sinon', () {
      expect(resolveAppLocale(null, const Locale('fr', 'CA')), const Locale('fr'));
      expect(resolveAppLocale(null, const Locale('de', 'DE')), const Locale('en'));
      expect(resolveAppLocale(null, const Locale('en', 'US')), const Locale('en'));
    });

    test('les deux langues sont déclarées', () {
      expect(appLocales.map((l) => l.languageCode), unorderedEquals(['en', 'fr']));
    });
  });

  group('messages d\'erreur', () {
    final serialErrors = <SerialException>[
      const SerialUnsupportedException('x', code: SerialErrorCode.unsupportedPlatform, params: {'platform': 'ios'}),
      const SerialUnsupportedException('x', code: SerialErrorCode.unsupportedPlatform, params: {'platform': 'fuchsia'}),
      const SerialDeviceNotFoundException('x', code: SerialErrorCode.deviceNotFound, params: {'device': 'Badger'}),
      const SerialDeviceNotFoundException('x', code: SerialErrorCode.portNotFound, params: {'path': 'COM5'}),
      const SerialPermissionException('x', code: SerialErrorCode.usbPermissionDenied),
      const SerialPermissionException('x', code: SerialErrorCode.portPermissionDenied, params: {'path': '/dev/ttyACM0', 'os': 'EACCES'}),
      const SerialOpenException('x', code: SerialErrorCode.openFailed, params: {'path': 'COM5', 'os': 'busy'}),
      const SerialOpenException('x', code: SerialErrorCode.openFailed, params: {'device': 'Badger'}),
      const SerialOpenException('x', code: SerialErrorCode.usbPortCreateFailed),
      const SerialOpenException('x', code: SerialErrorCode.usbStreamUnavailable),
      const SerialOpenException('x', code: SerialErrorCode.alreadyOpen, params: {'device': 'Badger'}),
      const SerialClosedException('x', code: SerialErrorCode.connectionClosed),
      const SerialClosedException('x', code: SerialErrorCode.closedDuringRead),
      const SerialIoException('x', code: SerialErrorCode.readFailed),
      const SerialTimeoutException('x', code: SerialErrorCode.noResponse, params: {'timeoutMs': 2500}),
      for (final op in SerialOperation.values)
        SerialIoException('x', code: SerialErrorCode.operationFailed, params: {'operation': op, 'device': 'Badger'}),
      const SerialUnsupportedException('x', code: SerialErrorCode.unsupportedStopBits),
      const SerialTimeoutException('x', code: SerialErrorCode.writeTimeout, params: {'remaining': 42, 'seconds': 5}),
      const SerialIoException('détail technique'),
    ];

    final protocolErrors = <ProtocolException>[
      const ProtocolIoException('x'),
      const ProtocolClosedException('x'),
      const ProtocolTimeoutException('x', code: ProtocolErrorCode.noResponse, params: {'timeoutMs': 2000}),
      const ProtocolTimeoutException('x', code: ProtocolErrorCode.rawReplNotEntered, params: {'attempts': 3}),
      const ProtocolTimeoutException('x', code: ProtocolErrorCode.programTimeout, params: {'timeoutMs': 30000}),
      const ProtocolStateException('x', code: ProtocolErrorCode.busy),
      const ProtocolStateException('x', code: ProtocolErrorCode.notActive),
      const ProtocolStateException('x', code: ProtocolErrorCode.sessionBroken),
      const ProtocolDesyncException('x', code: ProtocolErrorCode.unexpectedAck, params: {'hex': '52 41'}),
      const ProtocolDesyncException('x', code: ProtocolErrorCode.unexpectedCrcReply, params: {'reply': 'oups'}),
      const ProtocolIntegrityException('x',
          expectedCrc: 1, actualCrc: 2, params: {'path': '/a.py', 'expectedSize': 10, 'actualSize': 9}),
      const ProtocolRemoteException('OSError: [Errno 2] ENOENT', stderr: 'Traceback…', errno: 2),
      const ProtocolStateException('message technique'),
      const ProtocolTimeoutException('x', code: ProtocolErrorCode.espSyncFailed, params: {'attempts': 7}),
      ProtocolRomException(0x03, 0x07),
      const ProtocolDesyncException('x', code: ProtocolErrorCode.espBadPacket, params: {'hex': '01 08'}),
      ProtocolFlashVerifyException(expectedMd5: 'aa', actualMd5: 'bb'),
    ];

    final storageErrors = [
      for (final error in StorageError.values) StorageException(error, name: 'a.py', cause: 'disque plein'),
      const StorageException(StorageError.io),
    ];

    test('chaque erreur série a un message dans chaque langue, sans paramètre non remplacé', () {
      for (final error in serialErrors) {
        for (final l10n in [fr, en]) {
          final message = serialErrorMessage(l10n, error);
          expect(message, isNotEmpty, reason: '${error.code}');
          expect(message, isNot(contains('{')), reason: '${error.code}: $message');
        }
      }
    });

    test('chaque erreur de protocole a un message dans chaque langue', () {
      for (final error in protocolErrors) {
        for (final l10n in [fr, en]) {
          final message = protocolErrorMessage(l10n, error);
          expect(message, isNotEmpty, reason: '${error.code}');
          expect(message, isNot(contains('{')), reason: '${error.code}: $message');
        }
      }
    });

    test('chaque erreur de stockage a un message dans chaque langue', () {
      for (final error in storageErrors) {
        for (final l10n in [fr, en]) {
          expect(storageErrorMessage(l10n, error), isNot(contains('{')), reason: '${error.error}');
        }
      }
    });

    test('même erreur, deux langues, deux textes ; les paramètres sont insérés', () {
      const timeout = SerialTimeoutException('x', code: SerialErrorCode.noResponse, params: {'timeoutMs': 2500});

      expect(serialErrorMessage(fr, timeout), 'Aucune réponse de la carte après 2500 ms.');
      expect(serialErrorMessage(en, timeout), 'No response from the board after 2500 ms.');
    });

    test('permission Linux : le nom du groupe à utiliser est donné dans les deux langues', () {
      const error = SerialPermissionException(
        'x',
        code: SerialErrorCode.portPermissionDenied,
        params: {'path': '/dev/ttyACM0', 'os': 'Permission denied'},
      );

      expect(serialErrorMessage(fr, error), allOf(contains('dialout'), contains('/dev/ttyACM0')));
      expect(serialErrorMessage(en, error), allOf(contains('dialout'), contains('/dev/ttyACM0')));
    });

    test('iOS : l\'explication complète, pas le message générique', () {
      const error = SerialUnsupportedException('x', code: SerialErrorCode.unsupportedPlatform, params: {'platform': 'ios'});

      expect(serialErrorMessage(en, error), contains('MFi'));
      expect(serialErrorMessage(fr, error), contains('MFi'));
    });

    test('une erreur de la carte (trace Python) n\'est pas traduite', () {
      const error = ProtocolRemoteException('OSError: [Errno 2] ENOENT', stderr: 'Traceback…', errno: 2);

      expect(protocolErrorMessage(en, error), 'OSError: [Errno 2] ENOENT');
    });

    test('errorMessage choisit le bon traducteur et garde le texte brut des autres erreurs', () {
      expect(errorMessage(en, const ProtocolClosedException('x')), en.errLinkClosed);
      expect(errorMessage(en, const SerialClosedException('x', code: SerialErrorCode.connectionClosed)), en.errConnectionClosed);
      expect(errorMessage(en, const StorageException(StorageError.notFound, name: 'a')), contains('a'));
      expect(errorMessage(en, StateError('boom')), contains('boom'));
    });

    test('noms des transports', () {
      expect(transportLabel(fr, TransportKind.simulated), 'Simulateur');
      expect(transportLabel(en, TransportKind.simulated), 'Simulator');
      for (final kind in TransportKind.values) {
        expect(transportLabel(en, kind), isNotEmpty);
      }
    });
  });

  group('interface', () {
    late Directory storage;

    setUp(() => storage = Directory.systemTemp.createTempSync('nomad_l10n_test'));
    tearDown(() {
      try {
        storage.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows garde un instant le fichier de réglages ouvert : le dossier temporaire sera purgé plus tard.
      }
    });

    ProviderContainer newContainer({String? language}) {
      final container = ProviderContainer(overrides: [
        serialTransportProvider.overrideWithValue(FakeSerialTransport()),
        storageRootProvider.overrideWith((ref) => storage),
        if (language != null) fixedLocale(language),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<void> pumpApp(WidgetTester tester, ProviderContainer container) async {
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const NomadApp()));
      await settle(tester);
    }

    testWidgets('système en anglais : toute l\'interface est en anglais', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await pumpApp(tester, newContainer());

      expect(find.text('NomadMCU · Serial monitor'), findsOneWidget);
      expect(find.text('Serial monitor'), findsOneWidget); // barre de navigation
      expect(find.text('Editor'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Disconnected'), findsOneWidget);
      expect(find.text('Moniteur série'), findsNothing);
    });

    testWidgets('système en français : interface en français', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('fr', 'FR')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await pumpApp(tester, newContainer());

      expect(find.text('NomadMCU · Moniteur série'), findsOneWidget);
      expect(find.text('Réglages'), findsOneWidget);
    });

    testWidgets('système en allemand : repli sur l\'anglais', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await pumpApp(tester, newContainer());

      expect(find.text('NomadMCU · Serial monitor'), findsOneWidget);
    });

    testWidgets('les autres écrans sont aussi en anglais', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = newContainer(language: 'en');
      await pumpApp(tester, container);

      container.read(homeTabProvider.notifier).show(HomeTab.micropython);
      await settle(tester);
      expect(find.text('NomadMCU · MicroPython'), findsOneWidget);
      expect(find.text('Connect (raw REPL)'), findsOneWidget);
      expect(find.text('Run'), findsOneWidget);

      container.read(homeTabProvider.notifier).show(HomeTab.editor);
      await settle(tester);
      expect(find.text('NomadMCU · Editor'), findsOneWidget);
      expect(find.text('No file open.'), findsOneWidget);
      expect(find.text('No projects.'), findsOneWidget);
      expect(find.text('New project'), findsOneWidget);
    });

    testWidgets('changer la langue dans les réglages met à jour l\'écran tout de suite', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final container = newContainer();
      await pumpApp(tester, container);
      container.read(homeTabProvider.notifier).show(HomeTab.settings);
      await settle(tester);
      expect(find.text('NomadMCU · Settings'), findsOneWidget);

      await tester.tap(find.text('Français'));
      await settle(tester);

      expect(find.text('NomadMCU · Réglages'), findsOneWidget);
      expect(container.read(localeProvider), const Locale('fr'));
    });

    testWidgets('le choix de langue est mémorisé et retrouvé au démarrage suivant', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final first = newContainer();
      await tester.runAsync(() => first.read(localeProvider.notifier).setLocale(const Locale('fr')));

      expect(jsonDecode(File('${storage.path}/settings.json').readAsStringSync()), {'locale': 'fr'});

      final second = newContainer();
      second.read(localeProvider);
      await settle(tester);
      expect(second.read(localeProvider), const Locale('fr'));
    });

    testWidgets('revenir à « langue du système » efface le choix mémorisé', (tester) async {
      final container = newContainer();
      await tester.runAsync(() => container.read(localeProvider.notifier).setLocale(const Locale('fr')));

      await tester.runAsync(() => container.read(localeProvider.notifier).setLocale(null));

      expect(container.read(localeProvider), isNull);
      expect(jsonDecode(File('${storage.path}/settings.json').readAsStringSync()), {'locale': null});
      final restarted = newContainer();
      restarted.read(localeProvider);
      await settle(tester);
      expect(restarted.read(localeProvider), isNull);
    });

    testWidgets('un fichier de réglages corrompu est ignoré', (tester) async {
      File('${storage.path}/settings.json').writeAsStringSync('{"locale": ');
      final container = newContainer();
      container.read(localeProvider);
      await settle(tester);

      expect(container.read(localeProvider), isNull);
    });

    testWidgets('une langue inconnue dans les réglages est ignorée', (tester) async {
      File('${storage.path}/settings.json').writeAsStringSync('{"locale": "klingon"}');
      final container = newContainer();
      container.read(localeProvider);
      await settle(tester);

      expect(container.read(localeProvider), isNull);
    });
  });
}
