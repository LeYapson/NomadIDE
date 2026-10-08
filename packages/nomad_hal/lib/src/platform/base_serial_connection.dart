import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/serial_config.dart';
import '../domain/serial_device_info.dart';
import '../domain/serial_exceptions.dart';
import '../domain/serial_transport.dart';

/// Socle commun des implémentations de [SerialConnection].
///
/// Chaque plateforme n'implémente que les primitives `*Native` ; cette classe gère :
///  * le flux `input` broadcast et sa fermeture ;
///  * le suivi de l'état DTR/RTS ;
///  * la future [done], complétée une seule fois avec la cause de fin ;
///  * la conversion des erreurs natives en [SerialException].
abstract class BaseSerialConnection implements SerialConnection {
  BaseSerialConnection({required this.device, required SerialConfig config}) : _config = config;

  @override
  final SerialDeviceInfo device;

  SerialConfig _config;
  bool _dtr = false;
  bool _rts = false;
  bool _closing = false;
  final StreamController<Uint8List> _input = StreamController<Uint8List>.broadcast();
  final Completer<DisconnectReason> _done = Completer<DisconnectReason>();

  @override
  SerialConfig get config => _config;

  @override
  bool get isOpen => !_closing;

  @override
  bool get dtr => _dtr;

  @override
  bool get rts => _rts;

  @override
  Stream<Uint8List> get input => _input.stream;

  @override
  Future<DisconnectReason> get done => _done.future;

  // ---------------------------------------------------------------------------
  // Primitives à fournir par chaque plateforme.
  // ---------------------------------------------------------------------------

  @protected
  Future<void> writeNative(Uint8List data);

  @protected
  Future<void> applyConfigNative(SerialConfig config);

  @protected
  Future<void> setDtrNative(bool value);

  @protected
  Future<void> setRtsNative(bool value);

  /// Libère les ressources natives. Appelée une seule fois.
  @protected
  Future<void> closeNative();

  // ---------------------------------------------------------------------------
  // Helpers pour les implémentations.
  // ---------------------------------------------------------------------------

  /// À appeler à chaque réception d'octets.
  @protected
  void emitData(Uint8List data) {
    if (!_input.isClosed && data.isNotEmpty) _input.add(data);
  }

  /// À appeler quand la plateforme détecte la perte du périphérique.
  @protected
  void reportLost(DisconnectReason reason, [Object? error]) {
    if (_closing) return;
    if (error != null) debugPrint('[nomad_hal] ${device.id} : connexion perdue ($error)');
    unawaited(_finish(reason));
  }

  // ---------------------------------------------------------------------------
  // API publique.
  // ---------------------------------------------------------------------------

  @override
  Future<void> write(Uint8List data) =>
      data.isEmpty ? Future<void>.value() : _guard(SerialOperation.write, () => writeNative(data));

  @override
  Future<void> setConfig(SerialConfig config) => _guard(SerialOperation.configure, () async {
        await applyConfigNative(config);
        _config = config;
      });

  @override
  Future<void> setDtr(bool value) => _guard(SerialOperation.dtr, () async {
        await setDtrNative(value);
        _dtr = value;
      });

  @override
  Future<void> setRts(bool value) => _guard(SerialOperation.rts, () async {
        await setRtsNative(value);
        _rts = value;
      });

  @override
  Future<void> close() => _finish(DisconnectReason.closedByUser);

  Future<void> _guard(SerialOperation operation, Future<void> Function() action) async {
    if (_closing) throw const SerialClosedException('La connexion est fermée.', code: SerialErrorCode.connectionClosed);
    try {
      await action();
    } on SerialException {
      rethrow;
    } catch (e) {
      throw SerialIoException(
        '${operation.name} impossible sur ${device.displayName}.',
        cause: e,
        code: SerialErrorCode.operationFailed,
        params: {'operation': operation, 'device': device.displayName},
      );
    }
  }

  Future<void> _finish(DisconnectReason reason) async {
    if (_closing) {
      await _done.future;
      return;
    }
    _closing = true;
    try {
      await closeNative();
    } catch (e) {
      debugPrint('[nomad_hal] fermeture de ${device.id} : $e');
    }
    unawaited(_input.close());
    _done.complete(reason);
  }
}
