import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../io/byte_link.dart';
import '../io/byte_reader.dart';
import '../protocol_exceptions.dart';

// Caractères de contrôle du REPL MicroPython.
const int _ctrlA = 0x01; // entrer en raw REPL
const int _ctrlB = 0x02; // retour au REPL interactif
const int _ctrlC = 0x03; // interrompre
const int _ctrlD = 0x04; // fin du code (raw REPL) / séparateur des sorties
const int _cr = 0x0D;

final List<int> _banner = utf8.encode('raw REPL; CTRL-B to exit\r\n>');
final List<int> _friendlyPrompt = utf8.encode('>>> ');
const List<int> _eot = [_ctrlD];
const List<int> _prompt = [0x3E]; // '>'

/// Fin d'un programme interrompu : terminateur de stderr suivi de l'invite.
const List<int> _interruptTail = [_ctrlD, 0x3E];

/// Réglages temporels. Les valeurs par défaut sont celles de `mpremote`.
class RawReplOptions {
  const RawReplOptions({
    this.settleDelay = const Duration(milliseconds: 50),
    this.enterTimeout = const Duration(seconds: 3),
    this.enterAttempts = 3,
    this.ackTimeout = const Duration(seconds: 2),
    this.interruptTimeout = const Duration(seconds: 2),
    this.chunkSize = 256,
    this.chunkDelay = const Duration(milliseconds: 10),
  })  : assert(enterAttempts > 0),
        assert(chunkSize > 0);

  /// Pause entre l'interruption (Ctrl-C) et la purge du tampon d'entrée.
  final Duration settleDelay;

  /// Attente de la bannière raw REPL, par tentative.
  final Duration enterTimeout;
  final int enterAttempts;

  /// Attente des réponses courtes : « OK », invite `>`.
  final Duration ackTimeout;

  /// Attente de la fin d'un programme après Ctrl-C.
  final Duration interruptTimeout;

  /// Le code est envoyé par morceaux : les UART sans contrôle de flux
  /// (ESP8266, certaines cartes STM32) perdent des octets sinon.
  final int chunkSize;
  final Duration chunkDelay;
}

/// Résultat d'une exécution : stdout et stderr sont séparés par le protocole.
class ExecResult {
  const ExecResult(this.stdout, this.stderr);

  final Uint8List stdout;
  final Uint8List stderr;

  /// Faux si le programme a levé une exception (la trace est dans [stderr]).
  bool get ok => stderr.isEmpty;

  String get stdoutText => utf8.decode(stdout, allowMalformed: true);
  String get stderrText => utf8.decode(stderr, allowMalformed: true);
}

enum RawReplState {
  /// Pas en raw REPL : appeler [RawRepl.enter].
  inactive,

  /// Prêt à exécuter.
  ready,

  /// Une exécution est en cours.
  busy,

  /// Désynchronisé (timeout, réponse inattendue) : rappeler [RawRepl.enter].
  broken,
}

/// Client du raw REPL MicroPython.
///
/// Déroulé du protocole (identique à `pyboard.py` / `mpremote`) :
///
/// ```text
/// entrer :  \r \x03 \x03   interrompt le programme en cours
///           \r \x01        Ctrl-A → "raw REPL; CTRL-B to exit\r\n>"
/// exécuter: <code> \x04    envoi du code, fin par Ctrl-D
///           "OK" <stdout> \x04 <stderr> \x04 ">"
/// sortir :  \x02           Ctrl-B → retour au REPL interactif (">>> ")
/// ```
///
/// L'invite `>` finale est consommée à la fin de chaque [execute] : entre deux
/// appels, le tampon est vide et le protocole synchronisé.
///
/// ⚠️ Le [ByteLink] est partagé avec le moniteur série : pendant une session
/// raw REPL, l'application doit suspendre l'affichage du flux brut.
class RawRepl {
  RawRepl(ByteLink link, {this.options = const RawReplOptions()})
      : _link = link,
        _reader = ByteReader(link.input);

  final ByteLink _link;
  final ByteReader _reader;
  final RawReplOptions options;
  RawReplState _state = RawReplState.inactive;

  RawReplState get state => _state;

  bool get isActive => _state == RawReplState.ready || _state == RawReplState.busy;

  /// Entre en raw REPL. Réessaie [RawReplOptions.enterAttempts] fois, car la
  /// carte peut être occupée à booter ou à exécuter `main.py`.
  ///
  /// Utilisable depuis n'importe quel état : sert aussi à se resynchroniser.
  Future<void> enter() async {
    if (_state == RawReplState.busy) {
      throw const ProtocolStateException('Une exécution est en cours.');
    }
    try {
      for (var attempt = 1; attempt <= options.enterAttempts; attempt++) {
        await _link.write(_bytes([_cr, _ctrlC, _ctrlC]));
        await Future<void>.delayed(options.settleDelay);
        _reader.discard();
        await _link.write(_bytes([_cr, _ctrlA]));
        try {
          await _reader.readUntil(_banner, timeout: options.enterTimeout);
          _state = RawReplState.ready;
          return;
        } on ProtocolTimeoutException {
          // On réessaie ; l'échec définitif est signalé après la boucle.
        }
      }
      _state = RawReplState.broken;
      throw ProtocolTimeoutException(
        'La carte ne passe pas en raw REPL après ${options.enterAttempts} tentatives. '
        "Vérifiez qu'il s'agit bien d'une carte MicroPython et que le port n'est pas utilisé ailleurs.",
      );
    } on ProtocolClosedException {
      _state = RawReplState.inactive;
      rethrow;
    }
  }

  /// Exécute [code] et renvoie sa sortie.
  ///
  /// [timeout] borne la durée du **programme** (null : illimité). À
  /// l'expiration, il est interrompu (Ctrl-C), la session est resynchronisée
  /// et une [ProtocolTimeoutException] est levée avec la sortie partielle.
  ///
  /// [onStdout] / [onStderr] reçoivent les octets au fil de l'eau, avant la fin.
  Future<ExecResult> execute(
    String code, {
    Duration? timeout = const Duration(seconds: 10),
    void Function(Uint8List data)? onStdout,
    void Function(Uint8List data)? onStderr,
  }) async {
    switch (_state) {
      case RawReplState.inactive:
        throw const ProtocolStateException('Raw REPL inactif : appelez enter() d\'abord.');
      case RawReplState.busy:
        throw const ProtocolStateException('Une exécution est déjà en cours.');
      case RawReplState.broken:
        throw const ProtocolStateException('Session désynchronisée : appelez enter() pour la rétablir.');
      case RawReplState.ready:
        break;
    }
    _state = RawReplState.busy;

    final stdoutSoFar = BytesBuilder();
    var running = false;
    try {
      await _sendCode(utf8.encode(code));
      await _link.write(_bytes(_eot));

      final ack = await _reader.read(2, timeout: options.ackTimeout);
      if (ack[0] != 0x4F || ack[1] != 0x4B) {
        // 'O', 'K'
        _state = RawReplState.broken;
        throw ProtocolDesyncException('Réponse inattendue au lieu de « OK » : ${_hex(ack)}.', received: ack);
      }

      running = true;
      final clock = Stopwatch()..start();
      Duration? remaining() => timeout == null ? null : timeout - clock.elapsed;

      final out = await _reader.readUntil(
        _eot,
        timeout: remaining(),
        includeDelimiter: false,
        onData: (data) {
          stdoutSoFar.add(data);
          onStdout?.call(data);
        },
      );
      final err = await _reader.readUntil(
        _eot,
        timeout: remaining(),
        includeDelimiter: false,
        onData: onStderr,
      );
      running = false;
      await _reader.readUntil(_prompt, timeout: options.ackTimeout);

      _state = RawReplState.ready;
      return ExecResult(out, err);
    } on ProtocolTimeoutException {
      if (!running) {
        _state = RawReplState.broken;
        rethrow;
      }
      await _interruptAndResync();
      throw ProtocolTimeoutException(
        'Le programme a dépassé ${timeout!.inMilliseconds} ms et a été interrompu.',
        partialOutput: stdoutSoFar.takeBytes(),
      );
    } on ProtocolClosedException {
      _state = RawReplState.inactive;
      rethrow;
    } catch (_) {
      if (_state == RawReplState.busy) _state = RawReplState.broken;
      rethrow;
    }
  }

  /// Envoie Ctrl-C au programme en cours : [execute] se termine alors normalement,
  /// avec une trace `KeyboardInterrupt` dans stderr. Sans effet hors exécution.
  Future<void> interrupt() async {
    if (_state != RawReplState.busy) return;
    await _link.write(_bytes([_ctrlC]));
  }

  /// Quitte le raw REPL (Ctrl-B) et attend l'invite interactive `>>> `.
  Future<void> exit() async {
    if (_state == RawReplState.inactive) return;
    if (_state == RawReplState.busy) {
      throw const ProtocolStateException('Une exécution est en cours.');
    }
    try {
      _reader.discard();
      await _link.write(_bytes([_ctrlB]));
      await _reader.readUntil(_friendlyPrompt, timeout: options.ackTimeout);
    } finally {
      _state = RawReplState.inactive;
    }
  }

  /// Libère l'abonnement au lien (qui, lui, reste ouvert).
  Future<void> dispose() async {
    _state = RawReplState.inactive;
    await _reader.cancel();
  }

  Future<void> _sendCode(List<int> code) async {
    for (var offset = 0; offset < code.length; offset += options.chunkSize) {
      final end = offset + options.chunkSize < code.length ? offset + options.chunkSize : code.length;
      await _link.write(_bytes(code.sublist(offset, end)));
      if (end < code.length && options.chunkDelay > Duration.zero) {
        await Future<void>.delayed(options.chunkDelay);
      }
    }
  }

  /// Ctrl-C sur un programme en cours : MicroPython affiche la trace
  /// `KeyboardInterrupt` sur stderr, puis `\x04` et l'invite `>`.
  Future<void> _interruptAndResync() async {
    try {
      await _link.write(_bytes([_ctrlC]));
      await _reader.readUntil(_interruptTail, timeout: options.interruptTimeout);
      _state = RawReplState.ready;
    } on ProtocolClosedException {
      _state = RawReplState.inactive;
    } on ProtocolException {
      _state = RawReplState.broken;
    }
  }

  static Uint8List _bytes(List<int> data) => Uint8List.fromList(data);

  static String _hex(List<int> data) => data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}
