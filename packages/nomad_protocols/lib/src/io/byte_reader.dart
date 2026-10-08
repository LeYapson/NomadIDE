import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../protocol_exceptions.dart';

/// Lecteur tamponné au-dessus d'un flux d'octets : « lis N octets » ou
/// « lis jusqu'à tel marqueur, avec timeout ».
///
/// Il s'abonne dès sa construction : créez-le **avant** d'envoyer la commande
/// dont vous attendez la réponse.
///
/// Un timeout ne consomme rien : les octets déjà reçus restent en tampon
/// (utile pour la resynchronisation). Appelez [discard] pour les jeter.
class ByteReader {
  ByteReader(Stream<Uint8List> source) {
    _subscription = source.listen(_onData, onError: _onError, onDone: _onDone);
  }

  late final StreamSubscription<Uint8List> _subscription;
  final List<int> _buffer = <int>[];
  Completer<void>? _signal;
  Object? _error;
  bool _done = false;

  int get available => _buffer.length;

  /// Lit exactement [count] octets. [timeout] null : attend indéfiniment.
  Future<Uint8List> read(int count, {Duration? timeout}) async {
    final clock = Stopwatch()..start();
    while (_buffer.length < count) {
      await _waitForData(clock, timeout);
    }
    return _take(count);
  }

  /// Lit jusqu'à [delimiter] inclus (exclu si [includeDelimiter] est faux).
  ///
  /// [onData] reçoit au fil de l'eau les octets qui précèdent le délimiteur
  /// (sans jamais émettre un début de délimiteur) : c'est ce qui permet
  /// d'afficher la sortie d'un programme pendant qu'il s'exécute.
  Future<Uint8List> readUntil(
    List<int> delimiter, {
    Duration? timeout,
    bool includeDelimiter = true,
    void Function(Uint8List data)? onData,
  }) async {
    assert(delimiter.isNotEmpty);
    final clock = Stopwatch()..start();
    var searchFrom = 0;
    var emitted = 0;
    while (true) {
      final index = _indexOf(delimiter, searchFrom);
      if (index >= 0) {
        final chunk = _take(index + delimiter.length);
        if (onData != null && index > emitted) {
          onData(Uint8List.fromList(Uint8List.sublistView(chunk, emitted, index)));
        }
        return includeDelimiter ? chunk : Uint8List.sublistView(chunk, 0, index);
      }
      // Un délimiteur peut être à cheval sur deux chunks : on ne rescanne que la fin.
      final safe = math.max(0, _buffer.length - delimiter.length + 1);
      if (onData != null && safe > emitted) {
        onData(Uint8List.fromList(_buffer.sublist(emitted, safe)));
        emitted = safe;
      }
      searchFrom = safe;
      await _waitForData(clock, timeout);
    }
  }

  /// Vide le tampon (ex. avant une resynchronisation).
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

  Future<void> _waitForData(Stopwatch clock, Duration? timeout) async {
    final error = _error;
    if (error != null) throw ProtocolIoException('Erreur de lecture sur le lien.', cause: error);
    if (_done) throw const ProtocolClosedException('Le lien a été fermé.');

    Duration? remaining;
    if (timeout != null) {
      remaining = timeout - clock.elapsed;
      if (remaining <= Duration.zero) throw _timeout(timeout);
    }
    final signal = _signal ??= Completer<void>();
    try {
      await (remaining == null ? signal.future : signal.future.timeout(remaining));
    } on TimeoutException {
      throw _timeout(timeout!);
    }
  }

  static ProtocolTimeoutException _timeout(Duration timeout) =>
      ProtocolTimeoutException(
        'Aucune réponse de la carte après ${timeout.inMilliseconds} ms.',
        code: ProtocolErrorCode.noResponse,
        params: {'timeoutMs': timeout.inMilliseconds},
      );

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
