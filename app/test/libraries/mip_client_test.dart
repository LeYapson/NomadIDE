import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_mcu/features/libraries/data/mip_client.dart';

import '../support/fake_web.dart';

const _index = '''
{"v":2,"updated":1,"packages":[
 {"name":"ssd1306","version":"0.1.0","description":"Pilote d'écran OLED","license":"MIT","versions":{"6":["0.1.0"],"py":["0.1.0"]}},
 {"name":"requests","version":"0.10.0","description":"HTTP","license":"MIT","versions":{"py":["0.10.0"]}},
 {"name":"aioble","version":"0.6.2","license":"MIT","versions":{"6":["0.6.2"],"py":["0.6.2"]}},
 {"name":"aioble-core","version":"0.3.0","license":"MIT","versions":{"6":["0.3.0"],"py":["0.3.0"]}}
]}''';

const _pi = 'https://micropython.org/pi/v2';

void main() {
  late FakeWeb web;
  late Directory cacheDir;
  late MipClient client;

  setUp(() {
    web = FakeWeb()..text('$_pi/index.json', _index);
    cacheDir = Directory.systemTemp.createTempSync('nomad_mip_test');
    client = MipClient(web, cache: MipCache(cacheDir));
  });

  tearDown(() => cacheDir.deleteSync(recursive: true));

  group('index', () {
    test('liste les paquets et cherche dans le nom et la description', () async {
      final (:index, :offline) = await client.loadIndex();
      expect(offline, isFalse);
      expect(index.packages.map((p) => p.name), ['aioble', 'aioble-core', 'requests', 'ssd1306']);
      expect(index.search('oled').single.name, 'ssd1306');
      expect(index.search('aioble').map((p) => p.name), ['aioble', 'aioble-core']);
      expect(index.byName('ssd1306')!.license, 'MIT');
    });

    test('hors ligne, l\'index déjà téléchargé est repris du cache', () async {
      await client.loadIndex();
      web.offline = true;
      final (:index, :offline) = await client.loadIndex();
      expect(offline, isTrue);
      expect(index.packages, hasLength(4));
    });

    test('hors ligne sans cache : erreur réseau', () async {
      web.offline = true;
      expect(client.loadIndex(), throwsA(isA<MipException>().having((e) => e.error, 'error', MipError.network)));
    });
  });

  group('résolution', () {
    test('carte qui charge les .mpy 6 : la version compilée est téléchargée', () async {
      web
        ..text('$_pi/package/6/ssd1306/latest.json', '{"v":1,"version":"0.1.0","hashes":[["ssd1306.mpy","156dcec1"]]}')
        ..text('$_pi/file/15/156dcec1', 'MPY');
      final (:index, offline: _) = await client.loadIndex();
      final files = await client.resolve('ssd1306', mpy: 6, catalog: index);
      expect(files.single.path, 'ssd1306.mpy');
      expect(utf8.decode(files.single.bytes), 'MPY');
    });

    test('paquet publié seulement en sources, ou carte qui ne dit pas sa version : sources .py', () async {
      web
        ..text('$_pi/package/py/requests/0.10.0.json', '{"version":"0.10.0","hashes":[["requests/__init__.py","aa11"]]}')
        ..text('$_pi/file/aa/aa11', 'import socket');
      final (:index, offline: _) = await client.loadIndex();
      final files = await client.resolve('requests@0.10.0', mpy: 6, catalog: index);
      expect(files.single.path, 'requests/__init__.py');
    });

    test('les dépendances sont installées aussi, une seule fois chacune', () async {
      web
        ..text('$_pi/package/6/aioble/latest.json', '{"hashes":[["aioble/__init__.mpy","b1"]],"deps":[["aioble-core","latest"],["aioble-core","latest"]]}')
        ..text('$_pi/package/6/aioble-core/latest.json', '{"hashes":[["aioble/core.mpy","c2"]]}')
        ..text('$_pi/file/b1/b1', 'init')
        ..text('$_pi/file/c2/c2', 'core');
      final (:index, offline: _) = await client.loadIndex();
      final files = await client.resolve('aioble', mpy: 6, catalog: index);
      expect(files.map((f) => f.path), ['aioble/__init__.mpy', 'aioble/core.mpy']);
      expect(web.requested.where((u) => u.path.endsWith('aioble-core/latest.json')), hasLength(1));
    });

    test('un fichier déjà téléchargé est repris du cache, hors ligne compris', () async {
      web
        ..text('$_pi/package/6/ssd1306/latest.json', '{"hashes":[["ssd1306.mpy","156dcec1"]]}')
        ..text('$_pi/file/15/156dcec1', 'MPY');
      final (:index, offline: _) = await client.loadIndex();
      await client.resolve('ssd1306', mpy: 6, catalog: index);
      web.pages.remove('$_pi/file/15/156dcec1');
      final files = await client.resolve('ssd1306', mpy: 6, catalog: index);
      expect(utf8.decode(files.single.bytes), 'MPY');
    });

    test('paquet GitHub : package.json du dépôt, fichiers en adresses relatives et github:', () async {
      const raw = 'https://raw.githubusercontent.com/auteur/bme280/HEAD';
      web
        ..text('$raw/package.json', '{"urls":[["bme280.py","bme280.py"],["bme_util.py","github:auteur/outils/util.py"]],"deps":[["ssd1306","latest"]]}')
        ..text('$raw/bme280.py', 'class BME280')
        ..text('https://raw.githubusercontent.com/auteur/outils/HEAD/util.py', 'def f()')
        ..text('$_pi/package/6/ssd1306/latest.json', '{"hashes":[["ssd1306.mpy","156dcec1"]]}')
        ..text('$_pi/file/15/156dcec1', 'MPY');
      final (:index, offline: _) = await client.loadIndex();
      final files = await client.resolve('github:auteur/bme280', mpy: 6, catalog: index);
      expect(files.map((f) => f.path), ['bme280.py', 'bme_util.py', 'ssd1306.mpy']);
    });

    test('branche GitHub choisie avec @', () async {
      web
        ..text('https://raw.githubusercontent.com/auteur/bme280/v2/package.json', '{"urls":[["bme280.py","bme280.py"]]}')
        ..text('https://raw.githubusercontent.com/auteur/bme280/v2/bme280.py', 'v2');
      final files = await client.resolve('github:auteur/bme280@v2', mpy: 6);
      expect(utf8.decode(files.single.bytes), 'v2');
    });

    test('adresse directe d\'un fichier .py', () async {
      web.text('https://example.org/drivers/dht20.py', 'class DHT20');
      final files = await client.resolve('https://example.org/drivers/dht20.py', mpy: 6);
      expect(files.single.path, 'dht20.py');
    });

    test('paquet absent de l\'index : erreur « introuvable », sans requête', () async {
      final (:index, offline: _) = await client.loadIndex();
      web.requested.clear();
      expect(
        client.resolve('bme280', mpy: 6, catalog: index),
        throwsA(isA<MipException>().having((e) => e.error, 'error', MipError.notFound).having((e) => e.target, 'target', 'bme280')),
      );
      expect(web.requested, isEmpty);
    });

    test('une adresse en http (non chiffrée) est refusée', () async {
      expect(
        client.resolve('http://example.org/x.py', mpy: 6),
        throwsA(isA<MipException>().having((e) => e.error, 'error', MipError.insecure)),
      );
    });

    test('une description illisible donne une erreur claire', () async {
      web.text('https://raw.githubusercontent.com/a/b/HEAD/package.json', 'pas du json');
      expect(
        client.resolve('github:a/b', mpy: 6),
        throwsA(isA<MipException>().having((e) => e.error, 'error', MipError.badPackage)),
      );
    });
  });
}
