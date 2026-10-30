import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_mcu/app/app.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:nomad_mcu/features/flash/application/esp_flash_controller.dart';
import 'package:nomad_mcu/features/flash/application/flash_controller.dart';
import 'package:nomad_mcu/features/flash/presentation/esp_flash_view.dart';

import 'support/locale.dart';

/// En-tête d'image ESP32 ; [app] ajoute la description d'application (sinon : bootloader).
Uint8List _image({required bool app}) {
  final out = Uint8List(0x2000);
  out[0] = 0xE9;
  out[1] = 3;
  out[23] = 1;
  if (app) out.setAll(32, [0x32, 0x54, 0xCD, 0xAB]);
  return out;
}

/// Table de partitions d'un projet Arduino : une application à 0x10000.
Uint8List _table() {
  final out = Uint8List(0xC00)..fillRange(0, 0xC00, 0xFF);
  out.fillRange(0, 32, 0);
  out
    ..[0] = 0xAA
    ..[1] = 0x50
    ..[2] = 0x00 // application
    ..[3] = 0x10; // ota_0
  ByteData.sublistView(out)
    ..setUint32(4, 0x10000, Endian.little)
    ..setUint32(8, 0x140000, Endian.little);
  return out;
}

void main() {
  late List<PickedFile> picks;

  Widget app() => ProviderScope(
        overrides: [
          frenchLocale,
          serialTransportProvider.overrideWithValue(FakeSerialTransport()),
          uf2DrivePollProvider.overrideWithValue(null),
          binPickerProvider.overrideWithValue(() async => picks.isEmpty ? null : picks.removeAt(0)),
        ],
        child: const NomadApp(),
      );

  Future<void> openEsp(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    while (tester.takeException() != null) {}
    await tester.tap(find.text('Flasher').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ESP (.bin)'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    picks = [
      (name: 'sketch.ino.bootloader.bin', bytes: _image(app: false)),
      (name: 'sketch.ino.partitions.bin', bytes: _table()),
      (name: 'sketch.ino.bin', bytes: _image(app: true)),
    ];
  });

  testWidgets('ajouter des fichiers : chacun montre son adresse, modifiable, et peut être retiré', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await openEsp(tester);

    expect(find.text('Ajouter un fichier'), findsNothing, reason: 'rien à compléter tant qu\'aucun fichier n\'est choisi');
    await tester.tap(find.text('Choisir un fichier .bin'));
    await tester.pumpAndSettle();

    // Un fichier choisi : l'étape se replie ; on la rouvre pour en ajouter.
    await tester.tap(find.text('Fichier du programme'));
    await tester.pumpAndSettle();
    // Ouverte par l'utilisateur, l'étape le reste pendant qu'il ajoute des fichiers.
    await tester.tap(find.text('Ajouter un fichier'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un fichier'));
    await tester.pumpAndSettle();

    // Repliée, l'étape 1 résume la liste avec les adresses.
    await tester.tap(find.text('Fichier du programme'));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 fichiers ·'), findsOneWidget);
    expect(find.text('0x1000 · sketch.ino.bootloader.bin'), findsOneWidget);
    expect(find.text('0x8000 · sketch.ino.partitions.bin'), findsOneWidget);
    expect(find.text('0x10000 · sketch.ino.bin'), findsOneWidget);

    await tester.tap(find.text('Fichier du programme'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Adresse de sketch.ino.bin'), findsOneWidget);
    final removeButtons = find.widgetWithIcon(IconButton, Icons.close);
    expect(removeButtons, findsNWidgets(3));
    for (var i = 0; i < 3; i++) {
      final size = tester.getSize(removeButtons.at(i));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }

    await tester.tap(find.byTooltip('Retirer sketch.ino.partitions.bin'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Retirer sketch.ino.partitions.bin'), findsNothing);
    expect(find.byIcon(Icons.close), findsNWidgets(2));
  });

  testWidgets('trois fichiers sur un écran de 360 dp, texte à 150 % : rien ne déborde', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openEsp(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(EspFlashView)));
    final controller = container.read(espFlashProvider.notifier);
    for (final p in [...picks]) {
      controller.addPickedFile(p);
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fichier du programme'));
    await tester.pumpAndSettle();
    final list = find.descendant(of: find.byType(EspFlashView), matching: find.byType(Scrollable)).first;
    await tester.drag(list, const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
