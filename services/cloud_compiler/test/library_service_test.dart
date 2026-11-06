import 'dart:io';
import 'dart:typed_data';

import 'package:nomad_cloud_compiler/nomad_cloud_compiler.dart';
import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'libraries_support.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('nomad_libsvc_'));
  tearDown(() => dir.deleteSync(recursive: true));

  LibraryService service({required IndexFetcher fetch, DateTime Function()? clock, Duration maxAge = const Duration(hours: 24)}) => LibraryService(
        indexFile: File(p.join(dir.path, 'library_index.json')),
        fetch: fetch,
        cache: LibraryCache(root: Directory(p.join(dir.path, 'libs')), download: (url, {required maxBytes}) async => throw UnimplementedError()),
        maxAge: maxAge,
        clock: clock,
      );

  test('premier démarrage : télécharge l\'index et le garde sur le disque', () async {
    var fetched = 0;
    final svc = service(fetch: () async {
      fetched++;
      return indexJson(sampleReleases());
    });
    expect(svc.index, isNull);

    await svc.start();
    svc.dispose();

    expect(fetched, 1);
    expect(svc.index!.libraryCount, greaterThan(5));
    expect(File(p.join(dir.path, 'library_index.json')).existsSync(), isTrue);
  });

  test('redémarrage : l\'index du disque sert tout de suite, sans télécharger tant qu\'il est récent', () async {
    File(p.join(dir.path, 'library_index.json')).writeAsStringSync(indexJson(sampleReleases()));
    var fetched = 0;
    final svc = service(fetch: () async {
      fetched++;
      return indexJson(sampleReleases());
    });

    await svc.start();
    svc.dispose();

    expect(fetched, 0);
    expect(svc.index, isNotNull);
  });

  test('index périmé : rafraîchi ; échec du téléchargement : l\'ancien index reste servi', () async {
    File(p.join(dir.path, 'library_index.json')).writeAsStringSync(indexJson(sampleReleases()));
    var now = DateTime.now().add(const Duration(days: 3));
    final svc = service(fetch: () async => throw const SocketException('hors ligne'), clock: () => now);

    await svc.start();
    svc.dispose();

    expect(svc.index, isNotNull, reason: 'l\'ancien index est conservé');
    expect(now.isAfter(DateTime.now()), isTrue);
  });

  test('contenu téléchargé illisible : l\'index en place n\'est pas remplacé', () async {
    File(p.join(dir.path, 'library_index.json')).writeAsStringSync(indexJson(sampleReleases()));
    final before = File(p.join(dir.path, 'library_index.json')).readAsStringSync();
    final svc = service(fetch: () async => '{"pas": "un index"}', clock: () => DateTime.now().add(const Duration(days: 3)));
    await svc.start();
    svc.dispose();

    expect(File(p.join(dir.path, 'library_index.json')).readAsStringSync(), before);
    expect(svc.index!.latest('Servo'), isNotNull);
  });

  test('fichier d\'index abîmé sur le disque : retéléchargé', () async {
    File(p.join(dir.path, 'library_index.json')).writeAsStringSync('{ abîmé');
    final svc = service(fetch: () async => indexJson(sampleReleases()));
    await svc.start();
    svc.dispose();
    expect(svc.index, isNotNull);
  });

  test('plusieurs rafraîchissements simultanés ne téléchargent qu\'une fois', () async {
    var fetched = 0;
    final svc = service(fetch: () async {
      fetched++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return indexJson(sampleReleases());
    });
    await Future.wait([svc.refresh(), svc.refresh(), svc.refresh()]);
    expect(fetched, 1);
  });

  group('résolution d\'un en-tête (l\'index déclare presque jamais ses en-têtes)', () {
    late Uint8List oled;
    late Uint8List oledWemos;
    late Uint8List dht;
    late List<String> opened;
    late bool offline;

    setUp(() {
      oled = libraryZip(top: 'Adafruit_SSD1306-2.5.17', files: {'library.properties': 'name=Adafruit SSD1306\n', 'Adafruit_SSD1306.h': '#pragma once\n', 'Adafruit_SSD1306.cpp': '//\n'});
      oledWemos = libraryZip(top: 'wemos', files: {'library.properties': 'name=Wemos\n', 'src/Adafruit_SSD1306_Wemos.h': '#pragma once\n'});
      dht = libraryZip(files: {'library.properties': 'name=DHT sensor library\n', 'DHT.h': '#pragma once\n', 'DHT_U.h': '#pragma once\n'});
      opened = [];
      offline = false;
    });

    Future<LibraryService> resolver() async {
      final zips = {
        'Adafruit_SSD1306': oled,
        'Adafruit_SSD1306_Wemos_Mini_OLED': oledWemos,
        'DHT_sensor_library': dht,
      };
      final svc = LibraryService(
        indexFile: File(p.join(dir.path, 'library_index.json')),
        fetch: () async => indexJson([
          entryFor('Adafruit SSD1306', '2.5.17', oled, author: 'Adafruit'),
          entryFor('Adafruit SSD1306 Wemos Mini OLED', '1.0.0', oledWemos),
          releaseJson('desklab', '1.0.0', includes: ['Adafruit_SSD1306.h']),
          entryFor('DHT sensor library', '1.4.7', dht, author: 'Adafruit'),
        ]),
        cache: LibraryCache(
          root: Directory(p.join(dir.path, 'libs')),
          download: (url, {required maxBytes}) async {
            opened.add(url.pathSegments.last);
            if (offline) throw const SocketException('hors ligne');
            final key = zips.keys.firstWhere((k) => url.pathSegments.last.startsWith(k));
            return zips[key]!;
          },
        ),
      );
      await svc.start();
      svc.dispose();
      return svc;
    }

    test('une bibliothèque sans en-tête déclaré est confirmée en ouvrant son archive, et passe avant le fork qui le déclare', () async {
      final svc = await resolver();
      final result = await svc.resolveHeader('Adafruit_SSD1306.h');

      expect(result.candidates.map((c) => c.name), ['Adafruit SSD1306', 'desklab', 'Adafruit SSD1306 Wemos Mini OLED']);
      expect(result.confirmed, {'Adafruit SSD1306', 'desklab'}, reason: 'le Wemos a un autre en-tête');
      svc.dispose();
    });

    test('en-tête à la racine ou dans src/, casse ignorée', () async {
      final svc = await resolver();
      final result = await svc.resolveHeader('dht.h');
      expect(result.confirmed, {'DHT sensor library'});
      final second = await svc.resolveHeader('DHT_U.h');
      expect(second.confirmed, {'DHT sensor library'});
      expect(opened.where((o) => o.startsWith('DHT')), hasLength(1), reason: 'archive ouverte une seule fois');
    });

    test('budget épuisé : plus d\'ouverture, les candidats restent des suggestions', () async {
      final svc = await resolver();
      final result = await svc.resolveHeader('Adafruit_SSD1306.h', budget: VerifyBudget(0));
      expect(opened, isEmpty);
      expect(result.confirmed, {'desklab'}, reason: 'seul ce que l\'index déclare est sûr');
      expect(result.candidates.map((c) => c.name), contains('Adafruit SSD1306'));
    });

    test('téléchargement impossible : pas d\'erreur, candidat non confirmé', () async {
      offline = true;
      final svc = await resolver();
      final result = await svc.resolveHeader('DHT.h');
      expect(result.candidates.map((c) => c.name), ['DHT sensor library']);
      expect(result.confirmed, isEmpty);
    });

    test('un en-tête très courant n\'épuise pas le budget des suivants', () async {
      final many = [
        for (var i = 0; i < 10; i++) entryFor('DHT variant $i', '1.0.0', dht),
        entryFor('Adafruit SSD1306', '2.5.17', oled, author: 'Adafruit'),
      ];
      final zips = {'DHT_variant': dht, 'Adafruit_SSD1306': oled};
      final svc = LibraryService(
        indexFile: File(p.join(dir.path, 'library_index.json')),
        fetch: () async => indexJson(many),
        cache: LibraryCache(
          root: Directory(p.join(dir.path, 'libs')),
          download: (url, {required maxBytes}) async {
            opened.add(url.pathSegments.last);
            return zips.entries.firstWhere((e) => url.pathSegments.last.startsWith(e.key)).value;
          },
        ),
      );
      await svc.start();
      svc.dispose();
      final budget = VerifyBudget(4);

      final first = await svc.resolveHeader('DHT.h', budget: budget);
      final second = await svc.resolveHeader('Adafruit_SSD1306.h', budget: budget);

      expect(opened.where((o) => o.startsWith('DHT_variant')), hasLength(3), reason: '3 vérifications par en-tête au plus');
      expect(first.confirmed, hasLength(3));
      expect(second.confirmed, {'Adafruit SSD1306'}, reason: 'le budget a suffi pour l\'en-tête suivant');
    });

    test('en-tête sans ressemblance avec aucun nom : aucun candidat, rien d\'ouvert', () async {
      final svc = await resolver();
      final result = await svc.resolveHeader('Zzzzz.h');
      expect(result.candidates, isEmpty);
      expect(opened, isEmpty);
    });

    test('catalogue pas chargé : réponse vide', () async {
      final svc = LibraryService(
        indexFile: File(p.join(dir.path, 'absent.json')),
        fetch: () async => throw const SocketException('hors ligne'),
        cache: LibraryCache(root: Directory(p.join(dir.path, 'x')), download: (url, {required maxBytes}) async => throw UnimplementedError()),
      );
      await svc.start();
      svc.dispose();
      expect((await svc.resolveHeader('DHT.h')).candidates, isEmpty);
    });
  });

  group('liste de ce que le cœur fournit', () {
    const output = '''
/opt/arduino/data/packages/esp32/hardware/esp32/3.3.12/libraries/Wire
/opt/arduino/data/packages/esp32/hardware/esp32/3.3.12/libraries/Wire/src
/opt/arduino/data/packages/esp32/hardware/esp32/3.3.12/libraries/Wire/src/Wire.h
/opt/arduino/data/packages/esp32/hardware/esp32/3.3.12/libraries/WiFi
/opt/arduino/data/packages/esp32/hardware/esp32/3.3.12/libraries/WiFi/src/WiFi.h
/opt/arduino/data/packages/esp32/hardware/esp32/3.3.12/cores/esp32/Arduino.h
/opt/arduino/data/packages/rp2040/hardware/rp2040/4.4.2/libraries/Wire/src/Wire.h
/opt/arduino/data/packages/rp2040/hardware/rp2040/4.4.2/cores/rp2040/Arduino.h
/opt/arduino/data/packages/inconnu/hardware/x/1.0/libraries/Zed
ligne sans rapport
''';

    test('par famille de carte', () {
      final catalog = BuiltinCatalog.parse(output);
      final esp = catalog.forFamily(CompileFamily.esp);
      expect(esp.libraries, {'Wire', 'WiFi'});
      expect(esp.headers, containsAll(['Wire.h', 'WiFi.h', 'Arduino.h']));
      final pico = catalog.forFamily(CompileFamily.rp2040);
      expect(pico.libraries, {'Wire'});
      expect(pico.providesHeader('WiFi.h'), isFalse, reason: 'le WiFi de l\'ESP32 n\'est pas celui du RP2040');
      expect(esp.libraries, isNot(contains('Zed')));
    });

    test('sortie vide : rien de fourni', () {
      expect(BuiltinCatalog.parse('').forFamily(CompileFamily.esp).headers, isEmpty);
      expect(BuiltinCatalog.empty.forFamily(CompileFamily.rp2040).libraries, isEmpty);
    });
  });
}
