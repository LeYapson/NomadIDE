import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_hal/nomad_hal.dart';

void main() {
  const prompt = [0x3E, 0x3E, 0x3E, 0x20]; // ">>> "

  test('le REPL simulé affiche la bannière puis évalue une expression', () async {
    final transport = FakeSerialTransport();
    final device = (await transport.listDevices()).single;
    final connection = await transport.open(device);
    final reader = SerialReader(connection.input);

    final banner = await reader.readUntil(prompt);
    expect(utf8.decode(banner), startsWith('MicroPython'));

    await connection.write(Uint8List.fromList(utf8.encode('6*7\r')));
    final answer = utf8.decode(await reader.readUntil(prompt));
    expect(answer, contains('42'));

    await connection.close();
    expect(await connection.done, DisconnectReason.closedByUser);
    expect(connection.isOpen, isFalse);
    await transport.dispose();
  });

  test('les lignes DTR/RTS sont actives par défaut à l\'ouverture', () async {
    final transport = FakeSerialTransport();
    final connection = await transport.open(FakeSerialTransport.defaultDevice);
    expect(connection.dtr, isTrue);
    expect(connection.rts, isTrue);

    await connection.hardReset(pulse: Duration.zero);
    expect(connection.dtr, isFalse);
    expect(connection.rts, isFalse);
    await transport.dispose();
  });

  test('débranchement simulé → done = deviceLost et écriture refusée', () async {
    final transport = FakeSerialTransport();
    final connection = await transport.open(FakeSerialTransport.defaultDevice);

    transport.simulateDetach(FakeSerialTransport.defaultDevice.id);

    expect(await connection.done, DisconnectReason.deviceLost);
    await expectLater(
      connection.write(Uint8List.fromList([0x0D])),
      throwsA(isA<SerialClosedException>()),
    );
    expect(await transport.listDevices(), isEmpty);
    await transport.dispose();
  });
}
