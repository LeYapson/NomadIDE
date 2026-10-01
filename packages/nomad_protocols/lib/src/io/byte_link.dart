import 'dart:typed_data';

/// Canal d'octets bidirectionnel vers une carte : le seul contrat dont les
/// protocoles ont besoin.
///
/// `SerialConnection` (nomad_hal) le satisfait presque tel quel ; l'adaptateur
/// vit dans l'application, ce qui garde ce package indépendant de Flutter.
abstract interface class ByteLink {
  /// Flux **broadcast** des octets reçus, par chunks de taille arbitraire.
  /// Un octet reçu sans abonné est perdu : les protocoles s'abonnent avant d'écrire.
  Stream<Uint8List> get input;

  Future<void> write(Uint8List data);
}
