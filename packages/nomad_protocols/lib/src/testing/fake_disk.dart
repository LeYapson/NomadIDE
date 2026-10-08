import 'dart:convert';
import 'dart:typed_data';

import '../micropython/micropython_fs.dart';

import 'fake_raw_repl_board.dart';

String _unq(String s) => s.replaceAll(r"\'", "'").replaceAll(r'\\', r'\');

String _oserr(int errno, String name) =>
    'Traceback (most recent call last):\r\n  File "<stdin>", line 1, in <module>\r\nOSError: [Errno $errno] $name\r\n';

const _lit = r"((?:[^'\\]|\\.)*)";

/// Mini interpréteur du Python généré par `MicroPythonFs`, sur un faux disque.
class FakeDisk {
  final Map<String, Uint8List> files = {};
  final Set<String> dirs = {'/'};

  /// Nombre de prochains morceaux écrits dont un octet sera altéré (lien défaillant).
  int corruptWrites = 0;

  /// Nombre de prochains morceaux écrits qui lèvent une erreur Python sans errno.
  int garbledWrites = 0;

  BoardProgram run(String code) {
    BoardProgram ok(String out) => (stdout: out, stderr: '', hang: false);
    BoardProgram fail(int errno, String name) => (stdout: '', stderr: _oserr(errno, name), hang: false);
    String? arg(String pattern) => RegExp(pattern).firstMatch(code)?.group(1);

    final listPath = arg("os\\.ilistdir\\('$_lit'\\)");
    if (listPath != null) {
      final dir = _unq(listPath);
      if (!dirs.contains(dir)) return fail(2, 'ENOENT');
      final prefix = dir.endsWith('/') ? dir : '$dir/';
      final lines = <String, String>{};
      for (final f in files.keys.where((k) => k.startsWith(prefix))) {
        final rest = f.substring(prefix.length);
        if (!rest.contains('/')) lines[rest] = 'f|${files[f]!.length}|$rest';
      }
      for (final d in dirs.where((k) => k != dir && k.startsWith(prefix))) {
        final rest = d.substring(prefix.length);
        if (!rest.contains('/')) lines[rest] = 'd|-1|$rest';
      }
      return ok(lines.values.map((l) => '$l\r\n').join());
    }

    if (code.contains('crc32(')) {
      final crcPath = arg("open\\('$_lit','rb'\\)");
      final data = crcPath == null ? null : files[_unq(crcPath)];
      if (data == null) return fail(2, 'ENOENT');
      return ok('${data.length} ${MicroPythonFs.crc32(data)}\r\n');
    }

    final statPath = arg("os\\.stat\\('$_lit'\\)");
    if (statPath != null) {
      final p = _unq(statPath);
      return files.containsKey(p) || dirs.contains(p) ? ok('') : fail(2, 'ENOENT');
    }

    final readPath = arg("open\\('$_lit','rb'\\)");
    if (readPath != null) {
      final data = files[_unq(readPath)];
      if (data == null) return fail(2, 'ENOENT');
      final out = StringBuffer();
      for (var i = 0; i < data.length; i += 240) {
        final end = i + 240 < data.length ? i + 240 : data.length;
        out.write('${base64Encode(data.sublist(i, end))}\r\n');
      }
      return ok(out.toString());
    }

    final write = RegExp("open\\('$_lit','(wb|ab)'\\)[\\s\\S]*a2b_base64\\('([^']*)'\\)").firstMatch(code);
    if (write != null) {
      if (garbledWrites > 0) {
        garbledWrites--;
        return (
          stdout: '',
          stderr: 'Traceback (most recent call last):\r\n  File "<stdin>", line 6, in <module>\r\nValueError: invalid base64\r\n',
          hang: false,
        );
      }
      final path = _unq(write.group(1)!);
      final chunk = base64Decode(write.group(3)!);
      if (corruptWrites > 0 && chunk.isNotEmpty) {
        corruptWrites--;
        chunk[0] ^= 0xFF;
      }
      final previous = write.group(2) == 'ab' ? (files[path] ?? Uint8List(0)) : Uint8List(0);
      files[path] = Uint8List.fromList([...previous, ...chunk]);
      return ok('');
    }

    final remove = arg("os\\.remove\\('$_lit'\\)");
    if (remove != null) return files.remove(_unq(remove)) == null ? fail(2, 'ENOENT') : ok('');

    final mkdir = arg("os\\.mkdir\\('$_lit'\\)");
    if (mkdir != null) return dirs.add(_unq(mkdir)) ? ok('') : fail(17, 'EEXIST');

    final rmdir = arg("os\\.rmdir\\('$_lit'\\)");
    if (rmdir != null) return dirs.remove(_unq(rmdir)) ? ok('') : fail(2, 'ENOENT');

    final rename = RegExp("os\\.rename\\('$_lit','$_lit'\\)").firstMatch(code);
    if (rename != null) {
      final data = files.remove(_unq(rename.group(1)!));
      if (data == null) return fail(2, 'ENOENT');
      files[_unq(rename.group(2)!)] = data;
      return ok('');
    }
    return ok('');
  }
}
