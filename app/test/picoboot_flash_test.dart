import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:nomad_mcu/features/flash/application/flash_controller.dart';
import 'package:nomad_mcu/features/flash/data/picoboot_gateway.dart';
import 'package:nomad_protocols/nomad_protocols.dart';
import 'package:nomad_protocols/testing.dart';

import 'support/locale.dart';

const _flash = 0x10000000;

/// UF2 de [blocks] blocs de 256 octets à partir de la base de la flash (famille RP2040 par défaut).
Uint8List _uf2(int blocks, {int family = 0xE48BFF56}) {
  final out = Uint8List(blocks * 512);
  final d = ByteData.sublistView(out);
  for (var i = 0; i < blocks; i++) {
    final o = i * 512;
    d.setUint32(o, 0x0A324655, Endian.little);
    d.setUint32(o + 4, 0x9E5D5157, Endian.little);
    d.setUint32(o + 8, 0x2000, Endian.little);
    d.setUint32(o + 12, _flash + i * 256, Endian.little);
    d.setUint32(o + 16, 256, Endian.little);
    d.setUint32(o + 20, i, Endian.little);
    d.setUint32(o + 24, blocks, Endian.little);
    d.setUint32(o + 28, family, Endian.little);
    for (var j = 0; j < 256; j++) {
      out[o + 32 + j] = (i * 31 + j * 7 + 3) & 0xFE;
    }
    d.setUint32(o + 508, 0x0AB16F30, Endian.little);
  }
  return out;
}

/// Passerelle USB de test : une carte branchée sur la fausse ROM PICOBOOT.
class FakeGateway implements PicobootGateway {
  FakeGateway(this.rom, {this.present = true, this.hasPermission = true, this.grant = true, this.appearsAfterPolls = 0});

  final FakePicoboot rom;

  /// La carte est sur le bus (en BOOTSEL).
  bool present;
  bool hasPermission;

  /// Réponse de l'utilisateur à la demande d'autorisation.
  bool grant;

  /// La carte n'apparaît qu'après autant d'appels à [list] (le temps de redémarrer en BOOTSEL).
  int appearsAfterPolls;

  int permissionRequests = 0;
  int opened = 0;
  bool closed = false;
  int _polls = 0;

  @override
  Future<List<PicobootDevice>> list() async {
    _polls++;
    if (rom.rebooted) present = false; // la carte a redémarré : elle quitte le BOOTSEL
    if (!present && appearsAfterPolls > 0 && _polls > appearsAfterPolls && !rom.rebooted) present = true;
    return present ? [PicobootDevice(name: 'usb:fake', hasPermission: hasPermission)] : const [];
  }

  @override
  Future<bool> requestPermission(PicobootDevice device) async {
    permissionRequests++;
    hasPermission = grant;
    return grant;
  }

  @override
  Future<OpenPicobootChannel> open(PicobootDevice device) async {
    opened++;
    return _Channel(this);
  }
}

class _Channel implements OpenPicobootChannel {
  _Channel(this._gateway);

  final FakeGateway _gateway;

  FakePicoboot get _rom => _gateway.rom;

  @override
  Future<void> bulkOut(Uint8List data, {required Duration timeout}) => _rom.bulkOut(data, timeout: timeout);

  @override
  Future<Uint8List> bulkIn(int length, {required Duration timeout}) => _rom.bulkIn(length, timeout: timeout);

  @override
  Future<void> interfaceReset() => _rom.interfaceReset();

  @override
  Future<Uint8List> commandStatus() => _rom.commandStatus();

  @override
  Future<void> close() async => _gateway.closed = true;
}

void main() {
  late FakePicoboot rom;
  late FakeGateway gateway;
  late FakeSerialTransport serial;
  late ProviderContainer container;
  late PickedFile? nextPick;
  late List<FlashPhase> phases;

  void setUpBoard(FakeGateway g) {
    gateway = g;
    rom = g.rom;
    serial = FakeSerialTransport();
    nextPick = (name: 'firmware.uf2', bytes: _uf2(40));
    phases = [];
    container = ProviderContainer(overrides: [
      frenchLocale,
      serialTransportProvider.overrideWithValue(serial),
      picobootGatewayProvider.overrideWithValue(gateway),
      uf2PickerProvider.overrideWithValue(() async => nextPick),
      uf2DrivePollProvider.overrideWithValue(null),
      uf2TimeoutsProvider.overrideWithValue(
        (touch: const Duration(milliseconds: 300), drive: const Duration(milliseconds: 600), reboot: const Duration(milliseconds: 600)),
      ),
    ]);
    container.listen(flashProvider, (prev, next) {
      if (prev?.phase != next.phase) phases.add(next.phase);
    });
  }

  setUp(() async {
    setUpBoard(FakeGateway(FakePicoboot()));
    await container.read(flashProvider.notifier).refresh();
  });

  tearDown(() => container.dispose());

  FlashController controller() => container.read(flashProvider.notifier);
  FlashState state() => container.read(flashProvider);

  test('carte déjà en BOOTSEL : écrit, vérifie, redémarre, sans ouvrir le port série', () async {
    await controller().refresh();
    expect(state().bootselUsb, isTrue);

    await controller().pickFile();
    await controller().flash();

    expect(state().phase, FlashPhase.done, reason: state().message);
    final file = Uf2File.parse(nextPick!.bytes);
    for (final block in file.flashBlocks) {
      expect(rom.flash.sublist(block.address - _flash, block.address - _flash + block.data.length), block.data);
    }
    expect(rom.rebooted, isTrue);
    expect(gateway.closed, isTrue, reason: 'le canal USB est refermé');
    expect(state().message, contains('La carte a redémarré'));
    // Les étapes se succèdent dans l'ordre, y compris la vérification.
    expect(phases, containsAllInOrder([FlashPhase.touching, FlashPhase.erasing, FlashPhase.copying, FlashPhase.verifying, FlashPhase.rebooting, FlashPhase.done]));
  });

  test('autorisation USB demandée à l\'utilisateur quand Android ne l\'a pas encore accordée', () async {
    setUpBoard(FakeGateway(FakePicoboot(), hasPermission: false));
    await controller().pickFile();
    await controller().flash();
    expect(gateway.permissionRequests, 1);
    expect(state().phase, FlashPhase.done, reason: state().message);
    expect(phases, contains(FlashPhase.permission));
  });

  test('autorisation refusée : message clair, rien n\'est écrit', () async {
    setUpBoard(FakeGateway(FakePicoboot(), hasPermission: false, grant: false));
    await controller().pickFile();
    await controller().flash();
    expect(state().phase, FlashPhase.failed);
    expect(state().message, contains('Accès USB refusé'));
    expect(gateway.opened, 0);
    expect(rom.commands, isEmpty);
  });

  test('carte en fonctionnement : elle est basculée en BOOTSEL, puis flashée', () async {
    setUpBoard(FakeGateway(FakePicoboot(), present: false, appearsAfterPolls: 3));
    await controller().refreshDevicesForTest();
    await controller().pickFile();
    await controller().flash();

    expect(state().phase, FlashPhase.done, reason: state().message);
    expect(phases, contains(FlashPhase.waitingDrive));
    expect(rom.rebooted, isTrue);
  });

  test('aucune carte n\'apparaît en BOOTSEL : conseil BOOTSEL à la main', () async {
    setUpBoard(FakeGateway(FakePicoboot(), present: false));
    await controller().refreshDevicesForTest();
    await controller().pickFile();
    await controller().flash();
    expect(state().phase, FlashPhase.failed);
    expect(state().message, contains('BOOTSEL'));
    expect(rom.commands, isEmpty);
  });

  test('fichier prévu pour une autre puce : refusé avant toute opération USB', () async {
    nextPick = (name: 'esp.uf2', bytes: _uf2(4, family: 0x1C5F21B0));
    await controller().pickFile();
    await controller().flash();
    expect(state().phase, FlashPhase.failed);
    expect(state().message, contains('ESP32'));
    expect(gateway.opened, 0);
  });

  test('câble débranché pendant l\'écriture : message et avertissement « programme incomplet »', () async {
    rom.unplugAfterCommands = 6;
    await controller().pickFile();
    await controller().flash();
    expect(state().phase, FlashPhase.failed);
    expect(state().message, contains('incomplet'));
    expect(rom.rebooted, isFalse);
  });

  test('flash défaillante : la vérification échoue, la carte n\'est pas redémarrée', () async {
    rom.corruptWriteAt = 0x800;
    await controller().pickFile();
    await controller().flash();
    expect(state().phase, FlashPhase.failed);
    expect(state().message, contains('ne correspond pas'));
    expect(state().message, contains('10000800'));
    expect(rom.rebooted, isFalse);
  });

  test('refus de la ROM : le code d\'état apparaît dans le message', () async {
    rom.failing[PicobootCommand.flashErase] = 10;
    await controller().pickFile();
    await controller().flash();
    expect(state().phase, FlashPhase.failed);
    expect(state().message, contains('code 10'));
  });
}

extension on FlashController {
  /// Relit la liste des cartes série (la carte « en fonctionnement » de ces tests).
  Future<void> refreshDevicesForTest() => refresh();
}
