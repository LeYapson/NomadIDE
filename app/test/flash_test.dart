import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:nomad_mcu/features/flash/application/flash_controller.dart';
import 'package:nomad_protocols/nomad_protocols.dart';

import 'support/locale.dart';

const _info = 'UF2 Bootloader v3.0\r\nModel: Raspberry Pi RP2\r\nBoard-ID: RPI-RP2\r\n';

/// UF2 valide de [blocks] blocs.
Uint8List _uf2({int blocks = 4, int family = 0xE48BFF56}) {
  final out = Uint8List(blocks * 512);
  final d = ByteData.sublistView(out);
  for (var i = 0; i < blocks; i++) {
    final o = i * 512;
    d.setUint32(o, 0x0A324655, Endian.little);
    d.setUint32(o + 4, 0x9E5D5157, Endian.little);
    d.setUint32(o + 8, 0x2000, Endian.little);
    d.setUint32(o + 12, 0x10000000 + i * 256, Endian.little);
    d.setUint32(o + 16, 256, Endian.little);
    d.setUint32(o + 20, i, Endian.little);
    d.setUint32(o + 24, blocks, Endian.little);
    d.setUint32(o + 28, family, Endian.little);
    d.setUint32(o + 508, 0x0AB16F30, Endian.little);
  }
  return out;
}

/// Transport qui retient la connexion ouverte pour vérifier le touch 1200 bauds.
class _RecordingTransport extends FakeSerialTransport {
  _RecordingTransport() : super(devices: const [_pico]);

  static const _pico = SerialDeviceInfo(
    id: 'fake:pico',
    displayName: 'Pico',
    systemPath: 'COM9',
    vendorId: 0x2E8A,
    productId: 0x0005,
  );

  final List<SerialConnection> opened = [];

  @override
  Future<SerialConnection> open(
    SerialDeviceInfo device, {
    SerialConfig config = const SerialConfig(),
    bool dtr = true,
    bool rts = true,
  }) async {
    final c = await super.open(device, config: config, dtr: dtr, rts: rts);
    opened.add(c);
    return c;
  }
}

void main() {
  late Directory tmp;
  late Directory pico;
  late _RecordingTransport transport;
  late PickedFile? nextPick;
  late ProviderContainer container;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nomad_flash_');
    pico = await Directory('${tmp.path}/RPI-RP2').create();
    transport = _RecordingTransport();
    nextPick = (name: 'blink.uf2', bytes: _uf2());
    container = ProviderContainer(overrides: [
      frenchLocale,
      serialTransportProvider.overrideWithValue(transport),
      uf2DrivePollProvider.overrideWithValue(null),
      uf2TimeoutsProvider.overrideWithValue((touch: const Duration(milliseconds: 300), drive: const Duration(milliseconds: 600), reboot: const Duration(milliseconds: 300))),
      uf2PickerProvider.overrideWithValue(() async => nextPick),
      uf2FlasherProvider.overrideWithValue(Uf2Flasher(roots: () async => [pico.path], chunkSize: 1024)),
    ]);
    container.listen(flashProvider, (_, __) {});
    await container.read(flashProvider.notifier).refresh();
  });

  tearDown(() async {
    container.dispose();
    await tmp.delete(recursive: true);
  });

  FlashController controller() => container.read(flashProvider.notifier);
  FlashState state() => container.read(flashProvider);

  /// Simule le bootloader : le disque se vide dès que le fichier est complet.
  Future<void> bootloaderReboots(int size) async {
    final uf2 = File('${pico.path}/blink.uf2');
    while (!await uf2.exists() || await uf2.length() < size) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await File('${pico.path}/INFO_UF2.TXT').delete();
  }

  test('choisit d\'abord la carte RP2 branchée', () {
    expect(state().devices, hasLength(1));
    expect(state().selectedDevice?.id, 'fake:pico');
  });

  test('un fichier UF2 valide est lu et résumé', () async {
    await controller().pickFile();
    expect(state().file?.family, Uf2Family.rp2040);
    expect(state().fileName, 'blink.uf2');
    expect(state().canFlash, isTrue);
  });

  test('annuler le sélecteur ne change rien', () async {
    nextPick = null;
    await controller().pickFile();
    expect(state().file, isNull);
    expect(state().phase, FlashPhase.idle);
  });

  test('un fichier qui n\'est pas un UF2 est refusé avec un message', () async {
    nextPick = (name: 'blink.bin', bytes: Uint8List(1024));
    await controller().pickFile();
    expect(state().file, isNull);
    expect(state().phase, FlashPhase.failed);
    expect(state().message, contains('Fichier UF2 invalide'));
    expect(state().message, contains('bloc 0'));
  });

  test('disque déjà en BOOTSEL : copie sans toucher au port série', () async {
    await File('${pico.path}/INFO_UF2.TXT').writeAsString(_info);
    await controller().refresh();
    expect(state().drive?.boardId, 'RPI-RP2');

    await controller().pickFile();
    final reboot = bootloaderReboots(state().file!.bytes.length);
    await controller().flash();
    await reboot;

    expect(state().phase, FlashPhase.done);
    expect(state().message, contains('La carte a redémarré'));
    expect(transport.opened, isEmpty);
  });

  test('carte en fonctionnement : touch 1200 bauds, attente du disque, copie', () async {
    await controller().pickFile();
    // Le disque n'apparaît qu'une fois le port fermé, comme sur une vraie carte.
    unawaited(Future<void>.delayed(const Duration(milliseconds: 150), () async {
      expect(transport.opened.single.isOpen, isFalse);
      await File('${pico.path}/INFO_UF2.TXT').writeAsString(_info);
      await bootloaderReboots(_uf2().length);
    }));

    await controller().flash();

    expect(transport.opened.single.config.baudRate, 1200);
    expect(state().phase, FlashPhase.done);
  });

  test('un fichier prévu pour une autre puce est refusé', () async {
    await File('${pico.path}/INFO_UF2.TXT').writeAsString(_info);
    nextPick = (name: 'esp.uf2', bytes: _uf2(family: 0x1C5F21B0));
    await controller().pickFile();
    await controller().flash();
    expect(state().phase, FlashPhase.failed);
    expect(state().message, contains('ESP32'));
    expect(File('${pico.path}/esp.uf2').existsSync(), isFalse);
  });

  test('copie terminée sans redémarrage : message d\'avertissement', () async {
    await File('${pico.path}/INFO_UF2.TXT').writeAsString(_info);
    container.dispose();
    container = ProviderContainer(overrides: [
      frenchLocale,
      serialTransportProvider.overrideWithValue(transport),
      uf2DrivePollProvider.overrideWithValue(null),
      uf2TimeoutsProvider.overrideWithValue((touch: const Duration(milliseconds: 300), drive: const Duration(milliseconds: 600), reboot: const Duration(milliseconds: 300))),
      uf2PickerProvider.overrideWithValue(() async => nextPick),
      uf2FlasherProvider.overrideWithValue(Uf2Flasher(roots: () async => [pico.path], chunkSize: 1024)),
    ]);
    container.listen(flashProvider, (_, __) {});
    await controller().pickFile();
    // Le disque reste en place : le bootloader n'a pas redémarré.
    await controller().flash();
    expect(state().phase, FlashPhase.failed);
    expect(state().message, contains('n’a pas redémarré'));
  });

  test('aucun disque ne apparaît : message avec la marche à suivre', () async {
    await controller().pickFile();
    // Le port est bien touché, mais aucun disque n'apparaît.
    await controller().flash();
    expect(state().phase, FlashPhase.failed);
    expect(state().message, contains('BOOTSEL'));
    // Touch 1200 bauds, puis machine.bootloader() par le REPL : deux ouvertures.
    expect(transport.opened, hasLength(2));
    expect(transport.opened.first.config.baudRate, 1200);
  });

  test('disque retiré en pleine copie : on prévient que la carte peut être incomplète', () async {
    await File('${pico.path}/INFO_UF2.TXT').writeAsString(_info);
    container.dispose();
    container = ProviderContainer(overrides: [
      frenchLocale,
      serialTransportProvider.overrideWithValue(transport),
      uf2DrivePollProvider.overrideWithValue(null),
      uf2PickerProvider.overrideWithValue(() async => nextPick),
      uf2FlasherProvider.overrideWithValue(_UnpluggedFlasher(pico.path)),
    ]);
    container.listen(flashProvider, (_, __) {});
    await controller().pickFile();
    await controller().flash();
    expect(state().phase, FlashPhase.failed);
    expect(state().message, contains('incomplet'));
    expect(state().message, contains('1024 sur 2048'));
  });
}

/// Disque BOOTSEL arraché à mi-copie.
class _UnpluggedFlasher extends Uf2Flasher {
  _UnpluggedFlasher(this.path) : super(roots: () async => [path]);

  final String path;

  @override
  Future<Uf2FlashResult> flash(
    Uf2File file,
    Uf2Drive drive, {
    String fileName = 'firmware.uf2',
    void Function(int written, int total)? onProgress,
    Duration rebootTimeout = const Duration(seconds: 15),
    Duration poll = const Duration(milliseconds: 250),
  }) async {
    onProgress?.call(1024, file.bytes.length);
    throw Uf2CopyException(drive, 1024, file.bytes.length, 'disque retiré');
  }
}
