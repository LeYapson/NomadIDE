import 'dart:typed_data';

/// Erreurs communes aux protocoles carte.
sealed class ProtocolException implements Exception {
  const ProtocolException(this.message, {this.cause});

  /// Message lisible, destiné à l'utilisateur.
  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? '$runtimeType: $message' : '$runtimeType: $message (cause : $cause)';
}

/// La carte n'a pas répondu (ou le programme a dépassé son délai) à temps.
final class ProtocolTimeoutException extends ProtocolException {
  const ProtocolTimeoutException(super.message, {this.partialOutput});

  /// Sortie standard reçue avant l'expiration, si le protocole en produit.
  final Uint8List? partialOutput;
}

/// Le lien est fermé (câble débranché, déconnexion).
final class ProtocolClosedException extends ProtocolException {
  const ProtocolClosedException(super.message);
}

/// Échec d'écriture ou de lecture sur le lien.
final class ProtocolIoException extends ProtocolException {
  const ProtocolIoException(super.message, {super.cause});
}

/// Appel invalide dans l'état courant (ex. exécuter avant d'être entré en raw REPL).
final class ProtocolStateException extends ProtocolException {
  const ProtocolStateException(super.message);
}

/// La carte a répondu autre chose que ce que le protocole prévoit.
final class ProtocolDesyncException extends ProtocolException {
  const ProtocolDesyncException(super.message, {this.received});

  final Uint8List? received;
}

/// La carte a exécuté la commande mais Python a levé une exception
/// (fichier absent, répertoire non vide, …).
final class ProtocolRemoteException extends ProtocolException {
  const ProtocolRemoteException(super.message, {required this.stderr, this.errno});

  /// Trace complète renvoyée par la carte.
  final String stderr;

  /// Code `OSError` si la trace en contient un (2 = ENOENT, 17 = EEXIST, …).
  final int? errno;

  bool get isNotFound => errno == 2;
}
