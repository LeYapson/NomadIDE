import 'dart:typed_data';

import '../picoboot/picoboot_client.dart';
import '../protocol_exceptions.dart';

/// Fausse ROM de RP2040 en mode BOOTSEL qui parle PICOBOOT : accès exclusif, XIP, effacement par secteurs,
/// écriture par pages, relecture, redémarrage. La « flash » est un tableau d'octets.
///
/// Elle applique les mêmes règles d'alignement que la vraie ROM (effacement sur 4096, écriture sur 256), pour que
/// les tests attrapent les erreurs d'alignement du client.
class FakePicoboot implements PicobootChannel {
  FakePicoboot({int flashSize = 2 * 1024 * 1024}) : flash = Uint8List(flashSize)..fillRange(0, flashSize, 0xFF);

  static const int flashBase = 0x10000000;

  /// Contenu de la flash (adresse 0 = 0x10000000).
  final Uint8List flash;

  /// Commandes reçues, dans l'ordre (identifiants PICOBOOT).
  final List<int> commands = [];

  /// Vrai une fois la commande de redémarrage reçue.
  bool rebooted = false;

  /// Commande qui échoue, avec le code d'état renvoyé (ex. `{0x05: 4}` : l'écriture répond « adresse invalide »).
  final Map<int, int> failing = {};

  /// Altère l'octet à cette adresse (relative à la flash) au moment de l'écriture, pour simuler une flash défaillante.
  int? corruptWriteAt;

  /// Nombre de commandes avant de simuler un débranchement.
  int? unplugAfterCommands;

  bool _exclusive = false;
  bool _xipActive = true;
  int _lastToken = 0;
  int _lastStatus = 0;
  int _lastCommand = 0;
  bool _unplugged = false;

  // Commande en cours.
  Uint8List? _pendingIn;
  _Pending? _pending;

  @override
  Future<void> bulkOut(Uint8List data, {required Duration timeout}) async {
    _checkPlugged();
    final pending = _pending;
    if (pending != null) {
      // Données (commande OUT) ou accusé de réception (commande IN).
      if (pending.isIn) {
        _pending = null; // accusé d'une commande de lecture
      } else if (!pending.dataReceived) {
        pending.data = data;
        pending.dataReceived = true;
        _execute(pending);
        if (pending.transferLength == 0) _pending = null;
      }
      return;
    }
    if (data.length != 32) throw const ProtocolIoException('Paquet de commande invalide.');
    final view = ByteData.sublistView(data);
    if (view.getUint32(0, Endian.little) != PicobootClient.magic) {
      throw const ProtocolIoException('Marque PICOBOOT invalide.');
    }
    final command = _Pending(
      token: view.getUint32(4, Endian.little),
      id: data[8],
      size: data[9],
      transferLength: view.getUint32(12, Endian.little),
      args: Uint8List.fromList(data.sublist(16)),
    );
    commands.add(command.id);
    _lastToken = command.token;
    _lastCommand = command.id;
    final limit = unplugAfterCommands;
    if (limit != null && commands.length > limit) {
      _unplugged = true;
      throw const ProtocolClosedException('Câble débranché.');
    }
    if (command.isIn || command.transferLength > 0) {
      _pending = command;
      if (command.isIn) _execute(command);
    } else {
      _execute(command);
      _pending = command; // il reste l'accusé de réception à lire
    }
  }

  @override
  Future<Uint8List> bulkIn(int length, {required Duration timeout}) async {
    _checkPlugged();
    final pending = _pending;
    if (pending == null) throw const ProtocolIoException('Rien à lire.');
    if (pending.isIn && !pending.dataSent) {
      pending.dataSent = true;
      final data = _pendingIn ?? Uint8List(0);
      _pendingIn = null;
      if (_lastStatus != 0) throw const ProtocolIoException('Commande refusée.');
      return data;
    }
    // Accusé de réception d'une commande OUT.
    _pending = null;
    if (_lastStatus != 0) throw const ProtocolIoException('Commande refusée.');
    return Uint8List(0);
  }

  @override
  Future<void> interfaceReset() async {
    _checkPlugged();
    _pending = null;
    _pendingIn = null;
  }

  @override
  Future<Uint8List> commandStatus() async {
    _checkPlugged();
    final out = Uint8List(16);
    ByteData.sublistView(out)
      ..setUint32(0, _lastToken, Endian.little)
      ..setUint32(4, _lastStatus, Endian.little)
      ..setUint8(8, _lastCommand);
    return out;
  }

  void _checkPlugged() {
    if (_unplugged) throw const ProtocolClosedException('Câble débranché.');
  }

  void _execute(_Pending c) {
    final forced = failing[c.id];
    if (forced != null) {
      _lastStatus = forced;
      return;
    }
    _lastStatus = 0;
    final args = ByteData.sublistView(c.args);
    switch (c.id) {
      case PicobootCommand.exclusiveAccess:
        _exclusive = c.args[0] != 0;
      case PicobootCommand.exitXip:
        _xipActive = false;
      case PicobootCommand.enterCmdXip:
        _xipActive = true;
      case PicobootCommand.flashErase:
        final address = args.getUint32(0, Endian.little);
        final size = args.getUint32(4, Endian.little);
        if (!_inFlash(address, size)) {
          _lastStatus = 4;
        } else if (address % 4096 != 0 || size % 4096 != 0) {
          _lastStatus = 5;
        } else if (_xipActive) {
          _lastStatus = 9; // la vraie ROM veut le XIP désactivé pour effacer
        } else {
          flash.fillRange(address - flashBase, address - flashBase + size, 0xFF);
        }
      case PicobootCommand.write:
        final address = args.getUint32(0, Endian.little);
        final size = args.getUint32(4, Endian.little);
        final data = c.data;
        if (!_inFlash(address, size)) {
          _lastStatus = 4;
        } else if (address % 256 != 0 || size % 256 != 0) {
          _lastStatus = 5;
        } else if (_xipActive) {
          _lastStatus = 9;
        } else if (data == null || data.length != size) {
          _lastStatus = 3;
        } else {
          final at = address - flashBase;
          // L'écriture ne fait que passer des bits de 1 à 0 : sans effacement préalable, le résultat est un ET binaire.
          for (var i = 0; i < size; i++) {
            flash[at + i] &= data[i];
          }
          final corrupt = corruptWriteAt;
          if (corrupt != null && corrupt >= at && corrupt < at + size) {
            flash[corrupt] ^= 0xFF;
            corruptWriteAt = null;
          }
        }
      case PicobootCommand.read:
        final address = args.getUint32(0, Endian.little);
        final size = args.getUint32(4, Endian.little);
        if (!_inFlash(address, size)) {
          _lastStatus = 4;
        } else if (!_xipActive) {
          _lastStatus = 9; // flash illisible hors XIP
        } else {
          _pendingIn = Uint8List.fromList(flash.sublist(address - flashBase, address - flashBase + size));
        }
      case PicobootCommand.reboot:
        rebooted = true;
      default:
        _lastStatus = 1;
    }
  }

  bool _inFlash(int address, int size) => address >= flashBase && address + size <= flashBase + flash.length;

  /// Accès exclusif pris par l'hôte (pour les tests).
  bool get exclusive => _exclusive;
}

class _Pending {
  _Pending({required this.token, required this.id, required this.size, required this.transferLength, required this.args});

  final int token;
  final int id;
  final int size;
  final int transferLength;
  final Uint8List args;
  Uint8List? data;
  bool dataReceived = false;
  bool dataSent = false;

  bool get isIn => id & 0x80 != 0;
}
