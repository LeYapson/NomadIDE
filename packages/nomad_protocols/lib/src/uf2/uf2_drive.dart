import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'uf2_file.dart';

/// Disque de stockage exposé par un bootloader UF2 (BOOTSEL du RP2040, bootloader Adafruit…).
class Uf2Drive {
  const Uf2Drive({required this.path, required this.boardId, required this.model, this.version});

  /// Racine du disque (`E:\`, `/media/user/RPI-RP2`, `/Volumes/RPI-RP2`).
  final String path;

  /// Identifiant de carte annoncé par `INFO_UF2.TXT` (ex. `RPI-RP2`, `RP2350`).
  final String boardId;

  /// Ligne « Model » de `INFO_UF2.TXT` (ex. `Raspberry Pi RP2`).
  final String model;
  final String? version;

  /// Vrai pour le BOOTSEL d'un RP2040 / RP2350.
  bool get isRaspberryPi => boardId.startsWith('RPI-RP2') || boardId.startsWith('RP2350');

  /// Lit `INFO_UF2.TXT` ; renvoie `null` si [text] n'en est pas un.
  static Uf2Drive? parseInfo(String path, String text) {
    String? field(String name) {
      final m = RegExp('^$name:\\s*(.+?)\\s*\$', multiLine: true).firstMatch(text);
      return m?.group(1);
    }

    final boardId = field('Board-ID');
    if (boardId == null) return null;
    final version = RegExp(r'^UF2 Bootloader\s+(\S+)', multiLine: true).firstMatch(text)?.group(1);
    return Uf2Drive(path: path, boardId: boardId, model: field('Model') ?? '', version: version);
  }

  @override
  String toString() => 'Uf2Drive($path, $boardId)';
}

/// Où chercher les disques UF2. Remplaçable dans les tests.
typedef Uf2Roots = Future<List<String>> Function();

/// Racines possibles selon le système : lettres de lecteurs (Windows), points de montage ailleurs.
Future<List<String>> defaultUf2Roots() async {
  if (Platform.isWindows) {
    return [
      for (var c = 'D'.codeUnitAt(0); c <= 'Z'.codeUnitAt(0); c++) '${String.fromCharCode(c)}:\\',
    ];
  }
  final roots = <String>[];
  final bases = Platform.isMacOS
      ? ['/Volumes']
      : ['/media/${Platform.environment['USER'] ?? ''}', '/run/media/${Platform.environment['USER'] ?? ''}', '/media', '/mnt'];
  for (final base in bases) {
    final dir = Directory(base);
    if (!await dir.exists()) continue;
    try {
      await for (final e in dir.list(followLinks: false)) {
        if (e is Directory) roots.add(e.path);
      }
    } on FileSystemException {
      // dossier illisible : on passe au suivant
    }
  }
  return roots;
}

/// Détecte les disques UF2 branchés, et copie un fichier dessus.
class Uf2Flasher {
  Uf2Flasher({Uf2Roots? roots, this.chunkSize = 16 * 1024}) : _roots = roots ?? defaultUf2Roots;

  final Uf2Roots _roots;

  /// Taille des écritures : assez petite pour une barre de progression régulière.
  final int chunkSize;

  /// Disques UF2 actuellement visibles.
  Future<List<Uf2Drive>> findDrives() async {
    final found = <Uf2Drive>[];
    for (final root in await _roots()) {
      final info = File(_join(root, 'INFO_UF2.TXT'));
      try {
        if (!await info.exists()) continue;
        final drive = Uf2Drive.parseInfo(root, await info.readAsString());
        if (drive != null) found.add(drive);
      } on FileSystemException {
        // lecteur vide ou occupé
      }
    }
    return found;
  }

  /// Attend qu'un disque UF2 apparaisse (ex. après le touch 1200 bauds).
  /// Renvoie `null` si rien n'est apparu au bout de [timeout].
  Future<Uf2Drive?> waitForDrive({
    Duration timeout = const Duration(seconds: 10),
    Duration poll = const Duration(milliseconds: 250),
    bool Function(Uf2Drive)? where,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      for (final d in await findDrives()) {
        if (where == null || where(d)) return d;
      }
      if (DateTime.now().isAfter(deadline)) return null;
      await Future<void>.delayed(poll);
    }
  }

  /// Copie [file] sur [drive], puis attend que la carte redémarre (le disque disparaît).
  ///
  /// Le bootloader redémarre dès qu'il a reçu tous les blocs : le disque qui disparaît est la seule
  /// confirmation que la carte a accepté le programme.
  Future<Uf2FlashResult> flash(
    Uf2File file,
    Uf2Drive drive, {
    String fileName = 'firmware.uf2',
    void Function(int written, int total)? onProgress,
    Duration rebootTimeout = const Duration(seconds: 15),
    Duration poll = const Duration(milliseconds: 250),
  }) async {
    final target = File(_join(drive.path, fileName));
    final total = file.bytes.length;
    IOSink? sink;
    var written = 0;
    try {
      sink = target.openWrite();
      onProgress?.call(0, total);
      for (var offset = 0; offset < total; offset += chunkSize) {
        final end = offset + chunkSize < total ? offset + chunkSize : total;
        sink.add(Uint8List.sublistView(file.bytes, offset, end));
        await sink.flush();
        written = end;
        onProgress?.call(written, total);
      }
      await sink.close();
      sink = null;
    } on FileSystemException catch (e) {
      // La carte peut déjà être partie si l'erreur arrive à la toute fin de la copie.
      if (written >= total && !await _driveStillThere(drive)) return Uf2FlashResult.rebooted;
      throw Uf2CopyException(drive, written, total, e);
    } finally {
      if (sink != null) {
        try {
          await sink.close();
        } on Object {
          // la carte a disparu pendant la fermeture : rien à fermer
        }
      }
    }

    final deadline = DateTime.now().add(rebootTimeout);
    while (await _driveStillThere(drive)) {
      if (DateTime.now().isAfter(deadline)) return Uf2FlashResult.copiedNoReboot;
      await Future<void>.delayed(poll);
    }
    return Uf2FlashResult.rebooted;
  }

  Future<bool> _driveStillThere(Uf2Drive drive) async {
    try {
      return await File(_join(drive.path, 'INFO_UF2.TXT')).exists();
    } on FileSystemException {
      return false;
    }
  }

  static String _join(String root, String name) =>
      root.endsWith('/') || root.endsWith('\\') ? '$root$name' : '$root${Platform.pathSeparator}$name';
}

enum Uf2FlashResult {
  /// Copie terminée et disque disparu : la carte exécute le nouveau programme.
  rebooted,

  /// Copie terminée mais le disque est toujours là : le bootloader n'a pas redémarré
  /// (fichier refusé, mauvaise famille de puce…).
  copiedNoReboot,
}

/// La copie a échoué (disque retiré, plein, protégé en écriture).
class Uf2CopyException implements Exception {
  const Uf2CopyException(this.drive, this.written, this.total, this.cause);

  final Uf2Drive drive;
  final int written;
  final int total;
  final Object cause;

  @override
  String toString() => 'Uf2CopyException: copie interrompue à $written / $total octets sur ${drive.path} ($cause)';
}
