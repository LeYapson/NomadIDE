import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:test/test.dart';

void main() {
  test('LibraryRef : égalité, texte et JSON', () {
    const a = LibraryRef(name: 'DHT sensor library', version: '1.4.6');
    expect(a, const LibraryRef(name: 'DHT sensor library', version: '1.4.6'));
    expect(a.hashCode, const LibraryRef(name: 'DHT sensor library', version: '1.4.6').hashCode);
    expect(a == const LibraryRef(name: 'DHT sensor library', version: '1.4.4'), isFalse);
    expect(a.toString(), 'DHT sensor library@1.4.6');
    expect(LibraryRef.fromJson(a.toJson()), a);
  });

  test('résumé, détail et résultat de recherche font l\'aller-retour en JSON', () {
    const summary = LibrarySummary(
      name: 'DHT sensor library',
      latest: '1.4.6',
      author: 'Adafruit',
      sentence: 'DHT11, DHT22',
      category: 'Sensors',
      license: 'MIT',
      website: 'https://example.com',
      versionCount: 3,
    );
    final back = LibrarySummary.fromJson(summary.toJson());
    expect(back.latest, '1.4.6');
    expect(back.license, 'MIT');
    expect(back.versionCount, 3);

    final detail = LibraryDetail.fromJson(const LibraryDetail(
      summary: summary,
      paragraph: 'Long',
      versions: [
        LibraryVersion(version: '1.4.6', license: 'MIT', dependencies: ['Adafruit Unified Sensor']),
        LibraryVersion(version: '1.4.4'),
      ],
    ).toJson());
    expect(detail.versions.first.dependencies, ['Adafruit Unified Sensor']);
    expect(detail.versions.last.license, isNull);
    expect(detail.paragraph, 'Long');

    final result = LibrarySearchResult.fromJson(const LibrarySearchResult(total: 12, libraries: [summary]).toJson());
    expect(result.total, 12);
    expect(result.libraries.single.name, 'DHT sensor library');
  });

  test('champs facultatifs absents d\'une réponse', () {
    final minimal = LibrarySummary.fromJson({'name': 'X', 'latest': '1.0'});
    expect(minimal.license, isNull);
    expect(minimal.author, '');
    expect(minimal.versionCount, 1);
  });

  test('résolution d\'en-tête et fermeture', () {
    final resolution = IncludeResolution.fromJson(const IncludeResolution(
      header: 'DHT.h',
      candidates: [LibrarySummary(name: 'DHT', latest: '0.1.0')],
      confirmed: ['DHT'],
    ).toJson());
    expect(resolution.builtin, isFalse);
    expect(resolution.candidates.single.name, 'DHT');
    expect(resolution.confirmed, ['DHT']);
    expect(IncludeResolution.fromJson({'header': 'X.h'}).confirmed, isEmpty);
    expect(IncludeResolution.fromJson({'header': 'Wire.h', 'builtin': true}).candidates, isEmpty);

    final closure = LibraryClosure.fromJson(const LibraryClosure(libraries: [LibraryRef(name: 'A', version: '1.0')]).toJson());
    expect(closure.libraries.single.toString(), 'A@1.0');
  });

  test('l\'architecture d\'une carte pour filtrer les bibliothèques', () {
    expect(CompileBoard.esp32.architecture, 'esp32');
    expect(CompileBoard.esp32s3.architecture, 'esp32');
    expect(CompileBoard.rp2040.architecture, 'rp2040');
  });
}
