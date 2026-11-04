import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:nomad_mcu/app/settings.dart';
import 'package:nomad_mcu/features/compile/application/compile_controller.dart';
import 'package:nomad_mcu/features/compile/data/compile_api.dart';
import 'package:nomad_mcu/features/compile/data/project_config.dart';
import 'package:nomad_mcu/features/editor/application/editor_controller.dart';
import 'package:nomad_mcu/features/flash/application/esp_flash_controller.dart';
import 'package:nomad_mcu/features/projects/data/project_store.dart';

import '../support/compile_fakes.dart';
import '../support/locale.dart';

/// Réglages déjà renseignés, sans lire le disque.
class _ConfiguredSettings extends SettingsController {
  @override
  AppSettings build() => const AppSettings(compileServerUrl: 'https://compile.example.com', compileToken: 'secret-token', loaded: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory storage;
  late ProjectStore store;

  setUp(() {
    storage = Directory.systemTemp.createTempSync('nomad_compile_test');
    store = ProjectStore(storage);
  });
  tearDown(() => storage.deleteSync(recursive: true));

  Future<ProviderContainer> containerWith(FakeCompileApi? api, {bool configured = true}) async {
    final container = ProviderContainer(overrides: [
      frenchLocale,
      storageRootProvider.overrideWith((ref) => storage),
      serialTransportProvider.overrideWithValue(FakeSerialTransport()),
      compilePollIntervalProvider.overrideWithValue(Duration.zero),
      if (configured) settingsProvider.overrideWith(_ConfiguredSettings.new),
      compileApiProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  Future<void> makeProject(String name, Map<String, String> files) async {
    await store.createProject(name);
    for (final entry in files.entries) {
      await store.writeText(name, entry.key, entry.value);
    }
  }

  Future<void> until(ProviderContainer container, bool Function(CompileState) done) async {
    final clock = Stopwatch()..start();
    while (!done(container.read(compileProvider))) {
      if (clock.elapsed > const Duration(seconds: 5)) fail('état jamais atteint : ${container.read(compileProvider).phase}');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  group('prepare', () {
    test('sans service configuré', () async {
      await makeProject('blink', {'blink.ino': 'void setup(){}'});
      final container = await containerWith(null, configured: false);

      expect(await container.read(compileProvider.notifier).prepare('blink'), isNull);
      expect(container.read(compileProvider).problem, CompileProblem.notConfigured);
    });

    test('projet sans .ino ou avec plusieurs .ino', () async {
      await makeProject('vide', {'main.cpp': 'int main(){}'});
      await makeProject('deux', {'a.ino': '1', 'b.ino': '2'});
      final container = await containerWith(FakeCompileApi());
      final controller = container.read(compileProvider.notifier);

      expect(await controller.prepare('vide'), isNull);
      expect(container.read(compileProvider).problem, CompileProblem.noSketch);

      expect(await controller.prepare('deux'), isNull);
      expect(container.read(compileProvider).problem, CompileProblem.severalSketches);
      expect(container.read(compileProvider).detail, 'a.ino, b.ino');
    });

    test('projet trop gros pour le service', () async {
      await makeProject('gros', {'gros.ino': List.generate(5000, (i) => 'int v$i = $i;').join('\n')});
      final api = FakeCompileApi()..maxUploadBytes = 100;
      final container = await containerWith(api);

      expect(await container.read(compileProvider.notifier).prepare('gros'), isNull);
      expect(container.read(compileProvider).problem, CompileProblem.tooLarge);
      expect(container.read(compileProvider).detail, '100');
    });

    test('service injoignable', () async {
      await makeProject('blink', {'blink.ino': 'x'});
      final api = FakeCompileApi()..healthError = const CompileApiException(CompileErrorKind.unreachable);
      final container = await containerWith(api);

      expect(await container.read(compileProvider.notifier).prepare('blink'), isNull);
      expect(container.read(compileProvider).problem, CompileProblem.unreachable);
    });

    test('le paquet liste les fichiers, sans les dossiers cachés ni build', () async {
      await makeProject('blink', {
        'blink.ino': 'void setup(){}',
        'util.h': '#pragma once',
        'src/a.cpp': 'int a;',
        '.git/config': 'secret',
        'build/out.bin': 'x',
        'nomad.json': '{"board":"esp32"}',
      });
      final container = await containerWith(FakeCompileApi());

      final package = await container.read(compileProvider.notifier).prepare('blink');

      expect(package!.files, ['blink.ino', 'nomad.json', 'src/a.cpp', 'util.h']);
      expect(package.mainSketch, 'blink');
      final names = ZipDecoder().decodeBytes(package.zip).files.map((f) => f.name).toSet();
      expect(names, {'blink.ino', 'nomad.json', 'src/a.cpp', 'util.h'});
    });
  });

  group('start', () {
    test('file d\'attente, compilation, succès ; la carte est mémorisée dans nomad.json', () async {
      await makeProject('blink', {'blink.ino': 'void setup(){}'});
      final api = FakeCompileApi(script: [
        buildStatus(BuildState.queued, board: 'esp32s3', queuePosition: 0),
        buildStatus(BuildState.running, board: 'esp32s3'),
        buildStatus(BuildState.succeeded, board: 'esp32s3', durationMs: 22000, artifacts: const [
          BuildArtifact(name: 'blink.ino.merged.bin', role: ArtifactRole.merged, size: 4, sha256: 'x'),
        ]),
      ]);
      final container = await containerWith(api);
      final controller = container.read(compileProvider.notifier);

      final package = (await controller.prepare('blink'))!;
      await controller.start(package, CompileBoard.esp32s3);
      expect(container.read(compileProvider).phase, CompilePhase.queued);

      await until(container, (s) => s.phase == CompilePhase.succeeded);
      final state = container.read(compileProvider);
      expect(state.flashable!.name, 'blink.ino.merged.bin');
      expect(api.submitted.single.board, CompileBoard.esp32s3);
      expect(api.submitted.single.sketch, 'blink');
      expect((await ProjectConfig.read(store, 'blink')).board, CompileBoard.esp32s3);
    });

    test('erreurs du code : diagnostics, et ouverture du fichier dans l\'éditeur', () async {
      await makeProject('blink', {'blink.ino': 'void setup(){ foo(); }'});
      final api = FakeCompileApi(script: [
        buildStatus(BuildState.failed, log: 'blink.ino:1:15: error: foo', diagnostics: const [
          Diagnostic(file: 'blink.ino', line: 1, column: 15, severity: DiagnosticSeverity.error, message: "'foo' was not declared"),
          Diagnostic(file: 'blink.ino', line: 1, severity: DiagnosticSeverity.warning, message: 'unused'),
        ]),
      ]);
      final container = await containerWith(api);
      final controller = container.read(compileProvider.notifier);

      await controller.start((await controller.prepare('blink'))!, CompileBoard.esp32);
      await until(container, (s) => s.phase == CompilePhase.failed);
      final state = container.read(compileProvider);
      expect(state.errors.single.message, "'foo' was not declared");
      expect(state.warnings, hasLength(1));
      expect(state.problem, isNull, reason: "l'échec vient du code, pas du service");

      await controller.openDiagnostic(state.errors.single);
      final docs = container.read(editorProvider).documents;
      expect(docs.single.localPath, 'blink.ino');
      expect(docs.single.localProject, 'blink');
    });

    test('jeton refusé ou projet refusé à l\'envoi', () async {
      await makeProject('blink', {'blink.ino': 'x'});
      final api = FakeCompileApi(script: [buildStatus(BuildState.queued)])
        ..submitError = const CompileApiException(CompileErrorKind.unauthorized);
      final container = await containerWith(api);
      final controller = container.read(compileProvider.notifier);
      final package = (await controller.prepare('blink'))!;

      await controller.start(package, CompileBoard.esp32);
      expect(container.read(compileProvider).problem, CompileProblem.unauthorized);

      api.submitError = const CompileApiException(CompileErrorKind.rejected, detail: 'Nom de croquis invalide');
      await controller.start(package, CompileBoard.esp32);
      expect(container.read(compileProvider).problem, CompileProblem.rejected);
      expect(container.read(compileProvider).detail, 'Nom de croquis invalide');
    });

    test('build expiré pendant le suivi', () async {
      await makeProject('blink', {'blink.ino': 'x'});
      final api = FakeCompileApi(script: [buildStatus(BuildState.running)])
        ..statusError = const CompileApiException(CompileErrorKind.notFound);
      final container = await containerWith(api);
      final controller = container.read(compileProvider.notifier);

      await controller.start((await controller.prepare('blink'))!, CompileBoard.esp32);
      await until(container, (s) => s.phase == CompilePhase.failed);
      expect(container.read(compileProvider).problem, CompileProblem.expired);
    });

    test('coupures réseau : quelques essais, puis abandon', () async {
      await makeProject('blink', {'blink.ino': 'x'});
      final api = FakeCompileApi(script: [buildStatus(BuildState.running)])
        ..statusError = const CompileApiException(CompileErrorKind.unreachable);
      final container = await containerWith(api);
      final controller = container.read(compileProvider.notifier);

      await controller.start((await controller.prepare('blink'))!, CompileBoard.esp32);
      await until(container, (s) => s.phase == CompilePhase.failed);
      expect(container.read(compileProvider).problem, CompileProblem.unreachable);
      expect(api.statusCalls, 5);
    });

    test('annuler prévient le service et arrête le suivi', () async {
      await makeProject('blink', {'blink.ino': 'x'});
      final api = FakeCompileApi(script: [buildStatus(BuildState.running)]);
      final container = await containerWith(api);
      final controller = container.read(compileProvider.notifier);

      await controller.start((await controller.prepare('blink'))!, CompileBoard.esp32);
      await controller.cancel();

      expect(api.cancelled, ['b1']);
      expect(container.read(compileProvider).phase, CompilePhase.cancelled);
      final calls = api.statusCalls;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(api.statusCalls, calls, reason: 'plus de demande d\'état après l\'annulation');
    });
  });

  group('sendToFlash', () {
    final image = Uint8List.fromList(List.generate(64, (i) => i));

    Future<ProviderContainer> succeeded(FakeCompileApi api) async {
      await makeProject('blink', {'blink.ino': 'x'});
      final container = await containerWith(api);
      final controller = container.read(compileProvider.notifier);
      await controller.start((await controller.prepare('blink'))!, CompileBoard.esp32s3);
      await until(container, (s) => s.phase == CompilePhase.succeeded);
      return container;
    }

    BuildStatus done(String sha) => buildStatus(BuildState.succeeded, board: 'esp32s3', artifacts: [
          BuildArtifact(name: 'blink.ino.merged.bin', role: ArtifactRole.merged, size: image.length, sha256: sha),
          const BuildArtifact(name: 'blink.ino.elf', role: ArtifactRole.debug, size: 9, sha256: 'e'),
        ]);

    test('télécharge, vérifie l\'empreinte et prépare l\'écran Flasher', () async {
      final api = FakeCompileApi(script: [done(sha256.convert(image).toString())], artifact: image);
      final container = await succeeded(api);

      expect(await container.read(compileProvider.notifier).sendToFlash(), isTrue);

      expect(api.downloaded, ['blink.ino.merged.bin']);
      final parts = container.read(espFlashProvider).parts;
      expect(parts.single.name, 'blink.ino.merged.bin');
      expect(parts.single.bytes, image);
      expect(container.read(homeTabProvider), HomeTab.flash);
    });

    test('empreinte différente : refusé, rien n\'est envoyé au flash', () async {
      final api = FakeCompileApi(script: [done('0' * 64)], artifact: image);
      final container = await succeeded(api);

      expect(await container.read(compileProvider.notifier).sendToFlash(), isFalse);

      expect(container.read(compileProvider).problem, CompileProblem.checksum);
      expect(container.read(espFlashProvider).parts, isEmpty);
    });

    test('binaire expiré', () async {
      final api = FakeCompileApi(script: [done('x')], artifact: image)
        ..downloadError = const CompileApiException(CompileErrorKind.notFound);
      final container = await succeeded(api);

      expect(await container.read(compileProvider.notifier).sendToFlash(), isFalse);
      expect(container.read(compileProvider).problem, CompileProblem.expired);
    });
  });

  test('réglages : le service est configuré quand l\'adresse et le jeton sont renseignés', () {
    expect(const AppSettings().compileConfigured, isFalse);
    expect(const AppSettings(compileServerUrl: 'https://x.example').compileConfigured, isFalse);
    final settings = AppSettings.fromJson({'compileServerUrl': 'https://x.example', 'compileToken': 'abc', 'compileApprovedServer': 'https://x.example'});
    expect(settings.compileConfigured, isTrue);
    expect(settings.compileApprovedServer, 'https://x.example');
  });
}
