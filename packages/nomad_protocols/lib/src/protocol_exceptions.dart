import 'dart:typed_data';

/// Cause précise d'une erreur de protocole, pour que l'application affiche le
/// message dans la langue de l'utilisateur (les [ProtocolException.message] sont
/// des repères en français pour les journaux de développement).
enum ProtocolErrorCode {
  other,

  /// Erreur de lecture sur le lien.
  linkReadFailed,

  /// Le lien est fermé (câble débranché).
  linkClosed,

  /// Pas de réponse à temps. Paramètre : `timeoutMs`.
  noResponse,

  /// La carte ne passe pas en raw REPL. Paramètre : `attempts`.
  rawReplNotEntered,

  /// Le programme a dépassé son délai et a été interrompu. Paramètre : `timeoutMs`.
  programTimeout,

  /// Une exécution est déjà en cours.
  busy,

  /// Raw REPL inactif : `enter()` d'abord.
  notActive,

  /// Session désynchronisée : `enter()` pour la rétablir.
  sessionBroken,

  /// Réponse inattendue au lieu de « OK ». Paramètre : `hex`.
  unexpectedAck,

  /// Réponse inattendue au calcul du CRC. Paramètre : `reply`.
  unexpectedCrcReply,

  /// Fichier corrompu en route. Paramètres : `path`, `expectedSize`, `actualSize`.
  integrityMismatch,

  /// La carte a levé une exception Python.
  remoteError,
}

/// Erreurs communes aux protocoles carte.
sealed class ProtocolException implements Exception {
  const ProtocolException(
    this.message, {
    this.cause,
    this.code = ProtocolErrorCode.other,
    this.params = const {},
  });

  /// Repère en français pour les journaux ; l'interface s'appuie sur [code] et [params].
  final String message;
  final Object? cause;

  final ProtocolErrorCode code;

  /// Valeurs à insérer dans le message localisé (voir [ProtocolErrorCode]).
  final Map<String, Object?> params;

  @override
  String toString() => cause == null ? '$runtimeType: $message' : '$runtimeType: $message (cause : $cause)';
}

/// La carte n'a pas répondu (ou le programme a dépassé son délai) à temps.
final class ProtocolTimeoutException extends ProtocolException {
  const ProtocolTimeoutException(super.message, {this.partialOutput, super.code, super.params});

  /// Sortie standard reçue avant l'expiration, si le protocole en produit.
  final Uint8List? partialOutput;
}

/// Le lien est fermé (câble débranché, déconnexion).
final class ProtocolClosedException extends ProtocolException {
  const ProtocolClosedException(super.message, {super.code = ProtocolErrorCode.linkClosed, super.params});
}

/// Échec d'écriture ou de lecture sur le lien.
final class ProtocolIoException extends ProtocolException {
  const ProtocolIoException(super.message, {super.cause, super.code = ProtocolErrorCode.linkReadFailed, super.params});
}

/// Appel invalide dans l'état courant (ex. exécuter avant d'être entré en raw REPL).
final class ProtocolStateException extends ProtocolException {
  const ProtocolStateException(super.message, {super.code, super.params});
}

/// La carte a répondu autre chose que ce que le protocole prévoit.
final class ProtocolDesyncException extends ProtocolException {
  const ProtocolDesyncException(super.message, {this.received, super.code, super.params});

  final Uint8List? received;
}

/// Le fichier relu sur la carte ne correspond pas à ce qui a été envoyé
/// (octets perdus ou altérés sur le lien).
final class ProtocolIntegrityException extends ProtocolException {
  const ProtocolIntegrityException(
    super.message, {
    required this.expectedCrc,
    required this.actualCrc,
    super.code = ProtocolErrorCode.integrityMismatch,
    super.params,
  });

  final int expectedCrc;
  final int actualCrc;
}

/// La carte a exécuté la commande mais Python a levé une exception
/// (fichier absent, répertoire non vide, …).
final class ProtocolRemoteException extends ProtocolException {
  const ProtocolRemoteException(super.message, {required this.stderr, this.errno})
      : super(code: ProtocolErrorCode.remoteError);

  /// Trace complète renvoyée par la carte.
  final String stderr;

  /// Code `OSError` si la trace en contient un (2 = ENOENT, 17 = EEXIST, …).
  final int? errno;

  bool get isNotFound => errno == 2;
}
