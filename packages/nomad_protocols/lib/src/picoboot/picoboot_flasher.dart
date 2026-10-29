import 'dart:typed_data';

import '../protocol_exceptions.dart';
import '../uf2/uf2_file.dart';
import 'picoboot_client.dart';

/// Phase d'une écriture PICOBOOT, pour la barre de progression.
enum PicobootPhase { erasing, writing, verifying, rebooting }

typedef PicobootProgress = void Function(PicobootPhase phase, int done, int total);

/// Écrit un fichier UF2 dans la flash d'un RP2040 en mode BOOTSEL, par USB PICOBOOT, sans passer par le
/// disque de stockage : c'est la voie des téléphones Android, qui ne savent pas écrire sur ce disque.
///
/// Déroulé (comme `picotool load`) : accès exclusif, sortie du XIP, effacement par secteurs de 4 Ko, écriture par
/// pages de 256 octets, relecture pour vérifier, puis redémarrage sur le nouveau programme.
class PicobootFlasher {
  PicobootFlasher(this._client);

  final PicobootClient _client;

  static const int flashBase = 0x10000000;
  static const int flashLimit = 0x11000000; // 16 Mo adressables en XIP
  static const int sectorSize = 4096;
  static const int pageSize = 256;
  static const int chunkSize = 4096;

  Future<void> flashUf2(
    Uf2File file, {
    bool verify = true,
    int rebootDelayMs = 500,
    PicobootProgress? onProgress,
  }) async {
    final runs = _contiguousRuns(file);
    final eraseRanges = _eraseRanges(runs);
    final totalBytes = runs.fold<int>(0, (sum, r) => sum + r.data.length);
    final totalErase = eraseRanges.fold<int>(0, (sum, r) => sum + (r.end - r.start));

    await _client.exclusiveAccess();
    await _client.exitXip();

    var erased = 0;
    onProgress?.call(PicobootPhase.erasing, 0, totalErase);
    for (final range in eraseRanges) {
      await _client.flashErase(range.start, range.end - range.start);
      erased += range.end - range.start;
      onProgress?.call(PicobootPhase.erasing, erased, totalErase);
    }

    var written = 0;
    onProgress?.call(PicobootPhase.writing, 0, totalBytes);
    for (final run in runs) {
      for (var offset = 0; offset < run.data.length; offset += chunkSize) {
        final end = offset + chunkSize < run.data.length ? offset + chunkSize : run.data.length;
        await _client.write(run.address + offset, Uint8List.sublistView(run.data, offset, end));
        written += end - offset;
        onProgress?.call(PicobootPhase.writing, written, totalBytes);
      }
    }

    if (verify) {
      // La lecture de la flash passe par le XIP, qu'il faut réactiver après l'écriture.
      await _client.enterCmdXip();
      var checked = 0;
      onProgress?.call(PicobootPhase.verifying, 0, totalBytes);
      for (final run in runs) {
        for (var offset = 0; offset < run.data.length; offset += chunkSize) {
          final end = offset + chunkSize < run.data.length ? offset + chunkSize : run.data.length;
          final actual = await _client.read(run.address + offset, end - offset);
          final mismatch = _firstDifference(Uint8List.sublistView(run.data, offset, end), actual);
          if (mismatch != null) {
            final at = run.address + offset + mismatch;
            throw ProtocolStateException(
              'La flash relue à 0x${at.toRadixString(16)} ne correspond pas au fichier.',
              code: ProtocolErrorCode.picobootVerifyFailed,
              params: {'address': at.toRadixString(16)},
            );
          }
          checked += end - offset;
          onProgress?.call(PicobootPhase.verifying, checked, totalBytes);
        }
      }
    }

    onProgress?.call(PicobootPhase.rebooting, totalBytes, totalBytes);
    await _client.reboot(delayMs: rebootDelayMs);
  }

  /// Regroupe les blocs adjacents en plages continues, complétées par 0xFF jusqu'à une page entière.
  /// Refuse ce que PICOBOOT ne sait pas écrire : hors flash, ou début de bloc mal aligné.
  static List<_Run> _contiguousRuns(Uf2File file) {
    final blocks = file.flashBlocks.toList()..sort((a, b) => a.address.compareTo(b.address));
    if (blocks.isEmpty) {
      throw const ProtocolStateException(
        'Le fichier ne contient aucune donnée à écrire en flash.',
        code: ProtocolErrorCode.picobootBadImage,
        params: {'address': '0'},
      );
    }
    final runs = <_Run>[];
    for (final block in blocks) {
      final end = block.address + block.data.length;
      if (block.address < flashBase || end > flashLimit) _badImage(block.address);
      final last = runs.isEmpty ? null : runs.last;
      if (last != null && block.address == last.address + last.bytes.length) {
        last.bytes.addAll(block.data);
      } else {
        if (last != null && block.address < last.address + last.bytes.length) _badImage(block.address); // blocs qui se chevauchent
        if (block.address % pageSize != 0) _badImage(block.address);
        runs.add(_Run(block.address)..bytes.addAll(block.data));
      }
    }
    for (final run in runs) {
      final padding = (pageSize - run.bytes.length % pageSize) % pageSize;
      run.bytes.addAll(List.filled(padding, 0xFF));
    }
    return runs;
  }

  static Never _badImage(int address) => throw ProtocolStateException(
        'Le fichier contient des données que PICOBOOT ne peut pas écrire (adresse 0x${address.toRadixString(16)}).',
        code: ProtocolErrorCode.picobootBadImage,
        params: {'address': address.toRadixString(16)},
      );

  /// Plages de secteurs à effacer : celles des données, arrondies aux secteurs, fusionnées si elles se touchent.
  static List<({int start, int end})> _eraseRanges(List<_Run> runs) {
    final ranges = <({int start, int end})>[];
    for (final run in runs) {
      final start = run.address - run.address % sectorSize;
      final end = ((run.address + run.data.length + sectorSize - 1) ~/ sectorSize) * sectorSize;
      if (ranges.isNotEmpty && start <= ranges.last.end) {
        final last = ranges.removeLast();
        ranges.add((start: last.start, end: end > last.end ? end : last.end));
      } else {
        ranges.add((start: start, end: end));
      }
    }
    return ranges;
  }

  static int? _firstDifference(Uint8List expected, Uint8List actual) {
    if (actual.length != expected.length) return actual.length < expected.length ? actual.length : expected.length;
    for (var i = 0; i < expected.length; i++) {
      if (expected[i] != actual[i]) return i;
    }
    return null;
  }
}

class _Run {
  _Run(this.address);

  final int address;
  final List<int> bytes = [];

  /// Les octets, figés au premier accès (après le remplissage de la dernière page).
  late final Uint8List data = Uint8List.fromList(bytes);
}
