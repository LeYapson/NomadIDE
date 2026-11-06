import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:nomad_mcu/app/settings.dart';
import 'package:nomad_mcu/features/compile/application/arduino_libraries_controller.dart';
import 'package:nomad_mcu/features/compile/application/compile_controller.dart';
import 'package:nomad_mcu/features/compile/data/compile_api.dart';
import 'package:nomad_mcu/features/compile/data/project_config.dart';
import 'package:nomad_mcu/features/projects/data/project_store.dart';

import '../support/compile_fakes.dart';
import '../support/locale.dart';

class _ConfiguredSettings extends SettingsController {
  @override
  AppSettings build() => const AppSettings(compileServerUrl: 'https://compile.example.com', compileToken: 'secret-token', loaded: true);
}

void main() {
  late Directory storage;
  late ProjectStore store;
  late FakeCompileApi api;

  const dht = LibraryRef(name: 'DHT sensor library', version: '1.4.7');
  const unified = LibraryRef(name: 'Adafruit Unified Sensor', version: '1.1.15');

  setUp(() {
    storage = Directory.systemTemp.createTempSync('nomad_libctl_test');
    store = ProjectStore(storage);
    api = FakeCompileApi()
      ..latestVersion.addAll({'DHT sensor library': '1.4.7', 'Adafruit Unified Sensor': '1.1.15', 'Servo': '1.2.1'})
      ..dependencies['DHT sensor library'] = [unified];
  });
  tearDown(() => storage.deleteSync(recursive: true));

  Future<ProviderContainer> container({bool configured = true, FakeCompileApi? override}) async {
    await store.createProject('p');
    final c = ProviderContainer(overrides: [
      frenchLocale,
      storageRootProvider.overrideWith((ref) => storage),
      serialTransportProvider.overrideWithValue(FakeSerialTransport()),
      if (configured) settingsProvider.overrideWith(_ConfiguredSettings.new),
      compileApiProvider.overrideWithValue(configured ? (override ?? api) : null),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Future<ArduinoLibrariesController> loaded(ProviderContainer c, {CompileBoard board = CompileBoard.esp32}) async {
    final controller = c.read(arduinoLibrariesProvider.notifier);
    await controller.load('p', board);
    return controller;
  }

  test('load : lit les bibliothèques du nomad.json', () async {
    final c = await container();
    await ProjectConfig.writeLibraries(store, 'p', [dht, unified], ['DHT sensor library']);

    await loaded(c);

    final state = c.read(arduinoLibrariesProvider);
    expect(state.libraries, [dht, unified]);
    expect(state.chosen, [dht]);
    expect(state.dependencies, [unified]);
  });

  group('recherche', () {
    test('moins de deux caractères : pas d\'appel au service', () async {
      final c = await container();
      final controller = await loaded(c);
      await controller.search('d');
      expect(api.searches, isEmpty);
      expect(c.read(arduinoLibrariesProvider).results, isNull);
    });

    test('résultats gardés', () async {
      api.searchResult = const LibrarySearchResult(total: 57, libraries: [LibrarySummary(name: 'DHT sensor library', latest: '1.4.7')]);
      final c = await container();
      final controller = await loaded(c);

      await controller.search('  dht ');

      expect(api.searches, ['dht']);
      final state = c.read(arduinoLibrariesProvider);
      expect(state.results!.total, 57);
      expect(state.searching, isFalse);
      expect(state.query, 'dht');
    });

    test('service qui ne répond pas ou catalogue pas chargé : problème explicite', () async {
      final c = await container();
      final controller = await loaded(c);

      api.libraryError = const CompileApiException(CompileErrorKind.unavailable);
      await controller.search('dht');
      expect(c.read(arduinoLibrariesProvider).problem, CompileProblem.librariesUnavailable);

      api.libraryError = const CompileApiException(CompileErrorKind.unreachable);
      await controller.search('dht');
      expect(c.read(arduinoLibrariesProvider).problem, CompileProblem.unreachable);
    });

    test('service non configuré', () async {
      final c = await container(configured: false);
      final controller = await loaded(c);
      await controller.search('dht');
      expect(c.read(arduinoLibrariesProvider).problem, CompileProblem.notConfigured);
    });
  });

  group('ajout et retrait', () {
    test('ajouter : le service résout les dépendances, le projet enregistre la liste complète', () async {
      final c = await container();
      final controller = await loaded(c);

      expect(await controller.add('DHT sensor library'), isTrue);

      final state = c.read(arduinoLibrariesProvider);
      expect(state.libraries, [dht, unified]);
      expect(state.roots, ['DHT sensor library']);
      final config = await ProjectConfig.read(store, 'p');
      expect(config.libraries, [dht, unified]);
      expect(config.roots, ['DHT sensor library']);
      expect(api.closures.single.single.version, '', reason: 'sans version : la dernière');
    });

    test('ajouter à une version précise', () async {
      final c = await container();
      final controller = await loaded(c);
      await controller.add('DHT sensor library', version: '1.3.10');
      expect(c.read(arduinoLibrariesProvider).libraries.first.version, '1.3.10');
    });

    test('les bibliothèques déjà ajoutées gardent leur version quand on en ajoute une autre', () async {
      final c = await container();
      final controller = await loaded(c);
      await controller.add('DHT sensor library', version: '1.3.10');

      await controller.add('Servo');

      final request = api.closures.last;
      expect(request.firstWhere((l) => l.name == 'DHT sensor library').version, '1.3.10');
      final state = c.read(arduinoLibrariesProvider);
      expect(state.chosen.map((l) => '${l.name}@${l.version}'), ['DHT sensor library@1.3.10', 'Servo@1.2.1']);
    });

    test('ajouter deux fois la même bibliothèque ne refait rien', () async {
      final c = await container();
      final controller = await loaded(c);
      await controller.add('Servo');
      await controller.add('Servo');
      expect(api.closures, hasLength(1));
    });

    test('retirer : les dépendances devenues inutiles partent aussi, les autres restent', () async {
      final c = await container();
      final controller = await loaded(c);
      await controller.add('DHT sensor library');
      await controller.add('Servo');

      await controller.remove('DHT sensor library');

      final state = c.read(arduinoLibrariesProvider);
      expect(state.libraries.map((l) => l.name), ['Servo']);
      expect((await ProjectConfig.read(store, 'p')).libraries.map((l) => l.name), ['Servo']);

      await controller.remove('Servo');
      expect(c.read(arduinoLibrariesProvider).libraries, isEmpty);
      expect((await ProjectConfig.read(store, 'p')).libraries, isEmpty);
    });

    test('changer de version : dépendances recalculées', () async {
      final c = await container();
      final controller = await loaded(c);
      await controller.add('DHT sensor library');

      expect(await controller.setVersion('DHT sensor library', '1.3.10'), isTrue);

      expect(c.read(arduinoLibrariesProvider).chosen.single.version, '1.3.10');
      expect(c.read(arduinoLibrariesProvider).dependencies.single.name, 'Adafruit Unified Sensor');
    });

    test('le service refuse : la liste du projet ne bouge pas', () async {
      final c = await container();
      final controller = await loaded(c);
      await controller.add('Servo');
      api.libraryError = const CompileApiException(CompileErrorKind.rejected, detail: 'Bibliothèque inconnue : Nope.');

      expect(await controller.add('Nope'), isFalse);

      final state = c.read(arduinoLibrariesProvider);
      expect(state.problem, CompileProblem.rejected);
      expect(state.detail, contains('Nope'));
      expect(state.libraries.map((l) => l.name), ['Servo']);
      expect(state.working, isFalse);
      expect((await ProjectConfig.read(store, 'p')).libraries.map((l) => l.name), ['Servo']);
    });
  });

  group('suggestions d\'après les #include', () {
    setUp(() {
      api.includes['DHT.h'] = const IncludeResolution(
        header: 'DHT.h',
        candidates: [LibrarySummary(name: 'DHT sensor library', latest: '1.4.7'), LibrarySummary(name: 'DHTStable', latest: '1.1.4')],
        confirmed: ['DHT sensor library'],
      );
      api.includes['Wire.h'] = const IncludeResolution(header: 'Wire.h', builtin: true);
    });

    test('scan : ni les en-têtes du cœur ni ceux du projet ne sont proposés', () async {
      final c = await container();
      await store.writeText('p', 'p.ino', '#include <DHT.h>\n#include <Wire.h>\n#include "mien.h"\n#include <Inconnu.h>\n');
      await store.writeText('p', 'mien.h', '// mien\n');
      final controller = await loaded(c);

      await controller.scan();

      final suggestions = c.read(arduinoLibrariesProvider).suggestions;
      expect(suggestions.map((s) => s.header), ['DHT.h', 'Inconnu.h']);
      expect(api.resolved.single, ['DHT.h', 'Inconnu.h', 'Wire.h']);
      expect(suggestions.first.confirmed, ['DHT sensor library']);
      expect(suggestions.last.candidates, isEmpty);
      expect(c.read(arduinoLibrariesProvider).scanning, isFalse);
    });

    test('ajouter la bibliothèque confirmée fait disparaître la suggestion', () async {
      final c = await container();
      await store.writeText('p', 'p.ino', '#include <DHT.h>\n');
      final controller = await loaded(c);
      await controller.scan();
      expect(c.read(arduinoLibrariesProvider).suggestions, hasLength(1));

      await controller.add('DHT sensor library');

      expect(c.read(arduinoLibrariesProvider).suggestions, isEmpty);
    });

    test('une bibliothèque déjà dans le projet mais qui ne contient pas l\'en-tête ne le satisfait pas', () async {
      final c = await container();
      await store.writeText('p', 'p.ino', '#include <DHT.h>\n');
      final controller = await loaded(c);
      await controller.add('DHTStable');
      await controller.scan();
      expect(c.read(arduinoLibrariesProvider).suggestions.map((s) => s.header), ['DHT.h']);
    });

    test('scan sans aucun include externe : aucun appel au service', () async {
      final c = await container();
      await store.writeText('p', 'p.ino', 'void setup(){}\n');
      final controller = await loaded(c);
      await controller.scan();
      expect(api.resolved, isEmpty);
      expect(c.read(arduinoLibrariesProvider).suggestions, isEmpty);
    });

    test('après une compilation échouée : suggestions pour les en-têtes introuvables', () async {
      final c = await container();
      final controller = await loaded(c);

      await controller.suggestForMessages(['DHT.h: No such file or directory', '\'foo\' was not declared']);

      expect(c.read(arduinoLibrariesProvider).suggestions.single.header, 'DHT.h');
      expect(api.resolved.single, ['DHT.h']);
    });

    test('suggestions : un service muet ne fait pas échouer l\'affichage de l\'erreur de compilation', () async {
      final c = await container();
      final controller = await loaded(c);
      api.libraryError = const CompileApiException(CompileErrorKind.unreachable);

      await controller.suggestForMessages(['DHT.h: No such file or directory']);

      expect(c.read(arduinoLibrariesProvider).suggestions, isEmpty);
      expect(c.read(arduinoLibrariesProvider).problem, isNull);
    });

    test('scan : le service muet est signalé', () async {
      final c = await container();
      await store.writeText('p', 'p.ino', '#include <DHT.h>\n');
      final controller = await loaded(c);
      api.libraryError = const CompileApiException(CompileErrorKind.unavailable);
      await controller.scan();
      expect(c.read(arduinoLibrariesProvider).problem, CompileProblem.librariesUnavailable);
      expect(c.read(arduinoLibrariesProvider).scanning, isFalse);
    });
  });

  test('détail d\'une bibliothèque', () async {
    api.details['Servo'] = const LibraryDetail(
      summary: LibrarySummary(name: 'Servo', latest: '1.2.1'),
      versions: [LibraryVersion(version: '1.2.1'), LibraryVersion(version: '1.2.0')],
    );
    final c = await container();
    final controller = await loaded(c);
    expect((await controller.detailOf('Servo'))!.versions, hasLength(2));
    expect(await controller.detailOf('Nope'), isNull);
    expect(c.read(arduinoLibrariesProvider).problem, CompileProblem.expired);
  });
}
