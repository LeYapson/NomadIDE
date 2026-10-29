import 'dart:typed_data';

import '../protocol_exceptions.dart';

/// Le canal USB de l'interface PICOBOOT d'un RP2040 / RP2350 en mode BOOTSEL : une interface « vendor »
/// avec deux points d'entrée bulk (un OUT, un IN) et deux requêtes de contrôle.
///
/// Sur Android, l'implémentation passe par l'API USB Host ; dans les tests, par [FakePicoboot].
abstract interface class PicobootChannel {
  /// Envoie [data] sur le point d'entrée bulk OUT.
  Future<void> bulkOut(Uint8List data, {required Duration timeout});

  /// Lit au plus [length] octets sur le point d'entrée bulk IN (zéro octet est valide : paquet vide).
  Future<Uint8List> bulkIn(int length, {required Duration timeout});

  /// Requête de contrôle « vendor » `PICOBOOT_IF_RESET` (0x41) : débloque les points d'entrée.
  Future<void> interfaceReset();

  /// Requête de contrôle « vendor » `PICOBOOT_IF_CMD_STATUS` (0x42) : 16 octets décrivant la dernière commande.
  Future<Uint8List> commandStatus();
}

/// Codes de commande PICOBOOT. Le bit de poids fort indique un transfert de données vers l'hôte.
class PicobootCommand {
  static const int exclusiveAccess = 0x01;
  static const int reboot = 0x02;
  static const int flashErase = 0x03;
  static const int read = 0x84;
  static const int write = 0x05;
  static const int exitXip = 0x06;
  static const int enterCmdXip = 0x07;
}

/// État renvoyé par `PICOBOOT_IF_CMD_STATUS`.
class PicobootStatus {
  const PicobootStatus({required this.token, required this.code, required this.command, required this.inProgress});

  final int token;
  final int code;
  final int command;
  final bool inProgress;

  bool get ok => code == 0;
}

/// Client PICOBOOT : les commandes de la ROM du RP2040 pour écrire et relire la flash.
///
/// Une commande se déroule en trois temps : le paquet de 32 octets, l'éventuelle étape de données, puis un
/// accusé de réception d'un octet dans le sens opposé. Voir le chapitre « USB PICOBOOT Interface » de la
/// documentation du RP2040.
class PicobootClient {
  PicobootClient(this._channel);

  final PicobootChannel _channel;

  static const int magic = 0x431FD10B;
  static const Duration commandTimeout = Duration(seconds: 10);
  static const Duration dataTimeout = Duration(seconds: 3);

  int _token = 1;

  /// Prend la main sur le périphérique (pas de disque de stockage pendant l'opération).
  Future<void> exclusiveAccess({bool exclusive = true}) =>
      _command(PicobootCommand.exclusiveAccess, Uint8List(16)..[0] = exclusive ? 1 : 0, cmdSize: 1);

  /// Quitte le mode XIP : obligatoire avant d'effacer ou d'écrire la flash.
  Future<void> exitXip() => _command(PicobootCommand.exitXip, _args(const []));

  /// Réactive la lecture de la flash par XIP : nécessaire pour la relire.
  Future<void> enterCmdXip() => _command(PicobootCommand.enterCmdXip, _args(const []));

  /// Efface [size] octets de flash à partir de [address] (alignés sur 4096).
  /// L'effacement de plusieurs centaines de Ko prend plusieurs secondes : [timeout] est large.
  Future<void> flashErase(int address, int size, {Duration timeout = const Duration(seconds: 60)}) =>
      _command(PicobootCommand.flashErase, _args([address, size]), cmdSize: 8, timeout: timeout);

  /// Écrit [data] à [address] (alignée sur 256, longueur multiple de 256). N'efface pas.
  Future<void> write(int address, Uint8List data) =>
      _command(PicobootCommand.write, _args([address, data.length]), cmdSize: 8, out: data);

  /// Lit [size] octets à [address].
  Future<Uint8List> read(int address, int size) async {
    final data = await _command(PicobootCommand.read, _args([address, size]), cmdSize: 8, inLength: size);
    return data!;
  }

  /// Redémarre la carte. [pc] et [sp] à 0 : démarrage normal depuis la flash.
  Future<void> reboot({int pc = 0, int sp = 0, int delayMs = 500}) =>
      _command(PicobootCommand.reboot, _args([pc, sp, delayMs]), cmdSize: 12);

  Future<PicobootStatus> status() async {
    final raw = await _channel.commandStatus();
    final view = ByteData.sublistView(raw);
    return PicobootStatus(
      token: view.getUint32(0, Endian.little),
      code: view.getUint32(4, Endian.little),
      command: view.getUint8(8),
      inProgress: view.getUint8(9) != 0,
    );
  }

  /// Les 16 octets d'arguments d'une commande : jusqu'à quatre mots de 32 bits.
  static Uint8List _args(List<int> words) {
    final out = Uint8List(16);
    final view = ByteData.sublistView(out);
    for (var i = 0; i < words.length; i++) {
      view.setUint32(i * 4, words[i], Endian.little);
    }
    return out;
  }

  Future<Uint8List?> _command(
    int id,
    Uint8List args, {
    int cmdSize = 0,
    Uint8List? out,
    int? inLength,
    Duration? timeout,
  }) async {
    final transferLength = out?.length ?? inLength ?? 0;
    final packet = Uint8List(32);
    ByteData.sublistView(packet)
      ..setUint32(0, magic, Endian.little)
      ..setUint32(4, _token++, Endian.little)
      ..setUint8(8, id)
      ..setUint8(9, cmdSize)
      ..setUint32(12, transferLength, Endian.little);
    packet.setRange(16, 32, args);

    Uint8List? received;
    try {
      await _channel.bulkOut(packet, timeout: dataTimeout);
      final isIn = id & 0x80 != 0;
      if (transferLength > 0) {
        if (isIn) {
          received = await _channel.bulkIn(transferLength, timeout: dataTimeout);
        } else {
          await _channel.bulkOut(out!, timeout: dataTimeout);
        }
      }
      // Accusé de réception : un octet dans le sens opposé aux données (et, sans données, IN pour une commande OUT).
      final ackTimeout = transferLength == 0 ? (timeout ?? commandTimeout) : (timeout ?? dataTimeout);
      if (isIn) {
        await _channel.bulkOut(Uint8List(1), timeout: ackTimeout);
      } else {
        await _channel.bulkIn(1, timeout: ackTimeout);
      }
    } on ProtocolException catch (e) {
      // La ROM a peut-être refusé la commande : son état dit pourquoi, et on débloque l'interface.
      throw await _explain(id, e);
    }
    if (received != null && received.length != transferLength) {
      throw ProtocolDesyncException(
        'Lecture PICOBOOT incomplète (${received.length} octets sur $transferLength).',
        code: ProtocolErrorCode.other,
      );
    }
    return received;
  }

  /// Cherche la cause d'un échec : le code d'état de la ROM, sinon l'erreur de transport [original] telle quelle
  /// (câble débranché, délai dépassé…).
  Future<ProtocolException> _explain(int commandId, ProtocolException original) async {
    try {
      final status = await this.status();
      await _channel.interfaceReset();
      if (!status.ok) return ProtocolPicobootException(commandId, status.code);
    } on ProtocolException {
      // le périphérique ne répond plus : on garde l'erreur d'origine
    }
    return original;
  }
}
