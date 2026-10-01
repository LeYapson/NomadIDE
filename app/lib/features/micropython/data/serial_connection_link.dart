import 'dart:typed_data';

import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_protocols/nomad_protocols.dart';

/// Adapte une [SerialConnection] (HAL) au [ByteLink] attendu par les protocoles.
///
/// C'est le seul endroit où `nomad_hal` et `nomad_protocols` se rencontrent :
/// les erreurs de la HAL sont traduites en erreurs de protocole.
class SerialConnectionLink implements ByteLink {
  SerialConnectionLink(this._connection);

  final SerialConnection _connection;

  @override
  Stream<Uint8List> get input => _connection.input;

  @override
  Future<void> write(Uint8List data) async {
    try {
      await _connection.write(data);
    } on SerialClosedException catch (e) {
      throw ProtocolClosedException(e.message);
    } on SerialException catch (e) {
      throw ProtocolIoException(e.message, cause: e);
    }
  }
}
