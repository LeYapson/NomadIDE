import 'dart:math' as math;
import 'dart:typed_data';

/// MD5 (RFC 1321). Sert à comparer le contenu de la flash avec le fichier envoyé : la ROM de l'ESP
/// calcule le même condensé de son côté (commande SPI_FLASH_MD5). Pas utilisé pour de la sécurité.
Uint8List md5(List<int> message) {
  const s = [
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, //
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ];
  final k = List<int>.generate(64, (i) => _sine(i));

  var a0 = 0x67452301;
  var b0 = 0xefcdab89;
  var c0 = 0x98badcfe;
  var d0 = 0x10325476;

  final length = message.length;
  final padded = Uint8List(((length + 8) ~/ 64 + 1) * 64)
    ..setRange(0, length, message)
    ..[length] = 0x80;
  ByteData.sublistView(padded).setUint64(padded.length - 8, length * 8, Endian.little);

  final words = ByteData.sublistView(padded);
  for (var chunk = 0; chunk < padded.length; chunk += 64) {
    var a = a0, b = b0, c = c0, d = d0;
    for (var i = 0; i < 64; i++) {
      int f;
      int g;
      if (i < 16) {
        f = (b & c) | (~b & d);
        g = i;
      } else if (i < 32) {
        f = (d & b) | (~d & c);
        g = (5 * i + 1) % 16;
      } else if (i < 48) {
        f = b ^ c ^ d;
        g = (3 * i + 5) % 16;
      } else {
        f = c ^ (b | (~d & 0xFFFFFFFF));
        g = (7 * i) % 16;
      }
      f = (f + a + k[i] + words.getUint32(chunk + g * 4, Endian.little)) & 0xFFFFFFFF;
      a = d;
      d = c;
      c = b;
      b = (b + _rotl(f, s[i])) & 0xFFFFFFFF;
    }
    a0 = (a0 + a) & 0xFFFFFFFF;
    b0 = (b0 + b) & 0xFFFFFFFF;
    c0 = (c0 + c) & 0xFFFFFFFF;
    d0 = (d0 + d) & 0xFFFFFFFF;
  }

  final out = Uint8List(16);
  final view = ByteData.sublistView(out);
  view
    ..setUint32(0, a0, Endian.little)
    ..setUint32(4, b0, Endian.little)
    ..setUint32(8, c0, Endian.little)
    ..setUint32(12, d0, Endian.little);
  return out;
}

/// Condensé en hexadécimal minuscule (32 caractères).
String md5Hex(List<int> message) => md5(message).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

int _rotl(int x, int c) => ((x << c) | (x >> (32 - c))) & 0xFFFFFFFF;

/// Constantes K[i] = floor(2^32 × |sin(i + 1)|).
int _sine(int i) => (4294967296 * math.sin(i + 1.0).abs()).floor();
