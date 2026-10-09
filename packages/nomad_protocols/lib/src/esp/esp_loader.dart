import 'dart:async';
import 'dart:collection';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

import '../io/byte_link.dart';
import '../protocol_exceptions.dart';
import 'md5.dart';
import 'slip.dart';

/// Puce ESP reconnue d'après la valeur du registre 0x40001000 (« magic »).
enum EspChip {
  esp8266('ESP8266', [0xFFF0C101], bootloaderOffset: 0x0),
  esp32('ESP32', [0x00F01D83], bootloaderOffset: 0x1000),
  esp32s2('ESP32-S2', [0x000007C6], bootloaderOffset: 0x1000),
  esp32s3('ESP32-S3', [0x00000009], bootloaderOffset: 0x0),
  esp32c3('ESP32-C3', [0x6921506F, 0x1B31506F, 0x4881606F, 0x4361606F], bootloaderOffset: 0x0),
  esp32c6('ESP32-C6', [0x2CE0806F], bootloaderOffset: 0x0),
  esp32h2('ESP32-H2', [0xD7B73E80], bootloaderOffset: 0x0),
  unknown('ESP inconnue', [], bootloaderOffset: 0x0);

  const EspChip(this.label, this.magics, {required this.bootloaderOffset});

  final String label;
  final List<int> magics;

  /// Adresse où va le bootloader dans une image complète (les autres partitions se placent après).
  final int bootloaderOffset;

  /// La ROM de l'ESP8266 ne sait pas calculer un MD5 de la flash.
  bool get supportsMd5 => this != esp8266;

  /// Les ROM récentes (S2 et suivants) attendent un cinquième mot (« chiffrée ») dans FLASH_BEGIN.
  bool get beginHasEncryptedWord => switch (this) {
        esp8266 || esp32 || unknown => false,
        _ => true,
      };

  static EspChip fromMagic(int magic) => values.firstWhere((c) => c.magics.contains(magic), orElse: () => unknown);
}

/// Progression d'une écriture : octets du fichier déjà écrits sur [total].
typedef EspProgress = void Function(int done, int total);

/// Client du bootloader de la ROM des ESP32 / ESP8266 (protocole de `esptool`, par paquets SLIP).
///
/// Déroulé d'un flash : mettre la carte en bootloader (DTR/RTS, voir `enterEspBootloader` dans
/// nomad_hal), [sync], [detectChip], [writeFlash] pour chaque fichier, puis redémarrer la carte
/// (reset matériel par RTS). Seule la ROM est utilisée, sans le « stub » d'esptool : c'est plus lent,
/// mais il n'y a rien à téléverser dans la RAM.
///
/// Le chargeur s'abonne au lien dès sa construction ; appelez [dispose] à la fin.
class EspLoader {
  EspLoader(this._link, {this.commandTimeout = const Duration(seconds: 3)}) {
    _subscription = _link.input.listen(
      (data) {
        _frames.addAll(_decoder.add(data));
        _wake();
      },
      onError: (Object error, StackTrace _) {
        _error = error;
        _wake();
      },
      onDone: () {
        _closed = true;
        _wake();
      },
    );
  }

  static const int opFlashBegin = 0x02;
  static const int opFlashData = 0x03;
  static const int opFlashEnd = 0x04;
  static const int opSync = 0x08;
  static const int opReadReg = 0x0A;
  static const int opSpiSetParams = 0x0B;
  static const int opSpiAttach = 0x0D;
  static const int opChangeBaud = 0x0F;
  static const int opFlashDeflBegin = 0x10;
  static const int opFlashDeflData = 0x11;
  static const int opFlashDeflEnd = 0x12;
  static const int opSpiFlashMd5 = 0x13;

  /// Taille d'un bloc de données envoyé à la ROM.
  static const int blockSize = 0x400;

  /// Registre dont la valeur identifie la puce.
  static const int chipDetectMagicReg = 0x40001000;

  static const int _checksumSeed = 0xEF;

  final ByteLink _link;
  final Duration commandTimeout;

  late final StreamSubscription<Uint8List> _subscription;
  final SlipDecoder _decoder = SlipDecoder();
  final Queue<Uint8List> _frames = Queue();
  Completer<void>? _signal;
  Object? _error;
  bool _closed = false;

  /// Puce détectée par [detectChip].
  EspChip? chip;

  /// Nombre d'octets d'état en fin de réponse : 4 pour les ROM, 2 pour l'ESP8266.
  /// Inconnu avant [detectChip] : on le déduit alors de la taille de la réponse.
  int? _knownStatusLength;

  int get _statusLength => _knownStatusLength ?? 4;
  bool _flashAttached = false;

  Future<void> dispose() => _subscription.cancel();

  // --- Commandes de haut niveau -------------------------------------------------------------

  /// Synchronise avec la ROM. À appeler juste après l'entrée en bootloader ; réessaie [attempts] fois
  /// car la carte met quelques dizaines de ms à démarrer.
  Future<void> sync({int attempts = 7, Duration timeout = const Duration(milliseconds: 200)}) async {
    final payload = Uint8List.fromList([0x07, 0x07, 0x12, 0x20, ...List.filled(32, 0x55)]);
    for (var i = 0; i < attempts; i++) {
      _frames.clear();
      try {
        await _command(opSync, payload, timeout: timeout, checkStatus: false);
        // La ROM répond plusieurs fois : on jette les réponses en trop.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        _frames.clear();
        return;
      } on ProtocolTimeoutException {
        // pas encore prête : on renvoie
      }
    }
    throw ProtocolTimeoutException(
      'Le bootloader ESP ne répond pas à la synchronisation ($attempts essais).',
      code: ProtocolErrorCode.espSyncFailed,
      params: {'attempts': attempts},
    );
  }

  Future<int> readReg(int address) async {
    final response = await _command(opReadReg, _words([address]));
    return response.value;
  }

  /// Identifie la puce et retient la longueur d'état de sa ROM.
  Future<EspChip> detectChip() async {
    final magic = await readReg(chipDetectMagicReg);
    final detected = EspChip.fromMagic(magic);
    chip = detected;
    _knownStatusLength = detected == EspChip.esp8266 ? 2 : 4;
    return detected;
  }

  /// Change le débit de la ROM. [reconfigure] doit passer le port série au nouveau débit :
  /// la réponse arrive encore à l'ancien débit, la suite au nouveau.
  Future<void> changeBaudRate(int baudRate, {required Future<void> Function(int baudRate) reconfigure}) async {
    await _command(opChangeBaud, _words([baudRate, 0]));
    await reconfigure(baudRate);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _frames.clear();
  }

  /// Écrit [data] dans la flash à partir de [offset].
  ///
  /// [compress] envoie le fichier compressé (zlib), 3 à 4 fois plus vite pour un programme typique.
  /// [verify] relit le MD5 de la zone écrite et lève [ProtocolFlashVerifyException] s'il diffère
  /// (impossible sur ESP8266, dont la ROM n'a pas cette commande).
  Future<void> writeFlash(
    int offset,
    Uint8List data, {
    bool compress = true,
    bool verify = true,
    EspProgress? onProgress,
  }) async {
    if (data.isEmpty) return;
    final detected = chip ?? await detectChip();
    await _attachFlash(offset + data.length);

    final onRom = _RomWriter(this, detected);
    if (compress) {
      await onRom.writeCompressed(offset, data, onProgress);
    } else {
      await onRom.writeRaw(offset, data, onProgress);
    }

    if (verify && detected.supportsMd5) {
      final expected = md5Hex(data);
      final actual = await flashMd5(offset, data.length);
      if (actual != expected) throw ProtocolFlashVerifyException(expectedMd5: expected, actualMd5: actual);
    }
  }

  /// MD5 (32 caractères hexadécimaux) de [size] octets de flash à partir de [offset].
  Future<String> flashMd5(int offset, int size) async {
    final response = await _command(
      opSpiFlashMd5,
      _words([offset, size, 0, 0]),
      timeout: _scaledTimeout(size, secondsPerMb: 8),
    );
    final data = response.data;
    final digestLength = data.length - _statusLength;
    if (digestLength == 32) return String.fromCharCodes(data.sublist(0, 32)).toLowerCase();
    if (digestLength == 16) return data.sublist(0, 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    throw ProtocolDesyncException(
      'Réponse MD5 inattendue (${data.length} octets).',
      received: data,
      code: ProtocolErrorCode.espBadPacket,
      params: {'hex': _hex(data)},
    );
  }

  // --- Mécanique interne -----------------------------------------------------------------------

  Future<void> _attachFlash(int endAddress) async {
    if (_flashAttached) return;
    if (chip != EspChip.esp8266) {
      // La ROM des ESP32 veut deux mots, le second est un drapeau « ancien mode » toujours à 0.
      await _command(opSpiAttach, _words([0, 0]));
    }
    // Taille annoncée à la ROM : au moins 4 Mo, arrondie à 64 Ko ; elle ne sert qu'à borner les écritures.
    const minSize = 4 * 1024 * 1024;
    final size = endAddress > minSize ? ((endAddress + 0xFFFF) ~/ 0x10000) * 0x10000 : minSize;
    await _command(opSpiSetParams, _words([0, size, 64 * 1024, 4 * 1024, 256, 0xFFFF]));
    _flashAttached = true;
  }

  /// Délai pour les commandes longues (effacement, MD5) : proportionnel à la taille.
  static Duration _scaledTimeout(int size, {required int secondsPerMb}) {
    final ms = (secondsPerMb * 1000 * size / (1024 * 1024)).ceil();
    return Duration(milliseconds: ms < 3000 ? 3000 : ms);
  }

  Future<_Response> _command(
    int op,
    Uint8List data, {
    int checksum = 0,
    Duration? timeout,
    bool checkStatus = true,
  }) async {
    final packet = BytesBuilder(copy: false)
      ..addByte(0x00)
      ..addByte(op)
      ..add(_u16(data.length))
      ..add(_u32(checksum))
      ..add(data);
    await _link.write(slipEncode(packet.toBytes()));

    final limit = timeout ?? commandTimeout;
    final clock = Stopwatch()..start();
    while (true) {
      final frame = await _nextFrame(limit - clock.elapsed, limit);
      if (frame.length < 8 || frame[0] != 0x01 || frame[1] != op) continue; // réponse tardive d'une autre commande
      final view = ByteData.sublistView(frame);
      final size = view.getUint16(2, Endian.little);
      final end = 8 + size <= frame.length ? 8 + size : frame.length;
      final response = _Response(view.getUint32(4, Endian.little), Uint8List.sublistView(frame, 8, end));
      if (checkStatus) _checkStatus(op, response.data);
      return response;
    }
  }

  void _checkStatus(int op, Uint8List data) {
    final length = _knownStatusLength ?? (data.length >= 4 ? 4 : 2);
    if (data.length < length) {
      throw ProtocolDesyncException(
        'Réponse trop courte (${data.length} octets).',
        received: data,
        code: ProtocolErrorCode.espBadPacket,
        params: {'hex': _hex(data)},
      );
    }
    final status = data[data.length - length];
    final error = data[data.length - length + 1];
    if (status != 0) throw ProtocolRomException(op, error);
  }

  Future<Uint8List> _nextFrame(Duration remaining, Duration limit) async {
    final clock = Stopwatch()..start();
    while (true) {
      if (_frames.isNotEmpty) return _frames.removeFirst();
      final error = _error;
      if (error != null) throw ProtocolIoException('Erreur de lecture sur le lien.', cause: error);
      if (_closed) throw const ProtocolClosedException('Le lien a été fermé.');
      final left = remaining - clock.elapsed;
      if (left <= Duration.zero) throw _timeout(limit);
      final signal = _signal ??= Completer<void>();
      try {
        await signal.future.timeout(left);
      } on TimeoutException {
        throw _timeout(limit);
      }
    }
  }

  void _wake() {
    final signal = _signal;
    _signal = null;
    signal?.complete();
  }

  static ProtocolTimeoutException _timeout(Duration timeout) => ProtocolTimeoutException(
        'Aucune réponse du bootloader après ${timeout.inMilliseconds} ms.',
        code: ProtocolErrorCode.noResponse,
        params: {'timeoutMs': timeout.inMilliseconds},
      );

  static Uint8List _words(List<int> values) {
    final out = Uint8List(values.length * 4);
    final view = ByteData.sublistView(out);
    for (var i = 0; i < values.length; i++) {
      view.setUint32(i * 4, values[i], Endian.little);
    }
    return out;
  }

  static Uint8List _u16(int v) => Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);

  static Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);

  static String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}

class _Response {
  const _Response(this.value, this.data);

  final int value;
  final Uint8List data;
}

/// Séquence BEGIN / DATA… / END de la ROM, pour un fichier brut ou compressé.
class _RomWriter {
  _RomWriter(this._loader, this._chip);

  final EspLoader _loader;
  final EspChip _chip;

  static const _maxAttempts = 3;

  Future<void> writeRaw(int offset, Uint8List data, EspProgress? onProgress) async {
    final blocks = (data.length + EspLoader.blockSize - 1) ~/ EspLoader.blockSize;
    await _begin(
      EspLoader.opFlashBegin,
      eraseSize: _eraseSize(offset, data.length),
      blocks: blocks,
      offset: offset,
      timeout: EspLoader._scaledTimeout(data.length, secondsPerMb: 30),
    );
    onProgress?.call(0, data.length);
    for (var seq = 0; seq < blocks; seq++) {
      final start = seq * EspLoader.blockSize;
      final end = start + EspLoader.blockSize < data.length ? start + EspLoader.blockSize : data.length;
      // Le dernier bloc est complété par des 0xFF (état d'une flash effacée).
      final block = Uint8List(EspLoader.blockSize)
        ..fillRange(0, EspLoader.blockSize, 0xFF)
        ..setRange(0, end - start, data, start);
      await _sendBlock(EspLoader.opFlashData, seq, block);
      onProgress?.call(end, data.length);
    }
    await _loader._command(EspLoader.opFlashEnd, EspLoader._words([1])); // 1 : rester dans le bootloader
  }

  Future<void> writeCompressed(int offset, Uint8List data, EspProgress? onProgress) async {
    final compressed = Uint8List.fromList(ZLibCodec(level: 9).encode(data));
    final blocks = (compressed.length + EspLoader.blockSize - 1) ~/ EspLoader.blockSize;
    await _begin(
      EspLoader.opFlashDeflBegin,
      eraseSize: _eraseSize(offset, data.length),
      blocks: blocks,
      offset: offset,
      timeout: EspLoader._scaledTimeout(data.length, secondsPerMb: 30),
    );
    onProgress?.call(0, data.length);
    for (var seq = 0; seq < blocks; seq++) {
      final start = seq * EspLoader.blockSize;
      final end = start + EspLoader.blockSize < compressed.length ? start + EspLoader.blockSize : compressed.length;
      await _sendBlock(EspLoader.opFlashDeflData, seq, Uint8List.sublistView(compressed, start, end));
      onProgress?.call((data.length * end / compressed.length).floor(), data.length);
    }
    await _loader._command(EspLoader.opFlashDeflEnd, EspLoader._words([1]));
  }

  Future<void> _begin(int op, {required int eraseSize, required int blocks, required int offset, required Duration timeout}) {
    final words = [eraseSize, blocks, EspLoader.blockSize, offset, if (_chip.beginHasEncryptedWord) 0];
    return _loader._command(op, EspLoader._words(words), timeout: timeout);
  }

  /// En-tête de 16 octets (longueur, numéro, 0, 0) suivi du bloc ; somme de contrôle XOR du bloc seul.
  Future<void> _sendBlock(int op, int seq, Uint8List block) async {
    final payload = BytesBuilder(copy: false)
      ..add(EspLoader._words([block.length, seq, 0, 0]))
      ..add(block);
    var checksum = EspLoader._checksumSeed;
    for (final b in block) {
      checksum ^= b;
    }
    final bytes = payload.toBytes();
    for (var attempt = 1;; attempt++) {
      try {
        await _loader._command(op, bytes, checksum: checksum);
        return;
      } on ProtocolTimeoutException {
        // Un bloc perdu sur le lien : la ROM accepte le même numéro à nouveau.
        if (attempt >= _maxAttempts) rethrow;
      }
    }
  }

  /// Taille à effacer. L'ESP8266 a une particularité : sa ROM efface par blocs de 64 Ko et
  /// mal les débuts de zone, d'où le calcul d'esptool (`get_erase_size`).
  int _eraseSize(int offset, int size) {
    if (_chip != EspChip.esp8266) return size;
    const sectorsPerBlock = 16;
    const sectorSize = 4096;
    final numSectors = (size + sectorSize - 1) ~/ sectorSize;
    final startSector = offset ~/ sectorSize;
    var headSectors = sectorsPerBlock - (startSector % sectorsPerBlock);
    if (numSectors < headSectors) headSectors = numSectors;
    if (numSectors < 2 * headSectors) return ((numSectors + 1) ~/ 2) * sectorSize;
    return (numSectors - headSectors) * sectorSize;
  }
}
