import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_mcu/features/serial_monitor/domain/log_entry.dart';
import 'package:nomad_mcu/features/serial_monitor/domain/rx_line_assembler.dart';

Uint8List bytes(List<int> b) => Uint8List.fromList(b);

void main() {
  test('découpe sur \\n et conserve la ligne en cours', () {
    final assembler = RxLineAssembler();
    final lines = assembler.add(bytes(utf8.encode('boot ok\r\n>>> ')));
    expect(lines.map(terminalText), ['boot ok']);
    expect(terminalText(assembler.partial), '>>> ');
  });

  test("un caractère UTF-8 coupé entre deux chunks n'est pas corrompu", () {
    final assembler = RxLineAssembler();
    final encoded = utf8.encode('température\n'); // « é » = 0xC3 0xA9
    final cut = encoded.indexOf(0xC3) + 1;
    expect(assembler.add(bytes(encoded.sublist(0, cut))), isEmpty);
    final lines = assembler.add(bytes(encoded.sublist(cut)));
    expect(terminalText(lines.single), 'température');
  });

  test('une ligne sans fin est coupée à maxLineLength', () {
    final assembler = RxLineAssembler(maxLineLength: 4);
    final lines = assembler.add(bytes(utf8.encode('abcdefghij')));
    expect(lines.map(utf8.decode), ['abcd', 'efgh']);
    expect(utf8.decode(assembler.partial), 'ij');
  });

  test('terminalText retire les séquences ANSI et les \\r', () {
    final colored = utf8.encode('\x1B[0;32mI (312) wifi: connected\x1B[0m\r');
    expect(terminalText(bytes(colored)), 'I (312) wifi: connected');
  });
}
