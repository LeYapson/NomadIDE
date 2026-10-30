import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:nomad_mcu/features/flash/application/firmware_controller.dart';
import 'package:nomad_mcu/features/libraries/application/libraries_controller.dart';
import 'package:nomad_mcu/features/micropython/application/micropython_controller.dart';
import 'package:nomad_protocols/testing.dart';

import '../support/board_transport.dart';
import '../support/fake_web.dart';
import '../support/locale.dart';

const _pi = 'https://micropython.org/pi/v2';

const _index = '''
{"v":2,"packages":[
 {"name":"ssd1306","version":"0.1.0","description":"Pilote d'écran OLED","license":"MIT","versions":{"6":["0.1.0"],"py":["0.1.0"]}},
 {"name":"aioble","version":"0.6.2","license":"MIT","versions":{"6":["0.6.2"],"py":["0.6.2"]}},
 {"name":"aioble-core","version":"0.3.0","license":"MIT","versions":{"6":["0.3.0"],"py":["0.3.0"]}}
]}''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory storage;
  late FakeDisk disk;
  late FakeWeb web;
  late ProviderContainer container;

  setUp(() {
    storage = Directory.systemTemp.createTempSync('nomad_libs_test');
    disk = FakeDisk();
    web = FakeWeb()
      ..text('$_pi/index.json', _index)
      ..text('$_pi/package/6/ssd1306/latest.json', '{"hashes":[["ssd1306.mpy","156dcec1"]]}')
      ..text('$_pi/package/py/ssd1306/latest.json', '{"hashes":[["ssd1306.py","2ab0"]]}')
      ..text('$_pi/file/15/156dcec1', 'MPY ssd1306')
      ..text('$_pi/file/2a/2ab0', 'class SSD1306: pass')
      ..text('$_pi/package/6/aioble/latest.json', '{"hashes":[["aioble/__init__.mpy","b1"]],"deps":[["aioble-core","latest"]]}')
      ..text('$_pi/package/6/aioble-core/latest.json', '{"hashes":[["aioble/core.mpy","c2"]]}')
      ..text('$_pi/file/b1/b1', 'init')
      ..text('$_pi/file/c2/c2', 'core');
    container = ProviderContainer(overrides: [
      frenchLocale,
      serialTransportProvider.overrideWithValue(BoardTransport(FakeRawReplBoard(run: disk.run, outputChunkSize: 64))),
      storageRootProvider.overrideWith((ref) => storage),
      firmwareSourceProvider.overrideWithValue(web),
    ]);
    container.listen(librariesProvider, (_, __) {});
  });

  tearDown(() {
    container.dispose();
    storage.deleteSync(recursive: true);
  });

  MicroPythonController micro() => container.read(microPythonProvider.notifier);
  LibrariesController libs() => container.read(librariesProvider.notifier);
  LibrariesState state() => container.read(librariesProvider);
  String text(String path) => utf8.decode(disk.files[path]!);

  Future<void> connect() async {
    await micro().refreshDevices();
    await micro().connect();
    expect(container.read(microPythonProvider).isReady, isTrue);
  }

  test('installer une bibliothèque : la version compilée arrive dans /lib, vérifiée', () async {
    await connect();
    await libs().loadIndex();
    await libs().install('ssd1306');

    expect(state().succeeded, isTrue, reason: state().message);
    expect(text('/lib/ssd1306.mpy'), 'MPY ssd1306');
    expect(state().message, contains('import ssd1306'));
    expect(state().installed!.map((e) => e.name), ['ssd1306.mpy']);
  });

  test('carte qui n\'annonce pas de version .mpy : les sources sont installées', () async {
    disk.mpyVersion = 0;
    await connect();
    await libs().loadIndex();
    await libs().install('ssd1306');
    expect(text('/lib/ssd1306.py'), 'class SSD1306: pass');
    expect(disk.files.containsKey('/lib/ssd1306.mpy'), isFalse);
  });

  test('les dépendances suivent, et les sous-dossiers sont créés', () async {
    await connect();
    await libs().loadIndex();
    await libs().install('aioble');
    expect(text('/lib/aioble/__init__.mpy'), 'init');
    expect(text('/lib/aioble/core.mpy'), 'core');
    expect(disk.dirs, containsAll(['/lib', '/lib/aioble']));
    expect(state().message, contains('2 fichier(s)'));
  });

  test('pas assez de place : rien n\'est écrit et le message donne les tailles', () async {
    disk.capacity = 2000; // un fichier occupe au moins un bloc de 4 Ko
    await connect();
    await libs().loadIndex();
    await libs().install('ssd1306');

    expect(state().succeeded, isFalse);
    expect(state().message, contains('Pas assez de place'));
    expect(disk.files.keys.where((k) => k.startsWith('/lib')), isEmpty);
  });

  test('sans carte connectée : on demande de connecter, rien n\'est téléchargé', () async {
    await libs().loadIndex();
    web.requested.clear();
    await libs().install('ssd1306');
    expect(state().message, contains('Connectez une carte'));
    expect(web.requested, isEmpty);
  });

  test('bibliothèque introuvable : message clair', () async {
    await connect();
    await libs().loadIndex();
    await libs().install('bme280');
    expect(state().succeeded, isFalse);
    expect(state().message, contains('bme280 : introuvable'));
  });

  test('depuis GitHub : nom affiché tiré de l\'adresse', () async {
    web
      ..text('https://raw.githubusercontent.com/auteur/micropython-bme280/HEAD/package.json', '{"urls":[["bme280.py","bme280.py"]]}')
      ..text('https://raw.githubusercontent.com/auteur/micropython-bme280/HEAD/bme280.py', 'class BME280: pass');
    await connect();
    await libs().loadIndex();
    await libs().install('github:auteur/micropython-bme280');
    expect(state().succeeded, isTrue, reason: state().message);
    expect(text('/lib/bme280.py'), 'class BME280: pass');
    expect(state().message, contains('micropython-bme280 est installée'));
  });

  test('supprimer une bibliothèque en dossier efface tout son contenu', () async {
    await connect();
    await libs().loadIndex();
    await libs().install('aioble');
    final folder = state().installed!.singleWhere((e) => e.name == 'aioble');
    await libs().remove(folder);

    expect(disk.files.keys.where((k) => k.startsWith('/lib/aioble')), isEmpty);
    expect(disk.dirs, isNot(contains('/lib/aioble')));
    expect(state().installed, isEmpty);
    expect(state().message, contains('aioble a été supprimée'));
  });

  test('index injoignable et jamais téléchargé : échec avec un message réseau', () async {
    web.offline = true;
    await libs().loadIndex();
    expect(state().status, LibIndexStatus.failed);
    expect(state().message, contains('réseau injoignable'));
  });

  test('noms affichés et modules à importer', () {
    expect(LibrariesController.displayName('ssd1306'), 'ssd1306');
    expect(LibrariesController.displayName('requests@0.10.0'), 'requests');
    expect(LibrariesController.displayName('github:auteur/bme280@v2'), 'bme280');
    expect(LibrariesController.displayName('https://example.org/x/dht20.py'), 'dht20');
    expect(LibrariesController.displayName('https://example.org/lib/package.json'), 'lib');
    expect(LibrariesController.moduleName('aioble/__init__.mpy'), 'aioble');
    expect(LibrariesController.moduleName('ssd1306.mpy'), 'ssd1306');
  });

  test('aucun fichier binaire n\'est altéré au passage', () async {
    final binary = Uint8List.fromList(List.generate(3000, (i) => i % 256));
    web.pages['$_pi/file/15/156dcec1'] = binary;
    await connect();
    await libs().loadIndex();
    await libs().install('ssd1306');
    expect(disk.files['/lib/ssd1306.mpy'], binary);
  });
}
