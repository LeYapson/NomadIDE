
import 'package:flutter/services.dart';
import 'package:nomad_protocols/nomad_protocols.dart';

/// Une carte RP2040 en mode BOOTSEL vue par USB (interface PICOBOOT).
class PicobootDevice {
  const PicobootDevice({required this.name, required this.hasPermission});

  /// Identifiant système du périphérique (chemin USB).
  final String name;
  final bool hasPermission;
}

/// Canal PICOBOOT ouvert, à fermer à la fin.
abstract interface class OpenPicobootChannel implements PicobootChannel {
  Future<void> close();
}

/// Accès au PICOBOOT de la plateforme. Seul Android en a besoin : sur ordinateur, le disque BOOTSEL suffit.
/// Dans les tests : une passerelle branchée sur `FakePicoboot`.
abstract interface class PicobootGateway {
  /// Les cartes actuellement en BOOTSEL.
  Future<List<PicobootDevice>> list();

  /// Demande à l'utilisateur d'autoriser l'accès USB ; faux s'il refuse.
  Future<bool> requestPermission(PicobootDevice device);

  Future<OpenPicobootChannel> open(PicobootDevice device);
}

/// Passerelle Android : parle au code Kotlin `PicobootUsb` par un canal de plateforme.
class AndroidPicobootGateway implements PicobootGateway {
  static const MethodChannel _channel = MethodChannel('dev.nomadmcu/picoboot');

  @override
  Future<List<PicobootDevice>> list() async {
    final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('list') ?? const [];
    return [
      for (final d in raw) PicobootDevice(name: d['name']! as String, hasPermission: d['hasPermission'] == true),
    ];
  }

  @override
  Future<bool> requestPermission(PicobootDevice device) async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission', {'name': device.name}) ?? false;
    } on PlatformException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<OpenPicobootChannel> open(PicobootDevice device) async {
    try {
      await _channel.invokeMethod<int>('open', {'name': device.name});
    } on PlatformException catch (e) {
      throw _translate(e);
    }
    return _AndroidPicobootChannel();
  }
}

class _AndroidPicobootChannel implements OpenPicobootChannel {
  static const MethodChannel _channel = AndroidPicobootGateway._channel;

  @override
  Future<void> bulkOut(Uint8List data, {required Duration timeout}) =>
      _call(() => _channel.invokeMethod<void>('bulkOut', {'data': data, 'timeoutMs': timeout.inMilliseconds}));

  @override
  Future<Uint8List> bulkIn(int length, {required Duration timeout}) async {
    final data = await _call(
      () => _channel.invokeMethod<Uint8List>('bulkIn', {'length': length, 'timeoutMs': timeout.inMilliseconds}),
    );
    return data ?? Uint8List(0);
  }

  /// `PICOBOOT_IF_RESET` : requête « vendor » vers l'interface, sans données (bmRequestType 0x41).
  @override
  Future<void> interfaceReset() =>
      _call(() => _channel.invokeMethod<void>('control', {'requestType': 0x41, 'request': 0x41, 'length': 0}));

  /// `PICOBOOT_IF_CMD_STATUS` : 16 octets, de l'interface vers l'hôte (bmRequestType 0xC1).
  @override
  Future<Uint8List> commandStatus() async {
    final data = await _call(
      () => _channel.invokeMethod<Uint8List>('control', {'requestType': 0xC1, 'request': 0x42, 'length': 16}),
    );
    if (data == null || data.length != 16) {
      throw const ProtocolIoException('État PICOBOOT illisible.');
    }
    return data;
  }

  @override
  Future<void> close() async {
    try {
      await _channel.invokeMethod<void>('close');
    } on PlatformException {
      // la carte a déjà disparu
    }
  }

  Future<T?> _call<T>(Future<T?> Function() body) async {
    try {
      return await body();
    } on PlatformException catch (e) {
      throw _translate(e);
    }
  }
}

/// Traduit une erreur du code natif en erreur de protocole : le reste de l'app ne connaît pas `PlatformException`.
ProtocolException _translate(PlatformException e) {
  return switch (e.code) {
    'closed' || 'not_open' => ProtocolClosedException(e.message ?? 'La carte a été débranchée.'),
    'timeout' => ProtocolTimeoutException(
        e.message ?? 'Aucune réponse de la carte.',
        code: ProtocolErrorCode.noResponse,
        params: const {'timeoutMs': 0},
      ),
    _ => ProtocolIoException(e.message ?? 'Erreur USB.', cause: e),
  };
}
