import 'dart:convert';
import 'dart:typed_data';

import 'package:nomad_protocols/nomad_protocols.dart';
import 'package:test/test.dart';

void main() {
  group('SLIP', () {
    test('encadre et échappe C0 et DB', () {
      expect(slipEncode([0x01, 0xC0, 0x02, 0xDB, 0x03]), [0xC0, 0x01, 0xDB, 0xDC, 0x02, 0xDB, 0xDD, 0x03, 0xC0]);
    });

    test('décode un paquet reçu en plusieurs morceaux', () {
      final encoded = slipEncode([0x10, 0xC0, 0xDB, 0x20]);
      final decoder = SlipDecoder();
      final frames = <Uint8List>[];
      for (final b in encoded) {
        frames.addAll(decoder.add([b]));
      }
      expect(frames, [
        [0x10, 0xC0, 0xDB, 0x20],
      ]);
    });

    test('ignore le texte de boot avant le premier paquet', () {
      final decoder = SlipDecoder();
      final frames = decoder.add([...utf8.encode('ets Jun  8 2016 00:22:57\r\n'), ...slipEncode([1, 2, 3])]);
      expect(frames, hasLength(1));
      expect(frames.single, [1, 2, 3]);
    });

    test('plusieurs paquets dans un même chunk', () {
      final frames = SlipDecoder().add([...slipEncode([1]), ...slipEncode([2, 3])]);
      expect(frames, [
        [1],
        [2, 3],
      ]);
    });

    test('une séquence d\'échappement invalide fait perdre le paquet, pas le suivant', () {
      final frames = SlipDecoder().add([0xC0, 0x01, 0xDB, 0x99, 0x02, 0xC0, ...slipEncode([7])]);
      expect(frames, [
        [7],
      ]);
    });

    test('aller-retour sur toutes les valeurs d\'octet', () {
      final all = List<int>.generate(256, (i) => i);
      expect(SlipDecoder().add(slipEncode(all)).single, all);
    });
  });

  group('MD5', () {
    test('vecteurs de la RFC 1321', () {
      expect(md5Hex(utf8.encode('')), 'd41d8cd98f00b204e9800998ecf8427e');
      expect(md5Hex(utf8.encode('a')), '0cc175b9c0f1b6a831c399e269772661');
      expect(md5Hex(utf8.encode('abc')), '900150983cd24fb0d6963f7d28e17f72');
      expect(md5Hex(utf8.encode('message digest')), 'f96b697d7cb7938d525a2f31aaf161d0');
      expect(
        md5Hex(utf8.encode('12345678901234567890123456789012345678901234567890123456789012345678901234567890')),
        '57edf4a22be3c955ac49da2e2107b67a',
      );
    });

    test('messages dont la longueur tombe sur une frontière de bloc', () {
      expect(md5Hex(List.filled(55, 0x61)), 'ef1772b6dff9a122358552954ad0df65');
      expect(md5Hex(List.filled(56, 0x61)), '3b0c8ac703f828b04c6c197006d17218');
      expect(md5Hex(List.filled(64, 0x61)), '014842d480b571495a4a0363793f7367');
    });
  });
}
