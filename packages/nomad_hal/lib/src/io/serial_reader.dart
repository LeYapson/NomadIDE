import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../domain/serial_exceptions.dart';

/// Lecteur tamponné au-dessus d'un flux d'octets série.
///
/// Les protocoles (raw REPL MicroPython, esptool/SLIP, STM32 AN3155…) raisonnent
/// en « lis N octets » ou « lis jusqu'à tel marqueur, avec timeout », alors
/// qu'un port série livre des chunks de taille arbitraire. Cette classe fait le pont.
///
/// ⚠️ Elle s'abonne dès sa construction : créez-la **avant** d'envoyer la
/// commande dont vous attendez la réponse (le flux `input` est broadcast).
///
/// ```dart
/// final reader = SerialReader(conn.input);
/// await conn.write(ctrlA);                                   // entrer en raw REPL
/// await reader.readUntil(utf8.encode('raw REPL; CTRL-B to exit\r\n>'));
/// ```
class SerialReader {
  SerialReader(Stream<Uint8List> source) {
    _subscription = source.listen(_onData, onError: _onError, onDone: _onDone);
  }

  late final StreamSubscription<Uint8List> _subscription;
  final List<int> _buffer = <int>[];
  Completer<void>? _signal;
  Object? _error;
  bool _done = false;

  /// Nombre d'octets déjà reçus et pas encore consommés.
  int get available => _buffer.length;

  /// Lit exactement [count] octets.
  Future<Uint8List> read(int count, {Duration timeout = const Duration(seconds: 1)}) async {
    final clock = Stopwatch()..start();
    while (_buffer.length < count) {
      await _waitForData(clock, timeout);
    }
    return _take(count);
  }

  /// Lit jusqu'à [delimiter] inclus (ou exclu si [includeDelimiter] est faux).
  Future<Uint8List> readUntil(
    List<int> delimiter, {
    Duration timeout = const Duration(seconds: 1),
    bool includeDelimiter = true,
  }) async {
    assert(delimiter.isNotEmpty);
    final clock = Stopwatch()..start();
    var searchFrom = 0;
    while (true) {
      final index = _indexOf(delimiter, searchFrom);
      if (index >= 0) {
        final chunk = _take(index + delimiter.length);
        return includeDelimiter ? chunk : Uint8List.sublistView(chunk, 0, index);
      }
      // Le délimiteur peut être à cheval sur le prochain chunk : on ne rescanne que la fin.
      searchFrom = math.max(0, _buffer.length - delimiter.length + 1);
      await _waitForData(clock, timeout);
    }
  }

  /// Consomme tout ce qui est déjà en tampon, sans attendre.
  Uint8List takeAvailable() => _take(_buffer.length);

  /// Vide le tampon (ex. avant d'envoyer une commande, pour ignorer les logs de boot).
  void discard() => _buffer.clear();

  Future<void> cancel() => _subscription.cancel();

  void _onData(Uint8List data) {
    _buffer.addAll(data);
    _wake();
  }

  void _onError(Object error, StackTrace stackTrace) {
    _error = error;
    _wake();
  }

  void _onDone() {
    _done = true;
    _wake();
  }

  void _wake() {
    final signal = _signal;
    _signal = null;
    signal?.complete();
  }

  Future<void> _waitForData(Stopwatch clock, Duration timeout) async {
    final error = _error;
    if (error != null) {
      throw SerialIoException('Erreur de lecture sur le port série.', cause: error);
    }
    if (_done) {
      throw const SerialClosedException('Le port a été fermé pendant la lecture.');
    }
    final remaining = timeout - clock.elapsed;
    if (remaining <= Duration.zero) {
      throw SerialTimeoutException('Aucune réponse de la carte après ${timeout.inMilliseconds} ms.');
    }
    final signal = _signal ??= Completer<void>();
    try {
      await signal.future.timeout(remaining);
    } on TimeoutException {
      throw SerialTimeoutException('Aucune réponse de la carte après ${timeout.inMilliseconds} ms.');
    }
  }

  Uint8List _take(int count) {
    final out = Uint8List.fromList(_buffer.sublist(0, count));
    _buffer.removeRange(0, count);
    return out;
  }

  int _indexOf(List<int> needle, int from) {
    final last = _buffer.length - needle.length;
    outer:
    for (var i = from; i <= last; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (_buffer[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}
