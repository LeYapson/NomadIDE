import 'dart:typed_data';

/// Découpe un flux d'octets en lignes (séparateur `\n`).
///
/// On découpe **avant** le décodage UTF-8 : l'octet 0x0A ne peut jamais
/// apparaître au milieu d'un caractère multi-octets, alors qu'un chunk série
/// peut, lui, couper un caractère en deux.
///
/// La ligne en cours (sans `\n`) reste accessible via [partial] : c'est ce qui
/// permet d'afficher l'invite `>>> ` du REPL.
class RxLineAssembler {
  RxLineAssembler({this.maxLineLength = 4096});

  /// Au-delà, une « ligne » sans fin (flux binaire) est coupée de force.
  final int maxLineLength;

  final List<int> _partial = <int>[];

  bool get hasPartial => _partial.isNotEmpty;

  Uint8List get partial => Uint8List.fromList(_partial);

  /// Ajoute un chunk et renvoie les lignes complètes (sans le `\n`).
  List<Uint8List> add(Uint8List chunk) {
    final lines = <Uint8List>[];
    var start = 0;
    for (var i = 0; i < chunk.length; i++) {
      if (chunk[i] == 0x0A) {
        _partial.addAll(Uint8List.sublistView(chunk, start, i));
        lines.add(Uint8List.fromList(_partial));
        _partial.clear();
        start = i + 1;
      }
    }
    _partial.addAll(Uint8List.sublistView(chunk, start));
    while (_partial.length >= maxLineLength) {
      lines.add(Uint8List.fromList(_partial.sublist(0, maxLineLength)));
      _partial.removeRange(0, maxLineLength);
    }
    return lines;
  }

  /// Renvoie la ligne en cours et la vide (ex. avant d'afficher une commande envoyée).
  Uint8List? takePartial() {
    if (_partial.isEmpty) return null;
    final line = Uint8List.fromList(_partial);
    _partial.clear();
    return line;
  }

  void reset() => _partial.clear();
}
