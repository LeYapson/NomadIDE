import 'dart:typed_data';

/// Framing SLIP du bootloader ESP (esptool) : chaque paquet est encadré par `0xC0`,
/// et `0xC0` / `0xDB` à l'intérieur sont remplacés par `0xDB 0xDC` / `0xDB 0xDD`.
const int slipEnd = 0xC0;
const int _slipEsc = 0xDB;
const int _slipEscEnd = 0xDC;
const int _slipEscEsc = 0xDD;

/// Encadre [payload] pour l'envoi.
Uint8List slipEncode(List<int> payload) {
  final out = BytesBuilder(copy: false)..addByte(slipEnd);
  for (final b in payload) {
    switch (b) {
      case slipEnd:
        out
          ..addByte(_slipEsc)
          ..addByte(_slipEscEnd);
      case _slipEsc:
        out
          ..addByte(_slipEsc)
          ..addByte(_slipEscEsc);
      default:
        out.addByte(b);
    }
  }
  return (out..addByte(slipEnd)).toBytes();
}

/// Découpe un flux d'octets en paquets. Les octets reçus hors paquet (le texte de boot de la ROM,
/// par exemple « ets Jun 8 2016 … ») sont ignorés.
class SlipDecoder {
  final List<int> _frame = [];
  bool _inFrame = false;
  bool _escaped = false;

  /// Consomme [data] et renvoie les paquets complets qu'il a permis de terminer.
  List<Uint8List> add(List<int> data) {
    final frames = <Uint8List>[];
    for (final b in data) {
      if (b == slipEnd) {
        if (_inFrame && _frame.isNotEmpty) frames.add(Uint8List.fromList(_frame));
        _frame.clear();
        _inFrame = true;
        _escaped = false;
        continue;
      }
      if (!_inFrame) continue;
      if (_escaped) {
        _escaped = false;
        switch (b) {
          case _slipEscEnd:
            _frame.add(slipEnd);
          case _slipEscEsc:
            _frame.add(_slipEsc);
          default:
            // Séquence invalide : le paquet est perdu, on attend le suivant.
            _frame.clear();
            _inFrame = false;
        }
      } else if (b == _slipEsc) {
        _escaped = true;
      } else {
        _frame.add(b);
      }
    }
    return frames;
  }
}
