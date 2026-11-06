import 'package:nomad_cloud_compiler/nomad_cloud_compiler.dart';
import 'package:test/test.dart';

ArduinoVersion v(String text) => ArduinoVersion.tryParse(text)!;

void main() {
  test('analyse des versions, y compris celles qui ne sont pas du semver', () {
    expect(ArduinoVersion.tryParse('1.4.6'), isNotNull);
    expect(ArduinoVersion.tryParse('1.0'), isNotNull);
    expect(ArduinoVersion.tryParse('v2.3.4.5'), isNotNull);
    expect(ArduinoVersion.tryParse('1.0.0-beta.1'), isNotNull);
    expect(ArduinoVersion.tryParse(''), isNull);
    expect(ArduinoVersion.tryParse('abc'), isNull);
    expect(ArduinoVersion.tryParse('1.x'), isNull);
  });

  test('comparaison : nombre par nombre, 1.10 > 1.9, 1.0 == 1.0.0, finale > préversion', () {
    expect(v('1.10.0').compareTo(v('1.9.9')), greaterThan(0));
    expect(v('1.0'), v('1.0.0'));
    expect(v('1.0').hashCode, v('1.0.0').hashCode);
    expect(v('2.0.0').compareTo(v('2.0.0-beta.1')), greaterThan(0));
    expect(v('2.0.0-beta.2').compareTo(v('2.0.0-beta.1')), greaterThan(0));
    final sorted = [v('1.2.0'), v('1.10.0'), v('1.9.0')]..sort();
    expect(sorted.map((e) => e.toString()), ['1.2.0', '1.9.0', '1.10.0']);
  });

  group('satisfies', () {
    test('sans contrainte ou contrainte incomprise : accepté', () {
      expect(satisfies(v('1.0.0'), null), isTrue);
      expect(satisfies(v('1.0.0'), ''), isTrue);
      expect(satisfies(v('1.0.0'), 'n\'importe quoi'), isTrue);
    });

    test('version exacte et opérateurs', () {
      expect(satisfies(v('1.2.3'), '1.2.3'), isTrue);
      expect(satisfies(v('1.2.4'), '1.2.3'), isFalse);
      expect(satisfies(v('1.2.3'), '>=1.2.0'), isTrue);
      expect(satisfies(v('1.1.9'), '>=1.2.0'), isFalse);
      expect(satisfies(v('1.2.0'), '>1.2.0'), isFalse);
      expect(satisfies(v('1.2.0'), '<=1.2.0'), isTrue);
      expect(satisfies(v('1.2.0'), '<1.2.0'), isFalse);
      expect(satisfies(v('1.2.0'), '!=1.2.0'), isFalse);
    });

    test('plusieurs termes : tous exigés', () {
      expect(satisfies(v('1.5.0'), '>=1.0.0 <2.0.0'), isTrue);
      expect(satisfies(v('2.0.0'), '>=1.0.0 <2.0.0'), isFalse);
      expect(satisfies(v('1.5.0'), '>=1.0.0,<1.5.0'), isFalse);
    });

    test('^, ~ et jokers', () {
      expect(satisfies(v('1.9.0'), '^1.2.0'), isTrue);
      expect(satisfies(v('2.0.0'), '^1.2.0'), isFalse);
      expect(satisfies(v('0.2.5'), '^0.2.0'), isTrue);
      expect(satisfies(v('0.3.0'), '^0.2.0'), isFalse);
      expect(satisfies(v('1.2.9'), '~1.2.3'), isTrue);
      expect(satisfies(v('1.3.0'), '~1.2.3'), isFalse);
      expect(satisfies(v('1.2.7'), '1.2.x'), isTrue);
      expect(satisfies(v('1.3.0'), '1.2.x'), isFalse);
      expect(satisfies(v('3.0.0'), '*'), isTrue);
    });
  });
}
