import 'dart:async';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

import '../esp/esp_loader.dart';
import '../esp/md5.dart';
import '../esp/slip.dart';
import '../io/byte_link.dart';

/// Fausse ROM d'ESP qui parle le protocole d'esptool : synchro, registres, écriture brute ou
/// compressée, MD5. La « flash » est un tableau d'octets accessible par [flash].
///
/// Les réponses sont livrées par petits chunks, de façon asynchrone, pour éprouver le découpage SLIP.
class FakeEspRom implements ByteLink {
  FakeEspRom({
    this.chip = EspChip.esp32,
    int flashSize = 4 * 1024 * 1024,
    this.outputChunkSize = 5,
    this.silentSyncs = 0,
    this.bootText = '',
  }) : flash = Uint8List(flashSize)..fillRange(0, flashSize, 0xFF);

  final EspChip chip;
  final int outputChunkSize;

  /// Nombre de paquets SYNC à ignorer avant de répondre (carte qui démarre).
  int silentSyncs;

  /// Texte émis avant le premier paquet, comme le fait la ROM au démarrage.
  final String bootText;

  /// Contenu de la flash.
  final Uint8List flash;

  /// Opcodes reçus, dans l'ordre.
  final List<int> commands = [];

  /// Opcodes auxquels la ROM ne répond jamais.
  final Set<int> ignored = {};

  /// Opcodes refusés avec ce code d'erreur (ex. `{0x03: 0x08}`).
  final Map<int, int> failing = {};

  /// Nombre de paquets de données à perdre (pas de réponse) avant de les accepter.
  int dropDataPackets = 0;

  /// Octet de la prochaine donnée écrite à altérer (simule une flash défaillante) ; null : aucune.
  int? corruptWriteAt;

  /// Débit demandé par CHANGE_BAUDRATE.
  int? baudRate;

  bool spiAttached = false;
  List<int>? spiParams;

  final StreamController<Uint8List> _input = StreamController<Uint8List>.broadcast();
  final SlipDecoder _decoder = SlipDecoder();

  int _statusLength(int _) => chip == EspChip.esp8266 ? 2 : 4;

  // État de l'écriture en cours.
  int _offset = 0;
  int _blockSize = 0;
  int _expectedBlocks = 0;
  int _nextSeq = 0;
  bool _compressed = false;
  final BytesBuilder _compressedData = BytesBuilder();

  @override
  Stream<Uint8List> get input => _input.stream;

  /// Tout ce que l'hôte a écrit.
  final List<Uint8List> writes = [];

  @override
  Future<void> write(Uint8List data) async {
    writes.add(Uint8List.fromList(data));
    for (final frame in _decoder.add(data)) {
      _handle(frame);
    }
  }

  /// Simule le débranchement du câble.
  void unplug() => _input.close();

  /// Émet le texte de démarrage de la ROM.
  void boot() => _emitRaw(Uint8List.fromList(bootText.codeUnits));

  void _handle(Uint8List frame) {
    if (frame.length < 8 || frame[0] != 0x00) return;
    final op = frame[1];
    final view = ByteData.sublistView(frame);
    final size = view.getUint16(2, Endian.little);
    final checksum = view.getUint32(4, Endian.little);
    final data = Uint8List.sublistView(frame, 8, 8 + size > frame.length ? frame.length : 8 + size);
    commands.add(op);

    if (op == EspLoader.opSync) {
      if (silentSyncs > 0) {
        silentSyncs--;
        return;
      }
      // La vraie ROM répond plusieurs fois à une synchronisation.
      for (var i = 0; i < 3; i++) {
        _reply(op, 0, const []);
      }
      return;
    }
    if (ignored.contains(op)) return;
    final forced = failing[op];
    if (forced != null) {
      _reply(op, 0, const [], error: forced);
      return;
    }

    switch (op) {
      case EspLoader.opReadReg:
        final address = ByteData.sublistView(data).getUint32(0, Endian.little);
        _reply(op, address == EspLoader.chipDetectMagicReg ? chip.magics.firstOrNull ?? 0 : 0, const []);
      case EspLoader.opSpiAttach:
        spiAttached = true;
        _reply(op, 0, const []);
      case EspLoader.opSpiSetParams:
        final params = ByteData.sublistView(data);
        spiParams = [for (var i = 0; i + 4 <= data.length; i += 4) params.getUint32(i, Endian.little)];
        _reply(op, 0, const []);
      case EspLoader.opChangeBaud:
        baudRate = ByteData.sublistView(data).getUint32(0, Endian.little);
        _reply(op, 0, const []);
      case EspLoader.opFlashBegin:
      case EspLoader.opFlashDeflBegin:
        final p = ByteData.sublistView(data);
        _expectedBlocks = p.getUint32(4, Endian.little);
        _blockSize = p.getUint32(8, Endian.little);
        _offset = p.getUint32(12, Endian.little);
        _nextSeq = 0;
        _compressed = op == EspLoader.opFlashDeflBegin;
        _compressedData.clear();
        _reply(op, 0, const []);
      case EspLoader.opFlashData:
      case EspLoader.opFlashDeflData:
        _onData(op, data, checksum);
      case EspLoader.opFlashEnd:
        _reply(op, 0, const []);
      case EspLoader.opFlashDeflEnd:
        if (_compressed && _nextSeq == _expectedBlocks) {
          try {
            final raw = ZLibCodec().decode(_compressedData.toBytes());
            flash.setRange(_offset, _offset + raw.length, raw);
          } on Object {
            _reply(op, 0, const [], error: 0x0b);
            return;
          }
        }
        _reply(op, 0, const []);
      case EspLoader.opSpiFlashMd5:
        if (!chip.supportsMd5) {
          _reply(op, 0, const [], error: 0x05);
          return;
        }
        final p = ByteData.sublistView(data);
        final start = p.getUint32(0, Endian.little);
        final length = p.getUint32(4, Endian.little);
        _reply(op, 0, md5Hex(flash.sublist(start, start + length)).codeUnits);
      default:
        _reply(op, 0, const [], error: 0x05);
    }
  }

  void _onData(int op, Uint8List data, int checksum) {
    if (dropDataPackets > 0) {
      dropDataPackets--;
      return;
    }
    final p = ByteData.sublistView(data);
    final length = p.getUint32(0, Endian.little);
    final seq = p.getUint32(4, Endian.little);
    final block = Uint8List.sublistView(data, 16, 16 + length);
    var expected = 0xEF;
    for (final b in block) {
      expected ^= b;
    }
    if (expected != checksum) {
      _reply(op, 0, const [], error: 0x07);
      return;
    }
    if (seq != _nextSeq) {
      _reply(op, 0, const [], error: 0x08);
      return;
    }
    _nextSeq++;
    if (_compressed) {
      _compressedData.add(block);
    } else {
      final at = _offset + seq * _blockSize;
      flash.setRange(at, at + length, block);
      final corrupt = corruptWriteAt;
      if (corrupt != null && corrupt >= at && corrupt < at + length) {
        flash[corrupt] ^= 0xFF;
        corruptWriteAt = null;
      }
    }
    _reply(op, 0, const []);
  }

  void _reply(int op, int value, List<int> data, {int error = 0}) {
    final status = _statusLength(op);
    final body = [...data, if (error != 0) 1 else 0, error, ...List.filled(status - 2, 0)];
    final packet = BytesBuilder()
      ..addByte(0x01)
      ..addByte(op)
      ..add((ByteData(2)..setUint16(0, body.length, Endian.little)).buffer.asUint8List())
      ..add((ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List())
      ..add(body);
    _emitRaw(slipEncode(packet.toBytes()));
  }

  void _emitRaw(Uint8List bytes) {
    for (var i = 0; i < bytes.length; i += outputChunkSize) {
      final end = i + outputChunkSize < bytes.length ? i + outputChunkSize : bytes.length;
      final chunk = Uint8List.sublistView(bytes, i, end);
      Timer(Duration.zero, () {
        if (!_input.isClosed) _input.add(chunk);
      });
    }
  }
}
