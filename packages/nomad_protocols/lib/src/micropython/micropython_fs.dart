import 'dart:convert';
import 'dart:typed_data';

import '../protocol_exceptions.dart';
import 'raw_repl.dart';

/// Entrée d'un répertoire de la carte.
class RemoteEntry {
  const RemoteEntry(this.name, {required this.isDirectory, this.size});

  final String name;
  final bool isDirectory;

  /// Taille en octets ; null si le port MicroPython ne la fournit pas.
  final int? size;

  @override
  String toString() => isDirectory ? '$name/' : '$name (${size ?? '?'} o)';
}

/// Système de fichiers de la carte, piloté par du Python envoyé au [RawRepl].
///
/// Le contenu des fichiers transite en base64 : le raw REPL n'est pas
/// transparent aux octets (Ctrl-D, Ctrl-C, UTF-8 invalide).
class MicroPythonFs {
  MicroPythonFs(this._repl, {this.chunkSize = 384, this.timeout = const Duration(seconds: 10)})
      : assert(chunkSize > 0);

  final RawRepl _repl;

  /// Octets de fichier par appel `execute` lors d'une écriture.
  final int chunkSize;

  /// Délai de chaque appel `execute`.
  final Duration timeout;

  static const _b64Import = 'try:\n import binascii as b\nexcept ImportError:\n import ubinascii as b\n';

  Future<List<RemoteEntry>> list(String path) async {
    final out = await _run(
      'import os\n'
      'for e in os.ilistdir(${_py(path)}):\n'
      " print('d' if e[1]&0x4000 else 'f',e[3] if len(e)>3 else -1,e[0],sep='|')\n",
    );
    final entries = <RemoteEntry>[];
    for (final line in const LineSplitter().convert(out)) {
      final parts = line.split('|');
      if (parts.length < 3) continue;
      final size = int.tryParse(parts[1]);
      entries.add(RemoteEntry(
        parts.sublist(2).join('|'),
        isDirectory: parts[0] == 'd',
        size: size == null || size < 0 ? null : size,
      ));
    }
    return entries;
  }

  Future<bool> exists(String path) async {
    try {
      await _run('import os\nos.stat(${_py(path)})\n');
      return true;
    } on ProtocolRemoteException catch (e) {
      if (e.isNotFound) return false;
      rethrow;
    }
  }

  /// Lit un fichier. [onProgress] reçoit le nombre d'octets lus.
  Future<Uint8List> read(String path, {void Function(int bytes)? onProgress}) async {
    final builder = BytesBuilder(copy: false);
    var pending = '';
    void consume(String text) {
      final line = text.trim();
      if (line.isNotEmpty) builder.add(base64Decode(line));
    }

    await _run(
      'import os\n$_b64Import'
      "with open(${_py(path)},'rb') as f:\n"
      ' while True:\n'
      '  d=f.read(240)\n'
      '  if not d:break\n'
      '  print(b.b2a_base64(d).strip().decode())\n',
      onStdout: (data) {
        pending += utf8.decode(data, allowMalformed: true);
        final cut = pending.lastIndexOf('\n');
        if (cut < 0) return;
        const LineSplitter().convert(pending.substring(0, cut)).forEach(consume);
        pending = pending.substring(cut + 1);
        onProgress?.call(builder.length);
      },
    );
    consume(pending);
    return builder.takeBytes();
  }

  /// Écrit (crée ou remplace) un fichier, par morceaux de [chunkSize] octets.
  ///
  /// Avec [verify], la carte recalcule la taille et le CRC32 du fichier écrit :
  /// en cas d'écart (octets perdus sur le lien USB, par exemple) l'écriture est
  /// recommencée jusqu'à [retries] fois, puis [ProtocolIntegrityException] est levée.
  Future<void> write(
    String path,
    Uint8List data, {
    void Function(int sent, int total)? onProgress,
    bool verify = false,
    int retries = 1,
  }) async {
    for (var attempt = 0;; attempt++) {
      try {
        await _writeOnce(path, data, onProgress);
        if (verify) await _verify(path, data);
        return;
      } on ProtocolIntegrityException {
        if (attempt >= retries) rethrow;
      } on ProtocolRemoteException catch (e) {
        // Une erreur sans errno (base64 altéré, SyntaxError…) vient du lien ; une
        // erreur d'OS (dossier absent, disque plein) se reproduirait à l'identique.
        if (e.errno != null || attempt >= retries) rethrow;
      }
    }
  }

  Future<void> _writeOnce(String path, Uint8List data, void Function(int sent, int total)? onProgress) async {
    var offset = 0;
    do {
      final end = offset + chunkSize < data.length ? offset + chunkSize : data.length;
      final mode = offset == 0 ? 'wb' : 'ab';
      await _run(
        '$_b64Import'
        "with open(${_py(path)},'$mode') as f:\n"
        " f.write(b.a2b_base64('${base64Encode(data.sublist(offset, end))}'))\n",
      );
      offset = end;
      onProgress?.call(offset, data.length);
    } while (offset < data.length);
  }

  Future<void> _verify(String path, Uint8List data) async {
    final remote = await checksum(path);
    final expected = crc32(data);
    if (remote.size != data.length || remote.crc32 != expected) {
      throw ProtocolIntegrityException(
        'Écriture corrompue sur $path : attendu ${data.length} o / CRC ${expected.toRadixString(16)}, '
        'reçu ${remote.size} o / CRC ${remote.crc32.toRadixString(16)}.',
        expectedCrc: expected,
        actualCrc: remote.crc32,
        params: {'path': path, 'expectedSize': data.length, 'actualSize': remote.size},
      );
    }
  }

  /// Taille et CRC32 d'un fichier, calculés par la carte (rien ne transite par le lien).
  Future<({int size, int crc32})> checksum(String path) async {
    final out = await _run(
      'import os\n$_b64Import'
      'c=0\n'
      "with open(${_py(path)},'rb') as f:\n"
      ' while True:\n'
      '  d=f.read(512)\n'
      '  if not d:break\n'
      '  c=b.crc32(d,c)\n'
      "print(os.stat(${_py(path)})[6],c)\n",
    );
    final parts = out.trim().split(RegExp(r'\s+'));
    final size = parts.length == 2 ? int.tryParse(parts[0]) : null;
    final crc = parts.length == 2 ? int.tryParse(parts[1]) : null;
    if (size == null || crc == null) {
      throw ProtocolDesyncException(
        'Réponse inattendue au calcul du CRC : « ${out.trim()} ».',
        code: ProtocolErrorCode.unexpectedCrcReply,
        params: {'reply': out.trim()},
      );
    }
    return (size: size, crc32: crc & 0xFFFFFFFF);
  }

  /// CRC32 (polynôme IEEE 802.3), identique à `binascii.crc32` de MicroPython et CPython.
  static int crc32(List<int> data, [int crc = 0]) {
    var c = crc ^ 0xFFFFFFFF;
    for (final byte in data) {
      c = _crcTable[(c ^ byte) & 0xFF] ^ (c >>> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  static final List<int> _crcTable = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    }
    return c;
  });

  Future<void> remove(String path) => _run('import os\nos.remove(${_py(path)})\n');

  Future<void> mkdir(String path) => _run('import os\nos.mkdir(${_py(path)})\n');

  Future<void> rmdir(String path) => _run('import os\nos.rmdir(${_py(path)})\n');

  Future<void> rename(String from, String to) => _run('import os\nos.rename(${_py(from)},${_py(to)})\n');

  Future<String> _run(String code, {void Function(Uint8List data)? onStdout}) async {
    final result = await _repl.execute(code, timeout: timeout, onStdout: onStdout);
    if (!result.ok) {
      final trace = result.stderrText.trim();
      final errno = RegExp(r'OSError: (?:\[Errno )?(\d+)').firstMatch(trace)?.group(1);
      throw ProtocolRemoteException(
        trace.split('\n').last.trim(),
        stderr: trace,
        errno: errno == null ? null : int.parse(errno),
      );
    }
    return result.stdoutText;
  }

  /// Littéral chaîne Python sûr (guillemets simples, échappements).
  static String _py(String s) {
    final escaped = s
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r');
    return "'$escaped'";
  }
}
