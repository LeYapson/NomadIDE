import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_mcu/app/app.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:nomad_mcu/features/compile/application/local_toolchain_controller.dart';
import 'package:nomad_mcu/features/compile/local/local_toolchain.dart';
import 'package:path/path.dart' as p;

import 'support/locale.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('nomad_settings_toolchain_');
    final toolchain = LocalToolchain(root, os: 'windows', arch: 'x64');
    toolchain.cli
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('x');
    for (final core in toolchainCores) {
      final parts = core.split(':');
      Directory(p.join(toolchain.packagesDir.path, parts[0], 'hardware', parts[1], '1.0.0')).createSync(recursive: true);
    }
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  testWidgets('réglages : les outils de compilation locale installés peuvent être désinstallés, après confirmation', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        frenchLocale,
        serialTransportProvider.overrideWithValue(FakeSerialTransport()),
        localToolchainProvider.overrideWith((ref) => LocalToolchain(root, os: 'windows', arch: 'x64')),
      ],
      child: const NomadApp(),
    ));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(NomadApp)));
    container.read(homeTabProvider.notifier).show(HomeTab.settings);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Outils de compilation locale'), 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Installés : arduino-cli'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Désinstaller'));
    await tester.pumpAndSettle();
    expect(find.text('Désinstaller les outils de compilation locale ?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Désinstaller'));
    for (var i = 0; i < 20 && root.existsSync(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(root.existsSync(), isFalse);
    expect(find.textContaining('Non installés'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Désinstaller'), findsNothing);
  }, skip: !(Platform.isWindows || Platform.isMacOS || Platform.isLinux));
}
