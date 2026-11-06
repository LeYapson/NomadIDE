import 'dart:io';

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
