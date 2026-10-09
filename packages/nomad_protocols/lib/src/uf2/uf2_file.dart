import 'dart:typed_data';

/// Famille de puce visée par un fichier UF2 (champ « familyID » de chaque bloc).
enum Uf2Family {
  rp2040(0xE48BFF56, 'RP2040'),
  rp2350Arm(0xE48BFF59, 'RP2350 (ARM)'),
  rp2350Riscv(0xE48BFF5A, 'RP2350 (RISC-V)'),
  rp2350Absolute(0xE48BFF57, 'Absolu'),
  rp2Data(0xE48BFF58, 'Données'),
  esp32(0x1C5F21B0, 'ESP32'),
  esp32s2(0xBFDD4EEE, 'ESP32-S2'),
  esp32s3(0xC47E5767, 'ESP32-S3'),
  esp32c3(0xD42BA06C, 'ESP32-C3'),
  samd21(0x68ED2B88, 'SAMD21'),
  samd51(0x55114460, 'SAMD51'),
  nrf52840(0xADA52840, 'nRF52840'),
  unknown(0, 'Inconnue');

  const Uf2Family(this.id, this.label);

  final int id;
  final String label;

  static Uf2Family fromId(int id) => values.firstWhere((f) => f.id == id, orElse: () => unknown);

  /// Cartes RP2040 / RP2350 dont le BOOTSEL accepte ce fichier.
  bool get isRaspberryPi => switch (this) {
        rp2040 || rp2350Arm || rp2350Riscv || rp2350Absolute || rp2Data => true,
        _ => false,
      };
}

/// Fichier UF2 mal formé.
class Uf2FormatException implements FormatException {
  const Uf2FormatException(this.message, {this.blockIndex});

  @override
  final String message;

  /// Bloc fautif (à partir de 0), si l'erreur en désigne un.
  final int? blockIndex;

  @override
  dynamic get source => null;

  @override
  int? get offset => blockIndex == null ? null : blockIndex! * Uf2File.blockSize;

  @override
  String toString() => blockIndex == null ? 'Uf2FormatException: $message' : 'Uf2FormatException: $message (bloc $blockIndex)';
}

/// Un fichier UF2 lu et vérifié : chaque bloc de 512 octets est contrôlé avant tout envoi à la carte.
///
/// Format : https://github.com/microsoft/uf2 — 32 octets d'en-tête, 476 octets de données,
/// 4 octets de marque de fin.
class Uf2File {
  Uf2File._(this.bytes, this.blockCount, this.family, this.payloadSize, this.startAddress, this.endAddress);

  static const blockSize = 512;
  static const _magicStart0 = 0x0A324655; // « UF2\n »
  static const _magicStart1 = 0x9E5D5157;
  static const _magicEnd = 0x0AB16F30;
  static const _flagNotMainFlash = 0x00000001;
  static const _flagFamilyIdPresent = 0x00002000;

  /// Contenu brut, à copier tel quel sur la carte.
  final Uint8List bytes;
  final int blockCount;
  final Uf2Family family;

  /// Octets utiles (sans les en-têtes), c'est-à-dire la taille du programme.
  final int payloadSize;

  /// Plage d'adresses écrite en mémoire flash.
  final int startAddress;
  final int endAddress;

  /// Lit et vérifie [bytes]. Lève [Uf2FormatException] au premier défaut.
  factory Uf2File.parse(Uint8List bytes) {
    if (bytes.isEmpty) throw const Uf2FormatException('fichier vide');
    if (bytes.length % blockSize != 0) {
      throw Uf2FormatException('taille ${bytes.length} octets : pas un multiple de $blockSize');
    }
    final count = bytes.length ~/ blockSize;
    final data = ByteData.sublistView(bytes);

    var familyId = 0;
    var payload = 0;
    int? start;
    int? end;
    for (var i = 0; i < count; i++) {
      final o = i * blockSize;
      if (data.getUint32(o, Endian.little) != _magicStart0 ||
          data.getUint32(o + 4, Endian.little) != _magicStart1 ||
          data.getUint32(o + blockSize - 4, Endian.little) != _magicEnd) {
        throw Uf2FormatException('marque UF2 absente', blockIndex: i);
      }
      final flags = data.getUint32(o + 8, Endian.little);
      final address = data.getUint32(o + 12, Endian.little);
      final size = data.getUint32(o + 16, Endian.little);
      final blockNo = data.getUint32(o + 20, Endian.little);
      final total = data.getUint32(o + 24, Endian.little);
      if (size == 0 || size > 476) throw Uf2FormatException('taille de données $size invalide', blockIndex: i);
      if (total != count) {
        throw Uf2FormatException('le fichier annonce $total blocs, il en contient $count', blockIndex: i);
      }
      if (blockNo != i) throw Uf2FormatException('bloc numéroté $blockNo, attendu $i', blockIndex: i);

      if (flags & _flagFamilyIdPresent != 0) {
        final id = data.getUint32(o + 28, Endian.little);
        if (i == 0) {
          familyId = id;
        } else if (id != familyId) {
          throw Uf2FormatException('famille de puce différente selon les blocs', blockIndex: i);
        }
      }
      if (flags & _flagNotMainFlash == 0) {
        payload += size;
        start = start == null || address < start ? address : start;
        final blockEnd = address + size;
        end = end == null || blockEnd > end ? blockEnd : end;
      }
    }
    return Uf2File._(bytes, count, Uf2Family.fromId(familyId), payload, start ?? 0, end ?? 0);
  }
}
