import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_mcu/app/app.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:nomad_mcu/features/flash/application/firmware_controller.dart';
import 'package:nomad_mcu/features/flash/application/flash_controller.dart';
import 'package:nomad_mcu/features/flash/data/firmware_catalog.dart';

import 'support/locale.dart';

/// Image complète d'ESP32 : en-tête étendu et table de partitions à 0x7000.
Uint8List _fullEsp32Image() {
  final out = Uint8List(0x8100);
  out[0] = 0xE9;
  out[1] = 3;
  out[23] = 1;
  out[0x7000] = 0xAA;
  out[0x7001] = 0x50;
  return out;
}

class _Source implements FirmwareSource {
  final List<Uri> requested = [];

  @override
  Future<String> fetchText(Uri url) async {
    requested.add(url);
    return '<a href="/resources/firmware/ESP32_GENERIC-20260824-v1.29.0.bin">x</a>';
  }

  @override
  Future<Uint8List> fetchBytes(Uri url, {void Function(int done, int? total)? onProgress}) async {
    requested.add(url);
    return _fullEsp32Image();
  }
}

void main() {
  testWidgets('télécharger le firmware ESP32 : le fichier est choisi et l\'adresse passe à 0x1000', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = _Source();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        frenchLocale,
        serialTransportProvider.overrideWithValue(FakeSerialTransport()),
        uf2DrivePollProvider.overrideWithValue(null),
        firmwareSourceProvider.overrideWithValue(source),
      ],
      child: const NomadApp(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flasher').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ESP (.bin)'));
    await tester.pumpAndSettle();

    // Le firmware officiel est une section repliée de l'étape 1 : on l'ouvre.
    expect(find.text('Firmware MicroPython officiel'), findsOneWidget);
    expect(find.text('Chercher la dernière version'), findsNothing);
    await tester.tap(find.text('Firmware MicroPython officiel'));
    await tester.pumpAndSettle();
    expect(find.text('Télécharger et utiliser'), findsNothing);

    await tester.tap(find.text('Chercher la dernière version'));
    await tester.pumpAndSettle();
    expect(find.text('MicroPython v1.29.0 pour ESP32'), findsOneWidget);
    expect(find.textContaining('micropython.org/resources/firmware/ESP32_GENERIC-20260824-v1.29.0.bin'), findsOneWidget);
    // On voit l'adresse avant de télécharger, et rien n'a encore été téléchargé.
    expect(source.requested.where((u) => u.path.endsWith('.bin')), isEmpty);

    await tester.tap(find.text('Télécharger et utiliser'));
    await tester.pumpAndSettle();

    // L'étape 1 est terminée : elle se replie sur le fichier choisi, avec l'adresse déduite de son en-tête.
    expect(find.text('ESP32_GENERIC-20260824-v1.29.0.bin'), findsOneWidget);
    expect(find.textContaining('Image complète pour ESP32'), findsOneWidget);
    expect(find.text('Chercher la dernière version'), findsNothing);
    // L'adresse est dans les options avancées.
    await tester.tap(find.text('Options avancées'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '0x1000'), findsOneWidget);
  });
}
