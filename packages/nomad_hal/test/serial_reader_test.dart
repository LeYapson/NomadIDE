import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_hal/nomad_hal.dart';

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  late StreamController<Uint8List> source;
  late SerialReader reader;

  setUp(() {
    source = StreamController<Uint8List>();
    reader = SerialReader(source.stream);
  });

  tearDown(() async {
    await reader.cancel();
    await source.close();
  });

  test('read() assemble plusieurs chunks', () async {
    final result = reader.read(6);
    source
      ..add(bytes('abc'))
      ..add(bytes('def'));
    expect(utf8.decode(await result), 'abcdef');
  });

  test('readUntil() trouve un délimiteur à cheval sur deux chunks et garde le reste', () async {
    final result = reader.readUntil(utf8.encode('>>> '));
    source
      ..add(bytes('MicroPython\r\n>>'))
      ..add(bytes('> reste'));
    expect(utf8.decode(await result), 'MicroPython\r\n>>> ');
    expect(reader.available, 'reste'.length);
  });

  test('readUntil(includeDelimiter: false) exclut le délimiteur', () async {
    source.add(bytes('OK\x04suite'));
    final result = await reader.readUntil(const [0x04], includeDelimiter: false);
    expect(utf8.decode(result), 'OK');
  });

  test('timeout → SerialTimeoutException', () async {
    await expectLater(
      reader.read(1, timeout: const Duration(milliseconds: 20)),
      throwsA(isA<SerialTimeoutException>()),
    );
  });

  test('fin de flux pendant une lecture → SerialClosedException', () async {
    final result = reader.read(10);
    source.add(bytes('abc'));
    await source.close();
    await expectLater(result, throwsA(isA<SerialClosedException>()));
  });
}
