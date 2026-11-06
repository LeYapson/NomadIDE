import 'dart:convert';

import 'package:nomad_cloud_compiler/nomad_cloud_compiler.dart';
import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:test/test.dart';

import 'libraries_support.dart';

void main() {
  late LibraryIndex index;

  setUp(() => index = sampleIndex());

  group('lecture de l\'index', () {
    test('regroupe les versions par bibliothèque, de la plus ancienne à la plus récente', () {
      expect(index.releases('DHT sensor library').map((r) => r.version), ['1.3.10', '1.4.4', '1.4.6']);
      expect(index.latest('DHT sensor library')!.version, '1.4.6');
      expect(index.release('dht sensor LIBRARY', '1.4.4')!.name, 'DHT sensor library', reason: 'casse ignorée');
      expect(index.release('DHT sensor library', '9.9.9'), isNull);
    });

    test('les entrées incomplètes sont ignorées, les champs facultatifs absents tolérés', () {
      final tolerant = LibraryIndex.parse(jsonEncode({
        'libraries': [
          {'name': 'Sans version', 'url': 'https://downloads.arduino.cc/x.zip', 'checksum': 'SHA-256:$fakeHash'},
          {'name': 'Mauvaise empreinte', 'version': '1.0', 'url': 'https://downloads.arduino.cc/x.zip', 'checksum': 'SHA-256:zz'},
          {'name': 'Minimale', 'version': '1.0', 'url': 'https://downloads.arduino.cc/x.zip', 'checksum': 'SHA-256:$fakeHash'},
          'pas un objet',
        ],
      }));
      expect(tolerant.libraryCount, 1);
      final minimal = tolerant.latest('Minimale')!;
      expect(minimal.license, isNull);
      expect(minimal.providesIncludes, isEmpty);
      expect(minimal.sha256, fakeHash);
    });

    test('un fichier qui n\'est pas un index est refusé', () {
      expect(() => LibraryIndex.parse('{"autre": 1}'), throwsFormatException);
      expect(() => LibraryIndex.parse('pas du json'), throwsFormatException);
    });

    test('la dernière version est la dernière finale, sauf s\'il n\'y a que des préversions', () {
      expect(index.latest('Beta lib')!.version, '1.0.0');
      expect(index.latest('Pre only')!.version, '0.9.0-rc1');
    });
  });

  group('recherche', () {
    test('le nom passe avant l\'auteur et les descriptions', () {
      final names = index.search('dht').libraries.map((l) => l.name).toList();
      expect(names.first, 'DHT', reason: 'nom exact');
      expect(names, contains('DHT sensor library'));
    });

    test('un mot entier du nom passe avant le début d\'un nom collé ; à égalité, l\'éditeur connu d\'abord', () {
      final ranked = LibraryIndex.parse(indexJson([
        releaseJson('DHTNEW', '0.5.5', author: 'Rob Tillaart'),
        releaseJson('DHTNEW', '0.5.4', author: 'Rob Tillaart'),
        releaseJson('DHT sensor library', '1.4.7', author: 'Adafruit'),
        releaseJson('DHT helper', '1.0.0', author: 'Someone'),
        releaseJson('DHT helper', '0.9.0', author: 'Someone'),
        releaseJson('DHT helper', '0.8.0', author: 'Someone'),
      ])).search('dht').libraries.map((l) => l.name).toList();
      expect(ranked, ['DHT sensor library', 'DHT helper', 'DHTNEW']);
    });

    test('tous les mots doivent correspondre', () {
      expect(index.search('adafruit sensor').libraries.map((l) => l.name), contains('Adafruit Unified Sensor'));
      expect(index.search('dht moteur').total, 0);
      expect(index.search('   ').total, 0);
    });

    test('filtre par architecture : une bibliothèque réservée à AVR n\'est pas proposée pour l\'ESP32', () {
      expect(index.search('avronly').total, 1);
      expect(index.search('avronly', architecture: 'esp32').total, 0);
      expect(index.search('servo', architecture: 'esp32').total, 1);
      expect(index.search('servo', architecture: 'rp2040').total, 0);
    });

    test('limite et total', () {
      final result = index.search('a', limit: 2);
      expect(result.libraries.length, 2);
      expect(result.total, greaterThan(2));
    });

    test('le résumé donne la dernière version, la licence et le nombre de versions', () {
      final dht = index.search('dht sensor library').libraries.firstWhere((l) => l.name == 'DHT sensor library');
      expect(dht.latest, '1.4.6');
      expect(dht.license, 'MIT');
      expect(dht.versionCount, 3);
      expect(dht.author, 'Adafruit');
    });
  });

  test('détail : versions de la plus récente à la plus ancienne, avec dépendances', () {
    final detail = index.detail('dht sensor library')!;
    expect(detail.versions.map((v) => v.version), ['1.4.6', '1.4.4', '1.3.10']);
    expect(detail.versions.first.dependencies, ['Adafruit Unified Sensor']);
    expect(detail.paragraph, 'Temperature and humidity.');
    expect(index.detail('inconnue'), isNull);
  });

  group('fournisseurs d\'un en-tête', () {
    test('le nom égal à l\'en-tête d\'abord, puis les plus suivies', () {
      final names = index.providersOf('DHT.h').map((l) => l.name).toList();
      expect(names, ['DHT', 'DHT sensor library']);
    });

    test('à nom différent de l\'en-tête, l\'éditeur connu passe avant la bibliothèque qui a le plus de versions', () {
      final ranked = LibraryIndex.parse(indexJson([
        releaseJson('Adafruit SSD1306', '2.5.9', author: 'Adafruit', includes: ['Adafruit_SSD1306.h']),
        for (var i = 0; i < 6; i++) releaseJson('desklab', '1.0.$i', author: 'desklab', includes: ['Adafruit_SSD1306.h']),
      ])).providersOf('Adafruit_SSD1306.h').map((l) => l.name).toList();
      expect(ranked, ['Adafruit SSD1306', 'desklab']);
    });

    test('en-tête inconnu ou casse différente', () {
      expect(index.providersOf('Inconnu.h'), isEmpty);
      expect(index.providersOf('dht.h').map((l) => l.name), contains('DHT sensor library'));
    });

    test('respecte l\'architecture', () {
      expect(index.providersOf('AvrOnly.h', architecture: 'esp32'), isEmpty);
      expect(index.providersOf('Servo.h', architecture: 'esp32'), hasLength(1));
    });
  });

  group('candidats d\'après le nom', () {
    late LibraryIndex names;

    setUp(() {
      names = LibraryIndex.parse(indexJson([
        releaseJson('Adafruit SSD1306', '2.5.17', author: 'Adafruit'),
        releaseJson('Adafruit SSD1306 Wemos Mini OLED', '1.0.0', author: 'Someone'),
        releaseJson('desklab', '1.0.0', includes: ['Adafruit_SSD1306.h']),
        releaseJson('DHT sensor library', '1.4.7', author: 'Adafruit'),
        releaseJson('DHTStable', '1.1.4', includes: ['DHTStable.h']),
        releaseJson('Servo', '1.2.1', architectures: ['avr']),
      ]));
    });

    test('le nom, sans casse ni séparateurs, est celui de l\'en-tête', () {
      expect(names.nameScore('Adafruit_SSD1306.h', 'Adafruit SSD1306'), 100);
      expect(names.nameScore('adafruit_ssd1306.h', 'Adafruit SSD1306'), 100);
      expect(names.nameScore('Adafruit_SSD1306.h', 'Adafruit SSD1306 Wemos Mini OLED'), 70);
      expect(names.nameScore('DHT.h', 'DHT sensor library'), 70);
      expect(names.nameScore('Adafruit_SSD1306_Wemos.h', 'Adafruit SSD1306'), 50);
      expect(names.nameScore('X.h', 'X'), 0, reason: 'trop court pour être fiable');
      expect(names.nameScore('Wire.h', 'Unrelated'), 0);
    });

    test('classés par ressemblance, puis éditeur connu', () {
      expect(names.nameCandidates('Adafruit_SSD1306.h').map((c) => c.name), ['Adafruit SSD1306', 'Adafruit SSD1306 Wemos Mini OLED']);
      expect(names.nameCandidates('DHT.h').map((c) => c.name), ['DHT sensor library', 'DHTStable']);
    });

    test('respecte l\'architecture', () {
      expect(names.nameCandidates('Servo.h', architecture: 'esp32'), isEmpty);
      expect(names.nameCandidates('Servo.h', architecture: 'avr'), hasLength(1));
    });
  });

  group('fermeture (bibliothèque + dépendances à versions précises)', () {
    test('sans version : la dernière, avec ses dépendances', () {
      final outcome = index.closure([const LibraryRef(name: 'DHT sensor library', version: '')]);
      expect(outcome.ok, isTrue);
      final refs = outcome.releases.map((r) => '${r.name}@${r.version}').toList();
      expect(refs, ['DHT sensor library@1.4.6', 'Adafruit Unified Sensor@1.1.9']);
    });

    test('version demandée : gardée, et sa dépendance sans contrainte prend la dernière version', () {
      final outcome = index.closure([const LibraryRef(name: 'DHT sensor library', version: '1.3.10')]);
      expect(outcome.releases.map((r) => '${r.name}@${r.version}'), ['DHT sensor library@1.3.10', 'Adafruit Unified Sensor@1.1.9']);
    });

    test('bibliothèques fournies par le cœur : jamais cherchées', () {
      final outcome = index.closure([const LibraryRef(name: 'Adafruit BusIO', version: '')], builtin: {'Wire', 'SPI'});
      expect(outcome.ok, isTrue);
      expect(outcome.releases.map((r) => r.name), ['Adafruit BusIO']);
      final without = index.closure([const LibraryRef(name: 'Adafruit BusIO', version: '')]);
      expect(without.ok, isFalse);
      expect(without.problems.join(' '), contains('Wire'));
    });

    test('bibliothèque ou version inconnue', () {
      expect(index.closure([const LibraryRef(name: 'Nope', version: '')]).problems.single, contains('inconnue : Nope'));
      expect(index.closure([const LibraryRef(name: 'Servo', version: '9.9.9')]).problems.single, contains('Version inconnue'));
    });

    test('une dépendance doit respecter la contrainte de l\'appelant', () {
      final index = LibraryIndex.parse(indexJson([
        releaseJson('A', '1.0.0', dependencies: [
          {'name': 'B', 'version': '>=2.0.0'}
        ]),
        releaseJson('B', '1.0.0'),
        releaseJson('B', '1.5.0'),
      ]));
      final outcome = index.closure([const LibraryRef(name: 'A', version: '')]);
      expect(outcome.ok, isFalse);
      expect(outcome.problems.single, contains('Aucune version de B'));
    });

    test('deux contraintes incompatibles sur la même bibliothèque sont signalées', () {
      final index = LibraryIndex.parse(indexJson([
        releaseJson('A', '1.0.0', dependencies: [
          {'name': 'C', 'version': '<2.0.0'}
        ]),
        releaseJson('B', '1.0.0', dependencies: [
          {'name': 'C', 'version': '>=2.0.0'}
        ]),
        releaseJson('C', '1.0.0'),
        releaseJson('C', '2.0.0'),
      ]));
      final outcome = index.closure([const LibraryRef(name: 'A', version: ''), const LibraryRef(name: 'B', version: '')]);
      expect(outcome.ok, isFalse);
    });

    test('une bibliothèque réservée à une autre architecture est refusée', () {
      final outcome = index.closure([const LibraryRef(name: 'AvrOnly', version: '')], architecture: 'esp32');
      expect(outcome.ok, isFalse);
      expect(outcome.problems.single, contains('architecture'));
    });

    test('dépendances circulaires : pas de boucle infinie', () {
      final index = LibraryIndex.parse(indexJson([
        releaseJson('A', '1.0.0', dependencies: [
          {'name': 'B'}
        ]),
        releaseJson('B', '1.0.0', dependencies: [
          {'name': 'A'}
        ]),
      ]));
      final outcome = index.closure([const LibraryRef(name: 'A', version: '')]);
      expect(outcome.ok, isTrue);
      expect(outcome.releases.map((r) => r.name), ['A', 'B']);
    });
  });
}
