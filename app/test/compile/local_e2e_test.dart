// Essai réel de la compilation locale : télécharge arduino-cli et les cœurs (plus d'un Go) puis compile Blink.
// Désactivé par défaut. Pour le lancer :
//   NOMAD_LOCAL_E2E=<dossier d'installation> flutter test test/compile/local_e2e_test.dart
// Relancé sur le même dossier, il ne retélécharge rien.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:nomad_mcu/features/compile/data/sketch_project.dart';
import 'package:nomad_mcu/features/compile/local/local_compile_api.dart';
import 'package:nomad_mcu/features/compile/local/local_toolchain.dart';

void main() {
  final target = Platform.environment['NOMAD_LOCAL_E2E'];

  test('installation puis compilation de Blink sur ESP32, ESP32-S3 et RP2040', () async {
    final toolchain = LocalToolchain(Directory(target!));
    await for (final progress in toolchain.install()) {
      // ignore: avoid_print
      print('[install] ${progress.step.name} ${progress.core ?? ''} ${progress.line ?? ''}');
    }
    expect(toolchain.ready, isTrue);

    final api = LocalCompileApi(toolchain);
    addTearDown(api.close);
    final archive = Archive();
    archive.add(ArchiveFile.bytes('blink/blink.ino', utf8.encode(blinkSketch('Blink local'))));
    final zip = Uint8List.fromList(ZipEncoder().encode(archive));

    for (final board in [CompileBoard.esp32, CompileBoard.esp32s3, CompileBoard.rp2040]) {
      final submitted = await api.submit(zip, board);
      var status = submitted;
      while (!status.state.isFinished) {
        await Future<void>.delayed(const Duration(seconds: 2));
        status = await api.status(submitted.id);
      }
      // ignore: avoid_print
      print('[${board.id}] ${status.state.name} en ${status.durationMs} ms, artefacts : ${status.artifacts.map((a) => a.name).join(', ')}');
      expect(status.state, BuildState.succeeded, reason: status.log);
      expect(status.artifacts, isNotEmpty);
    }
  }, skip: target == null ? 'NOMAD_LOCAL_E2E non défini' : false, timeout: const Timeout(Duration(minutes: 60)));
}
