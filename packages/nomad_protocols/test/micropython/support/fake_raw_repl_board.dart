import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nomad_protocols/nomad_protocols.dart';

/// Ce que « fait » un programme sur la fausse carte.
typedef BoardProgram = ({String stdout, String stderr, bool hang});

enum _Mode { friendly, raw, running }

/// Fausse carte MicroPython qui parle le raw REPL (voir le déroulé dans `RawRepl`).
///
/// [run] simule l'interpréteur : il reçoit le code reçu et décrit sa sortie.
/// Les réponses sont livrées de façon asynchrone, par petits chunks, pour
/// éprouver les chevauchements de délimiteurs.
class FakeRawReplBoard implements ByteLink {
  FakeRawReplBoard({
    required this.run,
    this.outputChunkSize = 3,
    this.silentEnterAttempts = 0,
  });

  final BoardProgram Function(String code) run;
  final int outputChunkSize;

  /// Nombre de Ctrl-A à ignorer (carte occupée à booter) avant de répondre.
  int silentEnterAttempts;

  /// Tout ce que l'hôte a écrit, un élément par appel à [write].
  final List<Uint8List> writes = [];

  final StreamController<Uint8List> _input = StreamController<Uint8List>.broadcast();
  final List<int> _code = [];
  _Mode _mode = _Mode.friendly;

  bool get isRaw => _mode != _Mode.friendly;

  @override
  Stream<Uint8List> get input => _input.stream;

  @override
  Future<void> write(Uint8List data) async {
    writes.add(Uint8List.fromList(data));
    for (final byte in data) {
      _onByte(byte);
    }
  }

  /// Simule le débranchement du câble.
  void unplug() => _input.close();

  void _onByte(int byte) {
    if (byte == 0x01 && _mode != _Mode.running) {
      // Ctrl-A : (ré)entre en raw REPL, même s'il y est déjà.
      if (silentEnterAttempts > 0) {
        silentEnterAttempts--;
        return;
      }
      _mode = _Mode.raw;
      _code.clear();
      _emit('raw REPL; CTRL-B to exit\r\n>');
      return;
    }

    switch (_mode) {
      case _Mode.friendly:
        if (byte == 0x03) _emit('\r\n>>> ');
      case _Mode.raw:
        switch (byte) {
          case 0x04:
            if (_code.isEmpty) return; // soft reboot : hors périmètre
            _execute(utf8.decode(_code));
            _code.clear();
          case 0x02:
            _mode = _Mode.friendly;
            _emit('\r\nMicroPython (fake)\r\n>>> ');
          case 0x03:
            _code.clear();
          default:
            _code.add(byte);
        }
      case _Mode.running:
        if (byte == 0x03) {
          _mode = _Mode.raw;
          _emit('\x04Traceback (most recent call last):\r\nKeyboardInterrupt:\r\n\x04>');
        }
    }
  }

  void _execute(String code) {
    final program = run(code);
    _emit('OK${program.stdout}');
    if (program.hang) {
      _mode = _Mode.running; // la suite n'arrive qu'avec un Ctrl-C
    } else {
      _emit('\x04${program.stderr}\x04>');
    }
  }

  void _emit(String text) {
    final bytes = utf8.encode(text);
    for (var i = 0; i < bytes.length; i += outputChunkSize) {
      final end = i + outputChunkSize < bytes.length ? i + outputChunkSize : bytes.length;
      final chunk = Uint8List.fromList(bytes.sublist(i, end));
      // Timer.run : file FIFO, l'ordre des octets est préservé.
      Timer.run(() {
        if (!_input.isClosed) _input.add(chunk);
      });
    }
  }
}
