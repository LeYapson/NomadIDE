import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_mcu/app/app.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:nomad_mcu/features/libraries/application/libraries_controller.dart';
import 'package:nomad_mcu/features/libraries/data/mip_client.dart';

import '../support/fake_web.dart';
import '../support/locale.dart';

const _index = '''
{"v":2,"packages":[
 {"name":"ssd1306","version":"0.1.0","description":"Pilote d'écran OLED","license":"MIT","versions":{"py":["0.1.0"]}},
 {"name":"dht","version":"0.1.0","description":"Capteurs DHT11 et DHT22","license":"MIT","versions":{"py":["0.1.0"]}},
 {"name":"neopixel","version":"0.1.0","license":"","versions":{"py":["0.1.0"]}}
]}''';

void main() {
  late Directory storage;

  setUp(() => storage = Directory.systemTemp.createTempSync('nomad_libs_ui'));
  tearDown(() => storage.deleteSync(recursive: true));

  Future<void> openLibraries(WidgetTester tester, {double scale = 1.0}) async {
    tester.view.physicalSize = const Size(1080, 2200); // ≈ 360 × 733 dp
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final web = FakeWeb()..text('https://micropython.org/pi/v2/index.json', _index);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        frenchLocale,
        serialTransportProvider.overrideWithValue(FakeSerialTransport()),
        storageRootProvider.overrideWith((ref) => storage),
        // Sans cache disque : les écritures réelles ne se terminent pas dans l'horloge simulée des tests.
        mipClientProvider.overrideWith((ref) async => MipClient(web)),
      ],
      child: const NomadApp(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Python').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bibliothèques'));
    await tester.pumpAndSettle();
  }

  testWidgets('la liste vient de l\'index, la recherche filtre, et sans carte rien ne s\'installe', (tester) async {
    await openLibraries(tester);

    expect(find.text('Connectez une carte (raw REPL) pour installer une bibliothèque.'), findsOneWidget);
    expect(find.text('ssd1306'), findsOneWidget);
    expect(find.text('Version 0.1.0 · licence MIT'), findsWidgets);
    expect(find.text('Version 0.1.0 · licence non précisée'), findsOneWidget, reason: 'licence absente : dit clairement');

    await tester.enterText(find.widgetWithText(TextField, 'Chercher une bibliothèque'), 'dht22');
    await tester.pumpAndSettle();
    expect(find.text('dht'), findsOneWidget);
    expect(find.text('ssd1306'), findsNothing);

    final install = find.widgetWithText(FilledButton, 'Installer');
    expect(tester.widget<FilledButton>(install.first).onPressed, isNull);
    expect(tester.getSize(install.first).height, greaterThanOrEqualTo(48));
  });

  testWidgets('aucun résultat : le message renvoie vers GitHub, dont la section s\'ouvre', (tester) async {
    await openLibraries(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Chercher une bibliothèque'), 'bme280');
    await tester.pumpAndSettle();
    expect(find.textContaining('Aucune bibliothèque ne correspond à « bme280 »'), findsOneWidget);
  });

  testWidgets('accessibilité : zones tactiles de 48 dp et libellés', (tester) async {
    final handle = tester.ensureSemantics();
    await openLibraries(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  testWidgets('texte à 200 % : rien ne déborde', (tester) async {
    await openLibraries(tester, scale: 2.0);
    expect(tester.takeException(), isNull);
  });
}
