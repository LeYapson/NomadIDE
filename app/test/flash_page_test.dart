import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_mcu/app/app.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:nomad_mcu/features/flash/application/flash_controller.dart';
import 'package:nomad_mcu/features/flash/presentation/flash_page.dart';

import 'support/locale.dart';

Uint8List _uf2() {
  final out = Uint8List(512);
  final d = ByteData.sublistView(out);
  d.setUint32(0, 0x0A324655, Endian.little);
  d.setUint32(4, 0x9E5D5157, Endian.little);
  d.setUint32(8, 0x2000, Endian.little);
  d.setUint32(12, 0x10000000, Endian.little);
  d.setUint32(16, 256, Endian.little);
  d.setUint32(24, 1, Endian.little);
  d.setUint32(28, 0xE48BFF56, Endian.little);
  d.setUint32(508, 0x0AB16F30, Endian.little);
  return out;
}

Widget _app({required bool supported}) => ProviderScope(
      overrides: [
        frenchLocale,
        serialTransportProvider.overrideWithValue(FakeSerialTransport()),
        uf2SupportedProvider.overrideWithValue(supported),
        uf2DrivePollProvider.overrideWithValue(null),
        uf2PickerProvider.overrideWithValue(() async => (name: 'blink.uf2', bytes: _uf2())),
      ],
      child: const NomadApp(),
    );

final _flashButton = find.descendant(of: find.byType(FlashPage), matching: find.bySubtype<FilledButton>());

void main() {
  testWidgets("l'onglet Flasher guide les trois étapes et active le bouton après le choix du fichier", (tester) async {
    await tester.pumpWidget(_app(supported: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Flasher').last);
    await tester.pumpAndSettle();

    expect(find.text('NomadMCU · Flasher un programme'), findsOneWidget);
    expect(find.text('1. Fichier du programme'), findsOneWidget);
    expect(find.text('Aucun fichier choisi'), findsOneWidget);
    FilledButton flashButton() => tester.widget<FilledButton>(_flashButton);
    expect(flashButton().onPressed, isNull);

    await tester.tap(find.text('Choisir un fichier .uf2'));
    await tester.pumpAndSettle();

    expect(find.text('blink.uf2'), findsOneWidget);
    expect(find.textContaining('RP2040'), findsOneWidget);
    expect(flashButton().onPressed, isNotNull);
  });

  testWidgets("sur un système sans copie UF2 (Android), la page l'explique et bloque le bouton", (tester) async {
    await tester.pumpWidget(_app(supported: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Flasher').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choisir un fichier .uf2'));
    await tester.pumpAndSettle();

    expect(find.textContaining('PICOBOOT'), findsOneWidget);
    final button = tester.widget<FilledButton>(_flashButton);
    expect(button.onPressed, isNull);
  });
}
