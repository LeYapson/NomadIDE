/// Numéro de version d'une bibliothèque Arduino. L'index n'impose pas le semver (« 1.0 », « 2.3.4.5 »,
/// « 1.0.0-beta ») : on compare les nombres un à un, et une version finale l'emporte sur une préversion.
class ArduinoVersion implements Comparable<ArduinoVersion> {
  const ArduinoVersion._(this.numbers, this.pre, this.text);

  final List<int> numbers;

  /// Suffixe de préversion (« beta »), vide pour une version finale.
  final String pre;
  final String text;

  static ArduinoVersion? tryParse(String raw) {
    var text = raw.trim();
    if (text.startsWith('v') || text.startsWith('V')) text = text.substring(1);
    if (text.isEmpty) return null;
    final split = text.indexOf(RegExp(r'[-+]'));
    final core = split < 0 ? text : text.substring(0, split);
    final pre = split < 0 ? '' : text.substring(split + 1);
    final numbers = <int>[];
    for (final part in core.split('.')) {
      final n = int.tryParse(part);
      if (n == null || n < 0) return null;
      numbers.add(n);
    }
    return ArduinoVersion._(numbers, pre, raw.trim());
  }

  @override
  int compareTo(ArduinoVersion other) {
    final length = numbers.length > other.numbers.length ? numbers.length : other.numbers.length;
    for (var i = 0; i < length; i++) {
      final a = i < numbers.length ? numbers[i] : 0;
      final b = i < other.numbers.length ? other.numbers[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    if (pre.isEmpty && other.pre.isEmpty) return 0;
    if (pre.isEmpty) return 1;
    if (other.pre.isEmpty) return -1;
    return pre.compareTo(other.pre);
  }

  @override
  bool operator ==(Object other) => other is ArduinoVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(Object.hashAll(_trimmed(numbers)), pre);

  static List<int> _trimmed(List<int> numbers) {
    var end = numbers.length;
    while (end > 1 && numbers[end - 1] == 0) {
      end--;
    }
    return numbers.sublist(0, end);
  }

  @override
  String toString() => text;
}

/// Vrai si [version] respecte [constraint] (la syntaxe de `depends=` : « 1.2.3 », « >=1.0.0 », « ^1.2 »,
/// « ~1.2.3 », « 1.2.x », plusieurs termes séparés par des espaces ou des virgules, tous exigés).
///
/// Une contrainte qu'on ne comprend pas est acceptée : mieux vaut proposer la bibliothèque que refuser
/// à tort. Sans contrainte, toute version convient.
bool satisfies(ArduinoVersion version, String? constraint) {
  if (constraint == null || constraint.trim().isEmpty) return true;
  for (final term in constraint.split(RegExp(r'[\s,]+')).where((t) => t.isNotEmpty)) {
    if (!_termHolds(version, term)) return false;
  }
  return true;
}

bool _termHolds(ArduinoVersion v, String term) {
  final match = RegExp(r'^(>=|<=|!=|==|=|>|<|\^|~)?(.+)$').firstMatch(term);
  if (match == null) return true;
  final op = match.group(1) ?? '';
  final operand = match.group(2)!;

  if (operand.contains('x') || operand.contains('X') || operand.contains('*')) {
    final prefix = <int>[];
    for (final part in operand.split('.')) {
      if (part == 'x' || part == 'X' || part == '*') break;
      final n = int.tryParse(part);
      if (n == null) return true;
      prefix.add(n);
    }
    for (var i = 0; i < prefix.length; i++) {
      if ((i < v.numbers.length ? v.numbers[i] : 0) != prefix[i]) return false;
    }
    return true;
  }

  final target = ArduinoVersion.tryParse(operand);
  if (target == null) return true;
  final cmp = v.compareTo(target);
  switch (op) {
    case '>=':
      return cmp >= 0;
    case '>':
      return cmp > 0;
    case '<=':
      return cmp <= 0;
    case '<':
      return cmp < 0;
    case '!=':
      return cmp != 0;
    case '^':
      if (cmp < 0) return false;
      final upper = _caretUpper(target);
      return v.compareTo(upper) < 0;
    case '~':
      if (cmp < 0) return false;
      final n = target.numbers;
      final upper = ArduinoVersion.tryParse('${n.isNotEmpty ? n[0] : 0}.${(n.length > 1 ? n[1] : 0) + 1}.0')!;
      return v.compareTo(upper) < 0;
    default:
      return cmp == 0;
  }
}

ArduinoVersion _caretUpper(ArduinoVersion target) {
  final n = target.numbers;
  final major = n.isNotEmpty ? n[0] : 0;
  final minor = n.length > 1 ? n[1] : 0;
  return major > 0
      ? ArduinoVersion.tryParse('${major + 1}.0.0')!
      : ArduinoVersion.tryParse('0.${minor + 1}.0')!;
}
