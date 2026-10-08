import 'dart:convert';
import 'dart:typed_data';

import 'package:nomad_protocols/nomad_protocols.dart';
import 'package:test/test.dart';

import 'support/fake_raw_repl_board.dart';

/// Délais réduits : les tests ne doivent pas dormir.
const fast = RawReplOptions(
  settleDelay: Duration.zero,
  enterTimeout: Duration(milliseconds: 100),
  ackTimeout: Duration(milliseconds: 200),
  interruptTimeout: Duration(milliseconds: 200),
  chunkDelay: Duration.zero,
);

/// Mini interpréteur de la fausse carte.
BoardProgram interpret(String code) {
  if (code.contains('while True')) return (stdout: 'tick\n', stderr: '', hang: true);
  if (code.contains('raise')) {
    return (
      stdout: '',
      stderr: 'Traceback (most recent call last):\r\n  File "<stdin>", line 1, in <module>\r\nException: boom\r\n',
      hang: false,
    );
  }
  final print = RegExp(r'''^print\(["'](.*)["']\)$''').firstMatch(code.trim());
  if (print != null) return (stdout: '${print.group(1)}\r\n', stderr: '', hang: false);
  return (stdout: '', stderr: '', hang: false);
}

void main() {
  late FakeRawReplBoard board;
  late RawRepl repl;

  RawRepl newRepl([RawReplOptions options = fast]) => repl = RawRepl(board, options: options);

  setUp(() {
    board = FakeRawReplBoard(run: interpret);
    newRepl();
  });

  tearDown(() => repl.dispose());

  group('enter', () {
    test('interrompt le programme puis envoie Ctrl-A et attend la bannière', () async {
      await repl.enter();

      expect(repl.state, RawReplState.ready);
      expect(repl.isActive, isTrue);
      expect(board.isRaw, isTrue);
      expect(board.writes.map((w) => w.toList()), [
        [0x0D, 0x03, 0x03],
        [0x0D, 0x01],
      ]);
    });

    test('réessaie quand la carte est occupée à booter', () async {
      board.silentEnterAttempts = 1;

      await repl.enter();

      expect(repl.state, RawReplState.ready);
      expect(board.writes, hasLength(4)); // deux tentatives × (interruption + Ctrl-A)
    });

    test('échoue en timeout si la carte ne répond jamais', () async {
      board.silentEnterAttempts = 99;

      await expectLater(repl.enter(), throwsA(isA<ProtocolTimeoutException>()));
      expect(repl.state, RawReplState.broken);
    });
  });

  group('execute', () {
    setUp(() => repl.enter());

    test('renvoie la sortie standard, UTF-8 compris, et reste utilisable', () async {
      final first = await repl.execute('print("héllo")');
      final second = await repl.execute("print('suite')");

      expect(first.ok, isTrue);
      expect(first.stdoutText, 'héllo\r\n');
      expect(second.stdoutText, 'suite\r\n'); // l'invite finale a bien été consommée
      expect(repl.state, RawReplState.ready);
    });

    test('sépare stderr de stdout quand le programme lève une exception', () async {
      final result = await repl.execute('raise Exception("boom")');

      expect(result.ok, isFalse);
      expect(result.stdoutText, isEmpty);
      expect(result.stderrText, contains('Exception: boom'));
      expect(repl.state, RawReplState.ready);
    });

    test('envoie le code par morceaux puis Ctrl-D', () async {
      final chunked = newRepl(const RawReplOptions(
        settleDelay: Duration.zero,
        chunkSize: 4,
        chunkDelay: Duration.zero,
      ));
      await chunked.enter();
      board.writes.clear();

      await chunked.execute('print("hello world")'); // 20 octets

      expect(board.writes.map((w) => w.length), [4, 4, 4, 4, 4, 1]);
      expect(board.writes.last, [0x04]);
      final sent = board.writes.take(5).expand((w) => w).toList();
      expect(utf8.decode(sent), 'print("hello world")');
    });

    test('livre la sortie au fil de l\'eau', () async {
      final chunks = <int>[];
      final result = await repl.execute('print("abcdefghij")', onStdout: chunks.addAll);

      expect(utf8.decode(chunks), 'abcdefghij\r\n');
      expect(result.stdoutText, 'abcdefghij\r\n');
    });

    test('interrompt un programme trop long, garde la sortie partielle et se resynchronise', () async {
      await expectLater(
        repl.execute('while True: pass', timeout: const Duration(milliseconds: 100)),
        throwsA(
          isA<ProtocolTimeoutException>().having(
            (e) => utf8.decode(e.partialOutput ?? Uint8List(0)),
            'partialOutput',
            contains('tick'),
          ),
        ),
      );

      expect(repl.state, RawReplState.ready);
      expect((await repl.execute('print("vivant")')).stdoutText, 'vivant\r\n');
    });

    test('lève ProtocolClosedException si la carte est débranchée pendant l\'exécution', () async {
      final pending = repl.execute('while True: pass', timeout: null);
      final expectation = expectLater(pending, throwsA(isA<ProtocolClosedException>()));

      await Future<void>.delayed(const Duration(milliseconds: 20));
      board.unplug();

      await expectation;
      expect(repl.state, RawReplState.inactive);
    });
  });

  group('interrupt', () {
    setUp(() => repl.enter());

    test('Ctrl-C termine un programme sans fin avec une trace KeyboardInterrupt', () async {
      final pending = repl.execute('while True: pass', timeout: null);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await repl.interrupt();
      final result = await pending;

      expect(result.ok, isFalse);
      expect(result.stderrText, contains('KeyboardInterrupt'));
      expect(repl.state, RawReplState.ready);
      expect((await repl.execute('print("après")')).stdoutText, 'après\r\n');
    });

    test('interrupt sans exécution en cours ne fait rien', () async {
      board.writes.clear();

      await repl.interrupt();

      expect(board.writes, isEmpty);
    });
  });

  group('états', () {
    test('execute avant enter lève ProtocolStateException', () async {
      await expectLater(repl.execute('print("x")'), throwsA(isA<ProtocolStateException>()));
    });

    test('exit envoie Ctrl-B, attend ">>> " et désactive la session', () async {
      await repl.enter();

      await repl.exit();

      expect(board.writes.last, [0x02]);
      expect(board.isRaw, isFalse);
      expect(repl.state, RawReplState.inactive);
      await expectLater(repl.execute('print("x")'), throwsA(isA<ProtocolStateException>()));
    });

    test('enter permet de repartir après une désynchronisation', () async {
      board.silentEnterAttempts = 99;
      await expectLater(repl.enter(), throwsA(isA<ProtocolTimeoutException>()));
      expect(repl.state, RawReplState.broken);

      board.silentEnterAttempts = 0;
      await repl.enter();

      expect(repl.state, RawReplState.ready);
    });
  });
}
